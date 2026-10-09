package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Presence in the office. The office screen shows two rotating codes signed with a secret that only
// the server knows: the entry code opens the "in the office" interval, the exit code closes it. The
// entry code counts once a day: it marks the first arrival, and steps out and back in during the day
// follow the office Wi-Fi (visits.go). The exit code ends the office day. Tasks, colleague meetings
// and room codes count only inside the interval; an interval left open ends with the day. Static room codes at the doors work only after the entry code. Each of these
// requests must also come from the office network (network.go). Every office has its own screen:
// the codes carry the office id, and a player counts only the codes of the office they are in today.

const (
	presencePeriodSeconds = 30
	// The previous step is accepted too, so a code scanned right before rotation still works.
	presenceAcceptedPastSteps = 1
	presenceSignatureBytes    = 10
	purposeEntry              = "in"
	purposeExit               = "out"
	maxUsedPresenceTokens     = 40
)

var roomIDPattern = regexp.MustCompile(`^[a-z0-9_]{1,40}$`)

// presenceToken: "<office>.<step>.<signature>", signature = HMAC-SHA256(secret, "<purpose>|<office>.<step>").
func presenceToken(secret, purpose, office string, step int64) string {
	message := fmt.Sprintf("%s.%d", office, step)
	return message + "." + presenceSignature(secret, purpose, message)
}

func presenceSignature(secret, purpose, message string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(purpose + "|" + message))
	return hex.EncodeToString(mac.Sum(nil)[:presenceSignatureBytes])
}

func presenceStep(unix int64) int64 {
	return floorDiv(unix, presencePeriodSeconds)
}

// verifyPresenceToken returns "" or the error key. `now` is the real clock, not the dev clock.
func verifyPresenceToken(secret, purpose, office, token string, now int64) string {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || parts[0] != office {
		return "presence_token_invalid"
	}
	step, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return "presence_token_invalid"
	}
	current := presenceStep(now)
	if step > current || step < current-presenceAcceptedPastSteps {
		return "presence_token_invalid"
	}
	expected := presenceSignature(secret, purpose, parts[0]+"."+parts[1])
	if subtle.ConstantTimeCompare([]byte(expected), []byte(parts[2])) != 1 {
		return "presence_token_invalid"
	}
	return ""
}

// presenceEntry is the public "who is in the office" index, one system object per player.
type presenceEntry struct {
	Day   int    `json:"day"`
	In    bool   `json:"in"`
	Since int64  `json:"since"`
	Room  string `json:"room"`
	// "" in entries written before offices existed: the default office.
	Office string `json:"office,omitempty"`
}

func (e presenceEntry) office() string {
	if e.Office == "" {
		return defaultOfficeID()
	}
	return e.Office
}

// inOffice: checked in today and not checked out since.
func inOffice(state *PlayerState, today int) bool {
	key := dayKey(today)
	entered, ok := state.CheckinAt[key]
	return ok && state.CheckoutAt[key] < entered
}

// presenceOffice: the office of the player's last entry code.
func presenceOffice(state *PlayerState) string {
	if state.PresenceOffice == "" {
		return defaultOfficeID()
	}
	return state.PresenceOffice
}

// inMyOffice: in the office interval, entered in the office the player counts in today. A business
// trip that starts or ends during the day needs a new entry code in the new office.
func (tx *gameTx) inMyOffice() bool {
	return inOffice(tx.me.state, tx.today) && presenceOffice(tx.me.state) == tx.office()
}

// useToken checks a scanned code and remembers it so the same player cannot use it twice. Only the
// codes of the player's office today count.
func (tx *gameTx) useToken(purpose, token string) string {
	if problem := verifyPresenceToken(presenceSecret, purpose, tx.office(), token, time.Now().Unix()); problem != "" {
		return problem
	}
	state := tx.me.state
	if contains(state.UsedPresenceTokens, purpose+token) {
		return "presence_token_reused"
	}
	state.UsedPresenceTokens = append(state.UsedPresenceTokens, purpose+token)
	if len(state.UsedPresenceTokens) > maxUsedPresenceTokens {
		state.UsedPresenceTokens = state.UsedPresenceTokens[len(state.UsedPresenceTokens)-maxUsedPresenceTokens:]
	}
	return ""
}

// enterOffice opens the interval and its first visit and marks the day present (streak, calendar).
func (tx *gameTx) enterOffice() error {
	state := tx.me.state
	key := dayKey(tx.today)
	// Already in this office today (the check-in task after the entry code): keep the first arrival.
	again := tx.checkedInToday()
	state.PresenceDays[key] = true
	if !again {
		state.CheckinAt[key] = tx.now
	}
	delete(state.CheckoutAt, key)
	state.PresenceOffice = tx.office()
	state.Room = ""
	if !again || openVisit(state, tx.today) == nil {
		startVisit(state, tx.today, tx.now)
	}
	state.BestStreak = max(state.BestStreak, streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay))
	tx.logActivity(tx.me, activityCheckIn, map[string]any{"office": state.PresenceOffice})
	return tx.writePresence(true, "")
}

func (tx *gameTx) writePresence(in bool, room string) error {
	entry := presenceEntry{Day: tx.today, In: in, Since: tx.now, Room: room, Office: presenceOffice(tx.me.state)}
	return tx.writeSystem(presenceCollection, tx.me.userID, entry, "")
}

type actionResult struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

func fail(problem string) actionResult {
	return actionResult{Error: problem}
}

var okResult = actionResult{OK: true}

// rpcOfficeCheckIn: {"token"}. The entry code outside the check-in task. The first entry of the day
// goes through complete_task of the check-in task, which pays a reward; after it the code is refused
// until tomorrow (coming back from lunch needs only the office Wi-Fi). Only a business trip to
// another office that starts during the day needs the entry code of that office.
func rpcOfficeCheckIn(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Token string `json:"token"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.networkError(); problem != "" || err != nil {
			tx.logSuspicious("office_check_in", problem)
			return fail(problem), err
		}
		if tx.checkedInToday() {
			return fail("already_checked_in_today"), nil
		}
		if problem := tx.useToken(purposeEntry, request.Token); problem != "" {
			tx.logSuspicious("office_check_in", problem)
			return fail(problem), nil
		}
		return okResult, tx.enterOffice()
	})
}

// checkedInToday: the entry code of the office the player counts in today was already scanned today.
func (tx *gameTx) checkedInToday() bool {
	_, ok := tx.me.state.CheckinAt[dayKey(tx.today)]
	return ok && presenceOffice(tx.me.state) == tx.office()
}

// leaveOffice ends the office day and its open visit. `how` is visitOutCode for the exit code,
// visitOutHome for the "Go home" button.
func (tx *gameTx) leaveOffice(how string) error {
	limits, err := tx.limits()
	if err != nil {
		return err
	}
	tx.closeVisitAt(how, limits)
	tx.me.state.CheckoutAt[dayKey(tx.today)] = tx.now
	tx.me.state.Room = ""
	tx.logActivity(tx.me, activityCheckOut, map[string]any{"how": how})
	return tx.writePresence(false, "")
}

// rpcOfficeCheckOut: {"token"}. Ends the office day; the entry code is refused until tomorrow.
func rpcOfficeCheckOut(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Token string `json:"token"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem := tx.useToken(purposeExit, request.Token); problem != "" {
			tx.logSuspicious("office_check_out", problem)
			return fail(problem), nil
		}
		if !inOffice(tx.me.state, tx.today) {
			return fail("not_in_office"), nil
		}
		return okResult, tx.leaveOffice(visitOutCode)
	})
}

// rpcLeaveOffice: {}. The player goes home from the game ("Go home"): closes the interval without
// the exit code. Leaving can only shorten the time in the office, so it needs no proof and works
// outside the office network too (the player may press it already on the way home).
func rpcLeaveOffice(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if !inOffice(tx.me.state, tx.today) {
			return okResult, nil
		}
		return okResult, tx.leaveOffice(visitOutHome)
	})
}

// rpcEnterRoom: {"room_id"}. A static room code counts only inside the office interval. The room
// is shown to colleagues as where the player was seen last, and the player can take its tasks.
func rpcEnterRoom(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		RoomID string `json:"room_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if !roomIDPattern.MatchString(request.RoomID) {
		return "", errInvalidPayload
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		tx.me.state.Room = request.RoomID
		tx.logActivity(tx.me, activityRoom, map[string]any{"room": request.RoomID})
		return okResult, tx.writePresence(true, request.RoomID)
	})
}

type kioskCodes struct {
	Office      string `json:"office"`
	Entry       string `json:"entry"`
	Exit        string `json:"exit"`
	Period      int    `json:"period"`
	SecondsLeft int64  `json:"seconds_left"`
}

func currentKioskCodes(office string, now int64) kioskCodes {
	step := presenceStep(now)
	return kioskCodes{
		Office:      office,
		Entry:       presenceToken(presenceSecret, purposeEntry, office, step),
		Exit:        presenceToken(presenceSecret, purposeExit, office, step),
		Period:      presencePeriodSeconds,
		SecondsLeft: (step+1)*presencePeriodSeconds - now,
	}
}

// rpcKioskCodes: {"office"?}. The office screen asks for the current codes of its office with the
// server's HTTP key; without "office" it gets the default office. Player sessions are refused, so
// the codes cannot be fetched from home.
func rpcKioskCodes(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if userID, _ := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string); userID != "" {
		return "", errNotAdmin
	}
	var request struct {
		Office string `json:"office"`
	}
	if strings.TrimSpace(payload) != "" {
		if err := decodePayload(payload, &request); err != nil {
			return "", err
		}
	}
	if request.Office == "" {
		request.Office = defaultOfficeID()
	}
	if _, err := findOffice(ctx, nk, request.Office); err != nil {
		return "", err
	}
	return encodeResponse(currentKioskCodes(request.Office, time.Now().Unix()))
}

// officePresence lists players in the office now (the index), keyed by user id.
func officePresence(ctx context.Context, nk runtime.NakamaModule, today int, office string) (map[string]presenceEntry, error) {
	result := map[string]presenceEntry{}
	cursor := ""
	for {
		objects, next, err := nk.StorageList(ctx, "", systemUserID, presenceCollection, storagePageSize, cursor)
		if err != nil {
			return nil, errInternal
		}
		for _, object := range objects {
			var entry presenceEntry
			if json.Unmarshal([]byte(object.GetValue()), &entry) == nil && entry.Day == today && entry.In && entry.office() == office {
				result[object.GetKey()] = entry
			}
		}
		if next == "" {
			return result, nil
		}
		cursor = next
	}
}
