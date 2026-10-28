package main

import (
	"math"
	"testing"
)

func testContent(t *testing.T) *Content {
	t.Helper()
	content, err := loadContent("../content")
	if err != nil {
		t.Fatalf("server/content does not load: %v", err)
	}
	return content
}

func TestStockRefillsEveryMonday(t *testing.T) {
	catalog := []CatalogItem{{ID: "mug", WeeklyStock: 2}, {ID: "promo", WeeklyStock: 0}}
	stock := rewardStock{}
	stock.normalize()
	if !stock.refill(catalog, monday+2) {
		t.Fatal("the first read of a week must refill")
	}
	if stock.left(&catalog[0]) != 2 || stock.left(&catalog[1]) != unlimitedStock {
		t.Fatalf("left after refill: %d, %d", stock.left(&catalog[0]), stock.left(&catalog[1]))
	}
	if !stock.take(&catalog[0]) || !stock.take(&catalog[0]) || stock.take(&catalog[0]) {
		t.Error("a limit of 2 must give exactly 2 items")
	}
	if !stock.take(&catalog[1]) {
		t.Error("an unlimited item never runs out")
	}
	if stock.refill(catalog, monday+4) {
		t.Error("the same week must not refill again")
	}
	if !stock.refill(catalog, monday+7) || stock.left(&catalog[0]) != 2 {
		t.Error("next Monday must refill to the limit")
	}
	// The admin limit wins over the catalog; 0 makes the item unlimited.
	stock.Limits["mug"] = 0
	if stock.left(&catalog[0]) != unlimitedStock {
		t.Error("admin limit 0 must make the item unlimited")
	}
	stock.Limits["promo"] = 1
	stock.refill(catalog, monday+14)
	if stock.left(&catalog[1]) != 1 {
		t.Error("admin limit must apply on the refill")
	}
	// An item added to the catalog in the middle of the week is not out of stock until Monday.
	added := CatalogItem{ID: "new_merch", WeeklyStock: 4}
	if stock.left(&added) != 4 || !stock.take(&added) || stock.left(&added) != 3 {
		t.Errorf("new item left %d", stock.left(&added))
	}
}

func TestCosmeticItemsAreTheWardrobeUnlocks(t *testing.T) {
	content := testContent(t)
	if !content.isCosmetic("cap") || !content.isCosmetic("hoodie") {
		t.Error("merch that unlocks wardrobe items is customization")
	}
	if content.isCosmetic("promo_coffee") || content.isCosmetic("day_off") {
		t.Error("promo codes and perks are not customization")
	}
}

func TestDailyWheel(t *testing.T) {
	content := testContent(t)
	rules := &content.Rules.Wheel
	wheel := dailyWheel(content.Catalog, rules, monday)
	if len(wheel) != rules.ItemSectors+len(rules.CoinSectors) {
		t.Fatalf("sectors = %d", len(wheel))
	}
	again := dailyWheel(content.Catalog, rules, monday)
	seen := map[string]bool{}
	chances := 0.0
	for i, sector := range wheel {
		if sector != again[i] {
			t.Error("the wheel of a day must be the same for everyone")
		}
		if sector.Kind == sectorItem {
			if seen[sector.ItemID] {
				t.Errorf("item %s twice on one wheel", sector.ItemID)
			}
			seen[sector.ItemID] = true
		}
		chances += sector.Chance
	}
	if math.Abs(chances-100) > 1 {
		t.Errorf("chances add up to %.1f%%", chances)
	}
	changed := false
	for day := monday + 1; day < monday+10; day++ {
		other := dailyWheel(content.Catalog, rules, day)
		for i := range other {
			if other[i].ItemID != wheel[i].ItemID {
				changed = true
			}
		}
	}
	if !changed {
		t.Error("the wheel must change from day to day")
	}
}

// Every day fills every sector, even when the rolls pick more commons than the catalog has.
func TestWheelAndShopAreAlwaysFull(t *testing.T) {
	content := testContent(t)
	rules := &content.Rules.Wheel
	for day := monday; day < monday+500; day++ {
		if got := len(dailyWheel(content.Catalog, rules, day)); got != rules.ItemSectors+len(rules.CoinSectors) {
			t.Fatalf("day %d: %d wheel sectors", day, got)
		}
		if got := len(dailyOffers(content.Catalog, day)); got != shopSlots {
			t.Fatalf("day %d: %d shop offers", day, got)
		}
	}
}

func TestPickSectorFollowsWeights(t *testing.T) {
	sectors := []wheelSector{{Weight: 1}, {Weight: 3}, {Weight: 0}, {Weight: 6}}
	expectInt(t, "roll 0", int64(pickSector(sectors, 0)), 0)
	expectInt(t, "roll 0.05", int64(pickSector(sectors, 0.05)), 0)
	expectInt(t, "roll 0.1", int64(pickSector(sectors, 0.1)), 1)
	expectInt(t, "roll 0.39", int64(pickSector(sectors, 0.39)), 1)
	expectInt(t, "roll 0.4", int64(pickSector(sectors, 0.4)), 3)
	expectInt(t, "roll 0.999", int64(pickSector(sectors, 0.999)), 3)
}

// The wheel pays back about its price on average over many days: a fair game, not a coin printer.
func TestWheelValueIsCloseToItsPrice(t *testing.T) {
	content := testContent(t)
	rules := &content.Rules.Wheel
	total, rareOrBetter, legendary := 0.0, 0.0, 0.0
	const sampleDays = 400
	for day := monday; day < monday+sampleDays; day++ {
		wheel := dailyWheel(content.Catalog, rules, day)
		total += wheelExpectedValue(wheel)
		for _, sector := range wheel {
			if sector.Rarity != "" && sector.Rarity != "common" {
				rareOrBetter += sector.Chance
			}
			if sector.Rarity == "legendary" {
				legendary += sector.Chance
			}
		}
	}
	average := total / sampleDays
	price := float64(rules.SpinPrice)
	if average < 0.9*price || average > 1.25*price {
		t.Errorf("average spin value %.0f for a price of %.0f", average, price)
	}
	if share := rareOrBetter / sampleDays; share < 5 || share > 25 {
		t.Errorf("rare or better wins %.1f%% of spins", share)
	}
	if share := legendary / sampleDays; share > 0.5 {
		t.Errorf("legendary wins %.2f%% of spins", share)
	}
}

func TestSpinsLeft(t *testing.T) {
	state := &PlayerState{}
	expectInt(t, "fresh day", int64(spinsLeft(state, monday)), 1)
	state.WheelDay = monday
	expectInt(t, "after the spin", int64(spinsLeft(state, monday)), 0)
	state.WheelExtraSpins = 1
	expectInt(t, "spin given back", int64(spinsLeft(state, monday)), 1)
	expectInt(t, "next day with a spin given back", int64(spinsLeft(state, monday+1)), 2)
}
