package main

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"strconv"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// "My QR": the code a player shows a colleague in the meet-a-colleague tasks. It rotates every
// colleagueCodePeriodSeconds and is signed with the server secret, so a screenshot sent to someone
// outside the room stops working within seconds: the colleague has to scan it from the player's
// phone. A fresh scan is remembered for the day (PlayerState.Scanned), and only scanned colleagues
// count in the tasks, so a bingo card can be filled over hours.

const (
	colleagueCodePeriodSeconds = 10
	// The previous step is accepted too: a code scanned right before rotation still works, and a
	// code never lives longer than two periods.
	colleagueCodeAcceptedPastSteps = 1
	purposeColleague               = "user"
)

func colleagueCodeStep(unix int64) int64 {
	return floorDiv(unix, colleagueCodePeriodSeconds)
}

// colleagueCode: "<user id>.<step>.<signature>", signed like the office codes with its own purpose.
func colleagueCode(secret, userID string, step int64) string {
	return presenceToken(secret, purposeColleague, userID, step)
}

// verifyColleagueCode returns the user id behind a code, or the error key. `now` is the real clock.
func verifyColleagueCode(secret, code string, now int64) (string, string) {
	parts := strings.Split(code, ".")
	if len(parts) != 3 || !isUUID(parts[0]) {
		return "", "colleague_invalid"
	}
	step, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return "", "colleague_invalid"
	}
	expected := presenceSignature(secret, purposeColleague, parts[0]+"."+parts[1])
	if subtle.ConstantTimeCompare([]byte(expected), []byte(parts[2])) != 1 {
		return "", "colleague_invalid"
	}
	current := colleagueCodeStep(now)
	if step > current || step < current-colleagueCodeAcceptedPastSteps {
		return "", "colleague_code_expired"
	}
	return parts[0], ""
}

// rpcMyColleagueCode -> {"code", "expires_in"}: the caller's current "My QR" code and the seconds
// until it rotates. Read-only, so the phone may ask for it every few seconds.
func rpcMyColleagueCode(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	account, metadata, err := callerAccount(ctx, nk)
	if err != nil {
		return "", err
	}
	if metadata.Role != rolePlayer {
		return "", errNotPlayer
	}
	now := time.Now().Unix()
	step := colleagueCodeStep(now)
	return encodeResponse(map[string]any{
		"code":       colleagueCode(presenceSecret, account.GetUser().GetId(), step),
		"expires_in": (step+1)*colleagueCodePeriodSeconds - now,
	})
}

// rememberScan: the player scanned this colleague's live code today.
func (tx *gameTx) rememberScan(userID string) {
	state := tx.me.state
	if state.ScannedDay != tx.today {
		state.ScannedDay = tx.today
		state.Scanned = nil
	}
	if !contains(state.Scanned, userID) {
		state.Scanned = append(state.Scanned, userID)
	}
}

func (tx *gameTx) wasScanned(userID string) bool {
	return tx.me.state.ScannedDay == tx.today && contains(tx.me.state.Scanned, userID)
}
