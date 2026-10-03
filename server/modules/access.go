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
)

// accountMetadata: the role, the home office and department, and a business trip. Accounts made
// before offices existed have no office: they belong to the default office (game_rules.json).
type accountMetadata struct {
	Role         string `json:"role,omitempty"`
	OfficeID     string `json:"office,omitempty"`
	DepartmentID string `json:"department,omitempty"`
	Trip         *Trip  `json:"trip,omitempty"`
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
	return result
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

// placement: the office and department the player counts in on `today`.
func (m accountMetadata) placement(today int) (string, string) {
	if m.onTrip(today) {
		return m.Trip.OfficeID, m.Trip.DepartmentID
	}
	return m.homeOffice(), m.DepartmentID
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
