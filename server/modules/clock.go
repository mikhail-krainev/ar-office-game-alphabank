package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"sync/atomic"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Test clock: with TEST_CLOCK=true the admin moves the game time of every player forward from the
// panel, to check days, streaks, fines and statistics in a few minutes. The shift is one number of
// seconds in settings/clock. The rotating office codes and sessions keep the real clock, so the codes
// on the office screen stay valid. Never enable on a real server.

const (
	clockKey = "clock"
	// The admin can move the game up to a year ahead.
	maxClockShiftSeconds = 366 * secondsPerDay
)

var (
	testClock bool
	// Seconds added to the real time; read from storage at start, changed only by admin_set_clock.
	clockShift atomic.Int64
)

type clockSettings struct {
	ShiftSeconds int64 `json:"shift_seconds"`
}

// gameNow: the time every game rule uses (the real time plus the test clock shift).
func gameNow() int64 {
	now := time.Now().Unix()
	if testClock {
		now += clockShift.Load()
	}
	return now
}

func loadClock(ctx context.Context, nk runtime.NakamaModule) error {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: settingsCollection, Key: clockKey, UserID: systemUserID}})
	if err != nil {
		return err
	}
	if len(objects) > 0 {
		var settings clockSettings
		if json.Unmarshal([]byte(objects[0].GetValue()), &settings) == nil {
			clockShift.Store(settings.ShiftSeconds)
		}
	}
	return nil
}

type clockView struct {
	Enabled          bool  `json:"enabled"`
	ShiftSeconds     int64 `json:"shift_seconds"`
	Now              int64 `json:"now"`
	UTCOffsetMinutes int64 `json:"utc_offset_minutes"`
	MaxShiftSeconds  int64 `json:"max_shift_seconds"`
}

func currentClockView() clockView {
	view := clockView{Enabled: testClock, Now: gameNow(), UTCOffsetMinutes: gameContent.officeOffset() / 60, MaxShiftSeconds: maxClockShiftSeconds}
	if testClock {
		view.ShiftSeconds = clockShift.Load()
	}
	return view
}

// rpcAdminGetClock: -> clockView. "enabled" is false without TEST_CLOCK=true.
func rpcAdminGetClock(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	return encodeResponse(currentClockView())
}

var errClockDisabled = runtime.NewError("test_clock_disabled", codeFailedPrecondition)

// rpcAdminSetClock: {"shift_seconds"} -> clockView. 0 returns the game to the real time.
func rpcAdminSetClock(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	if !testClock {
		return "", errClockDisabled
	}
	var request clockSettings
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if request.ShiftSeconds < 0 || request.ShiftSeconds > maxClockShiftSeconds {
		return "", errInvalidPayload
	}
	data, err := json.Marshal(request)
	if err != nil {
		return "", errInternal
	}
	write := &runtime.StorageWrite{Collection: settingsCollection, Key: clockKey, UserID: systemUserID, Value: string(data)}
	if _, err := nk.StorageWrite(ctx, []*runtime.StorageWrite{write}); err != nil {
		logger.Error("save test clock: %v", err)
		return "", errInternal
	}
	clockShift.Store(request.ShiftSeconds)
	logger.Warn("test clock shift set to %d s", request.ShiftSeconds)
	return encodeResponse(currentClockView())
}
