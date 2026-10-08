package main

import (
	"encoding/json"
	"fmt"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Activity journal for the admin audit: one server-only storage object per player action, written
// in the same MultiUpdate as the change it describes. Coin movements are not duplicated here: the
// wallet ledger already records each of them with its time and reason.

const activityCollection = "activity"

const (
	activityLogin       = "login"
	activityCheckIn     = "check_in"
	activityCheckOut    = "check_out"
	activityRoom        = "room"
	activityTaskTaken   = "task_taken"
	activityTaskDone    = "task_done"
	activityTaskPending = "task_pending"
	activityTaskSkipped = "task_skipped"
	activityMet         = "met"
	activityPhotoAnswer = "photo_answer"
	activityFactsSent   = "facts_sent"
	activityFactsAnswer = "facts_answer"
	activityPlayWarning = "play_warning"
	activityPlayRest    = "play_rest"
	activityPlayBlocked = "play_blocked"
)

type activityEvent struct {
	T      int64          `json:"t"`
	Kind   string         `json:"kind"`
	Params map[string]any `json:"params,omitempty"`
}

// logActivity records an action of `doc` at the transaction time. The key starts with the time, so
// keys sort in the order of events.
func (tx *gameTx) logActivity(doc *playerDoc, kind string, params map[string]any) {
	value, err := json.Marshal(activityEvent{T: tx.now, Kind: kind, Params: params})
	if err != nil {
		tx.logger.Error("activity %s for %s: %v", kind, doc.userID, err)
		return
	}
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: activityCollection, Key: fmt.Sprintf("%d-%s", tx.now, randomKey()), UserID: doc.userID,
		Value: string(value),
	})
}
