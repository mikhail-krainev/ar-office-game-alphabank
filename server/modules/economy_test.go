package main

import (
	"math"
	"testing"
)

// Economy model (docs/economy.md): a typical player comes every workday and finishes most of the
// day's pack. These tests keep the prices and rewards in the agreed balance: a common reward after
// a day or two, rare after 2-3 days, epic after 1.5-2 weeks, legendary after about two months.

const (
	simCompletionShare = 0.8 // a typical player skips or fails some tasks
	simAverageScore    = 0.5 // half of the score bonus on average
)

// simulatedEarnings: coins a typical player has after each of `workdays` workdays in a row,
// the welcome bonus included.
func simulatedEarnings(content *Content, workdays int) []int {
	rules := &content.Rules
	checkIn := content.task("check_in")
	balances := []int{}
	balance := rules.Economy.WelcomeBonus
	day := monday
	for done := 0; done < workdays; day++ {
		if !isWorkday(day) {
			continue
		}
		multiplier := streakMultiplier(done, false, rules)
		earned := float64(taskReward(checkIn, multiplier))
		for id := range taskPack(content.Tasks, "sim-player", day) {
			reward := float64(taskReward(content.task(id), multiplier)) * (1 + rules.Economy.MaxScoreBonus*simAverageScore)
			earned += reward * simCompletionShare
		}
		balance += min(int(math.Round(earned)), rules.Economy.DailyCoinCap)
		balances = append(balances, balance)
		done++
	}
	return balances
}

// workdaysToAfford: workdays of saving until the balance reaches `price`.
func workdaysToAfford(balances []int, price int) int {
	for i, balance := range balances {
		if balance >= price {
			return i + 1
		}
	}
	return len(balances) + 1
}

func cheapestAndDearest(catalog []CatalogItem, rarity string) (int, int) {
	low, high := math.MaxInt, 0
	for _, item := range catalog {
		if item.Rarity == rarity {
			low, high = min(low, item.Price), max(high, item.Price)
		}
	}
	return low, high
}

func TestEconomyBalance(t *testing.T) {
	content := testContent(t)
	balances := simulatedEarnings(content, 80)
	// Days to afford an item from zero, without the welcome bonus: what a regular player feels.
	welcome := content.Rules.Economy.WelcomeBonus
	saved := make([]int, len(balances))
	for i, balance := range balances {
		saved[i] = balance - welcome
	}
	daily := float64(saved[19]) / 20
	if daily < 200 || daily > 450 {
		t.Errorf("a typical month pays %.0f coins a day", daily)
	}
	cases := []struct {
		rarity   string
		min, max int
	}{{"common", 1, 2}, {"rare", 2, 4}, {"epic", 7, 12}, {"legendary", 30, 50}}
	for _, c := range cases {
		low, high := cheapestAndDearest(content.Catalog, c.rarity)
		if days := workdaysToAfford(saved, low); days < c.min {
			t.Errorf("cheapest %s (%d coins) after %d workdays, want at least %d", c.rarity, low, days, c.min)
		}
		if days := workdaysToAfford(saved, high); days > c.max {
			t.Errorf("dearest %s (%d coins) after %d workdays, want at most %d", c.rarity, high, days, c.max)
		}
	}
	// The welcome bonus buys a first common reward or a spin on day one, not more.
	if low, _ := cheapestAndDearest(content.Catalog, "common"); welcome < low || welcome < content.Rules.Wheel.SpinPrice {
		t.Errorf("welcome bonus %d must cover a common reward or a spin", welcome)
	}
	// After a full week everything epic and legendary is still out of reach.
	if low, _ := cheapestAndDearest(content.Catalog, "epic"); balances[4] >= low {
		t.Errorf("first week balance %d already buys an epic reward (%d)", balances[4], low)
	}
	// The daily spin costs about a day of tasks: noticeable, but not a week of saving.
	if spin := float64(content.Rules.Wheel.SpinPrice); spin > 1.2*daily || spin < daily/2 {
		t.Errorf("spin %0.f for a daily income of %.0f", spin, daily)
	}
}

func TestDailyCapIsRarelyReached(t *testing.T) {
	content := testContent(t)
	rules := &content.Rules
	// A perfect day at the best streak with every task at full score may touch the cap, a typical
	// day must stay well below it.
	best := 0.0
	for day := monday; day < monday+60; day++ {
		if !isWorkday(day) {
			continue
		}
		earned := 0.0
		for id := range taskPack(content.Tasks, "cap-player", day) {
			earned += float64(taskReward(content.task(id), rules.Economy.MaxStreakMultiplier)) * (1 + rules.Economy.MaxScoreBonus)
		}
		best = max(best, earned)
	}
	if best < float64(rules.Economy.DailyCoinCap)*0.7 {
		t.Errorf("the cap %d is far above the best day %.0f: it limits nothing", rules.Economy.DailyCoinCap, best)
	}
	balances := simulatedEarnings(content, 40)
	for i := 1; i < len(balances); i++ {
		if balances[i]-balances[i-1] >= rules.Economy.DailyCoinCap {
			t.Errorf("a typical day %d hits the cap", i+1)
		}
	}
}
