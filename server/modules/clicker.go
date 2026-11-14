package main

import (
	"errors"
	"fmt"
	"math"
)

// Cat clicker (content/clicker.json). Points are a separate score of the clicker: they never turn
// into wallet coins. Numbers grow up to 1e300, so every amount is a float64; the server keeps the
// only true state and the client repeats these formulas just to animate between replies.

// ClickerTier: one tap upgrade and one passive upgrade of the same price level. The tap upgrade
// costs CostScale·10^Exp and adds GainScale·10^(Exp·GainPower) points per tap; the passive one costs IdleCost
// times more and adds IdleDivisor times less per second.
type ClickerTier struct {
	Exp  float64 `json:"exp"`
	Tap  string  `json:"tap"`
	Idle string  `json:"idle"`
}

// ClickerGold: a rebirth milestone. A run that reached 10^At points may be reborn into this gold
// level; the gold level multiplies all income by 10^Mult and adds a golden part to the cat.
type ClickerGold struct {
	At   float64 `json:"at"`
	Mult float64 `json:"mult"`
	Name string  `json:"name"`
}

// ClickerAchievement: Kind is taps, total (exponent of all-time points), gold, levels, combo or
// offline (exponent of points earned while the clicker was closed).
type ClickerAchievement struct {
	ID    string  `json:"id"`
	Name  string  `json:"name"`
	Kind  string  `json:"kind"`
	Value float64 `json:"value"`
}

type ClickerContent struct {
	Growth           float64              `json:"growth"`
	DoubleEvery      int                  `json:"double_every"`
	GainPower        float64              `json:"gain_power"`
	GainScale        float64              `json:"gain_scale"`
	CostScale        float64              `json:"cost_scale"`
	IdleDivisor      float64              `json:"idle_divisor"`
	IdleCost         float64              `json:"idle_cost"`
	UnlockShare      float64              `json:"unlock_share"`
	OnlineGapSeconds int64                `json:"online_gap_seconds"`
	OfflineRate      float64              `json:"offline_rate"`
	OfficeHours      int64                `json:"office_hours"`
	MaxTapsPerSecond float64              `json:"max_taps_per_second"`
	ComboFrom        float64              `json:"combo_from"`
	ComboTo          float64              `json:"combo_to"`
	ComboMax         float64              `json:"combo_max"`
	AchievementBonus float64              `json:"achievement_bonus"`
	MaxExponent      float64              `json:"max_exponent"`
	Tiers            []ClickerTier        `json:"tiers"`
	Gold             []ClickerGold        `json:"gold"`
	Achievements     []ClickerAchievement `json:"achievements"`
}

func validateClicker(c *ClickerContent) error {
	switch {
	case c.Growth <= 1 || c.DoubleEvery < 1 || c.GainPower <= 0 || c.GainScale <= 0 || c.CostScale <= 0 || c.IdleDivisor < 1 || c.IdleCost <= 0:
		return errors.New("growth, double_every, gain_power, gain_scale, cost_scale, idle_divisor and idle_cost must be positive")
	case c.UnlockShare <= 0 || c.UnlockShare > 1 || c.OfflineRate < 0 || c.OfflineRate > 1:
		return errors.New("unlock_share and offline_rate must be within (0, 1]")
	case c.OnlineGapSeconds < 1 || c.OfficeHours < 1 || c.MaxTapsPerSecond < 1:
		return errors.New("online_gap_seconds, office_hours and max_taps_per_second must be positive")
	case c.ComboFrom < 0 || c.ComboTo <= c.ComboFrom || c.ComboMax < 1:
		return errors.New("combo_to must exceed combo_from, combo_max must be at least 1")
	case c.MaxExponent < 10 || c.MaxExponent > 305:
		return errors.New("max_exponent must be within [10, 305]")
	case len(c.Tiers) == 0:
		return errors.New("tiers are empty")
	}
	for i, tier := range c.Tiers {
		if tier.Exp < 0 || tier.Exp > c.MaxExponent || tier.Tap == "" || tier.Idle == "" || i > 0 && tier.Exp <= c.Tiers[i-1].Exp {
			return fmt.Errorf("tier %d: names required, exp must grow and stay below max_exponent", i)
		}
	}
	for i, gold := range c.Gold {
		if gold.At > c.MaxExponent || gold.Mult < 0 || i > 0 && (gold.At <= c.Gold[i-1].At || gold.Mult < c.Gold[i-1].Mult) {
			return fmt.Errorf("gold %d: at and mult must grow, at below max_exponent", i)
		}
	}
	ids := map[string]bool{}
	for _, a := range c.Achievements {
		if a.ID == "" || ids[a.ID] {
			return fmt.Errorf("achievement %q: id must be unique", a.ID)
		}
		ids[a.ID] = true
		switch a.Kind {
		case "taps", "total", "gold", "levels", "combo", "offline":
		default:
			return fmt.Errorf("achievement %q: unknown kind %q", a.ID, a.Kind)
		}
	}
	return nil
}

// ClickerState: storage "clicker"/"state" of the player.
type ClickerState struct {
	// Last applied request number: a repeated request is answered without being applied twice.
	Seq int64 `json:"seq"`
	// Points to spend, points of this run (unlocks and rebirth) and of all time (leaderboard).
	Points float64 `json:"points"`
	Run    float64 `json:"run"`
	Total  float64 `json:"total"`
	// Levels of the tap and passive upgrades by tier.
	Tap  []int `json:"tap"`
	Idle []int `json:"idle"`
	Gold int   `json:"gold"`
	// All-time counters for achievements; they survive rebirth.
	Taps         int64    `json:"taps"`
	Offline      float64  `json:"offline"`
	BestCombo    float64  `json:"best_combo"`
	Rebirths     int      `json:"rebirths"`
	Achievements []string `json:"achievements"`
	// Unix time of the last request; the passive income is counted from here.
	LastSync int64 `json:"last_sync"`
	// Unix time the leaderboard record was last written.
	BoardAt int64 `json:"board_at"`
}

func (c *ClickerContent) normalize(s *ClickerState) {
	for len(s.Tap) < len(c.Tiers) {
		s.Tap = append(s.Tap, 0)
	}
	for len(s.Idle) < len(c.Tiers) {
		s.Idle = append(s.Idle, 0)
	}
	s.Tap = s.Tap[:len(c.Tiers)]
	s.Idle = s.Idle[:len(c.Tiers)]
	s.Gold = min(max(s.Gold, 0), len(c.Gold))
	if s.Achievements == nil {
		s.Achievements = []string{}
	}
}

func (c *ClickerContent) maxPoints() float64 { return math.Pow(10, c.MaxExponent) }

func (c *ClickerContent) cost(tier int) float64 { return c.CostScale * math.Pow(10, c.Tiers[tier].Exp) }

func (c *ClickerContent) tapGain(tier int) float64 {
	return c.GainScale * math.Pow(10, c.Tiers[tier].Exp*c.GainPower)
}

// levelBonus: a tier's output at `level`, doubled every DoubleEvery levels.
func (c *ClickerContent) levelBonus(level int) float64 {
	return float64(level) * math.Pow(2, float64(level/c.DoubleEvery))
}

// multiplier: gold level and achievements, applied to taps and the passive income alike.
func (c *ClickerContent) multiplier(s *ClickerState) float64 {
	m := 1 + c.AchievementBonus*float64(len(s.Achievements))
	if s.Gold > 0 {
		m *= math.Pow(10, c.Gold[s.Gold-1].Mult)
	}
	return m
}

// tapValue: points of one tap before the combo.
func (c *ClickerContent) tapValue(s *ClickerState) float64 {
	sum := 1.0
	for i, level := range s.Tap {
		sum += c.tapGain(i) * c.levelBonus(level)
	}
	return sum * c.multiplier(s)
}

// idleRate: passive points per second while the clicker is open.
func (c *ClickerContent) idleRate(s *ClickerState) float64 {
	sum := 0.0
	for i, level := range s.Idle {
		sum += c.tapGain(i) / c.IdleDivisor * c.levelBonus(level)
	}
	return sum * c.multiplier(s)
}

// combo: tapping faster than ComboFrom taps per second raises the tap value up to ComboMax times.
func (c *ClickerContent) combo(rate float64) float64 {
	share := (rate - c.ComboFrom) / (c.ComboTo - c.ComboFrom)
	return 1 + (c.ComboMax-1)*math.Min(1, math.Max(0, share))
}

// price of `count` levels of a tier from `level`: a geometric sum.
func (c *ClickerContent) price(kind string, tier, level, count int) float64 {
	base := c.cost(tier)
	if kind == "idle" {
		base *= c.IdleCost
	}
	return base * math.Pow(c.Growth, float64(level)) * (math.Pow(c.Growth, float64(count)) - 1) / (c.Growth - 1)
}

// affordable: how many levels `points` buy, at most `limit`.
func (c *ClickerContent) affordable(kind string, tier, level int, points float64, limit int) int {
	first := c.price(kind, tier, level, 1)
	if points < first {
		return 0
	}
	n := int(math.Floor(math.Log(points*(c.Growth-1)/first+1) / math.Log(c.Growth)))
	n = min(max(n, 1), limit)
	for n > 1 && c.price(kind, tier, level, n) > points {
		n--
	}
	return n
}

// unlocked: an upgrade shows up once this run reached UnlockShare of its first price.
func (c *ClickerContent) unlocked(s *ClickerState, kind string, tier int) bool {
	levels := s.Tap
	if kind == "idle" {
		levels = s.Idle
	}
	return levels[tier] > 0 || s.Run >= c.price(kind, tier, 0, 1)*c.UnlockShare
}

// reachableGold: the gold level this run allows; a rebirth needs more than the current one.
func (c *ClickerContent) reachableGold(s *ClickerState) int {
	gold := s.Gold
	for i := s.Gold; i < len(c.Gold); i++ {
		if s.Run >= math.Pow(10, c.Gold[i].At) {
			gold = i + 1
		}
	}
	return gold
}

// earn adds points to all three counters, never beyond maxPoints.
func (c *ClickerContent) earn(s *ClickerState, amount float64) float64 {
	if amount <= 0 || math.IsNaN(amount) {
		return 0
	}
	limit := c.maxPoints()
	amount = math.Min(amount, limit)
	s.Points = math.Min(limit, s.Points+amount)
	s.Run = math.Min(limit, s.Run+amount)
	s.Total = math.Min(limit, s.Total+amount)
	return amount
}

// officeWindow: the passive income while the clicker is closed counts only from the entry code
// until the exit (or "Go home") and for OfficeHours at most.
type officeWindow struct{ from, to int64 }

func (c *ClickerContent) windowSeconds(windows []officeWindow, from, to int64) int64 {
	total := int64(0)
	for _, w := range windows {
		end := min(w.to, w.from+c.OfficeHours*3600)
		if overlap := min(end, to) - max(w.from, from); overlap > 0 {
			total += overlap
		}
	}
	return total
}

func (c *ClickerContent) levels(s *ClickerState) int {
	n := 0
	for i := range s.Tap {
		n += s.Tap[i] + s.Idle[i]
	}
	return n
}

// grantAchievements adds the achievements the state reached; it returns the new ones.
func (c *ClickerContent) grantAchievements(s *ClickerState) []string {
	have := map[string]bool{}
	for _, id := range s.Achievements {
		have[id] = true
	}
	added := []string{}
	for _, a := range c.Achievements {
		if have[a.ID] || !c.reached(s, a) {
			continue
		}
		s.Achievements = append(s.Achievements, a.ID)
		added = append(added, a.ID)
	}
	return added
}

func (c *ClickerContent) reached(s *ClickerState, a ClickerAchievement) bool {
	switch a.Kind {
	case "taps":
		return float64(s.Taps) >= a.Value
	case "total":
		return s.Total >= math.Pow(10, a.Value)
	case "gold":
		return float64(s.Gold) >= a.Value
	case "levels":
		return float64(c.levels(s)) >= a.Value
	case "combo":
		return s.BestCombo >= a.Value
	case "offline":
		return s.Offline >= math.Pow(10, a.Value)
	}
	return false
}

// clickerTick is what one request brings before its own action: passive income since LastSync and
// the taps made since then.
type clickerTick struct {
	Passive float64 `json:"passive"`
	Offline bool    `json:"offline"`
	Seconds int64   `json:"seconds"`
	Taps    int64   `json:"taps"`
	Tapped  float64 `json:"tapped"`
	Combo   float64 `json:"combo"`
}

// tick applies passive income and taps up to `now`. `open`: the clicker was on screen since the
// previous request; a longer gap than OnlineGapSeconds counts as closed anyway.
func (c *ClickerContent) tick(s *ClickerState, now int64, taps int64, open bool, windows []officeWindow) clickerTick {
	result := clickerTick{Combo: 1}
	elapsed := int64(0)
	if s.LastSync > 0 && now > s.LastSync {
		elapsed = now - s.LastSync
	}
	if elapsed > 0 {
		rate := c.idleRate(s)
		if open && elapsed <= c.OnlineGapSeconds {
			result.Seconds = elapsed
			result.Passive = c.earn(s, rate*float64(elapsed))
		} else {
			result.Offline = true
			result.Seconds = c.windowSeconds(windows, s.LastSync, now)
			result.Passive = c.earn(s, rate*float64(result.Seconds)*c.OfflineRate)
			s.Offline = math.Min(c.maxPoints(), s.Offline+result.Passive)
		}
	}
	// Taps between two requests: at most MaxTapsPerSecond over the gap, the gap counted from one
	// second (several quick requests) up to the online gap (a reply that came late).
	window := float64(min(max(elapsed, 1), c.OnlineGapSeconds))
	result.Taps = min(max(taps, 0), int64(c.MaxTapsPerSecond*window))
	if result.Taps > 0 {
		result.Combo = c.combo(float64(result.Taps) / window)
		s.BestCombo = math.Max(s.BestCombo, result.Combo)
		s.Taps += result.Taps
		result.Tapped = c.earn(s, c.tapValue(s)*result.Combo*float64(result.Taps))
	}
	if now > s.LastSync {
		s.LastSync = now
	}
	return result
}

// buy raises a tier by `count` levels (0: as many as the points allow); it returns an error key.
func (c *ClickerContent) buy(s *ClickerState, kind string, tier, count int) string {
	if kind != "tap" && kind != "idle" || tier < 0 || tier >= len(c.Tiers) || count < 0 || count > 1000 {
		return "invalid_upgrade"
	}
	if !c.unlocked(s, kind, tier) {
		return "upgrade_locked"
	}
	levels := s.Tap
	if kind == "idle" {
		levels = s.Idle
	}
	limit := count
	if count == 0 {
		limit = 1000
	}
	n := c.affordable(kind, tier, levels[tier], s.Points, limit)
	if n == 0 || count > 0 && n < count {
		return "not_enough_points"
	}
	s.Points = math.Max(0, s.Points-c.price(kind, tier, levels[tier], n))
	levels[tier] += n
	return ""
}

// rebirth resets the run into the highest gold level it reached.
func (c *ClickerContent) rebirth(s *ClickerState) string {
	gold := c.reachableGold(s)
	if gold <= s.Gold {
		return "rebirth_locked"
	}
	s.Gold = gold
	s.Rebirths++
	s.Points = 0
	s.Run = 0
	for i := range s.Tap {
		s.Tap[i] = 0
		s.Idle[i] = 0
	}
	return ""
}

// boardScore: leaderboard scores are int64, so they hold the decimal logarithm of all-time points.
func clickerBoardScore(total float64) int64 {
	return int64(math.Log10(total+1) * 1e15)
}
