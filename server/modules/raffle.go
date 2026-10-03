package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Monthly parking draw, one per office (last Friday of the month, see game_rules.json): every office
// has its own parking. A player takes part in the draw of their home office, also on a business trip.
// Verifiable (commit-reveal): when a draw is created the server takes a secret seed and publishes
// only its SHA-256 commitment; at draw time the winner is HMAC-SHA256(seed, "<draw id>|<sorted
// ticket holders>") modulo the number of tickets. Anyone can recheck it once the seed is revealed.

const (
	rafflesCollection = "raffles"
	raffleDevKey      = "dev"
	raffleSeedBytes   = 32
	// 48 bits keep the value positive; the modulo bias is negligible for any realistic ticket count.
	raffleDigestBytes = 6
)

type raffleDraw struct {
	ID         string   `json:"id"`
	DrawAt     int64    `json:"draw_at"`
	Seed       string   `json:"seed"`
	Commitment string   `json:"commitment"`
	Tickets    []string `json:"tickets"`
	Drawn      bool     `json:"drawn"`
	Winner     string   `json:"winner"`
}

func newRaffleSeed() (string, error) {
	bytes := make([]byte, raffleSeedBytes)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func raffleCommitment(seedHex string) string {
	seed, _ := hex.DecodeString(seedHex)
	sum := sha256.Sum256(seed)
	return hex.EncodeToString(sum[:])
}

func canonicalEntries(entries []string) []string {
	sorted := append([]string{}, entries...)
	sort.Strings(sorted)
	return sorted
}

// raffleWinner: the ticket holder picked by the seed, or "" without tickets.
func raffleWinner(seedHex, drawID string, entries []string) string {
	sorted := canonicalEntries(entries)
	if len(sorted) == 0 {
		return ""
	}
	seed, _ := hex.DecodeString(seedHex)
	mac := hmac.New(sha256.New, seed)
	mac.Write([]byte(drawID + "|" + strings.Join(sorted, ",")))
	digest := mac.Sum(nil)
	var value uint64
	for i := range raffleDigestBytes {
		value = value<<8 | uint64(digest[i])
	}
	return sorted[value%uint64(len(sorted))]
}

// raffleSchedule: the office draw id and its time for the draw that is current on `today`: this
// month's last Friday, or next month's once that day is over.
func raffleSchedule(office string, today int, rules *Rules, offset int64) (string, int64) {
	drawDay := lastFridayOfMonth(today)
	if today > drawDay {
		drawDay = lastFridayOfMonth(lastDayOfMonth(today) + 1)
	}
	date := dateOf(drawDay)
	return fmt.Sprintf("parking-%s-%04d-%02d", office, date.Year(), int(date.Month())), unixAt(drawDay, rules.Raffle.DrawHour, rules.Raffle.DrawMinute, offset)
}

// raffleDevKey of the office: the dev draw that replaces its monthly draw for a day.
func raffleDevKeyOf(office string) string {
	return raffleDevKey + "-" + office
}

type loadedDraw struct {
	draw    raffleDraw
	version string
	// Changed or created in this transaction; commit saves it. A created draw is saved even
	// when nothing else changes, so its commitment stays.
	dirty bool
}

func readDraw(ctx context.Context, nk runtime.NakamaModule, key string) (*loadedDraw, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: rafflesCollection, Key: key, UserID: systemUserID}})
	if err != nil {
		return nil, errInternal
	}
	if len(objects) == 0 {
		return nil, nil
	}
	loaded := &loadedDraw{version: objects[0].GetVersion()}
	if err := json.Unmarshal([]byte(objects[0].GetValue()), &loaded.draw); err != nil {
		return nil, errInternal
	}
	return loaded, nil
}

// currentDraw returns the draw of the player's home office now, creating it (seed + commitment) on
// first use. A dev draw scheduled with dev_schedule_raffle replaces it for a day.
func (tx *gameTx) currentDraw() (*loadedDraw, error) {
	if tx.draw != nil {
		return tx.draw, nil
	}
	office := tx.me.metadata.homeOffice()
	id, drawAt := raffleSchedule(office, tx.today, &tx.content.Rules, tx.offset)
	if devMode {
		dev, err := readDraw(tx.ctx, tx.nk, raffleDevKeyOf(office))
		if err != nil {
			return nil, err
		}
		if dev != nil && tx.now < dev.draw.DrawAt+secondsPerDay {
			id, drawAt = dev.draw.ID, dev.draw.DrawAt
		}
	}
	loaded, err := readDraw(tx.ctx, tx.nk, id)
	if err != nil {
		return nil, err
	}
	if loaded == nil {
		seed, err := newRaffleSeed()
		if err != nil {
			return nil, errInternal
		}
		loaded = &loadedDraw{version: "*", dirty: true, draw: raffleDraw{ID: id, DrawAt: drawAt, Seed: seed, Commitment: raffleCommitment(seed), Tickets: []string{}}}
	}
	tx.draw = loaded
	return loaded, nil
}

// runDueDraw draws the current draw once its time has passed and tells every ticket holder.
func (tx *gameTx) runDueDraw() error {
	loaded, err := tx.currentDraw()
	if err != nil {
		return err
	}
	draw := &loaded.draw
	if draw.Drawn || tx.now < draw.DrawAt {
		return nil
	}
	draw.Drawn = true
	draw.Winner = raffleWinner(draw.Seed, draw.ID, draw.Tickets)
	loaded.dirty = true
	winnerName := ""
	if players, err := readPlayers(tx.ctx, tx.nk, []string{draw.Winner}, tx.today); err == nil {
		winnerName = players[draw.Winner].name
	}
	prize := tx.content.Rules.Raffle.PrizeName
	for _, userID := range draw.Tickets {
		doc, err := tx.other(userID)
		if err != nil {
			continue
		}
		if userID == draw.Winner {
			_, err = tx.notify(doc, "raffle_win", map[string]any{"prize": prize}, "")
		} else {
			_, err = tx.notify(doc, "raffle_lost", map[string]any{"prize": prize, "name": winnerName}, "")
		}
		if err != nil {
			return err
		}
	}
	return nil
}

type raffleEntrant struct {
	UserID string `json:"user_id"`
	Name   string `json:"name"`
	Avatar string `json:"avatar"`
}

type raffleView struct {
	DrawID           string          `json:"draw_id"`
	PrizeName        string          `json:"prize_name"`
	PrizeDescription string          `json:"prize_description"`
	TicketPrice      int             `json:"ticket_price"`
	DrawAt           int64           `json:"draw_at"`
	SecondsToDraw    int64           `json:"seconds_to_draw"`
	Drawn            bool            `json:"drawn"`
	Entrants         []raffleEntrant `json:"entrants"`
	HasTicket        bool            `json:"has_ticket"`
	BuyError         string          `json:"buy_error"`
	OfficeDays       int             `json:"office_days"`
	MinOfficeDays    int             `json:"min_office_days"`
	WindowDays       int             `json:"window_days"`
	Commitment       string          `json:"commitment"`
	RevealedSeed     string          `json:"revealed_seed"`
	WinnerID         string          `json:"winner_id"`
	WinnerName       string          `json:"winner_name"`
	IsWinner         bool            `json:"is_winner"`
}

func (tx *gameTx) officeDaysInWindow(window int) int {
	count := 0
	for key := range tx.me.state.PresenceDays {
		var day int
		if _, err := fmt.Sscan(key, &day); err == nil && day > tx.today-window && day <= tx.today {
			count++
		}
	}
	return count
}

func (tx *gameTx) raffleView(draw *raffleDraw) (raffleView, error) {
	rules := tx.content.Rules.Raffle
	view := raffleView{
		DrawID: draw.ID, PrizeName: rules.PrizeName, PrizeDescription: rules.PrizeDescription, TicketPrice: rules.TicketPrice,
		DrawAt: draw.DrawAt, SecondsToDraw: max(0, draw.DrawAt-tx.now), Drawn: draw.Drawn, Entrants: []raffleEntrant{},
		HasTicket: contains(draw.Tickets, tx.me.userID), MinOfficeDays: rules.MinOfficeDays, WindowDays: rules.WindowDays,
		OfficeDays: tx.officeDaysInWindow(rules.WindowDays), Commitment: draw.Commitment,
	}
	players, err := readPlayers(tx.ctx, tx.nk, draw.Tickets, tx.today)
	if err != nil {
		return view, err
	}
	for _, userID := range canonicalEntries(draw.Tickets) {
		player := players[userID]
		view.Entrants = append(view.Entrants, raffleEntrant{
			UserID: userID, Name: player.name, Avatar: publicAvatar(userID, player.avatar, tx.content.Rules.AvatarTemplates),
		})
	}
	if draw.Drawn {
		view.RevealedSeed = draw.Seed
		view.WinnerID = draw.Winner
		view.WinnerName = players[draw.Winner].name
		view.IsWinner = draw.Winner == tx.me.userID
	}
	switch {
	case draw.Drawn || tx.now >= draw.DrawAt:
		view.BuyError = "raffle_closed"
	case view.HasTicket:
		view.BuyError = "raffle_already_joined"
	case view.OfficeDays < view.MinOfficeDays:
		view.BuyError = "raffle_not_eligible"
	case tx.me.balance < int64(rules.TicketPrice):
		view.BuyError = "not_enough_coins"
	}
	return view, nil
}

func rpcGetRaffle(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if err := tx.tick(); err != nil {
			return nil, err
		}
		loaded, err := tx.currentDraw()
		if err != nil {
			return nil, err
		}
		return tx.raffleView(&loaded.draw)
	})
}

// rpcBuyRaffleTicket: {"operation_key"}.
func rpcBuyRaffleTicket(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
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
		loaded, err := tx.currentDraw()
		if err != nil {
			return nil, err
		}
		view, err := tx.raffleView(&loaded.draw)
		if err != nil {
			return nil, err
		}
		if view.BuyError != "" {
			return failedPurchase(view.BuyError, tx.me.balance), nil
		}
		loaded.draw.Tickets = append(loaded.draw.Tickets, tx.me.userID)
		loaded.dirty = true
		tx.credit(tx.me, -int64(view.TicketPrice), "raffle_ticket", loaded.draw.ID)
		return purchaseResult{Status: "granted", Balance: tx.me.balance}, nil
	})
}
