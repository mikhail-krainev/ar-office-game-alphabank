package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Working time comes first: the game must not eat the workday. Each workday a player gets only a
// pack of tasks, a task counts only inside the task hours and not sooner than the cooldown after the
// previous one, and continuous play is capped (play.go). The admin edits the numbers in the panel;
// until then the defaults come from game_rules.json ("limits").

const (
	settingsCollection = "settings"
	limitsKey          = "limits"

	maxCooldownMinutes  = 240
	minPlayLimitMinutes = 5
	maxPlayLimitMinutes = 480
	minGraceMinutes     = 1
	maxGraceMinutes     = 60
	minRestMinutes      = 1
	maxRestMinutes      = 240
)

var clockPattern = regexp.MustCompile(`^([01][0-9]|2[0-3]):[0-5][0-9]$`)

var errInvalidLimits = runtime.NewError("invalid_limits", codeInvalidArgument)

type Limits struct {
	// Minutes between two tasks; the check-in is not counted.
	TaskCooldownMinutes int `json:"task_cooldown_minutes"`
	// Office time ("HH:MM") when tasks count: from the start, before the end.
	TaskWindowStart string `json:"task_window_start"`
	TaskWindowEnd   string `json:"task_window_end"`
	// Continuous play before the warning.
	PlayLimitMinutes int `json:"play_limit_minutes"`
	// Time to leave the game after the warning; staying longer locks it until the next day.
	ExitGraceMinutes int `json:"exit_grace_minutes"`
	// Rest after leaving in time; the game opens again when it ends.
	RestMinutes int `json:"rest_minutes"`
}

// clockMinutes: "08:30" -> 510. Only strict "HH:MM" is accepted.
func clockMinutes(text string) (int, bool) {
	if !clockPattern.MatchString(text) {
		return 0, false
	}
	hour, _ := strconv.Atoi(text[:2])
	minute, _ := strconv.Atoi(text[3:])
	return hour*60 + minute, true
}

func validateLimits(limits Limits) error {
	start, startOK := clockMinutes(limits.TaskWindowStart)
	end, endOK := clockMinutes(limits.TaskWindowEnd)
	switch {
	case limits.TaskCooldownMinutes < 0 || limits.TaskCooldownMinutes > maxCooldownMinutes,
		!startOK || !endOK || start >= end,
		limits.PlayLimitMinutes < minPlayLimitMinutes || limits.PlayLimitMinutes > maxPlayLimitMinutes,
		limits.ExitGraceMinutes < minGraceMinutes || limits.ExitGraceMinutes > maxGraceMinutes,
		limits.RestMinutes < minRestMinutes || limits.RestMinutes > maxRestMinutes:
		return errInvalidLimits
	}
	return nil
}

// loadLimits: the admin's limits, or the defaults while the admin has not saved any.
func loadLimits(ctx context.Context, nk runtime.NakamaModule) (Limits, error) {
	defaults := gameContent.Rules.Limits
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: settingsCollection, Key: limitsKey, UserID: systemUserID}})
	if err != nil {
		return Limits{}, errInternal
	}
	if len(objects) == 0 {
		return defaults, nil
	}
	var limits Limits
	if json.Unmarshal([]byte(objects[0].GetValue()), &limits) != nil || validateLimits(limits) != nil {
		return defaults, nil
	}
	return limits, nil
}

func (tx *gameTx) limits() (Limits, error) {
	if tx.loadedLimits == nil {
		limits, err := loadLimits(tx.ctx, tx.nk)
		if err != nil {
			return Limits{}, err
		}
		tx.loadedLimits = &limits
	}
	return *tx.loadedLimits, nil
}

// rpcAdminGetLimits: -> {"limits", "defaults"}.
func rpcAdminGetLimits(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	limits, err := loadLimits(ctx, nk)
	if err != nil {
		return "", err
	}
	return encodeResponse(map[string]any{"limits": limits, "defaults": gameContent.Rules.Limits})
}

// rpcAdminSetLimits: every Limits field -> the saved limits. They apply from the next player action.
func rpcAdminSetLimits(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var limits Limits
	if err := decodePayload(payload, &limits); err != nil {
		return "", err
	}
	if err := validateLimits(limits); err != nil {
		return "", err
	}
	value, err := json.Marshal(limits)
	if err != nil {
		return "", errInternal
	}
	if _, err := nk.StorageWrite(ctx, []*runtime.StorageWrite{{
		Collection: settingsCollection, Key: limitsKey, UserID: systemUserID, Value: string(value),
		PermissionRead: permissionNone, PermissionWrite: permissionNone,
	}}); err != nil {
		logger.Error("save limits: %v", err)
		return "", errInternal
	}
	logger.Info("limits changed: %s", value)
	return encodeResponse(limits)
}

// --- Task packs ------------------------------------------------------------------

// workdayIndex numbers workdays in a row: Friday is followed by the next Monday. Only for workdays.
func workdayIndex(day int) int {
	monday := day - weekday(day)
	// Day -3 (1969-12-29) is a Monday.
	return int(floorDiv(int64(monday+3), 7))*5 + weekday(day)
}

// taskPack: the pack tasks a player gets on `day`. Two workdays in a row share all pack tasks (every
// task except the check-in), shuffled for the player and the pair: the first day gets one half, the
// next day the rest. Weekends have no pack.
func taskPack(tasks []Task, userID string, day int) map[string]bool {
	pack := map[string]bool{}
	if !isWorkday(day) {
		return pack
	}
	ids := []string{}
	for _, task := range tasks {
		if task.Minigame != presenceMinigame {
			ids = append(ids, task.ID)
		}
	}
	index := workdayIndex(day)
	rng := seededRand(fmt.Sprintf("pack|%s|%d", userID, floorDiv(int64(index), 2)))
	rng.Shuffle(len(ids), func(i, j int) { ids[i], ids[j] = ids[j], ids[i] })
	half := ids[:len(ids)/2]
	if index%2 != 0 {
		half = ids[len(ids)/2:]
	}
	for _, id := range half {
		pack[id] = true
	}
	return pack
}

// isTodaysTask: the check-in or a task of today's pack.
func (tx *gameTx) isTodaysTask(task *Task) bool {
	if task.Minigame == presenceMinigame {
		return true
	}
	if tx.pack == nil {
		tx.pack = taskPack(tx.content.Tasks, tx.me.userID, tx.today)
	}
	return tx.pack[task.ID]
}

// --- Task hours and cooldown -----------------------------------------------------

// localMinute: minutes since midnight in the office time zone.
func localMinute(now, offset int64) int {
	return int(((now+offset)%secondsPerDay+secondsPerDay)%secondsPerDay) / 60
}

func inTaskWindow(limits Limits, now, offset int64) bool {
	start, _ := clockMinutes(limits.TaskWindowStart)
	end, _ := clockMinutes(limits.TaskWindowEnd)
	minute := localMinute(now, offset)
	return minute >= start && minute < end
}

// cooldownLeft: seconds until the next task may count, 0 when it may now.
func cooldownLeft(lastTaskAt, now int64, limits Limits) int64 {
	return max(0, lastTaskAt+int64(limits.TaskCooldownMinutes)*60-now)
}

// taskTimeError: "" or why the task cannot count right now. The check-in always counts.
func (tx *gameTx) taskTimeError(task *Task) (string, error) {
	if task.Minigame == presenceMinigame || (devMode && tx.me.state.DevNoTaskLimits) {
		return "", nil
	}
	limits, err := tx.limits()
	if err != nil {
		return "", err
	}
	if !inTaskWindow(limits, tx.now, tx.offset) {
		return "outside_task_window", nil
	}
	if cooldownLeft(tx.me.state.LastTaskAt, tx.now, limits) > 0 {
		return "task_cooldown", nil
	}
	return "", nil
}

// taskSchedule tells the client when tasks count, so it can lock them before the player starts.
type taskSchedule struct {
	CooldownMinutes int    `json:"cooldown_minutes"`
	NextTaskIn      int64  `json:"next_task_in"`
	WindowStart     string `json:"window_start"`
	WindowEnd       string `json:"window_end"`
	InWindow        bool   `json:"in_window"`
}

func (tx *gameTx) taskSchedule() (taskSchedule, error) {
	limits, err := tx.limits()
	if err != nil {
		return taskSchedule{}, err
	}
	schedule := taskSchedule{
		CooldownMinutes: limits.TaskCooldownMinutes,
		NextTaskIn:      cooldownLeft(tx.me.state.LastTaskAt, tx.now, limits),
		WindowStart:     limits.TaskWindowStart,
		WindowEnd:       limits.TaskWindowEnd,
		InWindow:        inTaskWindow(limits, tx.now, tx.offset),
	}
	if devMode && tx.me.state.DevNoTaskLimits {
		schedule.NextTaskIn, schedule.InWindow = 0, true
	}
	return schedule, nil
}
