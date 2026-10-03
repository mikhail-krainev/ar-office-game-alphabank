package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"image"
	"image/png"
	"strings"
	"testing"
)

// 2026-09-14 is a Monday; UTC+5 like Yekaterinburg.
var monday = dayFromDate(2026, 9, 14)

const testOffset = 5 * 3600

func days(offsets ...int) map[string]bool {
	result := map[string]bool{}
	for _, offset := range offsets {
		result[dayKey(monday+offset)] = true
	}
	return result
}

func expectInt(t *testing.T, name string, got, want int64) {
	t.Helper()
	if got != want {
		t.Errorf("%s = %d, want %d", name, got, want)
	}
}

func TestCalendar(t *testing.T) {
	expectInt(t, "weekday(monday)", int64(weekday(monday)), 0)
	expectInt(t, "weekday(saturday)", int64(weekday(dayFromDate(2026, 9, 19))), 5)
	if !isWorkday(monday+4) || isWorkday(monday+5) {
		t.Error("Friday must be a workday and Saturday must not")
	}
	expectInt(t, "last Friday of September", int64(lastFridayOfMonth(monday)), int64(dayFromDate(2026, 9, 25)))
	expectInt(t, "last Friday of October", int64(lastFridayOfMonth(dayFromDate(2026, 10, 1))), int64(dayFromDate(2026, 10, 30)))
	expectInt(t, "last day of December", int64(lastDayOfMonth(dayFromDate(2026, 12, 5))), int64(dayFromDate(2026, 12, 31)))
	if shortDate(monday) != "14.09" {
		t.Errorf("shortDate = %q", shortDate(monday))
	}
	// 23:30 in Yekaterinburg is still the same local day, 00:30 is the next one.
	expectInt(t, "dayOf late evening", int64(dayOf(unixAt(monday, 23, 30, testOffset), testOffset)), int64(monday))
	expectInt(t, "dayOf after midnight", int64(dayOf(unixAt(monday+1, 0, 30, testOffset), testOffset)), int64(monday+1))
	expectInt(t, "dayOf before 1970", int64(dayOf(-1, 0)), -1)
}

func TestStreakSkipsWeekendsAndWaitsForToday(t *testing.T) {
	presence := days(-3, 0, 1, 2)
	expectInt(t, "Wednesday", int64(streak(presence, nil, monday+2, monday-30)), 4)
	expectInt(t, "Thursday before check-in", int64(streak(presence, nil, monday+3, monday-30)), 4)
	expectInt(t, "Friday after a missed Thursday", int64(streak(presence, nil, monday+4, monday-30)), 0)
}

func TestExcusedDaysDoNotBreakTheStreak(t *testing.T) {
	presence := days(0, 2)
	expectInt(t, "streak", int64(streak(presence, days(1), monday+2, monday-30)), 2)
	expectInt(t, "missed", int64(missedInRow(presence, days(1), monday+1, monday-30)), 0)
}

func TestUnbanExcusesTheBanWorkdays(t *testing.T) {
	// Banned on Wednesday after the check-in, unbanned the next Tuesday.
	state := &PlayerState{FirstDay: monday - 30, PresenceDays: days(0, 1, 2), ExcusedDays: map[string]bool{}}
	excuseDays(state, monday+2, monday+8)
	want := days(3, 4, 7)
	if len(state.ExcusedDays) != len(want) {
		t.Fatalf("excused = %v, want %v", state.ExcusedDays, want)
	}
	for key := range want {
		if !state.ExcusedDays[key] {
			t.Errorf("day %s not excused", key)
		}
	}
	expectInt(t, "streak", int64(streak(state.PresenceDays, state.ExcusedDays, monday+8, state.FirstDay)), 3)
	expectInt(t, "missed", int64(missedInRow(state.PresenceDays, state.ExcusedDays, monday+7, state.FirstDay)), 0)

	fresh := &PlayerState{PresenceDays: map[string]bool{}, ExcusedDays: map[string]bool{}}
	excuseDays(fresh, monday, monday+5)
	expectInt(t, "excused before the first login", int64(len(fresh.ExcusedDays)), 0)
}

func TestMissedDaysInARow(t *testing.T) {
	presence := days(0)
	expectInt(t, "Thursday", int64(missedInRow(presence, nil, monday+3, monday-30)), 3)
	expectInt(t, "next Monday", int64(missedInRow(presence, nil, monday+7, monday-30)), 5)
	expectInt(t, "before registration", int64(missedInRow(nil, nil, monday+1, monday)), 2)
}

func TestFines(t *testing.T) {
	tiers := []FineTier{{2, 3}, {3, 5}, {5, 10}, {10, 15}}
	for missed, want := range map[int]int{1: 0, 2: 3, 4: 5, 9: 10, 30: 15} {
		expectInt(t, fmt.Sprintf("finePercent(%d)", missed), int64(finePercent(missed, tiers)), int64(want))
	}
	cases := []struct{ balance, percent, want int64 }{{1000, 3, 30}, {970, 5, 49}, {1, 3, 1}, {0, 15, 0}, {10, 100, 10}, {500, 0, 0}}
	for _, c := range cases {
		expectInt(t, fmt.Sprintf("fineAmount(%d, %d)", c.balance, c.percent), fineAmount(c.balance, int(c.percent)), c.want)
	}
}

func TestStreakMultiplier(t *testing.T) {
	rules := &Rules{}
	rules.Economy.StreakMultiplierStep = 0.1
	rules.Economy.MaxStreakMultiplier = 2.0
	cases := []struct {
		streak  int
		present bool
		want    float64
	}{{0, false, 1.0}, {0, true, 1.0}, {4, false, 1.4}, {4, true, 1.3}, {30, true, 2.0}}
	for _, c := range cases {
		if got := streakMultiplier(c.streak, c.present, rules); fmt.Sprintf("%.2f", got) != fmt.Sprintf("%.2f", c.want) {
			t.Errorf("streakMultiplier(%d, %t) = %v, want %v", c.streak, c.present, got, c.want)
		}
	}
	task := &Task{Reward: 30, Difficulty: "hard"}
	expectInt(t, "taskReward", int64(taskReward(task, 1.5)), 90)
}

func TestPresenceTokens(t *testing.T) {
	const secret = "test-secret-0123456789"
	now := int64(1_790_000_000)
	step := presenceStep(now)
	entry := presenceToken(secret, purposeEntry, "hq", step)
	if problem := verifyPresenceToken(secret, purposeEntry, "hq", entry, now); problem != "" {
		t.Fatalf("fresh entry token rejected: %s", problem)
	}
	if verifyPresenceToken(secret, purposeExit, "hq", entry, now) == "" {
		t.Error("an entry token must not work as an exit token")
	}
	previous := presenceToken(secret, purposeEntry, "hq", step-1)
	if verifyPresenceToken(secret, purposeEntry, "hq", previous, now) != "" {
		t.Error("the previous step must still be accepted")
	}
	for name, token := range map[string]string{
		"two steps old":   presenceToken(secret, purposeEntry, "hq", step-2),
		"from the future": presenceToken(secret, purposeEntry, "hq", step+1),
		"other secret":    presenceToken("another-secret-000000", purposeEntry, "hq", step),
		"other office":    strings.Replace(entry, "hq.", "branch.", 1),
		"forged":          fmt.Sprintf("hq.%d.%s", step, strings.Repeat("00", presenceSignatureBytes)),
		"garbage":         "garbage",
	} {
		if verifyPresenceToken(secret, purposeEntry, "hq", token, now) == "" {
			t.Errorf("%s token accepted", name)
		}
	}
	codes := currentKioskCodes("hq", now)
	if codes.SecondsLeft < 1 || codes.SecondsLeft > presencePeriodSeconds || codes.Entry == codes.Exit {
		t.Errorf("kiosk codes = %+v", codes)
	}
}

func TestInOfficeInterval(t *testing.T) {
	state := &PlayerState{}
	state.normalize()
	if inOffice(state, monday) {
		t.Error("in the office without an entry")
	}
	state.CheckinAt[dayKey(monday)] = 100
	if !inOffice(state, monday) || inOffice(state, monday+1) {
		t.Error("the interval must be open today and closed the next day")
	}
	state.CheckoutAt[dayKey(monday)] = 200
	if inOffice(state, monday) {
		t.Error("still in the office after the exit code")
	}
	state.CheckinAt[dayKey(monday)] = 300
	if !inOffice(state, monday) {
		t.Error("coming back after lunch must reopen the interval")
	}
}

func TestRaffleDraw(t *testing.T) {
	const seed = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
	raw, _ := hex.DecodeString(seed)
	sum := sha256.Sum256(raw)
	if raffleCommitment(seed) != hex.EncodeToString(sum[:]) {
		t.Error("commitment is not SHA-256 of the seed")
	}
	winner := raffleWinner(seed, "parking-2026-09", []string{"c", "a", "b"})
	if winner != raffleWinner(seed, "parking-2026-09", []string{"b", "c", "a"}) {
		t.Error("the ticket order changed the winner")
	}
	if raffleWinner(seed, "parking-2026-09", nil) != "" {
		t.Error("a winner without tickets")
	}
	counts := map[string]int{}
	entries := []string{"a", "b", "c", "d"}
	for i := range 400 {
		fresh, err := newRaffleSeed()
		if err != nil {
			t.Fatal(err)
		}
		counts[raffleWinner(fresh, fmt.Sprintf("draw-%d", i), entries)]++
	}
	for _, entry := range entries {
		if counts[entry] < 50 {
			t.Errorf("%s won %d of 400 draws; the draw looks biased", entry, counts[entry])
		}
	}
	id, at := raffleSchedule(monday, &Rules{}, testOffset)
	if id != "parking-2026-09" || dayOf(at, testOffset) != dayFromDate(2026, 9, 25) {
		t.Errorf("schedule on Monday = %s, day %d", id, dayOf(at, testOffset))
	}
	if id, _ := raffleSchedule(dayFromDate(2026, 9, 26), &Rules{}, testOffset); id != "parking-2026-10" {
		t.Errorf("after the September draw day the October draw is current, got %s", id)
	}
}

func testFacts(nowHour int, present bool, currentStreak int) planFacts {
	return planFacts{
		now: unixAt(monday, nowHour, 0, testOffset), offset: testOffset, today: monday, streak: currentStreak,
		presentToday: present, reminderTimes: []string{"09:30", "14:00", "18:30"}, seed: "player",
	}
}

func ofKind(plan []plannedNotification, kind string) []plannedNotification {
	result := []plannedNotification{}
	for _, item := range plan {
		if item.Kind == kind {
			result = append(result, item)
		}
	}
	return result
}

func TestNotificationPlan(t *testing.T) {
	tomorrow := unixAt(monday+1, 0, 0, testOffset)
	today := []plannedNotification{}
	for _, item := range ofKind(planNotifications(testFacts(12, false, 4)), "streak_reminder") {
		if item.At < tomorrow {
			today = append(today, item)
		}
	}
	if len(today) != 2 || today[0].Params["streak"] != 4 || today[0].Params["deadline"] != "23:59 14.09" {
		t.Errorf("reminders before check-in = %+v", today)
	}
	after := ofKind(planNotifications(testFacts(12, true, 5)), "streak_reminder")
	if len(after) != 3 || after[0].At < tomorrow {
		t.Errorf("after check-in only tomorrow's reminders, got %+v", after)
	}
	gentle := planNotifications(testFacts(8, false, 0))
	if len(ofKind(gentle, "streak_reminder")) != 0 || len(ofKind(gentle, "check_in_reminder")) != 1 {
		t.Errorf("without a streak one gentle reminder, got %+v", gentle)
	}
	facts := testFacts(12, true, 1)
	facts.raffleDrawAt = unixAt(monday+1, 18, 0, testOffset)
	plan := planNotifications(facts)
	day, hour := ofKind(plan, "raffle_day"), ofKind(plan, "raffle_hour")
	if len(day) != 1 || len(hour) != 1 || day[0].At != unixAt(monday, 18, 0, testOffset) || day[0].Params["time"] != "18:00" {
		t.Errorf("draw announcements = %+v %+v", day, hour)
	}
	nudges := testFacts(0, true, 1)
	nudges.funTexts, nudges.funMax = []string{"a", "b", "c"}, 2
	nudges.funWindows = [][]string{{"07:00", "08:30"}, {"18:00", "21:00"}}
	for seed := range 20 {
		nudges.seed = fmt.Sprintf("player-%d", seed)
		for _, item := range ofKind(planNotifications(nudges), "fun") {
			local := dayOf(item.At, testOffset)
			morning := item.At >= unixAt(local, 7, 0, testOffset) && item.At < unixAt(local, 8, 30, testOffset)
			evening := item.At >= unixAt(local, 18, 0, testOffset) && item.At < unixAt(local, 21, 0, testOffset)
			if !morning && !evening {
				t.Errorf("nudge outside the windows: %+v", item)
			}
		}
	}
	first, second := planNotifications(testFacts(8, false, 3)), planNotifications(testFacts(8, false, 3))
	for i := range first {
		if first[i].ID != second[i].ID || first[i].ID < 0 {
			t.Error("notification ids must be stable and positive")
		}
	}
}

func TestDailyShop(t *testing.T) {
	catalog := []CatalogItem{}
	for i, rarity := range []string{"common", "common", "common", "common", "rare", "rare", "epic", "legendary"} {
		catalog = append(catalog, CatalogItem{ID: fmt.Sprintf("item%d", i), Rarity: rarity, Price: 100})
	}
	first, again := dailyOffers(catalog, monday), dailyOffers(catalog, monday)
	if len(first) != shopSlots {
		t.Fatalf("offers = %d, want %d", len(first), shopSlots)
	}
	seen := map[string]bool{}
	for i := range first {
		if first[i] != again[i] {
			t.Fatal("the same day must give the same shop to everyone")
		}
		if seen[first[i].ItemID] {
			t.Errorf("item %s offered twice", first[i].ItemID)
		}
		seen[first[i].ItemID] = true
		if first[i].DiscountPercent > 0 && first[i].Price >= first[i].BasePrice {
			t.Errorf("discount without a lower price: %+v", first[i])
		}
	}
}

func TestStatusAndAvatar(t *testing.T) {
	if clean, ok := cleanStatus("  Иду\nна кофе\t "); !ok || clean != "Идуна кофе" {
		t.Errorf("cleanStatus = %q, %t", clean, ok)
	}
	if _, ok := cleanStatus(strings.Repeat("я", maxStatusLength+1)); ok {
		t.Error("a too long status passed")
	}
	encode := func(side int) string {
		var buffer bytes.Buffer
		_ = png.Encode(&buffer, image.NewRGBA(image.Rect(0, 0, side, side)))
		return base64.StdEncoding.EncodeToString(buffer.Bytes())
	}
	if _, problem := validAvatarPNG(encode(avatarSide)); problem != "" {
		t.Errorf("a valid avatar rejected: %s", problem)
	}
	if _, problem := validAvatarPNG(encode(32)); problem != "avatar_invalid" {
		t.Errorf("a 32 px avatar: %q", problem)
	}
	if _, problem := validAvatarPNG("not base64!"); problem == "" {
		t.Error("garbage accepted as an avatar")
	}
	templates := []string{"me", "anna", "fox"}
	if got := publicAvatar("some-user", "me", templates); got == "me" || !contains(templates, got) {
		t.Errorf("publicAvatar(me) = %q", got)
	}
	if publicAvatar("some-user", "fox", templates) != "fox" {
		t.Error("a chosen template must stay")
	}
}
