package main

import (
	"context"
	"database/sql"
	"fmt"
	"hash/fnv"
	"math"
	"math/rand/v2"
	"regexp"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Reward shop (a daily assortment, the same for everyone), wardrobe and garage.

const (
	shopSlots      = 6
	discountChance = 0.4
	starterCar     = "vaz2104"
	defaultAvatar  = "me"
	customAvatar   = "custom"
)

var (
	discounts     = []int{10, 15, 20, 25, 30, 50}
	rarityWeights = []struct {
		rarity string
		weight int
	}{{"common", 58}, {"rare", 28}, {"epic", 11}, {"legendary", 3}}
	rarityOrder      = []string{"legendary", "epic", "rare", "common"}
	approvalRarities = map[string]bool{"epic": true, "legendary": true}
	colorPattern     = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
	// Slot -> outfit key of the colour the player can pick for it (client Outfit.COLOR_KEYS).
	outfitColorKeys = []string{"hair_color", "top_color", "pants_color", "shoes_color"}
)

type shopOffer struct {
	OfferID         string `json:"offer_id"`
	ItemID          string `json:"item_id"`
	Name            string `json:"name"`
	Description     string `json:"description"`
	Rarity          string `json:"rarity"`
	Icon            int    `json:"icon"`
	BasePrice       int    `json:"base_price"`
	Price           int    `json:"price"`
	DiscountPercent int    `json:"discount_percent"`
	Purchased       bool   `json:"purchased"`
}

func seededRand(text string) *rand.Rand {
	hash := fnv.New64a()
	hash.Write([]byte(text))
	seed := hash.Sum64()
	return rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))
}

// dailyOffers: the assortment of `day`, rolled from a seed of the day so every player sees the same shop.
func dailyOffers(catalog []CatalogItem, day int) []shopOffer {
	rng := seededRand(fmt.Sprintf("alfa-shop-%d", day))
	offers := []shopOffer{}
	picked := map[string]bool{}
	for range shopSlots {
		item := rollItem(rng, catalog, picked)
		if item == nil {
			break
		}
		picked[item.ID] = true
		offers = append(offers, shopOffer{
			OfferID: fmt.Sprintf("%d-%s", day, item.ID), ItemID: item.ID, Name: item.Name, Description: item.Description,
			Rarity: item.Rarity, Icon: item.Icon, BasePrice: item.Price, Price: item.Price,
		})
	}
	if len(offers) > 0 && rng.Float64() < discountChance {
		offer := &offers[rng.IntN(len(offers))]
		offer.DiscountPercent = discounts[rng.IntN(len(discounts))]
		offer.Price = int(math.Round(float64(offer.BasePrice) * float64(100-offer.DiscountPercent) / 100))
	}
	return offers
}

func rollItem(rng *rand.Rand, catalog []CatalogItem, exclude map[string]bool) *CatalogItem {
	total := 0
	for _, entry := range rarityWeights {
		total += entry.weight
	}
	roll := rng.IntN(total) + 1
	rarity := "common"
	for _, entry := range rarityWeights {
		roll -= entry.weight
		if roll <= 0 {
			rarity = entry.rarity
			break
		}
	}
	// Fall back to more common rarities when the rolled pool is exhausted.
	start := 0
	for i, name := range rarityOrder {
		if name == rarity {
			start = i
		}
	}
	for _, name := range rarityOrder[start:] {
		pool := []*CatalogItem{}
		for i := range catalog {
			if catalog[i].Rarity == name && !exclude[catalog[i].ID] {
				pool = append(pool, &catalog[i])
			}
		}
		if len(pool) > 0 {
			return pool[rng.IntN(len(pool))]
		}
	}
	return nil
}

func rpcGetShop(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		offers := dailyOffers(tx.content.Catalog, tx.today)
		bought := dayList(tx.me.state.Purchases, tx.today)
		for i := range offers {
			offers[i].Purchased = contains(bought, offers[i].OfferID)
		}
		return map[string]any{"offers": offers, "refresh_at": unixAt(tx.today+1, 0, 0, tx.offset)}, nil
	})
}

type purchaseResult struct {
	Status  string `json:"status"` // granted | pending_approval | failed
	Error   string `json:"error,omitempty"`
	Balance int64  `json:"balance"`
	Voucher string `json:"voucher,omitempty"`
}

func failedPurchase(problem string, balance int64) purchaseResult {
	return purchaseResult{Status: "failed", Error: problem, Balance: balance}
}

// rpcBuy: {"offer_id", "operation_key"}. Epic and legendary rewards wait for manual approval.
func rpcBuy(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		OfferID      string `json:"offer_id"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.playError(); problem != "" || err != nil {
			return failedPurchase(problem, tx.me.balance), err
		}
		state := tx.me.state
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return failedPurchase("duplicate_operation", tx.me.balance), err
		}
		var offer *shopOffer
		for _, candidate := range dailyOffers(tx.content.Catalog, tx.today) {
			if candidate.OfferID == request.OfferID {
				offer = &candidate
			}
		}
		switch {
		case offer == nil:
			return failedPurchase("offer_expired", tx.me.balance), nil
		case contains(dayList(state.Purchases, tx.today), offer.OfferID):
			return failedPurchase("already_purchased", tx.me.balance), nil
		case tx.me.balance < int64(offer.Price):
			return failedPurchase("not_enough_coins", tx.me.balance), nil
		}
		addToDay(state.Purchases, tx.today, offer.OfferID)
		if !contains(state.OwnedItems, offer.ItemID) {
			state.OwnedItems = append(state.OwnedItems, offer.ItemID)
		}
		tx.credit(tx.me, -int64(offer.Price), "shop_purchase", offer.ItemID)
		result := purchaseResult{Status: "granted", Balance: tx.me.balance}
		if approvalRarities[offer.Rarity] {
			result.Status = "pending_approval"
			err := tx.writeSystem(rewardsCollection, randomKey(), map[string]any{
				"user_id": tx.me.userID, "item_id": offer.ItemID, "price": offer.Price, "t": tx.now, "status": "pending",
			}, "")
			return result, err
		}
		if len(offer.ItemID) > 6 && offer.ItemID[:6] == "promo_" {
			result.Voucher = fmt.Sprintf("ALFA-%04X-%04X", rand.IntN(0x10000), rand.IntN(0x10000))
		}
		return result, nil
	})
}

// --- Wardrobe ----------------------------------------------------------------------

type wardrobeItemView struct {
	Slot        string `json:"slot"`
	ID          string `json:"id"`
	Name        string `json:"name"`
	Unlocked    bool   `json:"unlocked"`
	UnlockType  string `json:"unlock_type"`
	UnlockValue string `json:"unlock_value"`
}

// isUnlocked: streak items stay unlocked once earned (best streak), so a lost streak does not
// undress the player.
func (tx *gameTx) isUnlocked(entry *WardrobeEntry) bool {
	if entry.Unlock == nil {
		return true
	}
	state := tx.me.state
	switch entry.Unlock.Type {
	case "shop":
		return contains(state.OwnedItems, entry.Unlock.Item)
	case "streak":
		return max(state.BestStreak, streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay)) >= entry.Unlock.Days
	}
	return true
}

func rpcGetWardrobe(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		items := []wardrobeItemView{}
		for i := range tx.content.Wardrobe {
			entry := &tx.content.Wardrobe[i]
			view := wardrobeItemView{Slot: entry.Slot, ID: entry.ID, Name: entry.Name, UnlockType: "free", Unlocked: tx.isUnlocked(entry)}
			if entry.Unlock != nil {
				view.UnlockType = entry.Unlock.Type
				switch entry.Unlock.Type {
				case "shop":
					view.UnlockValue = entry.Unlock.Item
				case "streak":
					view.UnlockValue = fmt.Sprint(entry.Unlock.Days)
				}
			}
			items = append(items, view)
		}
		state := tx.me.state
		return map[string]any{
			"items": items, "outfit": state.Outfit,
			"streak_days": streak(state.PresenceDays, state.ExcusedDays, tx.today, state.FirstDay),
		}, nil
	})
}

// rpcSaveOutfit: {"outfit": {slot: item id, colour key: "#rrggbb"}}. Every slot must name an unlocked item.
func rpcSaveOutfit(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Outfit map[string]string `json:"outfit"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		clean := map[string]string{}
		for _, slot := range tx.content.wardrobeSlots() {
			entry := tx.content.wardrobeItem(slot, request.Outfit[slot])
			if entry == nil {
				return fail("unknown_item"), nil
			}
			if !tx.isUnlocked(entry) {
				return fail("item_locked"), nil
			}
			clean[slot] = entry.ID
		}
		for _, key := range outfitColorKeys {
			color := request.Outfit[key]
			if !colorPattern.MatchString(color) {
				return fail("invalid_color"), nil
			}
			clean[key] = toLowerASCII(color)
		}
		tx.me.state.Outfit = clean
		return okResult, nil
	})
}

// --- Garage ------------------------------------------------------------------------

type carView struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Price       int    `json:"price"`
	SpeedKmh    int    `json:"speed_kmh"`
	Owned       bool   `json:"owned"`
	Selected    bool   `json:"selected"`
}

func ownsCar(state *PlayerState, car *Car) bool {
	return car.Price == 0 || contains(state.Cars, car.ID)
}

func rpcGetGarage(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		cars := []carView{}
		for i := range tx.content.Cars {
			car := &tx.content.Cars[i]
			cars = append(cars, carView{
				ID: car.ID, Name: car.Name, Description: car.Description, Price: car.Price, SpeedKmh: car.SpeedKmh,
				Owned: ownsCar(tx.me.state, car), Selected: tx.me.state.Car == car.ID,
			})
		}
		return map[string]any{"cars": cars}, nil
	})
}

// rpcBuyCar: {"car_id", "operation_key"}.
func rpcBuyCar(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		CarID        string `json:"car_id"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.playError(); problem != "" || err != nil {
			return failedPurchase(problem, tx.me.balance), err
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return failedPurchase("duplicate_operation", tx.me.balance), err
		}
		car := tx.content.car(request.CarID)
		switch {
		case car == nil:
			return failedPurchase("unknown_car", tx.me.balance), nil
		case ownsCar(tx.me.state, car):
			return failedPurchase("already_owned", tx.me.balance), nil
		case tx.me.balance < int64(car.Price):
			return failedPurchase("not_enough_coins", tx.me.balance), nil
		}
		tx.me.state.Cars = append(tx.me.state.Cars, car.ID)
		tx.credit(tx.me, -int64(car.Price), "car_purchase", car.ID)
		return purchaseResult{Status: "granted", Balance: tx.me.balance}, nil
	})
}

// rpcSelectCar: {"car_id"} -> {ok, error, car: {id, name, speed_kmh}}.
func rpcSelectCar(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		CarID string `json:"car_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		car := tx.content.car(request.CarID)
		switch {
		case car == nil:
			return fail("unknown_car"), nil
		case !ownsCar(tx.me.state, car):
			return fail("car_not_owned"), nil
		}
		tx.me.state.Car = car.ID
		return map[string]any{"ok": true, "car": car}, nil
	})
}

func toLowerASCII(text string) string {
	bytes := []byte(text)
	for i, b := range bytes {
		if b >= 'A' && b <= 'Z' {
			bytes[i] = b + 32
		}
	}
	return string(bytes)
}
