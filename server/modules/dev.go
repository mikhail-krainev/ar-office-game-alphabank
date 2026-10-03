package main

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// DEV-ONLY RPCs, registered only when the server runs with DEV_MODE=true: desktop debug keys,
// the sensor emulator's QR list and the automated tour. Never enable on a real server.

const devMaxGrant = 100000

func registerDevRpcs(initializer runtime.Initializer) error {
	rpcs := map[string]func(context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule, string) (string, error){
		"dev_skip_day":        rpcDevSkipDay,
		"dev_schedule_raffle": rpcDevScheduleRaffle,
		"dev_grant_coins":     rpcDevGrantCoins,
		"dev_presence_codes":  rpcDevPresenceCodes,
		"dev_list_players":    rpcDevListPlayers,
		"dev_reset_day":       rpcDevResetDay,
		"dev_set_office_days": rpcDevSetOfficeDays,
		"dev_draw_now":        rpcDevDrawNow,
		"dev_clear_raffle":    rpcDevClearRaffle,
		"dev_task_limits":     rpcDevTaskLimits,
		"dev_play_state":      rpcDevPlayState,
	}
	for id, fn := range rpcs {
		if err := initializer.RegisterRpc(id, fn); err != nil {
			return err
		}
	}
	return nil
}

// rpcDevSkipDay moves the caller's clock one day forward (absence fines, lost streak).
func rpcDevSkipDay(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		tx.me.state.DevDayShift++
		return okResult, nil
	})
}

// rpcDevScheduleRaffle: {"seconds"}. A dev draw for everyone that starts `seconds` from now.
func rpcDevScheduleRaffle(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Seconds int64 `json:"seconds"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		at := tx.now + max(request.Seconds, 10)
		seed, err := newRaffleSeed()
		if err != nil {
			return nil, errInternal
		}
		draw := raffleDraw{ID: fmt.Sprintf("parking-dev-%d", at), DrawAt: at, Seed: seed, Commitment: raffleCommitment(seed), Tickets: []string{}}
		if err := tx.writeSystem(rafflesCollection, raffleDevKey, draw, ""); err != nil {
			return nil, err
		}
		return okResult, tx.writeSystem(rafflesCollection, draw.ID, draw, "*")
	})
}

// rpcDevGrantCoins: {"amount"}.
func rpcDevGrantCoins(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Amount int64 `json:"amount"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		tx.credit(tx.me, min(max(request.Amount, 0), devMaxGrant), "dev_grant", "dev")
		return map[string]any{"ok": true, "balance": tx.me.balance}, nil
	})
}

// rpcDevPresenceCodes: the office screen codes for the desktop QR emulator.
func rpcDevPresenceCodes(ctx context.Context, _ runtime.Logger, _ *sql.DB, _ runtime.NakamaModule, _ string) (string, error) {
	if _, err := callerID(ctx); err != nil {
		return "", err
	}
	return encodeResponse(currentKioskCodes(gameContent.Rules.Office.ID, time.Now().Unix()))
}

// rpcDevListPlayers: every other player with their office status, for the emulator's profile codes.
func rpcDevListPlayers(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		rows, err := db.QueryContext(ctx, `SELECT id FROM users WHERE id <> $1 AND id <> $2 AND disable_time = '1970-01-01 00:00:00 UTC'`, systemUserID, tx.me.userID)
		if err != nil {
			return nil, errInternal
		}
		defer rows.Close()
		ids := []string{}
		for rows.Next() {
			var id string
			if rows.Scan(&id) == nil {
				ids = append(ids, id)
			}
		}
		players, err := readPlayers(ctx, nk, ids)
		if err != nil {
			return nil, err
		}
		presence, err := officePresence(ctx, nk, tx.today)
		if err != nil {
			return nil, err
		}
		cards := []colleagueView{}
		for _, player := range players {
			cards = append(cards, tx.colleagueView(player, presence))
		}
		return map[string]any{"players": cards}, nil
	})
}

// rpcDevResetDay opens today's tasks again: completed, skipped, pending, met and assignments.
func rpcDevResetDay(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		state := tx.me.state
		key := dayKey(tx.today)
		for _, lists := range []map[string][]string{state.Completed, state.Skipped, state.Pending, state.Met} {
			delete(lists, key)
		}
		delete(state.Assignments, key)
		delete(state.Earned, key)
		state.LastTaskAt = 0
		return okResult, nil
	})
}

// rpcDevSetOfficeDays: {"days"}. Marks the last `days` days present (raffle eligibility, streaks).
func rpcDevSetOfficeDays(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Days int `json:"days"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		state := tx.me.state
		for day := tx.today - min(max(request.Days, 0), 60) + 1; day <= tx.today; day++ {
			state.PresenceDays[dayKey(day)] = true
			state.FirstDay = min(state.FirstDay, day)
		}
		return okResult, nil
	})
}

// rpcDevDrawNow moves the current draw's time into the past; the next call draws it.
func rpcDevDrawNow(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		loaded, err := tx.currentDraw()
		if err != nil {
			return nil, err
		}
		loaded.draw.DrawAt = tx.now - 1
		loaded.dirty = true
		if dev, err := readDraw(tx.ctx, tx.nk, raffleDevKey); err == nil && dev != nil && dev.draw.ID == loaded.draw.ID {
			return okResult, tx.writeSystem(rafflesCollection, raffleDevKey, loaded.draw, "")
		}
		return okResult, nil
	})
}

// rpcDevClearRaffle returns to the monthly draw.
func rpcDevClearRaffle(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if _, err := callerID(ctx); err != nil {
		return "", err
	}
	if err := nk.StorageDelete(ctx, []*runtime.StorageDelete{{Collection: rafflesCollection, Key: raffleDevKey, UserID: systemUserID}}); err != nil {
		return "", errInternal
	}
	return encodeResponse(okResult)
}

// rpcDevTaskLimits: {"off"}. Lets the caller complete tasks at any hour and without the pause
// between them, so the dev tour can close a whole day at once.
func rpcDevTaskLimits(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Off bool `json:"off"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		tx.me.state.DevNoTaskLimits = request.Off
		return okResult, nil
	})
}

// rpcDevPlayState: {"state"}: ok, warning, deferred, resting or blocked. Puts the caller's play-time limit
// into that state right away, to see the warning, the rest screen and the lock screen.
func rpcDevPlayState(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		State string `json:"state"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		limits, err := tx.limits()
		if err != nil {
			return nil, err
		}
		play := &tx.me.state.Play
		switch request.State {
		case playOK:
			*play = PlaySession{}
		case playWarning:
			*play = PlaySession{Seconds: limits.PlayLimitMinutes * 60, LastBeat: tx.now, WarnedAt: tx.now}
		case playDeferred:
			*play = PlaySession{Seconds: limits.PlayLimitMinutes * 60, LastBeat: tx.now, WarnedAt: tx.now, RestPending: true, DeferUntil: tx.now + defaultMinigameSeconds}
		case playResting:
			*play = PlaySession{LastBeat: tx.now, RestUntil: tx.now + int64(limits.RestMinutes)*60}
		case playBlocked:
			*play = PlaySession{LastBeat: tx.now, BlockedDay: tx.today}
		default:
			return nil, errInvalidPayload
		}
		return currentPlayStatus(play, tx.now, tx.offset, limits), nil
	})
}
