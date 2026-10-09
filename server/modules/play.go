package main

import (
	"context"
	"database/sql"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Continuous play limit. While the game is on screen the client sends a heartbeat every
// playBeatSeconds and the server adds up the play time. After PlayLimitMinutes without a break the
// player is warned and has ExitGraceMinutes to leave the game. Leaving in time starts a rest of
// RestMinutes: the game shows the rest screen until it ends and then counts from zero. Staying past
// the grace locks the game until the next day. A break as long as the rest also starts the count anew.
//
// A task minigame is never interrupted. While one is on screen the heartbeat names its task; when
// the limit comes then, the rest is deferred: the player finishes the minigame (complete_task still
// counts) and the rest starts as soon as it ends, without the warning and its grace. The deferral
// lasts at most the minigame's time limit plus a margin, so a client cannot keep it forever.

const (
	playBeatSeconds = 30
	// A longer silence between heartbeats means the game was closed or in the background.
	playAwaySeconds = 90

	// Minigame time limit when the task names none, a margin over it and the longest deferral.
	defaultMinigameSeconds = 600
	minigameMarginSeconds  = 120
	maxMinigameSeconds     = 7200

	playOK       = "ok"
	playWarning  = "warning"
	playDeferred = "deferred"
	playResting  = "resting"
	playBlocked  = "blocked"
)

// PlaySession is the play-time part of the player state.
type PlaySession struct {
	// Seconds of play since the last rest.
	Seconds  int   `json:"seconds"`
	LastBeat int64 `json:"last_beat"`
	// Unix time of the warning; 0 when the player was not warned.
	WarnedAt  int64 `json:"warned_at,omitempty"`
	RestUntil int64 `json:"rest_until,omitempty"`
	// Office day the game is locked for; 0 when it is not.
	BlockedDay int `json:"blocked_day,omitempty"`
	// Task minigame on screen and when it began (heartbeats name it while it lasts).
	MinigameTask  string `json:"minigame_task,omitempty"`
	MinigameSince int64  `json:"minigame_since,omitempty"`
	// The limit came during a minigame: the rest starts when it ends, at DeferUntil at the latest.
	RestPending bool  `json:"rest_pending,omitempty"`
	DeferUntil  int64 `json:"defer_until,omitempty"`
}

type playStatus struct {
	State         string `json:"state"`
	PlayedSeconds int    `json:"played_seconds"`
	LimitMinutes  int    `json:"limit_minutes"`
	GraceMinutes  int    `json:"grace_minutes"`
	RestMinutes   int    `json:"rest_minutes"`
	// Seconds left of the grace (warning), of the deferral (deferred) or of the rest (resting).
	SecondsLeft int64 `json:"seconds_left"`
	BeatSeconds int   `json:"beat_seconds"`
}

// minigameDeadline notes the task minigame named by a heartbeat (nil = none on screen) and returns
// the latest time it may last, or 0 without one. The same task in a row keeps its start time.
func minigameDeadline(s *PlaySession, task *Task, now int64) int64 {
	if task == nil {
		s.MinigameTask, s.MinigameSince = "", 0
		return 0
	}
	if s.MinigameTask != task.ID || s.MinigameSince == 0 {
		s.MinigameTask, s.MinigameSince = task.ID, now
	}
	seconds := int64(defaultMinigameSeconds)
	if limit, ok := task.Params["time_limit"].(float64); ok && limit > 0 {
		seconds = int64(limit)
	}
	return s.MinigameSince + min(seconds, maxMinigameSeconds) + minigameMarginSeconds
}

// playBeat records a heartbeat at `now`. `minigameUntil` is the latest end of the task minigame on
// screen, 0 without one. Returns the seconds of play it adds and what happened: "" or playWarning,
// playDeferred (the limit came during a minigame), playResting (the player left in time or the
// minigame ended) or playBlocked (stayed past the grace).
func playBeat(s *PlaySession, now, offset int64, limits Limits, minigameUntil int64) (int, string) {
	today := dayOf(now, offset)
	if s.BlockedDay == today || s.RestUntil > now {
		return 0, ""
	}
	away := s.LastBeat == 0 || now-s.LastBeat > playAwaySeconds
	if s.RestPending {
		if minigameUntil == 0 || now >= s.DeferUntil {
			// The minigame is over (or took too long): the rest starts now. A camera screen can pause
			// the game for a while, so a silence inside the deferral still counts as the minigame.
			s.RestPending, s.WarnedAt, s.Seconds = false, 0, 0
			s.RestUntil = min(now, s.DeferUntil) + int64(limits.RestMinutes)*60
			s.LastBeat = now
			return 0, playResting
		}
		credit := int(min(now-s.LastBeat, playAwaySeconds))
		s.Seconds += credit
		s.LastBeat = now
		return credit, ""
	}
	if s.WarnedAt != 0 && minigameUntil > now && s.MinigameSince <= s.WarnedAt+playAwaySeconds {
		// The minigame began right as the warning came (the answer crossed the start): defer instead.
		s.RestPending, s.DeferUntil = true, minigameUntil
		s.LastBeat = now
		return 0, playDeferred
	}
	event := ""
	if s.WarnedAt != 0 {
		deadline := s.WarnedAt + int64(limits.ExitGraceMinutes)*60
		// The moment the player stopped playing: the last heartbeat, or now if they still play.
		left := now
		if away {
			left = s.LastBeat
		}
		switch {
		case left >= deadline:
			s.BlockedDay = dayOf(deadline, offset)
			event = playBlocked
		case away:
			s.RestUntil = s.LastBeat + int64(limits.RestMinutes)*60
			event = playResting
		}
		if event != "" {
			s.WarnedAt, s.Seconds = 0, 0
			if s.BlockedDay == today || s.RestUntil > now {
				s.LastBeat = now
				return 0, event
			}
		}
	}
	if s.RestUntil != 0 && s.RestUntil <= now {
		s.RestUntil, s.Seconds = 0, 0
	}
	if s.LastBeat != 0 && now-s.LastBeat >= int64(limits.RestMinutes)*60 {
		s.Seconds = 0
	}
	credit := 0
	if !away {
		credit = int(now - s.LastBeat)
	}
	s.Seconds += credit
	s.LastBeat = now
	if s.WarnedAt == 0 && s.Seconds >= limits.PlayLimitMinutes*60 {
		s.WarnedAt = now
		if minigameUntil > now {
			s.RestPending, s.DeferUntil = true, minigameUntil
			event = playDeferred
		} else if event == "" {
			event = playWarning
		}
	}
	return credit, event
}

// startRest: the warned player chose to rest now instead of waiting for the grace to run out.
func startRest(s *PlaySession, now int64, limits Limits) bool {
	if s.WarnedAt == 0 || now >= s.WarnedAt+int64(limits.ExitGraceMinutes)*60 {
		return false
	}
	s.WarnedAt, s.Seconds = 0, 0
	s.RestUntil = now + int64(limits.RestMinutes)*60
	s.LastBeat = now
	return true
}

func currentPlayStatus(s *PlaySession, now, offset int64, limits Limits) playStatus {
	status := playStatus{
		State: playOK, PlayedSeconds: s.Seconds, LimitMinutes: limits.PlayLimitMinutes,
		GraceMinutes: limits.ExitGraceMinutes, RestMinutes: limits.RestMinutes, BeatSeconds: playBeatSeconds,
	}
	switch {
	case s.BlockedDay == dayOf(now, offset):
		status.State = playBlocked
	case s.RestUntil > now:
		status.State = playResting
		status.SecondsLeft = s.RestUntil - now
	case s.RestPending:
		status.State = playDeferred
		status.SecondsLeft = max(0, s.DeferUntil-now)
	case s.WarnedAt != 0:
		status.State = playWarning
		status.SecondsLeft = max(0, s.WarnedAt+int64(limits.ExitGraceMinutes)*60-now)
	}
	return status
}

// playError: "" or why the player may not act now (resting or locked for the day). Tasks,
// purchases and colleague answers check it, so a modified client cannot play through the limit.
// A deferred rest lets the minigame on screen finish and count.
func (tx *gameTx) playError() (string, error) {
	limits, err := tx.limits()
	if err != nil {
		return "", err
	}
	status := currentPlayStatus(&tx.me.state.Play, tx.now, tx.offset, limits)
	switch {
	case status.State == playBlocked, status.State == playWarning && status.SecondsLeft == 0:
		return "play_blocked", nil
	case status.State == playResting:
		return "play_resting", nil
	}
	return "", nil
}

func (tx *gameTx) logPlayEvent(event string, limits Limits) {
	switch event {
	case playWarning:
		tx.logActivity(tx.me, activityPlayWarning, map[string]any{"minutes": limits.PlayLimitMinutes})
	case playDeferred:
		tx.logActivity(tx.me, activityPlayWarning, map[string]any{"minutes": limits.PlayLimitMinutes, "during_task": tx.me.state.Play.MinigameTask})
	case playResting:
		tx.logActivity(tx.me, activityPlayRest, map[string]any{"minutes": limits.RestMinutes})
	case playBlocked:
		tx.logActivity(tx.me, activityPlayBlocked, nil)
	}
}

// rpcPlayHeartbeat: {"minigame": task id or ""}: the game is on screen, with that task's minigame.
// -> playStatus. The first heartbeat after a launch also tells the client whether the player must
// rest or is locked for the day.
func rpcPlayHeartbeat(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Minigame string `json:"minigame"`
	}
	if payload != "" {
		if err := decodePayload(payload, &request); err != nil {
			return "", err
		}
	}
	// The heartbeat checks the office network itself (selfCheckedRpcs): one from outside still tells
	// the server that the player left the office Wi-Fi (visits.go) before it is refused.
	allowed, err := callerInOfficeNetwork(ctx, nk)
	if err != nil {
		return "", err
	}
	if !allowed {
		if err := recordOutsideHeartbeat(ctx, logger, db, nk); err != nil {
			return "", err
		}
		return "", errOfficeNetwork
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		limits, err := tx.limits()
		if err != nil {
			return nil, err
		}
		if err := tx.seenInOfficeNetwork(limits); err != nil {
			return nil, err
		}
		state := tx.me.state
		// Only an open task of today counts as a minigame; anything else is play as usual.
		task := tx.content.task(request.Minigame)
		if task != nil && (!tx.isTodaysTask(task) || contains(dayList(state.Completed, tx.today), task.ID)) {
			task = nil
		}
		until := minigameDeadline(&state.Play, task, tx.now)
		credit, event := playBeat(&state.Play, tx.now, tx.offset, limits, until)
		if credit > 0 {
			state.PlaySeconds[dayKey(tx.today)] += credit
		}
		tx.logPlayEvent(event, limits)
		return currentPlayStatus(&state.Play, tx.now, tx.offset, limits), nil
	})
}

// rpcPlayRest: the warned player leaves for the rest right away. -> playStatus.
func rpcPlayRest(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		limits, err := tx.limits()
		if err != nil {
			return nil, err
		}
		play := &tx.me.state.Play
		if startRest(play, tx.now, limits) {
			tx.logPlayEvent(playResting, limits)
		}
		return currentPlayStatus(play, tx.now, tx.offset, limits), nil
	})
}
