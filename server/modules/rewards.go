package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Reward stock and the log of granted rewards, shared by the shop and the fortune wheel.
// Each catalog item may have a weekly stock (shop_catalog.json "weekly_stock", the admin overrides
// it in the panel; 0 = unlimited). The stock is refilled to the limit on the first action of every
// week (Monday, office time). An item that ran out stays in the shop and on the wheel marked as out
// of stock: it cannot be bought, and a wheel win of it is exchanged (wheel.go).
// Every granted reward is written to reward_log for the admin statistics.

const (
	stockCollection     = "reward_stock"
	stockKey            = "stock"
	rewardLogCollection = "reward_log"
	maxStock            = 10000
	unlimitedStock      = -1
	statsMaxRewardLog   = 300

	rewardSourceShop  = "shop"
	rewardSourceWheel = "wheel"
)

var (
	errInvalidStock  = runtime.NewError("invalid_stock", codeInvalidArgument)
	errStockConflict = runtime.NewError("stock_changed", codeFailedPrecondition)
)

type rewardStock struct {
	// First day (Monday) of the week the stock was last refilled.
	Week int `json:"week"`
	// Admin weekly limits; an item missing here uses its catalog weekly_stock. 0 = unlimited.
	Limits map[string]int `json:"limits"`
	// Items left this week; only limited items are listed.
	Left map[string]int `json:"left"`
}

type loadedStock struct {
	stock   rewardStock
	version string
	dirty   bool
}

func weekStart(day int) int {
	return day - weekday(day)
}

func (s *rewardStock) normalize() {
	if s.Limits == nil {
		s.Limits = map[string]int{}
	}
	if s.Left == nil {
		s.Left = map[string]int{}
	}
}

// limit: weekly limit of the item, 0 when unlimited.
func (s *rewardStock) limit(item *CatalogItem) int {
	if limit, ok := s.Limits[item.ID]; ok {
		return limit
	}
	return item.WeeklyStock
}

// refill restores every limited item to its weekly limit once a week. True when it changed the stock.
func (s *rewardStock) refill(catalog []CatalogItem, day int) bool {
	week := weekStart(day)
	if s.Week == week {
		return false
	}
	s.Week = week
	s.Left = map[string]int{}
	for i := range catalog {
		if limit := s.limit(&catalog[i]); limit > 0 {
			s.Left[catalog[i].ID] = limit
		}
	}
	return true
}

// left: items left this week, unlimitedStock when the item has no limit. An item limited after the
// last refill (new in the catalog) has its whole limit until the next one.
func (s *rewardStock) left(item *CatalogItem) int {
	limit := s.limit(item)
	if limit <= 0 {
		return unlimitedStock
	}
	if left, ok := s.Left[item.ID]; ok {
		return left
	}
	return limit
}

// take removes one item from the stock; false when it ran out.
func (s *rewardStock) take(item *CatalogItem) bool {
	switch left := s.left(item); {
	case left == unlimitedStock:
		return true
	case left <= 0:
		return false
	default:
		s.Left[item.ID] = left - 1
		return true
	}
}

func readStock(ctx context.Context, nk runtime.NakamaModule) (*loadedStock, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: stockCollection, Key: stockKey, UserID: systemUserID}})
	if err != nil {
		return nil, errInternal
	}
	loaded := &loadedStock{version: "*"}
	if len(objects) > 0 {
		if err := json.Unmarshal([]byte(objects[0].GetValue()), &loaded.stock); err != nil {
			return nil, errInternal
		}
		loaded.version = objects[0].GetVersion()
	}
	loaded.stock.normalize()
	return loaded, nil
}

// stock: the reward stock, read once per transaction and refilled when a new week began.
func (tx *gameTx) stock() (*rewardStock, error) {
	if tx.loadedStock == nil {
		loaded, err := readStock(tx.ctx, tx.nk)
		if err != nil {
			return nil, err
		}
		if loaded.stock.refill(tx.content.Catalog, tx.today) {
			loaded.dirty = true
		}
		tx.loadedStock = loaded
	}
	return &tx.loadedStock.stock, nil
}

// takeStock takes one item from the stock and marks it for the commit; false when it ran out.
func (tx *gameTx) takeStock(item *CatalogItem) (bool, error) {
	stock, err := tx.stock()
	if err != nil {
		return false, err
	}
	if !stock.take(item) {
		return false, nil
	}
	if stock.limit(item) > 0 {
		tx.loadedStock.dirty = true
	}
	return true, nil
}

// isCosmetic: the item unlocks something in the wardrobe, so it is in-game customization and is
// bought (or won) only once.
func (c *Content) isCosmetic(itemID string) bool {
	for i := range c.Wardrobe {
		unlock := c.Wardrobe[i].Unlock
		if unlock != nil && unlock.Type == "shop" && unlock.Item == itemID {
			return true
		}
	}
	return false
}

func (c *Content) catalogItem(id string) *CatalogItem {
	for i := range c.Catalog {
		if c.Catalog[i].ID == id {
			return &c.Catalog[i]
		}
	}
	return nil
}

// ownsCosmetic: the player already has this customization item.
func (tx *gameTx) ownsCosmetic(itemID string) bool {
	return tx.content.isCosmetic(itemID) && contains(tx.me.state.OwnedItems, itemID)
}

// grantItem gives a catalog item to the player: owned items, the approval request for epic and
// legendary rewards, a voucher for promo codes and the reward log. Returns the purchase status.
func (tx *gameTx) grantItem(item *CatalogItem, source string, price int) (purchaseResult, error) {
	state := tx.me.state
	if !contains(state.OwnedItems, item.ID) {
		state.OwnedItems = append(state.OwnedItems, item.ID)
	}
	result := purchaseResult{Status: "granted"}
	if approvalRarities[item.Rarity] {
		result.Status = "pending_approval"
		err := tx.writeSystem(rewardsCollection, randomKey(), map[string]any{
			"user_id": tx.me.userID, "item_id": item.ID, "price": price, "t": tx.now, "status": "pending", "source": source,
		}, "")
		if err != nil {
			return result, err
		}
	}
	if strings.HasPrefix(item.ID, "promo_") {
		result.Voucher = newVoucher()
	}
	return result, tx.logReward(item.ID, source, price, result.Status)
}

func (tx *gameTx) logReward(itemID, source string, price int, status string) error {
	return tx.writeSystem(rewardLogCollection, randomKey(), map[string]any{
		"user_id": tx.me.userID, "item_id": itemID, "source": source, "price": price, "status": status,
		"t": tx.now, "day": tx.today,
	}, "")
}

// --- Admin -----------------------------------------------------------------------

type rewardStockView struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Rarity       string `json:"rarity"`
	Price        int    `json:"price"`
	Cosmetic     bool   `json:"cosmetic"`
	WeeklyStock  int    `json:"weekly_stock"`
	DefaultStock int    `json:"default_stock"`
	// Items left this week; -1 when unlimited.
	Left int `json:"left"`
	// Granted rewards: through the shop, through the wheel, and both this week.
	FromShop  int `json:"from_shop"`
	FromWheel int `json:"from_wheel"`
	ThisWeek  int `json:"this_week"`
}

type rewardCounts struct {
	shop, wheel, week int
}

// loadRewardCounts: granted rewards per item from the reward log. Exchanged wheel wins are not
// rewards and are counted apart, as `exchanged`.
func loadRewardCounts(ctx context.Context, db *sql.DB, week int) (map[string]*rewardCounts, int, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT value->>'item_id', value->>'source', value->>'status', COALESCE((value->>'day')::int, 0), count(*)
		FROM storage WHERE collection = $1 AND user_id = $2
		GROUP BY 1, 2, 3, 4`, rewardLogCollection, systemUserID)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	counts := map[string]*rewardCounts{}
	exchanged := 0
	for rows.Next() {
		var (
			itemID, source, status string
			day, count             int
		)
		if err := rows.Scan(&itemID, &source, &status, &day, &count); err != nil {
			return nil, 0, err
		}
		if isExchangeStatus(status) {
			exchanged += count
			continue
		}
		entry := counts[itemID]
		if entry == nil {
			entry = &rewardCounts{}
			counts[itemID] = entry
		}
		if source == rewardSourceWheel {
			entry.wheel += count
		} else {
			entry.shop += count
		}
		if day >= week {
			entry.week += count
		}
	}
	return counts, exchanged, rows.Err()
}

func stockViews(stock *rewardStock, counts map[string]*rewardCounts) []rewardStockView {
	views := []rewardStockView{}
	for i := range gameContent.Catalog {
		item := &gameContent.Catalog[i]
		view := rewardStockView{
			ID: item.ID, Name: item.Name, Rarity: item.Rarity, Price: item.Price, Cosmetic: gameContent.isCosmetic(item.ID),
			WeeklyStock: stock.limit(item), DefaultStock: item.WeeklyStock, Left: stock.left(item),
		}
		if entry := counts[item.ID]; entry != nil {
			view.FromShop, view.FromWheel, view.ThisWeek = entry.shop, entry.wheel, entry.week
		}
		views = append(views, view)
	}
	return views
}

// adminStock reads the stock and refills it for the current week, so the panel shows what players see.
func adminStock(ctx context.Context, nk runtime.NakamaModule) (*loadedStock, int, error) {
	loaded, err := readStock(ctx, nk)
	if err != nil {
		return nil, 0, err
	}
	today := dayOf(gameNow(), gameContent.officeOffset())
	loaded.stock.refill(gameContent.Catalog, today)
	return loaded, today, nil
}

// rpcAdminGetRewards: -> {"items": [rewardStockView], "week_start", "wheel_exchanged"}.
func rpcAdminGetRewards(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	loaded, today, err := adminStock(ctx, nk)
	if err != nil {
		return "", err
	}
	counts, exchanged, err := loadRewardCounts(ctx, db, weekStart(today))
	if err != nil {
		logger.Error("reward counts: %v", err)
		return "", errInternal
	}
	return encodeResponse(map[string]any{
		"items": stockViews(&loaded.stock, counts), "week_start": weekStart(today), "wheel_exchanged": exchanged,
	})
}

// rpcAdminSetRewardStock: {"item_id", "weekly_stock", "left"} -> {"ok"}. weekly_stock 0 = unlimited;
// left sets what is left this week (ignored for unlimited items). Refills from the next Monday.
func rpcAdminSetRewardStock(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		ItemID      string `json:"item_id"`
		WeeklyStock int    `json:"weekly_stock"`
		Left        int    `json:"left"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	item := gameContent.catalogItem(request.ItemID)
	switch {
	case item == nil:
		return "", errInvalidPayload
	case request.WeeklyStock < 0 || request.WeeklyStock > maxStock || request.Left < 0 || request.Left > maxStock:
		return "", errInvalidStock
	}
	loaded, _, err := adminStock(ctx, nk)
	if err != nil {
		return "", err
	}
	loaded.stock.Limits[item.ID] = request.WeeklyStock
	delete(loaded.stock.Left, item.ID)
	if request.WeeklyStock > 0 {
		loaded.stock.Left[item.ID] = request.Left
	}
	value, err := json.Marshal(loaded.stock)
	if err != nil {
		return "", errInternal
	}
	_, err = nk.StorageWrite(ctx, []*runtime.StorageWrite{{
		Collection: stockCollection, Key: stockKey, UserID: systemUserID, Value: string(value), Version: loaded.version,
		PermissionRead: permissionNone, PermissionWrite: permissionNone,
	}})
	if err != nil {
		// A player bought the item at the same moment: the admin reloads and tries again.
		logger.Warn("reward stock write: %v", err)
		return "", errStockConflict
	}
	return encodeResponse(okResult)
}

type rewardLogEntry struct {
	T      int64  `json:"t"`
	ItemID string `json:"item_id"`
	Source string `json:"source"`
	Price  int    `json:"price"`
	Status string `json:"status"`
}

func loadRewardLog(ctx context.Context, db *sql.DB, userID string) ([]rewardLogEntry, error) {
	values, err := systemRowsOf(ctx, db, rewardLogCollection, userID, statsMaxRewardLog)
	if err != nil {
		return nil, err
	}
	entries := []rewardLogEntry{}
	for _, value := range values {
		var entry rewardLogEntry
		if json.Unmarshal([]byte(value), &entry) == nil {
			entries = append(entries, entry)
		}
	}
	return entries, nil
}
