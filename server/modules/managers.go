package main

import (
	"context"
	"database/sql"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Managers: department heads with their own panel, separate from the main admin's. The admin creates
// a manager and ticks the offices (with all their departments) and the single departments the
// manager sees; two more ticks let the manager create players there and delete them. The admin
// changes the ticks at any time. Managers call only the manager_* RPCs and the admin only the
// admin_* ones: requireAdmin refuses managers, withManager refuses the admin, and the game refuses
// both (not_player). Every manager RPC reads the scope again under a row lock (metadata_store.go),
// so a right the admin took away stops working at once, even for an action already on its way.

const (
	maxScopeOffices     = 64
	maxScopeDepartments = 256
	listManagersQuery   = `
		SELECT id, username, display_name, metadata, create_time
		FROM users WHERE metadata->>'role' = $1 ORDER BY create_time DESC`
)

type managerView struct {
	ID          string       `json:"id"`
	Username    string       `json:"username"`
	DisplayName string       `json:"display_name"`
	Scope       ManagerScope `json:"scope"`
	CreatedAt   int64        `json:"created_at"`
}

// scopeRequest: the ticks of the admin's manager form.
type scopeRequest struct {
	Offices     []string `json:"offices"`
	Departments []string `json:"departments"`
	CanCreate   bool     `json:"can_create"`
	CanDelete   bool     `json:"can_delete"`
}

// buildScope checks the ticked offices and departments against the existing ones and drops
// repeats. A manager without any office or department sees nothing, so the scope must not be empty.
func buildScope(request scopeRequest, offices []Office, departments []Department) (ManagerScope, error) {
	if len(request.Offices) > maxScopeOffices || len(request.Departments) > maxScopeDepartments {
		return ManagerScope{}, errInvalidScope
	}
	knownOffices := map[string]bool{}
	for _, office := range offices {
		knownOffices[office.ID] = true
	}
	knownDepartments := map[string]bool{}
	for _, department := range departments {
		knownDepartments[department.ID] = true
	}
	scope := ManagerScope{Offices: []string{}, Departments: []string{}, CanCreate: request.CanCreate, CanDelete: request.CanDelete}
	for _, id := range request.Offices {
		if !knownOffices[id] {
			return ManagerScope{}, errOfficeNotFound
		}
		if !contains(scope.Offices, id) {
			scope.Offices = append(scope.Offices, id)
		}
	}
	for _, id := range request.Departments {
		if !knownDepartments[id] {
			return ManagerScope{}, errDepartmentNotFound
		}
		if !contains(scope.Departments, id) {
			scope.Departments = append(scope.Departments, id)
		}
	}
	if len(scope.Offices) == 0 && len(scope.Departments) == 0 {
		return ManagerScope{}, errInvalidScope
	}
	return scope, nil
}

func loadScope(ctx context.Context, nk runtime.NakamaModule, request scopeRequest) (ManagerScope, error) {
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return ManagerScope{}, err
	}
	departments, err := listDepartments(ctx, nk)
	if err != nil {
		return ManagerScope{}, err
	}
	return buildScope(request, offices, departments)
}

// --- Admin RPCs ----------------------------------------------------------------------

// rpcAdminListManagers: -> {"managers": [managerView]}, newest first.
func rpcAdminListManagers(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	rows, err := db.QueryContext(ctx, listManagersQuery, roleManager)
	if err != nil {
		logger.Error("list managers: %v", err)
		return "", errInternal
	}
	defer func() { _ = rows.Close() }()
	managers := []managerView{}
	for rows.Next() {
		var (
			manager     managerView
			displayName sql.NullString
			metadata    string
			created     time.Time
		)
		if err := rows.Scan(&manager.ID, &manager.Username, &displayName, &metadata, &created); err != nil {
			logger.Error("scan manager: %v", err)
			return "", errInternal
		}
		manager.DisplayName = displayName.String
		manager.CreatedAt = created.Unix()
		if scope := parseMetadata(metadata).Manager; scope != nil {
			manager.Scope = *scope
		}
		manager.Scope.Offices, manager.Scope.Departments = nonNil(manager.Scope.Offices), nonNil(manager.Scope.Departments)
		managers = append(managers, manager)
	}
	if err := rows.Err(); err != nil {
		logger.Error("list managers: %v", err)
		return "", errInternal
	}
	return encodeResponse(map[string]any{"managers": managers})
}

// rpcAdminCreateManager: {"username", "password", "display_name", "scope": scopeRequest} -> managerView.
func rpcAdminCreateManager(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		Username    string       `json:"username"`
		Password    string       `json:"password"`
		DisplayName string       `json:"display_name"`
		Scope       scopeRequest `json:"scope"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	scope, err := loadScope(ctx, nk, request.Scope)
	if err != nil {
		return "", err
	}
	user, err := createAccount(ctx, logger, nk, request.Username, request.Password, request.DisplayName, accountMetadata{Role: roleManager, Manager: &scope})
	if err != nil {
		return "", err
	}
	logger.Info("manager %s (%s) created: offices %v, departments %v, create %t, delete %t",
		user.ID, user.Username, scope.Offices, scope.Departments, scope.CanCreate, scope.CanDelete)
	return encodeResponse(managerView{ID: user.ID, Username: user.Username, DisplayName: user.DisplayName, Scope: scope, CreatedAt: user.CreatedAt})
}

// rpcAdminUpdateManager: {"user_id", "scope": scopeRequest} -> {"scope"}. Replaces the offices,
// the departments and the rights; the manager's next call already follows them.
func rpcAdminUpdateManager(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID string       `json:"user_id"`
		Scope  scopeRequest `json:"scope"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	scope, err := loadScope(ctx, nk, request.Scope)
	if err != nil {
		return "", err
	}
	_, err = updateMetadata(ctx, db, request.UserID, func(metadata *accountMetadata) error {
		if metadata.Role != roleManager {
			return errUserNotFound
		}
		metadata.Manager = &scope
		return nil
	})
	if err != nil {
		return "", err
	}
	logger.Info("manager %s changed: offices %v, departments %v, create %t, delete %t",
		request.UserID, scope.Offices, scope.Departments, scope.CanCreate, scope.CanDelete)
	return encodeResponse(map[string]any{"scope": scope})
}

// rpcAdminDeleteUser: {"user_id"} -> {}. Deletes a player or a manager with all their data.
func rpcAdminDeleteUser(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	anyAccount := func(accountMetadata) error { return nil }
	if err := deleteAccount(ctx, logger, db, nk, request.UserID, anyAccount); err != nil {
		return "", err
	}
	return "{}", nil
}

// deleteAccount removes a player or a manager once `allowed` agrees. The account is first marked
// removed under the row lock: from then on every RPC refuses it and a concurrent change of the
// admin or another manager finds no account, so nobody edits a player that is being deleted.
// Then the sessions end and Nakama deletes the account and its storage and wallet.
func deleteAccount(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, userID string, allowed func(accountMetadata) error) error {
	var before accountMetadata
	_, err := updateMetadata(ctx, db, userID, func(metadata *accountMetadata) error {
		switch metadata.Role {
		case roleAdmin:
			return errAdminProtected
		case roleRemoved:
			return errUserNotFound
		}
		if err := allowed(*metadata); err != nil {
			return err
		}
		before = *metadata
		metadata.Role = roleRemoved
		return nil
	})
	if err != nil {
		return err
	}
	if err := nk.SessionLogout(userID, "", ""); err != nil {
		logger.Warn("sign out %s before deletion: %v", userID, err)
	}
	if err := nk.AccountDeleteId(ctx, userID, false); err != nil {
		logger.Error("delete user %s: %v", userID, err)
		// The account must not stay half-deleted: give it its role back.
		if _, undoErr := updateMetadata(ctx, db, userID, func(metadata *accountMetadata) error {
			*metadata = before
			return nil
		}); undoErr != nil {
			logger.Error("restore user %s after a failed deletion: %v", userID, undoErr)
		}
		return errInternal
	}
	// The "who is in the office" index is system-owned, so the account deletion leaves it.
	if err := nk.StorageDelete(ctx, []*runtime.StorageDelete{{Collection: presenceCollection, Key: userID, UserID: systemUserID}}); err != nil {
		logger.Warn("delete presence of %s: %v", userID, err)
	}
	logger.Info("user %s (%s) deleted", userID, before.Role)
	return nil
}

// --- Manager RPCs --------------------------------------------------------------------

// runManager runs `action` for the calling manager with the scope as it is now (withManager).
func runManager(ctx context.Context, db *sql.DB, action func(managerID string, scope ManagerScope) (any, error)) (string, error) {
	managerID, err := callerID(ctx)
	if err != nil {
		return "", err
	}
	return withManager(ctx, db, managerID, func(scope ManagerScope) (any, error) {
		return action(managerID, scope)
	})
}

// requireCovered: the player's home office and department are in the scope.
func requireCovered(scope ManagerScope, metadata accountMetadata) error {
	if err := playerOnly(metadata); err != nil {
		return errUserNotFound
	}
	if !scope.covers(metadata.homeOffice(), metadata.DepartmentID) {
		return errOutOfScope
	}
	return nil
}

// visibleOffices: the offices and departments of the scope, for the manager's filters and forms.
func visibleOffices(scope ManagerScope, offices []Office, departments []Department) ([]Office, []Department) {
	visibleDepartments := []Department{}
	officeSeen := map[string]bool{}
	for _, department := range departments {
		if scope.covers(department.OfficeID, department.ID) {
			visibleDepartments = append(visibleDepartments, department)
			officeSeen[department.OfficeID] = true
		}
	}
	visible := []Office{}
	for _, office := range offices {
		if officeSeen[office.ID] || contains(scope.Offices, office.ID) {
			// The networks and limits are the admin's business.
			visible = append(visible, Office{ID: office.ID, Name: office.Name, City: office.City, Networks: []string{}})
		}
	}
	return visible, visibleDepartments
}

// rpcManagerGetScope: -> {"display_name", "scope", "offices", "departments", "office_names"}: who
// the manager is and what they see. "office_names" names every office, so the panel shows where a
// player of the scope is today. The panel calls it right after signing in.
func rpcManagerGetScope(ctx context.Context, _ runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runManager(ctx, db, func(managerID string, scope ManagerScope) (any, error) {
		account, err := nk.AccountGetId(ctx, managerID)
		if err != nil {
			return nil, errUnauthenticated
		}
		offices, err := listOffices(ctx, nk)
		if err != nil {
			return nil, err
		}
		departments, err := listDepartments(ctx, nk)
		if err != nil {
			return nil, err
		}
		visible, visibleDepartments := visibleOffices(scope, offices, departments)
		names := map[string]string{}
		for _, office := range offices {
			names[office.ID] = office.Name
		}
		scope.Offices, scope.Departments = nonNil(scope.Offices), nonNil(scope.Departments)
		return map[string]any{
			"display_name": account.GetUser().GetDisplayName(), "scope": scope,
			"offices": visible, "departments": visibleDepartments, "office_names": names,
		}, nil
	})
}

// rpcManagerStatsOverview: -> {"players": [playerSummary]} of the scope's home offices and departments.
func rpcManagerStatsOverview(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runManager(ctx, db, func(managerID string, scope ManagerScope) (any, error) {
		players, _, err := loadPlayerRows(ctx, db, nk, "")
		if err != nil {
			logger.Error("manager %s stats overview: %v", managerID, err)
			return nil, errInternal
		}
		return map[string]any{"players": playersInScope(scope, players)}, nil
	})
}

func playersInScope(scope ManagerScope, players []playerSummary) []playerSummary {
	visible := []playerSummary{}
	for _, player := range players {
		if scope.covers(player.OfficeID, player.DepartmentID) {
			visible = append(visible, player)
		}
	}
	return visible
}

// rpcManagerPlayerStats: {"user_id"} -> the audit of a player of the scope (as admin_player_stats).
func rpcManagerPlayerStats(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runManager(ctx, db, func(_ string, scope ManagerScope) (any, error) {
		metadata, err := playerMetadata(ctx, nk, request.UserID)
		if err != nil {
			return nil, err
		}
		if err := requireCovered(scope, metadata); err != nil {
			return nil, err
		}
		return playerStats(ctx, logger, db, nk, request.UserID)
	})
}

// rpcManagerCreateUser: newPlayerRequest -> userView. Needs the create right and an office and
// department of the scope.
func rpcManagerCreateUser(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request newPlayerRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runManager(ctx, db, func(managerID string, scope ManagerScope) (any, error) {
		if !scope.CanCreate {
			return nil, errRightMissing
		}
		if !scope.covers(request.OfficeID, request.DepartmentID) {
			return nil, errOutOfScope
		}
		user, err := createPlayer(ctx, logger, nk, request)
		if err != nil {
			return nil, err
		}
		logger.Info("player %s created by manager %s", user.ID, managerID)
		return user, nil
	})
}

// rpcManagerDeleteUser: {"user_id"} -> {}. Needs the delete right and a player of the scope; the
// scope is checked against the player's office and department at the moment of the deletion.
func rpcManagerDeleteUser(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runManager(ctx, db, func(managerID string, scope ManagerScope) (any, error) {
		if !scope.CanDelete {
			return nil, errRightMissing
		}
		covered := func(metadata accountMetadata) error { return requireCovered(scope, metadata) }
		if err := deleteAccount(ctx, logger, db, nk, request.UserID, covered); err != nil {
			return nil, err
		}
		logger.Info("player %s deleted by manager %s", request.UserID, managerID)
		return map[string]any{}, nil
	})
}
