package main

import "testing"

// playFor sends heartbeats every playBeatSeconds from `start` for `seconds`; returns the last beat time.
func playFor(s *PlaySession, start int64, seconds int) int64 {
	now := start
	for elapsed := 0; elapsed <= seconds; elapsed += playBeatSeconds {
		now = start + int64(elapsed)
		playBeat(s, now, testOffset, testLimits, 0)
	}
	return now
}

func expectState(t *testing.T, name string, s *PlaySession, now int64, want string) playStatus {
	t.Helper()
	status := currentPlayStatus(s, now, testOffset, testLimits)
	if status.State != want {
		t.Errorf("%s: state %q, want %q (%+v)", name, status.State, want, *s)
	}
	return status
}

func TestPlayWarnsAfterTheLimit(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	now := playFor(&s, start, 59*60)
	expectState(t, "after 59 minutes", &s, now, playOK)
	expectInt(t, "seconds counted", int64(s.Seconds), 59*60)
	// A late heartbeat (60 s instead of 30) still counts in full.
	now += 60
	_, event := playBeat(&s, now, testOffset, testLimits, 0)
	if event != playWarning {
		t.Errorf("event at the limit = %q", event)
	}
	status := expectState(t, "at the limit", &s, now, playWarning)
	expectInt(t, "grace left", status.SecondsLeft, 5*60)
}

func TestLeavingInTimeStartsTheRest(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	warned := playFor(&s, start, 60*60)
	expectState(t, "warned", &s, warned, playWarning)
	// The player closes the game two minutes later and comes back after ten minutes.
	left := playFor(&s, warned, 2*60)
	back := left + 10*60
	if _, event := playBeat(&s, back, testOffset, testLimits, 0); event != playResting {
		t.Errorf("event on return = %q", event)
	}
	status := expectState(t, "back too early", &s, back, playResting)
	expectInt(t, "rest left", status.SecondsLeft, 20*60)
	// After the rest the count starts from zero.
	after := left + 30*60
	playBeat(&s, after, testOffset, testLimits, 0)
	expectState(t, "after the rest", &s, after, playOK)
	expectInt(t, "seconds after the rest", int64(s.Seconds), 0)
}

func TestStayingPastTheGraceLocksTheDay(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	warned := playFor(&s, start, 60*60)
	now := playFor(&s, warned, 5*60)
	expectState(t, "past the grace", &s, now, playBlocked)
	if _, event := playBeat(&s, now+3600, testOffset, testLimits, 0); event != "" {
		t.Errorf("a locked player's heartbeat changes nothing, got %q", event)
	}
	expectState(t, "an hour later", &s, now+3600, playBlocked)
	tomorrow := unixAt(monday+1, 9, 0, testOffset)
	playBeat(&s, tomorrow, testOffset, testLimits, 0)
	expectState(t, "next day", &s, tomorrow, playOK)
	expectInt(t, "seconds next day", int64(s.Seconds), 0)
}

func TestClosingAfterTheGraceStillLocks(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	warned := playFor(&s, start, 60*60)
	left := playFor(&s, warned, 6*60)
	back := left + 40*60
	if _, event := playBeat(&s, back, testOffset, testLimits, 0); event != "" && event != playBlocked {
		t.Errorf("event = %q", event)
	}
	expectState(t, "returned after playing past the grace", &s, back, playBlocked)
}

func TestRestNowAndNaturalBreaks(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	warned := playFor(&s, start, 60*60)
	if !startRest(&s, warned+60, testLimits) {
		t.Fatal("a warned player may rest at once")
	}
	expectState(t, "resting", &s, warned+60, playResting)
	if startRest(&s, warned+120, testLimits) {
		t.Error("rest cannot start twice")
	}

	// A break as long as the rest resets the count without any warning.
	var natural PlaySession
	now := playFor(&natural, start, 40*60)
	now += 30 * 60
	playBeat(&natural, now, testOffset, testLimits, 0)
	expectInt(t, "seconds after a long break", int64(natural.Seconds), 0)
	// A short break keeps it.
	now = playFor(&natural, now, 10*60)
	playBeat(&natural, now+5*60, testOffset, testLimits, 0)
	expectInt(t, "seconds after a short break", int64(natural.Seconds), 10*60)
}

func TestLimitDuringAMinigameDefersTheRest(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	now := playFor(&s, start, 58*60)
	task := &Task{ID: "squats", Params: map[string]any{"time_limit": float64(120)}}
	// The player starts the minigame at 58 minutes; the limit comes in the middle of it.
	for elapsed := int64(30); elapsed <= 120; elapsed += playBeatSeconds {
		until := minigameDeadline(&s, task, now+elapsed)
		_, event := playBeat(&s, now+elapsed, testOffset, testLimits, until)
		if elapsed == 120 && event != playDeferred {
			t.Errorf("event at the limit in a minigame = %q", event)
		}
	}
	status := expectState(t, "inside the minigame", &s, now+120, playDeferred)
	if status.SecondsLeft <= 0 {
		t.Errorf("deferral must last while the minigame may, got %d", status.SecondsLeft)
	}
	// Still inside the minigame three minutes later: no grace runs out, nothing is locked.
	inside := now + 180
	playBeat(&s, inside, testOffset, testLimits, minigameDeadline(&s, task, inside))
	expectState(t, "still in the minigame", &s, inside, playDeferred)
	// The minigame ends: the rest starts at once.
	end := inside + 20
	if _, event := playBeat(&s, end, testOffset, testLimits, minigameDeadline(&s, nil, end)); event != playResting {
		t.Errorf("event after the minigame = %q", event)
	}
	rest := expectState(t, "after the minigame", &s, end, playResting)
	expectInt(t, "rest left", rest.SecondsLeft, 30*60)
}

func TestDeferralEndsWithTheMinigameTimeLimit(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	task := &Task{ID: "squats", Params: map[string]any{"time_limit": float64(120)}}
	first := minigameDeadline(&s, task, start)
	expectInt(t, "deadline", first, start+120+minigameMarginSeconds)
	if minigameDeadline(&s, task, start+60) != first {
		t.Error("the same minigame in a row keeps its start")
	}
	s = PlaySession{Seconds: 60 * 60, LastBeat: start, WarnedAt: start, RestPending: true, DeferUntil: start + 240}
	// A client that keeps naming the minigame past its limit gets the rest anyway.
	late := start + 300
	if _, event := playBeat(&s, late, testOffset, testLimits, start+600); event != playResting {
		t.Errorf("event past the deferral = %q", event)
	}
	expectInt(t, "rest counts from the end of the deferral", s.RestUntil, start+240+30*60)
}

func TestMinigameStartedAsTheWarningCameIsDeferred(t *testing.T) {
	var s PlaySession
	start := unixAt(monday, 10, 0, testOffset)
	warned := playFor(&s, start, 60*60)
	task := &Task{ID: "stairs", Params: map[string]any{"time_limit": float64(300)}}
	next := warned + playBeatSeconds
	if _, event := playBeat(&s, next, testOffset, testLimits, minigameDeadline(&s, task, next)); event != playDeferred {
		t.Errorf("event = %q", event)
	}
	// Six minutes in the minigame: past the grace, but nothing is locked.
	later := next + 6*60
	playBeat(&s, later, testOffset, testLimits, minigameDeadline(&s, task, later))
	expectState(t, "long minigame", &s, later, playDeferred)
	// A minigame started long after the warning is not deferred: the client locks tasks then.
	var late PlaySession
	warned = playFor(&late, start, 60*60)
	playFor(&late, warned, 3*60)
	minigameDeadline(&late, task, warned+3*60)
	later = warned + 3*60 + playBeatSeconds
	if _, event := playBeat(&late, later, testOffset, testLimits, minigameDeadline(&late, task, later)); event == playDeferred {
		t.Error("a minigame started in the grace must not defer the rest")
	}
}
