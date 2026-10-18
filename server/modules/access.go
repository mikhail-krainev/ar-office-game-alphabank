package main

import (
	"context"
	"encoding/json"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

// Roles live in the account metadata, which only the server can write.
const (
	roleAdmin  = "admin"
	rolePlayer = "player"
	// A department head: sees the statistics of the offices and departments the admin gave them
	// and, when allowed, creates and deletes players there (managers.go). Never plays.
	roleManager = "manager"
	// A player account being deleted (managers.go: deletePlayer); every RPC refuses it.
	roleRemoved = "removed"
)

// accountMetadata: the role, the home office and department, a business trip, an office visit found
// by its network and, for a manager, the access scope. Accounts made before offices existed have no
// office: they belong to the default office (game_rules.json).
type accountMetadata struct {
	Role         string        `json:"role,omitempty"`
	OfficeID     string        `json:"office,omitempty"`
	DepartmentID string        `json:"department,omitempty"`
	Trip         *Trip         `json:"trip,omitempty"`
	Visit        *Visit        `json:"visit,omitempty"`
	Manager      *ManagerScope `json:"manager,omitempty"`
}

// Visit: an office the player came to without a business trip, found by the network of the request
// (network.go: followOfficeNetwork). It lasts only for its day: tasks, the entry code and colleagues
// follow that office, the statistics and the parking draw stay with the home office.
type Visit struct {
	OfficeID string `json:"office"`
	Day      int    `json:"day"`
}

// ManagerScope: what a manager may see and do. A whole office covers all its departments, also
// the ones created later. The admin changes the scope and the rights at any time.
type ManagerScope struct {
	Offices     []string `json:"offices"`
	Departments []string `json:"departments"`
	CanCreate   bool     `json:"can_create"`
	CanDelete   bool     `json:"can_delete"`
}

// covers: a player of this home office and department is in the scope.
func (s ManagerScope) covers(officeID, departmentID string) bool {
	return contains(s.Offices, officeID) || (departmentID != "" && contains(s.Departments, departmentID))
}

// Trip: a business trip. Until the end day (inclusive, office day number) the player counts in the
// trip office and department: presence, colleagues, the network and the limits follow them. The
// parking draw and the statistics stay with the home office.
type Trip struct {
	OfficeID     string `json:"office"`
	DepartmentID string `json:"department"`
	Until        int    `json:"until"`
}

func (m accountMetadata) toMap() map[string]any {
	result := map[string]any{"role": m.Role}
	if m.OfficeID != "" {
		result["office"] = m.OfficeID
	}
	if m.DepartmentID != "" {
		result["department"] = m.DepartmentID
	}
	if m.Trip != nil {
		result["trip"] = map[string]any{"office": m.Trip.OfficeID, "department": m.Trip.DepartmentID, "until": m.Trip.Until}
	}
	if m.Visit != nil {
		result["visit"] = map[string]any{"office": m.Visit.OfficeID, "day": m.Visit.Day}
	}
	if m.Manager != nil {
		result["manager"] = map[string]any{
			"offices": nonNil(m.Manager.Offices), "departments": nonNil(m.Manager.Departments),
			"can_create": m.Manager.CanCreate, "can_delete": m.Manager.CanDelete,
		}
	}
	return result
}

func nonNil(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

// homeOffice: the office the admin gave the player.
func (m accountMetadata) homeOffice() string {
	if m.OfficeID == "" {
		return defaultOfficeID()
	}
	return m.OfficeID
}

// onTrip: a business trip covers `today`.
func (m accountMetadata) onTrip(today int) bool {
	return m.Trip != nil && today <= m.Trip.Until
}

// plannedPlacement: the office and department the admin set for `today`: the trip or the home.
func (m accountMetadata) plannedPlacement(today int) (string, string) {
	if m.onTrip(today) {
		return m.Trip.OfficeID, m.Trip.DepartmentID
	}
	return m.homeOffice(), m.DepartmentID
}

// visitOn: the office visit found by the network on `today`, or nil.
func (m accountMetadata) visitOn(today int) *Visit {
	if m.Visit == nil || m.Visit.Day != today {
		return nil
	}
	return m.Visit
}

// placement: the office and department the player counts in on `today`. An office found by its
// network wins over the plan: a player who flew to another city without a trip plays there with
// the home department; one on a trip who came back home plays at home.
func (m accountMetadata) placement(today int) (string, string) {
	office, department := m.plannedPlacement(today)
	visit := m.visitOn(today)
	if visit == nil || visit.OfficeID == office {
		return office, department
	}
	return visit.OfficeID, m.DepartmentID
}

// guestOffice: the office the player is visiting today without a trip, or "".
func (m accountMetadata) guestOffice(today int) string {
	office, _ := m.placement(today)
	if planned, _ := m.plannedPlacement(today); office == planned {
		return ""
	}
	return office
}

func parseMetadata(raw string) accountMetadata {
	var metadata accountMetadata
	if raw != "" {
		// Malformed metadata means no role, which denies access.
		_ = json.Unmarshal([]byte(raw), &metadata)
	}
	return metadata
}

func callerID(ctx context.Context) (string, error) {
	userID, _ := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if userID == "" {
		return "", errUnauthenticated
	}
	return userID, nil
}

func callerAccount(ctx context.Context, nk runtime.NakamaModule) (*api.Account, accountMetadata, error) {
	userID, err := callerID(ctx)
	if err != nil {
		return nil, accountMetadata{}, err
	}
	account, err := nk.AccountGetId(ctx, userID)
	if err != nil {
		return nil, accountMetadata{}, errUnauthenticated
	}
	return account, parseMetadata(account.GetUser().GetMetadata()), nil
}

// requireAdmin: the caller is the main admin. Managers are refused: their panel calls only the
// manager_* RPCs, which check the scope.
func requireAdmin(ctx context.Context, nk runtime.NakamaModule) error {
	_, metadata, err := callerAccount(ctx, nk)
	if err != nil {
		return err
	}
	if metadata.Role != roleAdmin {
		return errNotAdmin
	}
	return nil
}
