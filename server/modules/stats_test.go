package main

import "testing"

func TestStatsSummaryAndDays(t *testing.T) {
	state := &PlayerState{FirstDay: monday, BestStreak: 1}
	state.normalize()
	// In the office Monday and Tuesday, missed Wednesday, back on Friday; today is Monday next week.
	state.PresenceDays = days(0, 1, 4)
	state.CheckinAt[dayKey(monday)] = 100
	state.Completed[dayKey(monday)] = []string{"check_in", "squats"}
	state.Skipped[dayKey(monday+1)] = []string{"carry_coffee"}
	state.Met[dayKey(monday)] = []string{"a", "b"}
	state.Met[dayKey(monday+4)] = []string{"a"}
	state.TaskLog[dayKey(monday)] = []TaskLogEntry{{ID: "check_in", Reward: 10, T: 100}}
	state.Earned[dayKey(monday)] = 10
	today := monday + 7

	var summary playerSummary
	summarize(&summary, state, today)
	expectInt(t, "streak", int64(summary.Streak), 1)
	expectInt(t, "best streak", int64(summary.BestStreak), 1)
	expectInt(t, "office days", int64(summary.OfficeDays), 3)
	expectInt(t, "tasks", int64(summary.TasksTotal), 2)
	expectInt(t, "skipped", int64(summary.SkippedTotal), 1)
	expectInt(t, "colleagues", int64(summary.Colleagues), 2)

	names := newNameBook(&Content{Tasks: []Task{{ID: "carry_coffee", Title: "Донести кофе"}}})
	list := statsDays(state, playerSummary{Today: today}, names)
	// Newest first; the weekend without activity is left out: next Monday + Friday..Monday workdays.
	expectInt(t, "days", int64(len(list)), 6)
	expectInt(t, "first listed day", int64(list[0].Day), int64(today))
	last := list[len(list)-1]
	if last.Day != monday || !last.Present || last.CheckinAt != 100 || len(last.Tasks) != 1 {
		t.Errorf("first day record = %+v", last)
	}
	tuesday := list[len(list)-2]
	if len(tuesday.Skipped) != 1 || tuesday.Skipped[0].Name != "Донести кофе" {
		t.Errorf("skipped tasks = %+v", tuesday.Skipped)
	}
	if !names.userIDs["a"] || !names.userIDs["b"] {
		t.Error("met colleagues must be collected for name lookup")
	}
}
