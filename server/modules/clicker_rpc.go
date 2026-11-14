package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"math"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

const (
	clickerCollection  = "clicker"
	clickerKey         = "state"
	clickerBoard       = "clicker"
	clickerBoardEvery  = 10
	clickerBoardLimit  = 50
	clickerHistoryDays = 14
)

type clickerRequest struct {
	Action string `json:"action"`
	Seq    int64  `json:"seq"`
	Taps   int64  `json:"taps"`
	Open   bool   `json:"open"`
	Kind   string `json:"kind"`
	Tier   int    `json:"tier"`
	Count  int    `json:"count"`
}

func createClickerBoard(ctx context.Context, nk runtime.NakamaModule) error {
	return nk.LeaderboardCreate(ctx, clickerBoard, true, "desc", "set", "", nil, true)
}

func (tx *gameTx) clickerLoad() (*ClickerState, string, error) {
	objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: clickerCollection, Key: clickerKey, UserID: tx.me.userID}})
	if err != nil {
		return nil, "", errInternal
	}
	state := &ClickerState{}
	version := "*"
	if len(objects) > 0 {
		if err := json.Unmarshal([]byte(objects[0].GetValue()), state); err != nil {
			return nil, "", errInternal
		}
		version = objects[0].GetVersion()
	}
	tx.content.Clicker.normalize(state)
	return state, version, nil
}

func (tx *gameTx) clickerSave(state *ClickerState, version string) error {
	value, err := json.Marshal(state)
	if err != nil {
		return err
	}
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: clickerCollection, Key: clickerKey, UserID: tx.me.userID, Value: string(value),
		Version: version, PermissionRead: permissionNone, PermissionWrite: permissionNone,
	})
	return nil
}

// clickerWindows: the office intervals of the last days, from the entry code to the exit.
func (tx *gameTx) clickerWindows(from int64) []officeWindow {
	first, _ := tx.me.metadata.localDay(max(from, tx.now-clickerHistoryDays*secondsPerDay))
	windows := []officeWindow{}
	for day := first; day <= tx.today; day++ {
		key := dayKey(day)
		entered, ok := tx.me.state.CheckinAt[key]
		if !ok {
			continue
		}
		left := tx.now
		if out := tx.me.state.CheckoutAt[key]; out > entered {
			left = out
		}
		windows = append(windows, officeWindow{from: entered, to: left})
	}
	return windows
}

// rpcClicker: {"action": get|sync|buy|rebirth, "seq", "taps", "open", "kind", "tier", "count"}.
// Every request first adds the passive income and the taps since the previous one; a request whose
// seq is not above the last applied one only returns the state.
func rpcClicker(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request clickerRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	switch request.Action {
	case "get", "sync", "buy", "rebirth":
	default:
		return "", errInvalidPayload
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		rules := &tx.content.Clicker
		state, version, err := tx.clickerLoad()
		if err != nil {
			return nil, err
		}
		taps := int64(0)
		duplicate := request.Action != "get" && request.Seq <= state.Seq
		if request.Action != "get" && !duplicate {
			state.Seq = request.Seq
			taps = request.Taps
		}
		tick := rules.tick(state, tx.now, taps, request.Open, tx.clickerWindows(state.LastSync))
		errorKey := ""
		if !duplicate {
			switch request.Action {
			case "buy":
				errorKey = rules.buy(state, request.Kind, request.Tier, request.Count)
			case "rebirth":
				errorKey = rules.rebirth(state)
			}
		}
		added := rules.grantAchievements(state)
		if request.Action == "rebirth" || len(added) > 0 || tx.now-state.BoardAt >= clickerBoardEvery {
			state.BoardAt = tx.now
			tx.clickerPublish(state)
		}
		if err := tx.clickerSave(state, version); err != nil {
			return nil, err
		}
		result := map[string]any{"ok": errorKey == "", "error": errorKey, "state": clickerView(rules, state), "tick": tick, "added": added, "now": tx.now}
		if request.Action == "get" {
			result["rules"] = rules
		}
		return result, nil
	})
}

// clickerView: the state with the derived numbers the screen shows.
func clickerView(rules *ClickerContent, s *ClickerState) map[string]any {
	return map[string]any{
		"seq": s.Seq, "points": s.Points, "run": s.Run, "total": s.Total, "tap": s.Tap, "idle": s.Idle,
		"gold": s.Gold, "taps": s.Taps, "offline": s.Offline, "best_combo": s.BestCombo, "rebirths": s.Rebirths,
		"achievements": s.Achievements, "tap_value": rules.tapValue(s), "idle_rate": rules.idleRate(s),
		"multiplier": rules.multiplier(s), "rebirth_gold": rules.reachableGold(s),
	}
}

// clickerPublish writes the leaderboard record; a failure only delays the next record.
func (tx *gameTx) clickerPublish(s *ClickerState) {
	metadata := map[string]any{"name": tx.me.displayName(), "gold": s.Gold, "total": s.Total, "points": s.Points, "tap_value": tx.content.Clicker.tapValue(s), "rebirths": s.Rebirths}
	username := tx.me.account.GetUser().GetUsername()
	// SET: a rebirth keeps the all-time score but changes the cat and the points in the metadata.
	operator := int(api.Operator_SET)
	if _, err := tx.nk.LeaderboardRecordWrite(tx.ctx, clickerBoard, tx.me.userID, username, clickerBoardScore(s.Total), 0, metadata, &operator); err != nil {
		tx.logger.Warn("clicker leaderboard write for %s failed: %v", tx.me.userID, err)
	}
}

// rpcClickerTop: {} -> the leaderboard of all colleagues and the caller's own place.
func rpcClickerTop(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		records, own, _, _, err := nk.LeaderboardRecordsList(ctx, clickerBoard, []string{tx.me.userID}, clickerBoardLimit, "", 0)
		if err != nil {
			logger.Error("clicker leaderboard list failed: %v", err)
			return nil, errInternal
		}
		entries := []map[string]any{}
		for _, record := range records {
			entries = append(entries, clickerEntry(record, tx.me.userID))
		}
		var mine map[string]any
		if len(own) > 0 {
			mine = clickerEntry(own[0], tx.me.userID)
		}
		return map[string]any{"ok": true, "entries": entries, "me": mine}, nil
	})
}

func clickerEntry(record interface {
	GetOwnerId() string
	GetRank() int64
	GetMetadata() string
	GetScore() int64
}, me string) map[string]any {
	entry := map[string]any{}
	_ = json.Unmarshal([]byte(record.GetMetadata()), &entry)
	if _, ok := entry["total"]; !ok {
		entry["total"] = math.Pow(10, float64(record.GetScore())/1e15) - 1
	}
	entry["id"] = record.GetOwnerId()
	entry["rank"] = record.GetRank()
	entry["me"] = record.GetOwnerId() == me
	return entry
}
