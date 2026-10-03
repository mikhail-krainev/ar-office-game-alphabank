package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"image/png"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/heroiclabs/nakama-common/runtime"
)

// The player's own account: the daily login (welcome bonus, absence fines), the profile page with
// the attendance calendar, the status and the avatar.

const (
	maxStatusLength   = 60
	avatarMaxBytes    = 64 * 1024
	avatarSide        = 64
	calendarWeeks     = 18
	avatarCollection  = "avatar"
	avatarKey         = "custom"
	permissionPublic  = 2
	dayBeforeFirstDay = 1
)

// tick runs what depends only on time passing: absence fines, expired photo requests, the draw.
func (tx *gameTx) tick() error {
	if err := tx.processAbsences(); err != nil {
		return err
	}
	if err := tx.expirePhotoRequests(); err != nil {
		return err
	}
	return tx.runDueDraw()
}

// processAbsences fines every workday missed in a row since the last run: the first missed day
// only breaks the streak, later ones take a growing share of the balance.
func (tx *gameTx) processAbsences() error {
	state := tx.me.state
	if state.FirstDay == 0 {
		return nil
	}
	attendance := tx.content.Rules.Attendance
	start := max(state.ProcessedDay+1, state.FirstDay, tx.today-attendance.MaxCatchUpDays)
	for day := start; day < tx.today; day++ {
		key := dayKey(day)
		if !isWorkday(day) || state.PresenceDays[key] || state.ExcusedDays[key] {
			continue
		}
		missed := missedInRow(state.PresenceDays, state.ExcusedDays, day, state.FirstDay)
		if missed == 1 {
			if lost := streak(state.PresenceDays, state.ExcusedDays, day-1, state.FirstDay); lost > 0 {
				if _, err := tx.notify(tx.me, "streak_reset", map[string]any{"streak": lost, "date": shortDate(day)}, ""); err != nil {
					return err
				}
				state.MorningReport.LostStreak = max(state.MorningReport.LostStreak, lost)
			}
		}
		percent := finePercent(missed, attendance.FineTiers)
		if amount := fineAmount(tx.me.balance, percent); amount > 0 {
			tx.credit(tx.me, -amount, "absence_fine", "day:"+key)
			if _, err := tx.notify(tx.me, "penalty", map[string]any{"amount": amount, "missed": missed, "percent": percent, "date": shortDate(day)}, ""); err != nil {
				return err
			}
			state.MorningReport.Fined += amount
		}
	}
	if start < tx.today {
		state.ProcessedDay = tx.today - 1
	}
	return nil
}

type profileData struct {
	UserID       string            `json:"user_id"`
	DisplayName  string            `json:"display_name"`
	Department   string            `json:"department"`
	Status       string            `json:"status"`
	Avatar       string            `json:"avatar"`
	Balance      int64             `json:"balance"`
	StreakDays   int               `json:"streak_days"`
	PresentToday bool              `json:"present_today"`
	InOffice     bool              `json:"in_office"`
	Multiplier   float64           `json:"multiplier"`
	WelcomeBonus int               `json:"welcome_bonus"`
	FinedCoins   int64             `json:"fined_coins"`
	LostStreak   int               `json:"lost_streak"`
	CarID        string            `json:"car_id"`
	CarName      string            `json:"car_name"`
	CarSpeedKmh  int               `json:"car_speed_kmh"`
	Outfit       map[string]string `json:"outfit"`
}

func (tx *gameTx) profile() profileData {
	state := tx.me.state
	data := profileData{
		UserID: tx.me.userID, DisplayName: tx.me.displayName(), Department: tx.department(),
		Status: state.Status, Avatar: state.Avatar, Balance: tx.me.balance,
		StreakDays:   streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay),
		PresentToday: state.PresenceDays[dayKey(tx.today)], InOffice: tx.inMyOffice(),
		Multiplier: tx.multiplier(), CarID: state.Car, CarName: state.Car, CarSpeedKmh: 110, Outfit: state.Outfit,
	}
	if car := tx.content.car(state.Car); car != nil {
		data.CarName, data.CarSpeedKmh = car.Name, car.SpeedKmh
	}
	return data
}

// rpcLogin: the start of a game session. The first login pays the welcome bonus; the answer carries
// the fines and the lost streak since the previous login for the morning card, once.
func rpcLogin(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		state := tx.me.state
		welcome := 0
		if !state.WelcomeGiven {
			state.WelcomeGiven = true
			state.FirstDay = tx.today
			state.ProcessedDay = tx.today - dayBeforeFirstDay
			welcome = tx.content.Rules.Economy.WelcomeBonus
			tx.credit(tx.me, int64(welcome), "welcome_bonus", "welcome")
		}
		state.LastLoginDay = tx.today
		tx.logActivity(tx.me, activityLogin, nil)
		if err := tx.tick(); err != nil {
			return nil, err
		}
		data := tx.profile()
		data.WelcomeBonus = welcome
		data.FinedCoins = state.MorningReport.Fined
		data.LostStreak = state.MorningReport.LostStreak
		state.MorningReport = MorningReport{}
		return data, nil
	})
}

func rpcGetMyProfile(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		return tx.profile(), nil
	})
}

type dayRecord struct {
	Day     int            `json:"day"`
	Present bool           `json:"present"`
	Tasks   []TaskLogEntry `json:"tasks"`
	Earned  int            `json:"earned"`
}

// rpcGetProfilePage: profile, totals and the attendance calendar (whole weeks, Monday first).
func rpcGetProfilePage(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if err := tx.tick(); err != nil {
			return nil, err
		}
		state := tx.me.state
		tasksTotal := 0
		for _, done := range state.Completed {
			tasksTotal += len(done)
		}
		days := []dayRecord{}
		start := tx.today - weekday(tx.today) - (calendarWeeks-1)*7
		for day := start; day <= tx.today; day++ {
			record := dayRecord{Day: day, Present: state.PresenceDays[dayKey(day)], Tasks: state.TaskLog[dayKey(day)]}
			if record.Tasks == nil {
				record.Tasks = []TaskLogEntry{}
			}
			for _, entry := range record.Tasks {
				record.Earned += entry.Reward
			}
			days = append(days, record)
		}
		return map[string]any{
			"profile": tx.profile(), "best_streak": max(state.BestStreak, streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay)),
			"office_days_total": len(state.PresenceDays), "tasks_total": tasksTotal, "coins_earned_total": state.CoinsEarned,
			"days": days, "today": tx.today, "has_custom_avatar": state.HasCustomAvatar,
		}, nil
	})
}

// cleanStatus drops control characters and line breaks, which would break the one-line status.
func cleanStatus(text string) (string, bool) {
	var builder strings.Builder
	for _, r := range strings.TrimSpace(text) {
		if !unicode.IsControl(r) {
			builder.WriteRune(r)
		}
	}
	clean := builder.String()
	return clean, utf8.RuneCountInString(clean) <= maxStatusLength
}

// rpcSetStatus: {"text"}.
func rpcSetStatus(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Text string `json:"text"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		clean, ok := cleanStatus(request.Text)
		if !ok {
			return fail("status_too_long"), nil
		}
		tx.me.state.Status = clean
		return okResult, nil
	})
}

// rpcSetAvatar: {"avatar_id"}: a template, or "custom" for the uploaded picture.
func rpcSetAvatar(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		AvatarID string `json:"avatar_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		switch {
		case request.AvatarID == customAvatar && !tx.me.state.HasCustomAvatar:
			return fail("avatar_missing"), nil
		case request.AvatarID != customAvatar && !tx.content.isAvatarTemplate(request.AvatarID):
			return fail("unknown_avatar"), nil
		}
		tx.me.state.Avatar = request.AvatarID
		return okResult, nil
	})
}

// validAvatarPNG: a square PNG of avatarSide pixels, at most avatarMaxBytes.
func validAvatarPNG(encoded string) ([]byte, string) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) == 0 || len(data) > avatarMaxBytes {
		return nil, "avatar_too_big"
	}
	config, err := png.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width != avatarSide || config.Height != avatarSide {
		return nil, "avatar_invalid"
	}
	return data, ""
}

// rpcUploadAvatar: {"png": base64}. Other players see it through get_avatar.
func rpcUploadAvatar(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		PNG string `json:"png"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		data, problem := validAvatarPNG(request.PNG)
		if problem != "" {
			return fail(problem), nil
		}
		value, _ := json.Marshal(map[string]string{"png": base64.StdEncoding.EncodeToString(data)})
		tx.writes = append(tx.writes, &runtime.StorageWrite{
			Collection: avatarCollection, Key: avatarKey, UserID: tx.me.userID, Value: string(value),
			PermissionRead: permissionPublic, PermissionWrite: permissionNone,
		})
		tx.me.state.HasCustomAvatar = true
		tx.me.state.Avatar = customAvatar
		return okResult, nil
	})
}

// rpcGetAvatar: {"user_id"} -> {"png": base64 or ""}.
func rpcGetAvatar(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if _, err := callerID(ctx); err != nil {
		return "", err
	}
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if !isUUID(request.UserID) {
		return encodeResponse(map[string]string{"png": ""})
	}
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: avatarCollection, Key: avatarKey, UserID: request.UserID}})
	if err != nil {
		return "", errInternal
	}
	var value struct {
		PNG string `json:"png"`
	}
	if len(objects) > 0 {
		_ = json.Unmarshal([]byte(objects[0].GetValue()), &value)
	}
	return encodeResponse(value)
}
