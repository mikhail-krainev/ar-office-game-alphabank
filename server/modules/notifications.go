package main

import (
	"context"
	"database/sql"
	"fmt"
	"hash/fnv"
	"sort"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Scheduled notifications (reminders, draw announcements, light-hearted nudges). The server
// returns a plan for the next days; the client hands it to the OS scheduler and replaces it on
// every sync, so a stale plan never outlives the next launch.

const (
	planHorizonDays = 2
	dayEndHour      = 23
	dayEndMinute    = 59
	// Nudges keep this distance from other notifications of the plan.
	minNudgeGapSeconds = 3600
)

type planFacts struct {
	now           int64
	offset        int64
	today         int
	streak        int
	presentToday  bool
	reminderTimes []string
	raffleDrawAt  int64
	raffleJoined  bool
	funTexts      []string
	funWindows    [][]string
	funMax        int
	seed          string
}

type plannedNotification struct {
	ID           int64          `json:"id"`
	At           int64          `json:"at"`
	DelaySeconds int64          `json:"delay_seconds"`
	Kind         string         `json:"kind"`
	Params       map[string]any `json:"params"`
}

func planNotifications(facts planFacts) []plannedNotification {
	plan := []plannedNotification{}
	for offset := range planHorizonDays {
		plan = planStreak(facts, facts.today+offset, plan)
	}
	plan = planRaffle(facts, plan)
	for offset := range planHorizonDays {
		plan = planFun(facts, facts.today+offset, plan)
	}
	sort.SliceStable(plan, func(i, j int) bool { return plan[i].At < plan[j].At })
	for i := range plan {
		plan[i].DelaySeconds = max(0, plan[i].At-facts.now)
	}
	return plan
}

// planStreak: workday reminders to check in before the day ends. Tomorrow's reminder is planned
// only when the streak is already safe today; otherwise the next sync replaces it.
func planStreak(facts planFacts, day int, plan []plannedNotification) []plannedNotification {
	if !isWorkday(day) || (day == facts.today && facts.presentToday) {
		return plan
	}
	if day > facts.today && !facts.presentToday && isWorkday(facts.today) {
		return plan
	}
	deadline := unixAt(day, dayEndHour, dayEndMinute, facts.offset)
	deadlineText := fmt.Sprintf("%02d:%02d %s", dayEndHour, dayEndMinute, shortDate(day))
	for index, text := range facts.reminderTimes {
		hour, minute := parseClock(text)
		at := unixAt(day, hour, minute, facts.offset)
		if at <= facts.now || at >= deadline {
			continue
		}
		if facts.streak > 0 {
			plan = addPlanned(plan, "streak_reminder", day, index, at, map[string]any{"streak": facts.streak, "deadline": deadlineText})
		} else if index == 0 {
			// Without a streak one gentle reminder a day is enough.
			plan = addPlanned(plan, "check_in_reminder", day, index, at, map[string]any{"deadline": deadlineText})
		}
	}
	return plan
}

func planRaffle(facts planFacts, plan []plannedNotification) []plannedNotification {
	if facts.raffleDrawAt <= 0 {
		return plan
	}
	drawDay := dayOf(facts.raffleDrawAt, facts.offset)
	local := ((facts.raffleDrawAt+facts.offset)%secondsPerDay + secondsPerDay) % secondsPerDay
	params := map[string]any{"time": fmt.Sprintf("%02d:%02d", local/3600, local/60%60), "date": shortDate(drawDay), "joined": facts.raffleJoined}
	for _, entry := range []struct {
		kind   string
		before int64
	}{{"raffle_day", 86400}, {"raffle_hour", 3600}} {
		if at := facts.raffleDrawAt - entry.before; at > facts.now {
			plan = addPlanned(plan, entry.kind, drawDay, 0, at, params)
		}
	}
	return plan
}

// funSpan is one window for nudges on a day: its start and length in minutes.
type funSpan struct {
	start   int64
	minutes int64
}

// planFun: one or two nudges a day at random minutes inside the windows, away from other
// notifications. The windows lie outside working hours, so the game never calls during work.
func planFun(facts planFacts, day int, plan []plannedNotification) []plannedNotification {
	spans := []funSpan{}
	total := int64(0)
	for _, window := range facts.funWindows {
		if len(window) != 2 {
			continue
		}
		startHour, startMinute := parseClock(window[0])
		endHour, endMinute := parseClock(window[1])
		start := unixAt(day, startHour, startMinute, facts.offset)
		minutes := (unixAt(day, endHour, endMinute, facts.offset) - start) / 60
		if minutes > 0 {
			spans = append(spans, funSpan{start: start, minutes: minutes})
			total += minutes
		}
	}
	if len(facts.funTexts) == 0 || facts.funMax <= 0 || total == 0 {
		return plan
	}
	rng := seededRand(fmt.Sprintf("fun|%s|%d", facts.seed, day))
	count := 1 + rng.IntN(facts.funMax)
	used := map[int]bool{}
	for index := range count {
		at := funMinute(spans, rng.Int64N(total))
		textIndex := rng.IntN(len(facts.funTexts))
		if used[textIndex] {
			textIndex = (textIndex + 1) % len(facts.funTexts)
		}
		used[textIndex] = true
		if at <= facts.now || !isFree(plan, at) {
			continue
		}
		plan = addPlanned(plan, "fun", day, index, at, map[string]any{"text": facts.funTexts[textIndex]})
	}
	return plan
}

// funMinute: unix time of the `minute`-th minute counted through the spans one after another.
func funMinute(spans []funSpan, minute int64) int64 {
	for _, span := range spans {
		if minute < span.minutes {
			return span.start + minute*60
		}
		minute -= span.minutes
	}
	last := spans[len(spans)-1]
	return last.start + last.minutes*60
}

func isFree(plan []plannedNotification, at int64) bool {
	for _, item := range plan {
		if gap := item.At - at; gap < minNudgeGapSeconds && gap > -minNudgeGapSeconds {
			return false
		}
	}
	return true
}

func addPlanned(plan []plannedNotification, kind string, day, index int, at int64, params map[string]any) []plannedNotification {
	return append(plan, plannedNotification{ID: notificationID(kind, day, index), At: at, Kind: kind, Params: params})
}

// notificationID: stable positive id, so rescheduling replaces a notification instead of duplicating it.
func notificationID(kind string, day, index int) int64 {
	hash := fnv.New32a()
	fmt.Fprintf(hash, "%s|%d|%d", kind, day, index)
	return int64(hash.Sum32() & 0x7fffffff)
}

func rpcGetNotificationPlan(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if err := tx.tick(); err != nil {
			return nil, err
		}
		draw, err := tx.currentDraw()
		if err != nil {
			return nil, err
		}
		state := tx.me.state
		rules := tx.content.Rules.Notifications
		facts := planFacts{
			now: tx.now, offset: tx.offset, today: tx.today,
			streak:       streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay),
			presentToday: state.PresenceDays[dayKey(tx.today)], reminderTimes: rules.ReminderTimes,
			raffleJoined: contains(draw.draw.Tickets, tx.me.userID),
			funTexts:     tx.content.FunTexts, funWindows: rules.FunWindows, funMax: rules.FunMax, seed: tx.me.userID,
		}
		if !draw.draw.Drawn {
			facts.raffleDrawAt = draw.draw.DrawAt
		}
		return map[string]any{"notifications": planNotifications(facts)}, nil
	})
}
