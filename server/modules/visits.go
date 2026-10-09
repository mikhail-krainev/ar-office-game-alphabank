package main

import (
	"context"
	"database/sql"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Office visits within a day. The entry code is scanned once a day: it marks the first arrival and
// opens the first visit. After that the office Wi-Fi alone tells whether the player is in. While the
// game is open it sends a heartbeat every playBeatSeconds (play.go), and each heartbeat from the
// office network keeps the visit open. A heartbeat from outside the network, or no heartbeat from it
// for Limits.AwayMinutes, closes the visit at the last heartbeat from the office network; the next
// heartbeat from the network opens a new visit without any code. The exit code or "Go home" ends the
// office day: the visit closes and the entry code is refused until tomorrow. A visit nobody closed
// ends at the last heartbeat from the office network, which is when the player left.
//
// The server sees the network only while the game is open, so a game closed for longer than
// AwayMinutes also counts as a step out, and a walk outside with the game closed for less is missed.

const (
	visitOutNetwork = "network"
	visitOutAway    = "away"
	visitOutCode    = "code"
	visitOutHome    = "home"
	visitOutOffice  = "office"

	activityOfficeOut  = "office_out"
	activityOfficeBack = "office_back"
)

type OfficeVisit struct {
	In int64 `json:"in"`
	// Last heartbeat from the office network inside the visit.
	Seen int64 `json:"seen"`
	// 0 while the visit is open.
	Out int64 `json:"out,omitempty"`
	// How the visit ended: visitOutNetwork, visitOutAway, visitOutCode, visitOutHome or visitOutOffice.
	How string `json:"how,omitempty"`
}

func (v OfficeVisit) open() bool {
	return v.Out == 0
}

// openVisit: the last visit of the day when it is still open, or nil.
func openVisit(state *PlayerState, day int) *OfficeVisit {
	visits := state.Visits[dayKey(day)]
	if len(visits) == 0 || !visits[len(visits)-1].open() {
		return nil
	}
	return &visits[len(visits)-1]
}

// startVisit opens a visit at `now`, closing one left open (a business trip to another office).
func startVisit(state *PlayerState, day int, now int64) {
	if visit := openVisit(state, day); visit != nil {
		closeVisit(visit, now, visitOutOffice)
	}
	key := dayKey(day)
	state.Visits[key] = append(state.Visits[key], OfficeVisit{In: now, Seen: now})
}

func closeVisit(visit *OfficeVisit, at int64, how string) {
	visit.Out = max(at, visit.In)
	visit.How = how
}

// stale: the visit got no heartbeat from the office network for longer than `awaySeconds`.
func (v OfficeVisit) stale(now, awaySeconds int64) bool {
	return now-v.Seen > awaySeconds
}

func awaySeconds(limits Limits) int64 {
	return int64(limits.AwayMinutes) * 60
}

// closeVisitAt closes the open visit of today, if any: at the last heartbeat from the office network
// when it is stale, at `now` with `how` otherwise.
func (tx *gameTx) closeVisitAt(how string, limits Limits) {
	visit := openVisit(tx.me.state, tx.today)
	if visit == nil {
		return
	}
	at := tx.now
	if visit.stale(tx.now, awaySeconds(limits)) {
		at, how = visit.Seen, visitOutAway
	}
	closeVisit(visit, at, how)
	tx.logActivity(tx.me, activityOfficeOut, map[string]any{"how": how, "at": visit.Out})
}

// seenInOfficeNetwork: a heartbeat came from the office network. Closes a visit that went silent
// for too long and opens a new one when the player is back.
func (tx *gameTx) seenInOfficeNetwork(limits Limits) error {
	state := tx.me.state
	if !tx.inMyOffice() {
		return nil
	}
	if visit := openVisit(state, tx.today); visit != nil && visit.stale(tx.now, awaySeconds(limits)) {
		closeVisit(visit, visit.Seen, visitOutAway)
		tx.logActivity(tx.me, activityOfficeOut, map[string]any{"how": visitOutAway, "at": visit.Out})
	}
	if visit := openVisit(state, tx.today); visit != nil {
		visit.Seen = tx.now
		return nil
	}
	startVisit(state, tx.today, tx.now)
	tx.logActivity(tx.me, activityOfficeBack, nil)
	return tx.writePresence(true, state.Room)
}

// seenOutsideOfficeNetwork: a heartbeat came from outside the office network, so the player has left
// the office Wi-Fi. The open visit ends at the last heartbeat from the office network.
func (tx *gameTx) seenOutsideOfficeNetwork(limits Limits) error {
	state := tx.me.state
	visit := openVisit(state, tx.today)
	if visit == nil {
		return nil
	}
	how := visitOutNetwork
	if visit.stale(tx.now, awaySeconds(limits)) {
		how = visitOutAway
	}
	closeVisit(visit, visit.Seen, how)
	tx.logActivity(tx.me, activityOfficeOut, map[string]any{"how": how, "at": visit.Out})
	return tx.writePresence(false, "")
}

// recordOutsideHeartbeat runs a heartbeat that came from outside the office network: it only closes
// the open visit, the caller then refuses the heartbeat with office_network_required.
func recordOutsideHeartbeat(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule) error {
	_, err := runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		limits, err := tx.limits()
		if err != nil {
			return nil, err
		}
		return okResult, tx.seenOutsideOfficeNetwork(limits)
	})
	return err
}

// visitsOfDay: the visits of a day for the admin. A visit still open closes at the last heartbeat
// from the office network once it went silent or the day is over.
func visitsOfDay(state *PlayerState, day, today int, now, awaySeconds int64) []OfficeVisit {
	visits := append([]OfficeVisit{}, state.Visits[dayKey(day)]...)
	if len(visits) == 0 {
		return visits
	}
	last := &visits[len(visits)-1]
	if last.open() && (day < today || last.stale(now, awaySeconds)) {
		closeVisit(last, last.Seen, visitOutAway)
	}
	return visits
}

// leftAt: when the player left the office that day: the exit code or "Go home", else the end of
// the last closed visit. 0 while the player is still in.
func leftAt(state *PlayerState, visits []OfficeVisit, day int) int64 {
	key := dayKey(day)
	if checkout := state.CheckoutAt[key]; checkout > state.CheckinAt[key] {
		return checkout
	}
	if len(visits) == 0 {
		return 0
	}
	return visits[len(visits)-1].Out
}
