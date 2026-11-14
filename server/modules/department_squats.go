package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const squatPlansCollection = "department_squats"

type squatPlan struct {
	Total         int            `json:"total"`
	Contributions map[string]int `json:"contributions"`
}

type squatWorkout struct {
	ID       string `json:"id"`
	Day      int    `json:"day"`
	Started  int64  `json:"started"`
	LastAt   int64  `json:"last_at"`
	Sequence int    `json:"sequence"`
}

func squatHelpReward(reps, goal, total int) (int, int64) {
	accepted := max(0, min(reps, goal-total))
	return accepted, int64(accepted) * 15
}
func (tx *gameTx) squatGoal() (int, int, error) {
	office, department := tx.me.metadata.placement(tx.today)
	rows, err := tx.db.QueryContext(tx.ctx, `SELECT u.id,u.metadata,s.value FROM users u LEFT JOIN storage s ON s.user_id=u.id AND s.collection='game' AND s.key='state' WHERE u.id<>$1`, systemUserID)
	if err != nil {
		return 0, 0, errInternal
	}
	defer rows.Close()
	count := 0
	for rows.Next() {
		var id, metadata string
		var value sql.NullString
		if rows.Scan(&id, &metadata, &value) != nil {
			return 0, 0, errInternal
		}
		m := parseMetadata(metadata)
		o, d := m.placement(tx.today)
		if m.Role != rolePlayer || o != office || d != department {
			continue
		}
		state := parseState(value)
		if taskPack(tx.content.Tasks, id, tx.today)["squats"] || contains(dayList(state.Given, tx.today), "squats") {
			count++
		}
	}
	if rows.Err() != nil {
		return 0, 0, errInternal
	}
	return count * 20, count, nil
}
func (tx *gameTx) squatPlan() (*squatPlan, string, string, error) {
	office, department := tx.me.metadata.placement(tx.today)
	key := fmt.Sprintf("%s|%s|%d", office, department, tx.today)
	objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: squatPlansCollection, Key: key, UserID: systemUserID}})
	if err != nil {
		return nil, "", "", errInternal
	}
	plan := &squatPlan{Contributions: map[string]int{}}
	version := "*"
	if len(objects) > 0 {
		if json.Unmarshal([]byte(objects[0].GetValue()), plan) != nil {
			return nil, "", "", errInternal
		}
		version = objects[0].GetVersion()
	}
	if plan.Contributions == nil {
		plan.Contributions = map[string]int{}
	}
	return plan, key, version, nil
}
func (tx *gameTx) addPersonalSquats(reps int) error {
	plan, key, version, err := tx.squatPlan()
	if err != nil {
		return err
	}
	plan.Total += reps
	plan.Contributions[tx.me.userID] += reps
	return tx.writeSystem(squatPlansCollection, key, plan, version)
}
func rpcDepartmentSquats(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var a struct {
		Action    string `json:"action"`
		Operation string `json:"operation_key"`
		Session   string `json:"session"`
		Sequence  int    `json:"sequence"`
	}
	if err := decodePayload(payload, &a); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if err := tx.tick(); err != nil {
			return nil, err
		}
		goal, assigned, err := tx.squatGoal()
		if err != nil {
			return nil, err
		}
		plan, key, version, err := tx.squatPlan()
		if err != nil {
			return nil, err
		}
		result := map[string]any{"ok": true, "goal": goal, "assigned": assigned, "total": plan.Total, "mine": plan.Contributions[tx.me.userID], "reward_per_rep": 15, "balance": tx.me.balance, "can_help": contains(dayList(tx.me.state.Completed, tx.today), "squats")}
		if a.Action == "get" {
			return result, nil
		}
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		if !contains(dayList(tx.me.state.Completed, tx.today), "squats") {
			return fail("personal_squats_required"), nil
		}
		claimed, err := tx.claimOperation(a.Operation)
		if err != nil {
			return nil, err
		}
		if !claimed {
			result["error"] = "duplicate_operation"
			result["ok"] = false
			return result, nil
		}
		now := time.Now().Unix()
		work := &tx.me.state.SquatWorkout
		switch a.Action {
		case "start":
			*work = squatWorkout{ID: randomKey(), Day: tx.today, Started: now}
			result["session"] = work.ID
		case "rep":
			if a.Session == "" || a.Session != work.ID || work.Day != tx.today || a.Sequence != work.Sequence+1 {
				return fail("invalid_workout"), nil
			}
			if now-work.LastAt < 1 || int64(a.Sequence) > now-work.Started {
				return fail("too_fast"), nil
			}
			work.Sequence = a.Sequence
			work.LastAt = now
			accepted, reward := squatHelpReward(1, goal, plan.Total)
			plan.Total += accepted
			plan.Contributions[tx.me.userID] += accepted
			tx.credit(tx.me, reward, "department_squat", key)
			tx.me.state.CoinsEarned += int(reward)
			if accepted > 0 {
				if err := tx.writeSystem(squatPlansCollection, key, plan, version); err != nil {
					return nil, err
				}
			}
			result["total"] = plan.Total
			result["mine"] = plan.Contributions[tx.me.userID]
			result["reward"] = reward
			result["balance"] = tx.me.balance
		default:
			return fail("invalid_action"), nil
		}
		return result, nil
	})
}
