package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"net/netip"
	"regexp"
	"sort"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Offices are the game zones. Every player belongs to one office (and a department of it); colleagues
// for joint tasks come only from the office the player is in today, so a task never pairs people
// from different cities. Each office has its own network, entry and exit codes, working-time limits
// and parking draw. Offices are system-owned storage objects that only the server reads and writes.

const (
	officesCollection = "offices"
	// The office for accounts made before offices existed, when game_rules.json names none.
	fallbackOfficeID  = "hq"
	maxOfficeNetworks = 32
	maxTripDays       = 366
)

// Office ids go into the entry codes ("<office>.<step>.<signature>"), so they never contain a dot.
var officeIDPattern = regexp.MustCompile(`^[a-z0-9_]{1,32}$`)

type Office struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	City     string   `json:"city"`
	Networks []string `json:"networks"`
	// Working-time limits of the office; nil = the defaults from game_rules.json.
	Limits *Limits `json:"limits,omitempty"`
}

type officeValue struct {
	Name     string   `json:"name"`
	City     string   `json:"city"`
	Networks []string `json:"networks"`
	Limits   *Limits  `json:"limits,omitempty"`
}

// defaultOfficeID: the office of game_rules.json, which the first start creates.
func defaultOfficeID() string {
	if gameContent == nil || gameContent.Rules.Office.ID == "" {
		return fallbackOfficeID
	}
	return gameContent.Rules.Office.ID
}

// prefixes: the office network. Empty turns the network check off for this office.
func (o *Office) prefixes() []netip.Prefix {
	prefixes, _ := parseOfficeNetworks(strings.Join(o.Networks, ","))
	return prefixes
}

// limits: the admin's limits of the office, or the defaults.
func (o *Office) limits() Limits {
	if o != nil && o.Limits != nil && validateLimits(*o.Limits) == nil {
		return *o.Limits
	}
	return gameContent.Rules.Limits
}

// normalizeNetworks checks the CIDR prefixes (or single addresses) and returns them cleaned.
func normalizeNetworks(networks []string) ([]string, error) {
	if len(networks) > maxOfficeNetworks {
		return nil, errInvalidNetworks
	}
	cleaned := []string{}
	for _, network := range networks {
		if strings.Contains(network, ",") {
			return nil, errInvalidNetworks
		}
		prefixes, err := parseOfficeNetworks(network)
		if err != nil {
			return nil, errInvalidNetworks
		}
		for _, prefix := range prefixes {
			cleaned = append(cleaned, prefix.String())
		}
	}
	return cleaned, nil
}

func decodeOffice(id, raw string) (Office, bool) {
	var value officeValue
	if json.Unmarshal([]byte(raw), &value) != nil {
		return Office{}, false
	}
	if value.Networks == nil {
		value.Networks = []string{}
	}
	return Office{ID: id, Name: value.Name, City: value.City, Networks: value.Networks, Limits: value.Limits}, true
}

func listOffices(ctx context.Context, nk runtime.NakamaModule) ([]Office, error) {
	offices := []Office{}
	cursor := ""
	for {
		objects, next, err := nk.StorageList(ctx, "", systemUserID, officesCollection, storagePageSize, cursor)
		if err != nil {
			return nil, errInternal
		}
		for _, object := range objects {
			if office, ok := decodeOffice(object.GetKey(), object.GetValue()); ok {
				offices = append(offices, office)
			}
		}
		if next == "" {
			break
		}
		cursor = next
	}
	sort.SliceStable(offices, func(i, j int) bool {
		return strings.ToLower(offices[i].Name) < strings.ToLower(offices[j].Name)
	})
	return offices, nil
}

// readOffice: the office, or nil when there is none with this id.
func readOffice(ctx context.Context, nk runtime.NakamaModule, id string) (*Office, error) {
	if !officeIDPattern.MatchString(id) {
		return nil, nil
	}
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: officesCollection, Key: id, UserID: systemUserID}})
	if err != nil {
		return nil, errInternal
	}
	if len(objects) == 0 {
		return nil, nil
	}
	office, ok := decodeOffice(id, objects[0].GetValue())
	if !ok {
		return nil, errInternal
	}
	return &office, nil
}

func findOffice(ctx context.Context, nk runtime.NakamaModule, id string) (*Office, error) {
	office, err := readOffice(ctx, nk, id)
	if err == nil && office == nil {
		err = errOfficeNotFound
	}
	return office, err
}

// writeOffice stores an office. version "*" writes only when the key does not exist yet.
func writeOffice(ctx context.Context, nk runtime.NakamaModule, office Office, version string) error {
	value, err := json.Marshal(officeValue{Name: office.Name, City: office.City, Networks: office.Networks, Limits: office.Limits})
	if err != nil {
		return errInternal
	}
	_, err = nk.StorageWrite(ctx, []*runtime.StorageWrite{{
		Collection: officesCollection, Key: office.ID, UserID: systemUserID, Value: string(value), Version: version,
		PermissionRead: permissionNone, PermissionWrite: permissionNone,
	}})
	return err
}

func officeNameTaken(offices []Office, name, exceptID string) bool {
	for _, office := range offices {
		if office.ID != exceptID && strings.EqualFold(office.Name, name) {
			return true
		}
	}
	return false
}

func newOfficeID() (string, error) {
	bytes := make([]byte, 4)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return "office_" + hex.EncodeToString(bytes), nil
}

// seedOffices creates the default office on the first start: its network comes from OFFICE_NETWORKS
// and its limits from the limits the admin saved before offices existed. Departments made before
// offices existed are moved into it.
func seedOffices(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, networksEnv string) error {
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return err
	}
	if len(offices) == 0 {
		prefixes, err := parseOfficeNetworks(networksEnv)
		if err != nil {
			return err
		}
		office := Office{ID: defaultOfficeID(), Name: "Главный офис", City: "Екатеринбург", Networks: []string{}}
		for _, prefix := range prefixes {
			office.Networks = append(office.Networks, prefix.String())
		}
		if limits, ok, err := legacyLimits(ctx, nk); err != nil {
			return err
		} else if ok {
			office.Limits = &limits
		}
		if err := writeOffice(ctx, nk, office, "*"); err != nil {
			return err
		}
		logger.Info("office %s created", office.ID)
		offices = append(offices, office)
	}
	for _, office := range offices {
		if len(office.Networks) == 0 {
			logger.Warn("office %s has no network: presence there is not checked against the office network", office.ID)
		}
	}
	return moveLegacyDepartments(ctx, nk)
}

// legacyLimits: the limits the admin saved before offices existed (settings/limits).
func legacyLimits(ctx context.Context, nk runtime.NakamaModule) (Limits, bool, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: settingsCollection, Key: limitsKey, UserID: systemUserID}})
	if err != nil {
		return Limits{}, false, err
	}
	if len(objects) == 0 {
		return Limits{}, false, nil
	}
	var limits Limits
	if json.Unmarshal([]byte(objects[0].GetValue()), &limits) != nil || validateLimits(limits) != nil {
		return Limits{}, false, nil
	}
	return limits, true, nil
}

// --- The office of a transaction --------------------------------------------------------

// office: the office the player counts in today.
func (tx *gameTx) office() string {
	office, _ := tx.me.metadata.placement(tx.today)
	return office
}

// department: the department the player counts in today.
func (tx *gameTx) department() string {
	_, department := tx.me.metadata.placement(tx.today)
	return department
}

// currentOffice loads today's office once per transaction; nil when it does not exist.
func (tx *gameTx) currentOffice() (*Office, error) {
	if !tx.officeLoaded {
		office, err := readOffice(tx.ctx, tx.nk, tx.office())
		if err != nil {
			return nil, err
		}
		tx.loadedOffice, tx.officeLoaded = office, true
	}
	return tx.loadedOffice, nil
}

// --- Admin RPCs ----------------------------------------------------------------------

type officeRequest struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	City     string   `json:"city"`
	Networks []string `json:"networks"`
}

// clean checks the name, the city (may be empty) and the networks of an office request.
func (r officeRequest) clean() (Office, error) {
	name, err := normalizeName(r.Name)
	if err != nil {
		return Office{}, err
	}
	city := ""
	if strings.TrimSpace(r.City) != "" {
		if city, err = normalizeName(r.City); err != nil {
			return Office{}, err
		}
	}
	networks, err := normalizeNetworks(r.Networks)
	if err != nil {
		return Office{}, err
	}
	return Office{ID: r.ID, Name: name, City: city, Networks: networks}, nil
}

// rpcAdminListOffices: -> {"offices": [Office]}.
func rpcAdminListOffices(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return "", err
	}
	return encodeResponse(map[string]any{"offices": offices, "default_limits": gameContent.Rules.Limits})
}

// rpcAdminCreateOffice: {"name", "city", "networks"} -> the new office.
func rpcAdminCreateOffice(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request officeRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if request.ID != "" {
		return "", errInvalidPayload
	}
	office, err := request.clean()
	if err != nil {
		return "", err
	}
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return "", err
	}
	if officeNameTaken(offices, office.Name, "") {
		return "", errOfficeExists
	}
	if office.ID, err = newOfficeID(); err != nil {
		return "", errInternal
	}
	if err := writeOffice(ctx, nk, office, "*"); err != nil {
		logger.Error("create office %q: %v", office.Name, err)
		return "", errInternal
	}
	logger.Info("office %s created: %q", office.ID, office.Name)
	return encodeResponse(office)
}

// rpcAdminUpdateOffice: {"id", "name", "city", "networks"} -> the office. The limits stay.
func rpcAdminUpdateOffice(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request officeRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	office, err := request.clean()
	if err != nil {
		return "", err
	}
	existing, err := findOffice(ctx, nk, request.ID)
	if err != nil {
		return "", err
	}
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return "", err
	}
	if officeNameTaken(offices, office.Name, office.ID) {
		return "", errOfficeExists
	}
	office.Limits = existing.Limits
	if err := writeOffice(ctx, nk, office, ""); err != nil {
		logger.Error("update office %s: %v", office.ID, err)
		return "", errInternal
	}
	logger.Info("office %s changed: %q, networks %v", office.ID, office.Name, office.Networks)
	return encodeResponse(office)
}
