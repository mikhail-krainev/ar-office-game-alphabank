package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"math/rand/v2"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Fortune wheel: a paid spin once a day (game_rules.json "wheel"). Every day the wheel gets its
// sectors, the same for everyone: coin prizes and catalog items rolled by rarity like the shop.
// Each sector has its own chance (a weight by rarity), shown to the player. A win of an item that is
// out of stock, or of customization the player already has, waits for the player's choice: the spin
// back, or coins equal to the item's price.

const (
	sectorCoins = "coins"
	sectorItem  = "item"

	wheelChoiceRespin = "respin"
	wheelChoiceCoins  = "coins"

	wheelReasonOutOfStock = "out_of_stock"
	wheelReasonOwned      = "owned"

	// reward_log statuses of exchanged wins: they are not rewards.
	rewardStatusRespin = "exchanged_respin"
	rewardStatusCoins  = "exchanged_coins"
)

func validateWheel(rules *WheelRules) error {
	if rules.SpinPrice <= 0 || rules.ItemSectors < 0 || rules.ItemSectors+len(rules.CoinSectors) == 0 {
		return errors.New("spin_price and sectors are required")
	}
	for _, sector := range rules.CoinSectors {
		if sector.Coins <= 0 || sector.Weight <= 0 {
			return errors.New("coin sectors need coins and a weight")
		}
	}
	for _, rarity := range rarityOrder {
		if rules.ItemSectors > 0 && rules.RarityWeights[rarity] <= 0 {
			return fmt.Errorf("rarity_weights.%s is missing", rarity)
		}
	}
	return nil
}

func isExchangeStatus(status string) bool {
	return status == rewardStatusRespin || status == rewardStatusCoins
}

type WheelCoinSector struct {
	Coins  int     `json:"coins"`
	Weight float64 `json:"weight"`
}

type WheelRules struct {
	SpinPrice     int                `json:"spin_price"`
	ItemSectors   int                `json:"item_sectors"`
	CoinSectors   []WheelCoinSector  `json:"coin_sectors"`
	RarityWeights map[string]float64 `json:"rarity_weights"`
}

// WheelPending: a win the player has to exchange (out of stock or already owned).
type WheelPending struct {
	Day    int    `json:"day"`
	Sector int    `json:"sector"`
	ItemID string `json:"item_id"`
	Coins  int    `json:"coins"`
	Reason string `json:"reason"`
}

type wheelSector struct {
	Kind   string  `json:"kind"`
	Coins  int     `json:"coins,omitempty"`
	ItemID string  `json:"item_id,omitempty"`
	Name   string  `json:"name"`
	Rarity string  `json:"rarity,omitempty"`
	Icon   int     `json:"icon"`
	Price  int     `json:"price,omitempty"`
	Weight float64 `json:"-"`
	// Chance of the sector in percent, rounded to 0.1.
	Chance     float64 `json:"chance"`
	OutOfStock bool    `json:"out_of_stock"`
	Owned      bool    `json:"owned"`
}

// dailyWheel: the sectors of `day`, rolled from a seed of the day so every player sees the same wheel.
func dailyWheel(catalog []CatalogItem, rules *WheelRules, day int) []wheelSector {
	rng := seededRand(fmt.Sprintf("alfa-wheel-%d", day))
	sectors := []wheelSector{}
	for _, prize := range rules.CoinSectors {
		sectors = append(sectors, wheelSector{Kind: sectorCoins, Coins: prize.Coins, Name: fmt.Sprintf("%d", prize.Coins), Icon: -1, Weight: prize.Weight})
	}
	picked := map[string]bool{}
	for range rules.ItemSectors {
		item := rollItem(rng, catalog, picked)
		if item == nil {
			break
		}
		picked[item.ID] = true
		sectors = append(sectors, wheelSector{
			Kind: sectorItem, ItemID: item.ID, Name: item.Name, Rarity: item.Rarity, Icon: item.Icon, Price: item.Price,
			Weight: rules.RarityWeights[item.Rarity],
		})
	}
	rng.Shuffle(len(sectors), func(i, j int) { sectors[i], sectors[j] = sectors[j], sectors[i] })
	total := 0.0
	for _, sector := range sectors {
		total += sector.Weight
	}
	for i := range sectors {
		if total > 0 {
			sectors[i].Chance = math.Round(sectors[i].Weight/total*1000) / 10
		}
	}
	return sectors
}

// pickSector: index of the sector a roll in [0, 1) lands on, by the sector weights.
func pickSector(sectors []wheelSector, roll float64) int {
	total := 0.0
	for _, sector := range sectors {
		total += sector.Weight
	}
	target := roll * total
	for i, sector := range sectors {
		target -= sector.Weight
		if target < 0 {
			return i
		}
	}
	return len(sectors) - 1
}

// wheelExpectedValue: average coins a spin pays back, an item counted at its price.
func wheelExpectedValue(sectors []wheelSector) float64 {
	total, value := 0.0, 0.0
	for _, sector := range sectors {
		total += sector.Weight
		if sector.Kind == sectorCoins {
			value += sector.Weight * float64(sector.Coins)
		} else {
			value += sector.Weight * float64(sector.Price)
		}
	}
	if total == 0 {
		return 0
	}
	return value / total
}

// spinsLeft: today's free spin plus spins given back for exchanged wins.
func spinsLeft(state *PlayerState, today int) int {
	left := state.WheelExtraSpins
	if state.WheelDay != today {
		left++
	}
	return left
}

// wheelSectors: today's sectors marked for the player (out of stock, already owned).
func (tx *gameTx) wheelSectors() ([]wheelSector, error) {
	sectors := dailyWheel(tx.content.Catalog, &tx.content.Rules.Wheel, tx.today)
	stock, err := tx.stock()
	if err != nil {
		return nil, err
	}
	for i := range sectors {
		item := tx.content.catalogItem(sectors[i].ItemID)
		if item == nil {
			continue
		}
		sectors[i].OutOfStock = stock.left(item) == 0
		sectors[i].Owned = tx.ownsCosmetic(item.ID)
	}
	return sectors, nil
}

func (tx *gameTx) wheelView() (map[string]any, error) {
	sectors, err := tx.wheelSectors()
	if err != nil {
		return nil, err
	}
	state := tx.me.state
	return map[string]any{
		"sectors": sectors, "spin_price": tx.content.Rules.Wheel.SpinPrice, "spins_left": spinsLeft(state, tx.today),
		"free_spin": state.WheelExtraSpins > 0, "pending": state.WheelPending, "balance": tx.me.balance, "refresh_at": unixAt(tx.today+1, 0, 0, tx.offset),
	}, nil
}

func rpcGetWheel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		return tx.wheelView()
	})
}

type spinResult struct {
	Status    string        `json:"status"` // granted | pending_approval | coins | choice | failed
	Error     string        `json:"error,omitempty"`
	Sector    int           `json:"sector"`
	Prize     *wheelSector  `json:"prize,omitempty"`
	Coins     int           `json:"coins,omitempty"`
	Voucher   string        `json:"voucher,omitempty"`
	Pending   *WheelPending `json:"pending,omitempty"`
	Balance   int64         `json:"balance"`
	SpinsLeft int           `json:"spins_left"`
}

func (tx *gameTx) failedSpin(problem string) spinResult {
	return spinResult{Status: "failed", Error: problem, Sector: -1, Balance: tx.me.balance, SpinsLeft: spinsLeft(tx.me.state, tx.today)}
}

// rpcSpinWheel: {"operation_key"}. Pays for the spin (a spin given back is free) and grants the prize.
func rpcSpinWheel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.playError(); problem != "" || err != nil {
			return tx.failedSpin(problem), err
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return tx.failedSpin("duplicate_operation"), err
		}
		state := tx.me.state
		price := int64(tx.content.Rules.Wheel.SpinPrice)
		isFreeSpin := state.WheelExtraSpins > 0
		switch {
		case state.WheelPending != nil:
			return tx.failedSpin("wheel_choice_pending"), nil
		case spinsLeft(state, tx.today) <= 0:
			return tx.failedSpin("wheel_spun_today"), nil
		case !isFreeSpin && tx.me.balance < price:
			return tx.failedSpin("not_enough_coins"), nil
		}
		sectors, err := tx.wheelSectors()
		if err != nil {
			return nil, err
		}
		if len(sectors) == 0 {
			return tx.failedSpin("wheel_empty"), nil
		}
		if isFreeSpin {
			state.WheelExtraSpins--
		} else {
			state.WheelDay = tx.today
			tx.credit(tx.me, -price, "wheel_spin", dayKey(tx.today))
		}
		index := pickSector(sectors, rand.Float64())
		return tx.grantSector(sectors, index)
	})
}

func (tx *gameTx) grantSector(sectors []wheelSector, index int) (spinResult, error) {
	sector := sectors[index]
	result := spinResult{Sector: index, Prize: &sector}
	if sector.Kind == sectorCoins {
		tx.credit(tx.me, int64(sector.Coins), "wheel_coins", dayKey(tx.today))
		result.Status, result.Coins = "coins", sector.Coins
		return tx.finishSpin(result), tx.logReward("coins", rewardSourceWheel, sector.Coins, "coins")
	}
	item := tx.content.catalogItem(sector.ItemID)
	if item == nil {
		return tx.failedSpin("unknown_item"), nil
	}
	reason := ""
	if tx.ownsCosmetic(item.ID) {
		reason = wheelReasonOwned
	} else {
		taken, err := tx.takeStock(item)
		if err != nil {
			return spinResult{}, err
		}
		if !taken {
			reason = wheelReasonOutOfStock
		}
	}
	if reason != "" {
		tx.me.state.WheelPending = &WheelPending{Day: tx.today, Sector: index, ItemID: item.ID, Coins: item.Price, Reason: reason}
		result.Status, result.Pending = "choice", tx.me.state.WheelPending
		return tx.finishSpin(result), nil
	}
	granted, err := tx.grantItem(item, rewardSourceWheel, tx.content.Rules.Wheel.SpinPrice)
	result.Status, result.Voucher = granted.Status, granted.Voucher
	return tx.finishSpin(result), err
}

func (tx *gameTx) finishSpin(result spinResult) spinResult {
	result.Balance = tx.me.balance
	result.SpinsLeft = spinsLeft(tx.me.state, tx.today)
	return result
}

// rpcResolveWheel: {"choice": "respin" | "coins", "operation_key"}. Settles a win that could not be
// given: the spin back (usable any day) or the item's price in coins.
func rpcResolveWheel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Choice       string `json:"choice"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if request.Choice != wheelChoiceRespin && request.Choice != wheelChoiceCoins {
		return "", errInvalidPayload
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return tx.failedSpin("duplicate_operation"), err
		}
		state := tx.me.state
		pending := state.WheelPending
		if pending == nil {
			return tx.failedSpin("no_wheel_choice"), nil
		}
		state.WheelPending = nil
		result := spinResult{Sector: pending.Sector, Status: request.Choice}
		if request.Choice == wheelChoiceCoins {
			tx.credit(tx.me, int64(pending.Coins), "wheel_exchange", pending.ItemID)
			result.Coins = pending.Coins
			return tx.finishSpin(result), tx.logReward(pending.ItemID, rewardSourceWheel, pending.Coins, rewardStatusCoins)
		}
		state.WheelExtraSpins++
		return tx.finishSpin(result), tx.logReward(pending.ItemID, rewardSourceWheel, 0, rewardStatusRespin)
	})
}
