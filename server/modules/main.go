// Package main is the Office Game module for Nakama: accounts created by the admin, offices, departments
// and every game rule (presence, tasks, coins, shop, colleagues, the parking draw). The client only
// sends actions; this module checks them and changes the state.
package main

import (
	"context"
	"database/sql"
	"errors"

	"github.com/heroiclabs/nakama-common/runtime"
)

const (
	defaultContentDir    = "/nakama/data/content"
	minPresenceSecretLen = 16
)

var (
	gameContent *Content
	// DEV_MODE=true: dev RPCs and the per-player dev clock. Never on a real server.
	devMode bool
	// Signs the office entry and exit codes; only the server knows it.
	presenceSecret string
)

type rpcFunc = func(context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule, string) (string, error)

func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	env, _ := ctx.Value(runtime.RUNTIME_CTX_ENV).(map[string]string)
	contentDir := env["CONTENT_DIR"]
	if contentDir == "" {
		contentDir = defaultContentDir
	}
	var err error
	if gameContent, err = loadContent(contentDir); err != nil {
		return err
	}
	presenceSecret = env["PRESENCE_SECRET"]
	if len(presenceSecret) < minPresenceSecretLen {
		return errors.New("set PRESENCE_SECRET (16+ characters)")
	}
	devMode = env["DEV_MODE"] == "true"
	// OFFICE_NETWORKS only seeds the network of the default office; the admin edits offices in the panel.
	if _, err := parseOfficeNetworks(env["OFFICE_NETWORKS"]); err != nil {
		return err
	}
	if err := registerAuthHooks(initializer); err != nil {
		return err
	}
	rpcs := map[string]rpcFunc{
		// Account and admin: from anywhere.
		"get_profile":             rpcGetProfile,
		"list_departments":        rpcListDepartments,
		"admin_list_offices":      rpcAdminListOffices,
		"admin_create_office":     rpcAdminCreateOffice,
		"admin_update_office":     rpcAdminUpdateOffice,
		"admin_create_department": rpcAdminCreateDepartment,
		"admin_rename_department": rpcAdminRenameDepartment,
		"admin_list_users":        rpcAdminListUsers,
		"admin_create_user":       rpcAdminCreateUser,
		"admin_update_user":       rpcAdminUpdateUser,
		"admin_set_password":      rpcAdminSetPassword,
		"admin_set_banned":        rpcAdminSetBanned,
		"admin_set_trip":          rpcAdminSetTrip,
		"admin_stats_overview":    rpcAdminStatsOverview,
		"admin_player_stats":      rpcAdminPlayerStats,
		"admin_get_limits":        rpcAdminGetLimits,
		"admin_set_limits":        rpcAdminSetLimits,
		// Game: only from the office network (officeOnly below), except the ones in anywhereRpcs.
		"login":                 rpcLogin,
		"get_my_profile":        rpcGetMyProfile,
		"list_tasks":            rpcListTasks,
		"complete_task":         rpcCompleteTask,
		"skip_task":             rpcSkipTask,
		"office_check_in":       rpcOfficeCheckIn,
		"office_check_out":      rpcOfficeCheckOut,
		"enter_room":            rpcEnterRoom,
		"kiosk_codes":           rpcKioskCodes,
		"get_shop":              rpcGetShop,
		"buy":                   rpcBuy,
		"get_wardrobe":          rpcGetWardrobe,
		"save_outfit":           rpcSaveOutfit,
		"get_garage":            rpcGetGarage,
		"buy_car":               rpcBuyCar,
		"select_car":            rpcSelectCar,
		"get_notification_plan": rpcGetNotificationPlan,
		"assign_colleague":      rpcAssignColleague,
		"lookup_colleague":      rpcLookupColleague,
		"get_inbox":             rpcGetInbox,
		"mark_inbox_read":       rpcMarkInboxRead,
		"respond_photo_request": rpcRespondPhotoRequest,
		"get_profile_page":      rpcGetProfilePage,
		"set_status":            rpcSetStatus,
		"set_avatar":            rpcSetAvatar,
		"upload_avatar":         rpcUploadAvatar,
		"get_avatar":            rpcGetAvatar,
		"get_raffle":            rpcGetRaffle,
		"buy_raffle_ticket":     rpcBuyRaffleTicket,
		"play_heartbeat":        rpcPlayHeartbeat,
		"play_rest":             rpcPlayRest,
	}
	for id, fn := range rpcs {
		if gameRpc(id) {
			fn = officeOnly(fn)
		}
		if err := initializer.RegisterRpc(id, fn); err != nil {
			return err
		}
	}
	if devMode {
		logger.Warn("DEV_MODE is on: dev RPCs and the dev clock are enabled")
		if err := registerDevRpcs(initializer); err != nil {
			return err
		}
	}
	if err := seedDepartments(ctx, nk); err != nil {
		return err
	}
	if err := seedOffices(ctx, logger, nk, env["OFFICE_NETWORKS"]); err != nil {
		return err
	}
	if err := ensureAdmin(ctx, logger, db, nk); err != nil {
		return err
	}
	logger.Info("office game module loaded")
	return nil
}

// ensureAdmin creates the admin panel account from ADMIN_USERNAME / ADMIN_PASSWORD, or resets its
// password to the configured one, so the environment is the only source of the admin credentials.
func ensureAdmin(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule) error {
	env, _ := ctx.Value(runtime.RUNTIME_CTX_ENV).(map[string]string)
	username := normalizeUsername(env["ADMIN_USERNAME"])
	password := env["ADMIN_PASSWORD"]
	if validateUsername(username) != nil || validatePassword(password) != nil {
		return errors.New("set ADMIN_USERNAME (3-32 of a-z 0-9 . _ -) and ADMIN_PASSWORD (8+ characters)")
	}
	users, err := nk.UsersGetUsername(ctx, []string{username})
	if err != nil {
		return err
	}
	var userID string
	if len(users) == 0 {
		if userID, _, _, err = nk.AuthenticateEmail(ctx, adminEmail(username), password, username, true); err != nil {
			return err
		}
		logger.Info("admin account %q created", username)
	} else {
		userID = users[0].GetId()
		if parseMetadata(users[0].GetMetadata()).Role == rolePlayer {
			return errors.New("ADMIN_USERNAME belongs to a player account")
		}
		if err := setPassword(ctx, db, userID, password); err != nil {
			return err
		}
	}
	metadata := accountMetadata{Role: roleAdmin}
	return nk.AccountUpdateId(ctx, userID, "", metadata.toMap(), "Администратор", "", "", "", "")
}
