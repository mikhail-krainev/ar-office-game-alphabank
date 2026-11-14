package main

import (
	"math"
	"path/filepath"
	"testing"
)

func testClicker(t *testing.T) *ClickerContent {
	t.Helper()
	content, err := loadContent(filepath.Join("..", "content"))
	if err != nil {
		t.Fatalf("load content: %v", err)
	}
	return &content.Clicker
}

func newClickerState(c *ClickerContent) *ClickerState {
	s := &ClickerState{}
	c.normalize(s)
	return s
}

func TestClickerTapsAreCappedAndComboed(t *testing.T) {
	c := testClicker(t)
	s := newClickerState(c)
	s.LastSync = 1000
	tick := c.tick(s, 1002, 500, true, nil)
	if tick.Taps != int64(c.MaxTapsPerSecond*2) {
		t.Fatalf("taps = %d, want the cap %v", tick.Taps, c.MaxTapsPerSecond*2)
	}
	if tick.Combo != c.ComboMax {
		t.Fatalf("combo = %v, want %v", tick.Combo, c.ComboMax)
	}
	if s.Points != float64(tick.Taps)*c.ComboMax {
		t.Fatalf("points = %v", s.Points)
	}
	slow := newClickerState(c)
	slow.LastSync = 1000
	if tick := c.tick(slow, 1004, 4, true, nil); tick.Combo != 1 || slow.Points != 4 {
		t.Fatalf("slow taps: combo %v, points %v", tick.Combo, slow.Points)
	}
}

func TestClickerPassiveOnlineAndOffline(t *testing.T) {
	c := testClicker(t)
	s := newClickerState(c)
	s.Idle[0] = 6
	rate := c.idleRate(s)
	s.LastSync = 10_000
	if tick := c.tick(s, 10_010, 0, true, nil); tick.Offline || math.Abs(tick.Passive-rate*10) > 1e-9 {
		t.Fatalf("online tick = %+v, rate %v", tick, rate)
	}
	// Closed for a day: only the office interval counts, capped at OfficeHours, at half the rate.
	s.Points = 0
	windows := []officeWindow{{from: 20_000, to: 20_000 + 20*3600}}
	tick := c.tick(s, 200_000, 0, true, windows)
	if !tick.Offline || tick.Seconds != c.OfficeHours*3600 {
		t.Fatalf("offline tick = %+v", tick)
	}
	if want := rate * float64(c.OfficeHours*3600) * c.OfflineRate; math.Abs(s.Points-want) > want*1e-12 {
		t.Fatalf("offline points = %v, want %v", s.Points, want)
	}
	// Not in the office: nothing.
	s.Points = 0
	if tick := c.tick(s, 400_000, 0, false, nil); tick.Passive != 0 || s.Points != 0 {
		t.Fatalf("away tick = %+v", tick)
	}
}

func TestClickerBuyUnlockAndPrice(t *testing.T) {
	c := testClicker(t)
	s := newClickerState(c)
	if problem := c.buy(s, "tap", 3, 1); problem != "upgrade_locked" {
		t.Fatalf("locked tier: %q", problem)
	}
	c.earn(s, 100)
	if problem := c.buy(s, "tap", 0, 0); problem != "" {
		t.Fatalf("buy max: %q", problem)
	}
	spent := 100 - s.Points
	if s.Tap[0] < 2 || math.Abs(spent-c.price("tap", 0, 0, s.Tap[0])) > 1e-9 || s.Points >= c.price("tap", 0, s.Tap[0], 1) {
		t.Fatalf("bought %d levels, spent %v, left %v", s.Tap[0], spent, s.Points)
	}
	if problem := c.buy(s, "tap", 0, 10); problem != "not_enough_points" {
		t.Fatalf("buy 10 without points: %q", problem)
	}
	if problem := c.buy(s, "boost", 0, 1); problem != "invalid_upgrade" {
		t.Fatalf("unknown kind: %q", problem)
	}
}

func TestClickerRebirthKeepsAllTime(t *testing.T) {
	c := testClicker(t)
	s := newClickerState(c)
	c.earn(s, 1e5)
	if problem := c.rebirth(s); problem != "rebirth_locked" {
		t.Fatalf("early rebirth: %q", problem)
	}
	c.earn(s, math.Pow(10, c.Gold[1].At))
	s.Tap[0] = 30
	if problem := c.rebirth(s); problem != "" || s.Gold != 2 {
		t.Fatalf("rebirth: %q, gold %d", problem, s.Gold)
	}
	if s.Points != 0 || s.Run != 0 || s.Tap[0] != 0 || s.Total < math.Pow(10, c.Gold[1].At) {
		t.Fatalf("after rebirth: %+v", s)
	}
	if got := c.multiplier(s); got < math.Pow(10, c.Gold[1].Mult) {
		t.Fatalf("multiplier = %v", got)
	}
}

func TestClickerPointsStopAtTheCeiling(t *testing.T) {
	c := testClicker(t)
	s := newClickerState(c)
	c.earn(s, math.MaxFloat64)
	c.earn(s, math.MaxFloat64)
	if s.Total != c.maxPoints() || math.IsInf(s.Points, 0) {
		t.Fatalf("total = %v", s.Total)
	}
	c.grantAchievements(s)
	if !contains(s.Achievements, "total_300") {
		t.Fatalf("achievements = %v", s.Achievements)
	}
	if score := clickerBoardScore(s.Total); score <= 0 || score > math.MaxInt64/10 {
		t.Fatalf("score = %d", score)
	}
}
