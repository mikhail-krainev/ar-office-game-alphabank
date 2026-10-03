package main

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	"golang.org/x/crypto/bcrypt"
)

// Admin RPCs for player accounts. An account exists only after the admin creates it; creating it
// is the activation. A banned account cannot sign in until it is unbanned. Every player has a home
// office and a department of that office; a business trip moves them to another office and
// department until its end date.

type userView struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	DisplayName  string    `json:"display_name"`
	Role         string    `json:"role"`
	OfficeID     string    `json:"office_id"`
	DepartmentID string    `json:"department_id"`
	Trip         *tripView `json:"trip"`
	Banned       bool      `json:"banned"`
	CreatedAt    int64     `json:"created_at"`
}

// tripView: a business trip that has not ended yet (an ended one is not shown).
type tripView struct {
	OfficeID     string `json:"office_id"`
	DepartmentID string `json:"department_id"`
	// Last day of the trip, "YYYY-MM-DD".
	Until  string `json:"until"`
	Active bool   `json:"active"`
}

const tripDateLayout = "2006-01-02"

// tripOf: the trip of the account, nil when there is none or it has ended by `today`.
func tripOf(metadata accountMetadata, today int) *tripView {
	if !metadata.onTrip(today) {
		return nil
	}
	return &tripView{
		OfficeID: metadata.Trip.OfficeID, DepartmentID: metadata.Trip.DepartmentID,
		Until: dateOf(metadata.Trip.Until).Format(tripDateLayout), Active: true,
	}
}

// parseTripDate: "YYYY-MM-DD" -> office day number.
func parseTripDate(text string) (int, bool) {
	date, err := time.Parse(tripDateLayout, text)
	if err != nil {
		return 0, false
	}
	return dayFromDate(date.Year(), date.Month(), date.Day()), true
}

// validTripEnd: a trip ends today or later, within a year.
func validTripEnd(until, today int) bool {
	return until >= today && until-today <= maxTripDays
}

func officeToday() int {
	return dayOf(time.Now().Unix(), gameContent.officeOffset())
}

// rpcAdminListUsers: -> {"users": [userView]}, newest first.
func rpcAdminListUsers(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	rows, err := db.QueryContext(ctx, `
		SELECT id, username, display_name, metadata, disable_time, create_time
		FROM users WHERE id <> $1 ORDER BY create_time DESC`, systemUserID)
	if err != nil {
		logger.Error("list users: %v", err)
		return "", errInternal
	}
	defer rows.Close()
	users := []userView{}
	for rows.Next() {
		var (
			user        userView
			displayName sql.NullString
			metadata    string
			disabled    time.Time
			created     time.Time
		)
		if err := rows.Scan(&user.ID, &user.Username, &displayName, &metadata, &disabled, &created); err != nil {
			logger.Error("scan user: %v", err)
			return "", errInternal
		}
		parsed := parseMetadata(metadata)
		user.DisplayName = displayName.String
		user.Role = parsed.Role
		user.DepartmentID = parsed.DepartmentID
		if parsed.Role == rolePlayer {
			user.OfficeID = parsed.homeOffice()
			user.Trip = tripOf(parsed, officeToday())
		}
		user.Banned = disabled.Unix() > 0
		user.CreatedAt = created.Unix()
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		logger.Error("list users: %v", err)
		return "", errInternal
	}
	return encodeResponse(map[string]any{"users": users})
}

// rpcAdminCreateUser: {"username", "password", "display_name", "office_id", "department_id"} -> userView.
func rpcAdminCreateUser(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		Username     string `json:"username"`
		Password     string `json:"password"`
		DisplayName  string `json:"display_name"`
		OfficeID     string `json:"office_id"`
		DepartmentID string `json:"department_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	username := normalizeUsername(request.Username)
	if err := validateUsername(username); err != nil {
		return "", err
	}
	if err := validatePassword(request.Password); err != nil {
		return "", err
	}
	displayName, err := normalizeName(request.DisplayName)
	if err != nil {
		return "", err
	}
	if _, err := findOffice(ctx, nk, request.OfficeID); err != nil {
		return "", err
	}
	department, err := findOfficeDepartment(ctx, nk, request.OfficeID, request.DepartmentID)
	if err != nil {
		return "", err
	}
	if existing, err := nk.UsersGetUsername(ctx, []string{username}); err != nil {
		return "", errInternal
	} else if len(existing) > 0 {
		return "", errUsernameTaken
	}
	userID, _, created, err := nk.AuthenticateEmail(ctx, playerEmail(username), request.Password, username, true)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "username") {
			return "", errUsernameTaken
		}
		logger.Error("create user %q: %v", username, err)
		return "", errInternal
	}
	if !created {
		return "", errUsernameTaken
	}
	metadata := accountMetadata{Role: rolePlayer, OfficeID: request.OfficeID, DepartmentID: department.ID}
	if err := nk.AccountUpdateId(ctx, userID, "", metadata.toMap(), displayName, "", "", "", ""); err != nil {
		logger.Error("set up user %s: %v", userID, err)
		// A half-made account without a department must not stay.
		if deleteErr := nk.AccountDeleteId(ctx, userID, false); deleteErr != nil {
			logger.Error("delete half-made user %s: %v", userID, deleteErr)
		}
		return "", errInternal
	}
	logger.Info("user %s (%s) created in office %s, department %s", userID, username, request.OfficeID, department.ID)
	return encodeResponse(userView{
		ID: userID, Username: username, DisplayName: displayName, Role: rolePlayer,
		OfficeID: request.OfficeID, DepartmentID: department.ID, CreatedAt: time.Now().Unix(),
	})
}

// rpcAdminUpdateUser: {"user_id", "display_name"?, "office_id"?, "department_id"?} -> {}. A new
// home office needs a department of that office.
func rpcAdminUpdateUser(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID       string `json:"user_id"`
		DisplayName  string `json:"display_name"`
		OfficeID     string `json:"office_id"`
		DepartmentID string `json:"department_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	metadata, err := playerMetadata(ctx, nk, request.UserID)
	if err != nil {
		return "", err
	}
	displayName := ""
	if request.DisplayName != "" {
		if displayName, err = normalizeName(request.DisplayName); err != nil {
			return "", err
		}
	}
	if request.OfficeID != "" || request.DepartmentID != "" {
		office, department := metadata.homeOffice(), metadata.DepartmentID
		if request.OfficeID != "" {
			office = request.OfficeID
		}
		if request.DepartmentID != "" {
			department = request.DepartmentID
		}
		if _, err := findOffice(ctx, nk, office); err != nil {
			return "", err
		}
		if _, err := findOfficeDepartment(ctx, nk, office, department); err != nil {
			return "", err
		}
		metadata.OfficeID, metadata.DepartmentID = office, department
	}
	if err := nk.AccountUpdateId(ctx, request.UserID, "", metadata.toMap(), displayName, "", "", "", ""); err != nil {
		logger.Error("update user %s: %v", request.UserID, err)
		return "", errInternal
	}
	return "{}", nil
}

// rpcAdminSetTrip: {"user_id", "office_id", "department_id", "until"} -> {"trip"}. Sends the player
// on a business trip until "until" ("YYYY-MM-DD", inclusive): in that office and department they
// check in, meet colleagues and follow its limits. Empty "office_id" ends the trip now.
func rpcAdminSetTrip(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID       string `json:"user_id"`
		OfficeID     string `json:"office_id"`
		DepartmentID string `json:"department_id"`
		Until        string `json:"until"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	metadata, err := playerMetadata(ctx, nk, request.UserID)
	if err != nil {
		return "", err
	}
	today := officeToday()
	if request.OfficeID == "" {
		metadata.Trip = nil
	} else {
		until, ok := parseTripDate(request.Until)
		if !ok || !validTripEnd(until, today) || request.OfficeID == metadata.homeOffice() {
			return "", errInvalidTrip
		}
		if _, err := findOffice(ctx, nk, request.OfficeID); err != nil {
			return "", err
		}
		if _, err := findOfficeDepartment(ctx, nk, request.OfficeID, request.DepartmentID); err != nil {
			return "", err
		}
		metadata.Trip = &Trip{OfficeID: request.OfficeID, DepartmentID: request.DepartmentID, Until: until}
	}
	if err := nk.AccountUpdateId(ctx, request.UserID, "", metadata.toMap(), "", "", "", "", ""); err != nil {
		logger.Error("set trip of %s: %v", request.UserID, err)
		return "", errInternal
	}
	if metadata.Trip == nil {
		logger.Info("trip of %s ended", request.UserID)
	} else {
		logger.Info("user %s on a trip to office %s, department %s, until %s", request.UserID, request.OfficeID, request.DepartmentID, request.Until)
	}
	return encodeResponse(map[string]any{"trip": tripOf(metadata, today)})
}

// rpcAdminSetPassword: {"user_id", "password"} -> {}. Signs the user out everywhere.
func rpcAdminSetPassword(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID   string `json:"user_id"`
		Password string `json:"password"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if _, err := playerMetadata(ctx, nk, request.UserID); err != nil {
		return "", err
	}
	if err := validatePassword(request.Password); err != nil {
		return "", err
	}
	if err := setPassword(ctx, db, request.UserID, request.Password); err != nil {
		logger.Error("set password of %s: %v", request.UserID, err)
		return "", errInternal
	}
	if err := nk.SessionLogout(request.UserID, "", ""); err != nil {
		logger.Warn("sign out %s after password change: %v", request.UserID, err)
	}
	return "{}", nil
}

// rpcAdminSetBanned: {"user_id", "banned"} -> {}. A ban also ends the user's sessions.
// The ban is first written to the game state, so a game RPC already running for the player fails
// its version check and is refused on retry. An unban keeps all progress and excuses the workdays
// of the ban, so the player is not fined and keeps the streak; the player signs in again.
func rpcAdminSetBanned(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID string `json:"user_id"`
		Banned bool   `json:"banned"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if _, err := playerMetadata(ctx, nk, request.UserID); err != nil {
		return "", err
	}
	if request.Banned {
		return banPlayer(ctx, logger, db, nk, request.UserID)
	}
	return unbanPlayer(ctx, logger, db, nk, request.UserID)
}

func banPlayer(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, userID string) (string, error) {
	if _, err := setBannedAt(ctx, logger, db, nk, userID, true); err != nil {
		return "", err
	}
	if err := nk.UsersBanId(ctx, []string{userID}); err != nil {
		logger.Error("ban %s: %v", userID, err)
		// The game must not stay blocked while the account looks active in the panel.
		if _, undoErr := setBannedAt(ctx, logger, db, nk, userID, false); undoErr != nil {
			logger.Error("undo game ban of %s: %v", userID, undoErr)
		}
		return "", errInternal
	}
	return "{}", nil
}

// unbanPlayer clears the game ban before the account ban: until the account is unbanned the player
// cannot sign in, and the account's disable_time still gives the ban start if this call is retried.
func unbanPlayer(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, userID string) (string, error) {
	if _, err := setBannedAt(ctx, logger, db, nk, userID, false); err != nil {
		return "", err
	}
	if err := nk.UsersUnbanId(ctx, []string{userID}); err != nil {
		logger.Error("unban %s: %v", userID, err)
		return "", errInternal
	}
	return "{}", nil
}

// setBannedAt records the ban in the player's game state or, on unban, clears it and excuses the
// workdays from the ban day up to yesterday.
func setBannedAt(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, userID string, banned bool) (string, error) {
	return runUserTx(ctx, logger, db, nk, userID, func(tx *gameTx) (any, error) {
		state := tx.me.state
		if banned {
			if state.BannedAt == 0 {
				state.BannedAt = tx.now
			}
			return nil, nil
		}
		if start := tx.me.banStart(); start > 0 {
			excuseDays(state, dayOf(start, tx.offset), tx.today)
		}
		state.BannedAt = 0
		return nil, nil
	})
}

// playerMetadata loads a player account for an admin action. Admin accounts are managed only
// through the server environment.
func playerMetadata(ctx context.Context, nk runtime.NakamaModule, userID string) (accountMetadata, error) {
	if userID == "" || userID == systemUserID {
		return accountMetadata{}, errUserNotFound
	}
	account, err := nk.AccountGetId(ctx, userID)
	if err != nil {
		return accountMetadata{}, errUserNotFound
	}
	metadata := parseMetadata(account.GetUser().GetMetadata())
	if metadata.Role == roleAdmin {
		return accountMetadata{}, errAdminProtected
	}
	metadata.Role = rolePlayer
	return metadata, nil
}

// setPassword replaces the password hash. Nakama has no runtime call for it; it stores bcrypt
// hashes in users.password.
func setPassword(ctx context.Context, db *sql.DB, userID, password string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `UPDATE users SET password = $1, update_time = now() WHERE id = $2`, hash, userID)
	return err
}
