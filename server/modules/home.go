package main

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/heroiclabs/nakama-common/runtime"
)

// The player's home (content/home.json): apartments from a 20 m² studio to a 240 m² house, colour
// palettes and interior items the player buys with coins and places in the apartment. The home
// works outside the office network too (network.go: anywhereRpcs): spending coins on looks is not
// an office action, while every coin is still earned only in the office.

const (
	starterApartment = "studio20"
	originalPalette  = "original"
	homeKindFurn     = "furniture"
	homeKindPoster   = "poster"
	maxHomeCoord     = 64
)

type Apartment struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Area        int    `json:"area"`
	Price       int    `json:"price"`
	Width       int    `json:"width"`
	Height      int    `json:"height"`
	Palette     string `json:"palette"`
}

type HomePalette struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Price int    `json:"price"`
}

type HomeItem struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Kind  string `json:"kind"`
	Price int    `json:"price"`
}

type HomeContent struct {
	MaxOwned   int           `json:"max_owned"`
	MaxPlaced  int           `json:"max_placed"`
	Apartments []Apartment   `json:"apartments"`
	Palettes   []HomePalette `json:"palettes"`
	Items      []HomeItem    `json:"items"`
}

// PlacedItem: an interior item at a cell of the apartment map (its top-left footprint cell).
type PlacedItem struct {
	Item string `json:"item"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
}

type ApartmentDecor struct {
	Palette string       `json:"palette"`
	Placed  []PlacedItem `json:"placed"`
}

// HomeState: the apartment the player lives in, what they bought and how each apartment looks.
type HomeState struct {
	Apartment  string                     `json:"apartment"`
	Apartments []string                   `json:"apartments"`
	Palettes   []string                   `json:"palettes"`
	Items      map[string]int             `json:"items"`
	Decor      map[string]*ApartmentDecor `json:"decor"`
}

func (h *HomeState) normalize() {
	if h.Apartment == "" {
		h.Apartment = starterApartment
	}
	if h.Apartments == nil {
		h.Apartments = []string{}
	}
	if h.Palettes == nil {
		h.Palettes = []string{}
	}
	if h.Items == nil {
		h.Items = map[string]int{}
	}
	if h.Decor == nil {
		h.Decor = map[string]*ApartmentDecor{}
	}
}

func validateHome(home *HomeContent) error {
	if home.MaxOwned <= 0 || home.MaxPlaced <= 0 {
		return fmt.Errorf("max_owned and max_placed must be positive")
	}
	palettes := map[string]bool{}
	for _, palette := range home.Palettes {
		if palette.ID == "" || palette.Price < 0 || palettes[palette.ID] {
			return fmt.Errorf("palette %q: empty or duplicate id or negative price", palette.ID)
		}
		palettes[palette.ID] = true
	}
	if !palettes[originalPalette] {
		return fmt.Errorf("palette %q is missing", originalPalette)
	}
	apartments := map[string]bool{}
	for _, apartment := range home.Apartments {
		switch {
		case apartment.ID == "" || apartments[apartment.ID]:
			return fmt.Errorf("apartment %q: empty or duplicate id", apartment.ID)
		case apartment.Price < 0, apartment.Width <= 0 || apartment.Width > maxHomeCoord, apartment.Height <= 0 || apartment.Height > maxHomeCoord:
			return fmt.Errorf("apartment %s: bad price or size", apartment.ID)
		case !palettes[apartment.Palette]:
			return fmt.Errorf("apartment %s: unknown palette %q", apartment.ID, apartment.Palette)
		}
		apartments[apartment.ID] = true
	}
	if !apartments[starterApartment] {
		return fmt.Errorf("apartment %q is missing", starterApartment)
	}
	items := map[string]bool{}
	for _, item := range home.Items {
		if item.ID == "" || items[item.ID] || item.Price <= 0 || (item.Kind != homeKindFurn && item.Kind != homeKindPoster) {
			return fmt.Errorf("item %q: empty or duplicate id, bad price or kind", item.ID)
		}
		items[item.ID] = true
	}
	return nil
}

func (h *HomeContent) apartment(id string) *Apartment {
	for i := range h.Apartments {
		if h.Apartments[i].ID == id {
			return &h.Apartments[i]
		}
	}
	return nil
}

func (h *HomeContent) palette(id string) *HomePalette {
	for i := range h.Palettes {
		if h.Palettes[i].ID == id {
			return &h.Palettes[i]
		}
	}
	return nil
}

func (h *HomeContent) item(id string) *HomeItem {
	for i := range h.Items {
		if h.Items[i].ID == id {
			return &h.Items[i]
		}
	}
	return nil
}

func ownsApartment(home *HomeState, apartment *Apartment) bool {
	return apartment.Price == 0 || contains(home.Apartments, apartment.ID)
}

// ownsPalette: the free palette, a bought one, or the design of an apartment the player owns.
func ownsPalette(content *HomeContent, home *HomeState, palette *HomePalette) bool {
	if palette.Price == 0 || contains(home.Palettes, palette.ID) {
		return true
	}
	for i := range content.Apartments {
		apartment := &content.Apartments[i]
		if apartment.Palette == palette.ID && ownsApartment(home, apartment) {
			return true
		}
	}
	return false
}

// decorOf: how `apartment` looks; a new apartment starts with its own design and no items.
func decorOf(home *HomeState, apartment *Apartment) ApartmentDecor {
	if decor := home.Decor[apartment.ID]; decor != nil {
		return ApartmentDecor{Palette: decor.Palette, Placed: append([]PlacedItem{}, decor.Placed...)}
	}
	return ApartmentDecor{Palette: apartment.Palette, Placed: []PlacedItem{}}
}

// placedElsewhere: copies of each item standing in the apartments other than `except`.
func placedElsewhere(home *HomeState, except string) map[string]int {
	counts := map[string]int{}
	for id, decor := range home.Decor {
		if id == except || decor == nil {
			continue
		}
		for _, placed := range decor.Placed {
			counts[placed.Item]++
		}
	}
	return counts
}

// homeDecorError: "" or why `decor` cannot be the look of `apartment`. The client checks that items
// do not overlap the furniture and keep the way to the door free; the server checks what money
// buys: ownership, copies and the map bounds.
func homeDecorError(content *HomeContent, home *HomeState, apartment *Apartment, decor ApartmentDecor) string {
	palette := content.palette(decor.Palette)
	if palette == nil {
		return "unknown_palette"
	}
	if !ownsPalette(content, home, palette) {
		return "palette_not_owned"
	}
	if len(decor.Placed) > content.MaxPlaced {
		return "too_many_items"
	}
	used := placedElsewhere(home, apartment.ID)
	cells := map[PlacedItem]bool{}
	for _, placed := range decor.Placed {
		if content.item(placed.Item) == nil {
			return "unknown_item"
		}
		if placed.X < 0 || placed.Y < 0 || placed.X >= apartment.Width || placed.Y >= apartment.Height {
			return "out_of_bounds"
		}
		if cells[placed] {
			return "duplicate_item"
		}
		cells[placed] = true
		used[placed.Item]++
		if used[placed.Item] > home.Items[placed.Item] {
			return "item_not_owned"
		}
	}
	return ""
}

type apartmentView struct {
	Apartment
	Owned   bool `json:"owned"`
	Current bool `json:"current"`
}

type homePaletteView struct {
	HomePalette
	Owned bool `json:"owned"`
}

type homeItemView struct {
	HomeItem
	Owned int `json:"owned"`
	// Copies standing in the other apartments, so not free for the current one.
	Elsewhere int `json:"elsewhere"`
}

// homeView: the catalog with ownership, the current apartment and its look.
func (tx *gameTx) homeView() map[string]any {
	content := &tx.content.Home
	home := &tx.me.state.Home
	current := content.apartment(home.Apartment)
	if current == nil {
		current = content.apartment(starterApartment)
	}
	apartments := []apartmentView{}
	for i := range content.Apartments {
		apartment := content.Apartments[i]
		apartments = append(apartments, apartmentView{Apartment: apartment, Owned: ownsApartment(home, &apartment), Current: apartment.ID == current.ID})
	}
	palettes := []homePaletteView{}
	for i := range content.Palettes {
		palettes = append(palettes, homePaletteView{HomePalette: content.Palettes[i], Owned: ownsPalette(content, home, &content.Palettes[i])})
	}
	elsewhere := placedElsewhere(home, current.ID)
	items := []homeItemView{}
	for _, item := range content.Items {
		items = append(items, homeItemView{HomeItem: item, Owned: home.Items[item.ID], Elsewhere: elsewhere[item.ID]})
	}
	return map[string]any{
		"apartments": apartments, "palettes": palettes, "items": items,
		"apartment": current.ID, "decor": decorOf(home, current), "max_owned": content.MaxOwned,
	}
}

func rpcGetHome(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		return tx.homeView(), nil
	})
}

type homePurchaseResult struct {
	purchaseResult
	Home map[string]any `json:"home,omitempty"`
}

// rpcBuyHome: {"kind": "apartment" | "palette" | "item", "id", "operation_key"} -> the purchase
// result and the updated home. A bought apartment is not moved into: the player moves with save_home.
func rpcBuyHome(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Kind         string `json:"kind"`
		ID           string `json:"id"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		failed := func(problem string) homePurchaseResult {
			return homePurchaseResult{purchaseResult: failedPurchase(problem, tx.me.balance)}
		}
		if problem, err := tx.playError(); problem != "" || err != nil {
			return failed(problem), err
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return failed("duplicate_operation"), err
		}
		price, problem := tx.homePrice(request.Kind, request.ID)
		if problem != "" {
			return failed(problem), nil
		}
		if tx.me.balance < int64(price) {
			return failed("not_enough_coins"), nil
		}
		home := &tx.me.state.Home
		switch request.Kind {
		case "apartment":
			home.Apartments = append(home.Apartments, request.ID)
		case "palette":
			home.Palettes = append(home.Palettes, request.ID)
		case "item":
			home.Items[request.ID]++
		}
		tx.credit(tx.me, -int64(price), "home_purchase", request.Kind+":"+request.ID)
		return homePurchaseResult{purchaseResult: purchaseResult{Status: "granted", Balance: tx.me.balance}, Home: tx.homeView()}, nil
	})
}

// homePrice: the price of a home purchase, or why it cannot be bought.
func (tx *gameTx) homePrice(kind, id string) (int, string) {
	content := &tx.content.Home
	home := &tx.me.state.Home
	switch kind {
	case "apartment":
		apartment := content.apartment(id)
		if apartment == nil {
			return 0, "unknown_apartment"
		}
		if ownsApartment(home, apartment) {
			return 0, "home_already_owned"
		}
		return apartment.Price, ""
	case "palette":
		palette := content.palette(id)
		if palette == nil {
			return 0, "unknown_palette"
		}
		if ownsPalette(content, home, palette) {
			return 0, "home_already_owned"
		}
		return palette.Price, ""
	case "item":
		item := content.item(id)
		if item == nil {
			return 0, "unknown_item"
		}
		if home.Items[id] >= content.MaxOwned {
			return 0, "too_many_copies"
		}
		return item.Price, ""
	}
	return 0, "unknown_kind"
}

// rpcSaveHome: {"apartment", "palette", "placed": [{item, x, y}]}: moves into an owned apartment and
// sets its look; without "palette" only moves in. -> {ok, error, home}.
func rpcSaveHome(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Apartment string       `json:"apartment"`
		Palette   string       `json:"palette"`
		Placed    []PlacedItem `json:"placed"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		content := &tx.content.Home
		home := &tx.me.state.Home
		apartment := content.apartment(request.Apartment)
		switch {
		case apartment == nil:
			return fail("unknown_apartment"), nil
		case !ownsApartment(home, apartment):
			return fail("apartment_not_owned"), nil
		}
		// No palette: only the move, the apartment keeps its look.
		decor := decorOf(home, apartment)
		if request.Palette != "" {
			decor = ApartmentDecor{Palette: request.Palette, Placed: request.Placed}
		}
		if decor.Placed == nil {
			decor.Placed = []PlacedItem{}
		}
		if problem := homeDecorError(content, home, apartment, decor); problem != "" {
			return fail(problem), nil
		}
		home.Apartment = apartment.ID
		home.Decor[apartment.ID] = &decor
		return map[string]any{"ok": true, "home": tx.homeView()}, nil
	})
}
