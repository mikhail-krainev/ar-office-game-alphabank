package main

import (
	"context"
	"database/sql"
	"math"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Daily office tasks: list, completion with a proof checked here, skipping.

const (
	presenceMinigame = "presence_qr"
	photoMinigame    = "selfie"
	meetMinigame     = "meet_colleague"
	bingoMinigame    = "colleague_bingo"
)

var difficultyMultipliers = map[string]float64{"normal": 1.0, "hard": 2.0, "very_hard": 3.0}

// Errors of honest play that are not logged as suspicious.
var benignTaskErrors = map[string]bool{
	"presence_required": true, "task_failed": true, "already_completed": true, "task_skipped": true,
	"pending_confirmation": true, "no_colleague_available": true, "task_not_today": true,
	"task_cooldown": true, "outside_task_window": true, "play_resting": true, "play_blocked": true,
}

type taskView struct {
	ID                   string         `json:"id"`
	Title                string         `json:"title"`
	Description          string         `json:"description"`
	Room                 string         `json:"room"`
	Floor                string         `json:"floor"`
	Spot                 []int          `json:"spot"`
	Minigame             string         `json:"minigame"`
	Fallback             string         `json:"fallback"`
	Params               map[string]any `json:"params"`
	Assignment           string         `json:"assignment"`
	BaseReward           int            `json:"base_reward"`
	Reward               int            `json:"reward"`
	Difficulty           string         `json:"difficulty"`
	DifficultyMultiplier float64        `json:"difficulty_multiplier"`
	Skippable            bool           `json:"skippable"`
	Completed            bool           `json:"completed"`
	Skipped              bool           `json:"skipped"`
	Pending              bool           `json:"pending"`
}

type taskResult struct {
	OK          bool   `json:"ok"`
	Error       string `json:"error,omitempty"`
	Reward      int    `json:"reward"`
	Balance     int64  `json:"balance"`
	Pending     bool   `json:"pending"`
	PartnerName string `json:"partner_name,omitempty"`
}

func (tx *gameTx) multiplier() float64 {
	state := tx.me.state
	return streakMultiplier(streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay), state.PresenceDays[dayKey(tx.today)], &tx.content.Rules)
}

// taskReward: base reward x difficulty x streak multiplier.
func taskReward(task *Task, multiplier float64) int {
	return int(math.Round(float64(task.Reward) * difficultyMultipliers[task.Difficulty] * multiplier))
}

// capLeft: coins the player can still earn on `day` before the daily cap.
func capLeft(state *PlayerState, day int, rules *Rules) int {
	return rules.Economy.DailyCoinCap - state.Earned[dayKey(day)]
}

// grantTask closes a task for `day` with its reward: completed list, daily earnings, history, wallet.
func (tx *gameTx) grantTask(doc *playerDoc, task *Task, day, reward int) {
	state := doc.state
	addToDay(state.Completed, day, task.ID)
	removeFromDay(state.Pending, day, task.ID)
	state.Earned[dayKey(day)] += reward
	state.TaskLog[dayKey(day)] = append(state.TaskLog[dayKey(day)], TaskLogEntry{ID: task.ID, Title: task.Title, Reward: reward, T: tx.now})
	state.CoinsEarned += int(tx.credit(doc, int64(reward), "task_reward", task.ID))
	tx.logActivity(doc, activityTaskDone, map[string]any{"task": task.ID, "reward": reward})
}

func rpcListTasks(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if err := tx.tick(); err != nil {
			return nil, err
		}
		state := tx.me.state
		multiplier := tx.multiplier()
		schedule, err := tx.taskSchedule()
		if err != nil {
			return nil, err
		}
		tasks := []taskView{}
		for i := range tx.content.Tasks {
			task := &tx.content.Tasks[i]
			if !tx.isTodaysTask(task) {
				continue
			}
			tasks = append(tasks, taskView{
				ID: task.ID, Title: task.Title, Description: task.Description, Room: task.Room, Floor: task.Floor,
				Spot: task.Spot, Minigame: task.Minigame, Fallback: task.Fallback, Params: task.Params,
				Assignment: task.Assignment, BaseReward: task.Reward, Reward: taskReward(task, multiplier),
				Difficulty: task.Difficulty, DifficultyMultiplier: difficultyMultipliers[task.Difficulty],
				Skippable: task.Skippable,
				Completed: contains(dayList(state.Completed, tx.today), task.ID),
				Skipped:   contains(dayList(state.Skipped, tx.today), task.ID),
				Pending:   contains(dayList(state.Pending, tx.today), task.ID),
			})
		}
		return map[string]any{"tasks": tasks, "in_office": inOffice(state, tx.today), "schedule": schedule}, nil
	})
}

// rpcSkipTask: {"task_id"}. Closes a skippable task of today's pack without a reward.
func rpcSkipTask(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		TaskID string `json:"task_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		state := tx.me.state
		task := tx.content.task(request.TaskID)
		if problem, err := tx.playError(); problem != "" || err != nil {
			return fail(problem), err
		}
		switch {
		case task == nil:
			return fail("unknown_task"), nil
		case !tx.isTodaysTask(task):
			return fail("task_not_today"), nil
		case !task.Skippable:
			return fail("task_not_skippable"), nil
		case contains(dayList(state.Completed, tx.today), task.ID):
			return fail("already_completed"), nil
		case contains(dayList(state.Pending, tx.today), task.ID):
			return fail("pending_confirmation"), nil
		}
		addToDay(state.Skipped, tx.today, task.ID)
		tx.logActivity(tx.me, activityTaskSkipped, map[string]any{"task": task.ID})
		return okResult, nil
	})
}

type taskProof struct {
	PresenceToken string   `json:"presence_token"`
	ColleagueID   string   `json:"colleague_id"`
	ColleagueIDs  []string `json:"colleague_ids"`
	PartnerID     string   `json:"partner_id"`
	Faces         int      `json:"faces"`
	Score         float64  `json:"score"`
}

// rpcCompleteTask: {"task_id", "success", "operation_key", "proof"} -> taskResult.
func rpcCompleteTask(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		TaskID       string         `json:"task_id"`
		Success      bool           `json:"success"`
		OperationKey string         `json:"operation_key"`
		Proof        map[string]any `json:"proof"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	proof := parseProof(request.Proof)
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		result := taskResult{Balance: tx.me.balance}
		// Checked before the operation key is claimed, so the client may retry after the rest.
		if problem, err := tx.playError(); problem != "" || err != nil {
			result.Error = problem
			return result, err
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil {
			return nil, err
		}
		if !claimed {
			result.Error = "duplicate_operation"
			return result, nil
		}
		task := tx.content.task(request.TaskID)
		if task == nil {
			result.Error = "unknown_task"
			return result, nil
		}
		if result.Error, err = tx.taskError(task, request.Success, proof); err != nil {
			return nil, err
		}
		if result.Error != "" {
			if !benignTaskErrors[result.Error] {
				tx.logSuspicious(task.ID, result.Error)
			}
			return result, nil
		}
		if task.Minigame == presenceMinigame {
			// Presence counts even when the daily coin cap is already reached.
			if err := tx.enterOffice(); err != nil {
				return nil, err
			}
		}
		score := min(max(proof.Score, 0), 1)
		reward := int(math.Round(float64(taskReward(task, tx.multiplier())) * (1 + tx.content.Rules.Economy.MaxScoreBonus*score)))
		reward = min(reward, capLeft(tx.me.state, tx.today, &tx.content.Rules))
		if reward <= 0 {
			result.Error = "daily_cap_reached"
			return result, nil
		}
		result.OK = true
		if task.Minigame != presenceMinigame {
			tx.me.state.LastTaskAt = tx.now
		}
		if task.Minigame == photoMinigame {
			// The reward waits for the colleague: they confirm the photo on their phone.
			result.Pending = true
			result.PartnerName, err = tx.submitPhoto(task, proof.PartnerID, reward)
			return result, err
		}
		tx.rememberMet(task, proof)
		tx.grantTask(tx.me, task, tx.today, reward)
		result.Reward = reward
		result.Balance = tx.me.balance
		return result, nil
	})
}

func parseProof(raw map[string]any) taskProof {
	proof := taskProof{}
	proof.PresenceToken, _ = raw["presence_token"].(string)
	proof.ColleagueID, _ = raw["colleague_id"].(string)
	proof.PartnerID, _ = raw["partner_id"].(string)
	if faces, ok := raw["faces"].(float64); ok {
		proof.Faces = int(faces)
	}
	proof.Score, _ = raw["score"].(float64)
	if ids, ok := raw["colleague_ids"].([]any); ok {
		for _, id := range ids {
			if text, ok := id.(string); ok {
				proof.ColleagueIDs = append(proof.ColleagueIDs, text)
			}
		}
	}
	return proof
}

// taskError: why the task can't be completed now, or "" when it can.
func (tx *gameTx) taskError(task *Task, success bool, proof taskProof) (string, error) {
	state := tx.me.state
	switch {
	case !success:
		return "task_failed", nil
	case contains(dayList(state.Completed, tx.today), task.ID):
		return "already_completed", nil
	case contains(dayList(state.Skipped, tx.today), task.ID):
		return "task_skipped", nil
	case contains(dayList(state.Pending, tx.today), task.ID):
		return "pending_confirmation", nil
	case !tx.isTodaysTask(task):
		return "task_not_today", nil
	case task.Minigame == presenceMinigame:
		if problem := tx.networkError(); problem != "" {
			return problem, nil
		}
		return tx.useToken(purposeEntry, proof.PresenceToken), nil
	}
	if problem := tx.presenceError(); problem != "" {
		return problem, nil
	}
	if problem, err := tx.taskTimeError(task); problem != "" || err != nil {
		return problem, err
	}
	return tx.verifySocial(task, proof)
}

// rememberMet: colleagues met in a completed task; each can be met in one task a day.
func (tx *gameTx) rememberMet(task *Task, proof taskProof) {
	switch task.Minigame {
	case meetMinigame:
		addToDay(tx.me.state.Met, tx.today, proof.ColleagueID)
		tx.logActivity(tx.me, activityMet, map[string]any{"task": task.ID, "colleagues": []string{proof.ColleagueID}})
	case bingoMinigame:
		for _, id := range proof.ColleagueIDs {
			addToDay(tx.me.state.Met, tx.today, id)
		}
		tx.logActivity(tx.me, activityMet, map[string]any{"task": task.ID, "colleagues": proof.ColleagueIDs})
	}
}
