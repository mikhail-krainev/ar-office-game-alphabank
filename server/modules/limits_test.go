package main

import (
	"fmt"
	"testing"
)

var testLimits = Limits{
	TaskCooldownMinutes: 30, TaskWindowStart: "08:00", TaskWindowEnd: "20:00",
	PlayLimitMinutes: 60, ExitGraceMinutes: 5, RestMinutes: 30, AwayMinutes: 15,
}

func packTasks(count int) []Task {
	tasks := []Task{{ID: "check_in", Minigame: presenceMinigame}}
	for i := range count {
		tasks = append(tasks, Task{ID: fmt.Sprintf("task_%d", i), Minigame: "stairs"})
	}
	return tasks
}

func TestWorkdayIndexSkipsWeekends(t *testing.T) {
	for offset := range 4 {
		expectInt(t, "Monday..Thursday in a row", int64(workdayIndex(monday+offset+1)-workdayIndex(monday+offset)), 1)
	}
	expectInt(t, "Friday to Monday", int64(workdayIndex(monday+7)-workdayIndex(monday+4)), 1)
	expectInt(t, "1970-01-01 (Thursday)", int64(workdayIndex(0)), 3)
}

func TestTaskPacksSplitAllTasksOverTwoWorkdays(t *testing.T) {
	tasks := packTasks(11)
	for _, start := range []int{monday, monday + 1, monday + 4} {
		first, second := taskPack(tasks, "player", start), taskPack(tasks, "player", nextWorkday(start))
		if workdayIndex(start)%2 != 0 {
			// Odd days close a pair: look at the pair that starts on the next workday instead.
			continue
		}
		if len(first)+len(second) != 11 || len(first) != 5 || len(second) != 6 {
			t.Errorf("pack sizes from %d: %d + %d", start, len(first), len(second))
		}
		for id := range first {
			if second[id] {
				t.Errorf("task %s is in both packs of the pair", id)
			}
		}
		if first["check_in"] || second["check_in"] {
			t.Error("the check-in is never in a pack")
		}
	}
	if len(taskPack(tasks, "player", monday+5)) != 0 {
		t.Error("weekends have no pack")
	}
	// Players get their own packs; one player always gets the same pack for a day.
	same := 0
	for i := range 20 {
		day := monday + 7*i
		if fmt.Sprint(taskPack(tasks, "anna", day)) == fmt.Sprint(taskPack(tasks, "igor", day)) {
			same++
		}
		if fmt.Sprint(taskPack(tasks, "anna", day)) != fmt.Sprint(taskPack(tasks, "anna", day)) {
			t.Error("a pack must not change within the day")
		}
	}
	if same > 2 {
		t.Errorf("packs of two players matched on %d of 20 days", same)
	}
}

func nextWorkday(day int) int {
	day++
	for !isWorkday(day) {
		day++
	}
	return day
}

func TestTaskWindowAndCooldown(t *testing.T) {
	inside := unixAt(monday, 8, 0, testOffset)
	if !inTaskWindow(testLimits, inside, testOffset) || !inTaskWindow(testLimits, unixAt(monday, 19, 59, testOffset), testOffset) {
		t.Error("08:00 and 19:59 are inside the task hours")
	}
	if inTaskWindow(testLimits, unixAt(monday, 7, 59, testOffset), testOffset) || inTaskWindow(testLimits, unixAt(monday, 20, 0, testOffset), testOffset) {
		t.Error("07:59 and 20:00 are outside the task hours")
	}
	expectInt(t, "cooldown right after a task", cooldownLeft(inside, inside, testLimits), 1800)
	expectInt(t, "cooldown after 29 minutes", cooldownLeft(inside, inside+29*60, testLimits), 60)
	expectInt(t, "cooldown after 30 minutes", cooldownLeft(inside, inside+30*60, testLimits), 0)
	expectInt(t, "no task yet", cooldownLeft(0, inside, testLimits), 0)
}

func TestValidateLimits(t *testing.T) {
	if err := validateLimits(testLimits); err != nil {
		t.Errorf("defaults rejected: %v", err)
	}
	broken := []func(*Limits){
		func(l *Limits) { l.TaskCooldownMinutes = -1 },
		func(l *Limits) { l.TaskCooldownMinutes = maxCooldownMinutes + 1 },
		func(l *Limits) { l.TaskWindowStart = "8:00" },
		func(l *Limits) { l.TaskWindowEnd = "24:00" },
		func(l *Limits) { l.TaskWindowStart, l.TaskWindowEnd = "20:00", "08:00" },
		func(l *Limits) { l.PlayLimitMinutes = 0 },
		func(l *Limits) { l.ExitGraceMinutes = 0 },
		func(l *Limits) { l.RestMinutes = maxRestMinutes + 1 },
	}
	for i, breakIt := range broken {
		limits := testLimits
		breakIt(&limits)
		if validateLimits(limits) == nil {
			t.Errorf("case %d must be rejected: %+v", i, limits)
		}
	}
	zero := testLimits
	zero.TaskCooldownMinutes = 0
	if validateLimits(zero) != nil {
		t.Error("a zero cooldown turns the cooldown off and is allowed")
	}
}

func TestHiddenTasksNeverGetIntoPacks(t *testing.T) {
	tasks := packTasks(11)
	tasks[1].Hidden = true
	for day := monday; day < monday+5; day++ {
		if taskPack(tasks, "player", day)[tasks[1].ID] {
			t.Fatalf("hidden task %s is in the pack of day %d", tasks[1].ID, day)
		}
	}
}
