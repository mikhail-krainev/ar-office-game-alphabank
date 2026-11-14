package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const loungeCollection = "lounge_rooms"

type loungePlayer struct {
	CharacterAvatar bool `json:"character_avatar"`

	Departed bool `json:"departed"`

	DecisionAt int64 `json:"decision_at"`

	ID         string            `json:"id"`
	Name       string            `json:"name"`
	Avatar     string            `json:"avatar"`
	Outfit     map[string]string `json:"outfit"`
	Ready      bool              `json:"ready"`
	Team       int               `json:"team"`
	Score      int               `json:"score"`
	Cards      []int             `json:"cards,omitempty"`
	Done       bool              `json:"done"`
	Passed     bool              `json:"passed"`
	Eliminated bool              `json:"eliminated"`
	Seen       int64             `json:"seen"`
}

type rouletteBet struct {
	Player int    `json:"player"`
	Field  string `json:"field"`
	Amount int64  `json:"amount"`
}

type loungeRoom struct {
	Awards map[string]int64 `json:"awards,omitempty"`

	Positions        map[string]int `json:"positions,omitempty"`
	QuietKings       int            `json:"quiet_kings"`
	TurnIrreversible bool           `json:"turn_irreversible"`
	PortalEntry      map[int]int    `json:"portal_entry,omitempty"`

	Captured []int `json:"captured,omitempty"`

	Training   bool  `json:"training"`
	MemorySize int   `json:"memory_size"`
	TieBreaks  int   `json:"tie_breaks"`
	Heat       int   `json:"heat"`
	HeatAt     int64 `json:"heat_at"`

	ID       string           `json:"id"`
	Game     string           `json:"game"`
	Host     string           `json:"host"`
	Capacity int              `json:"capacity"`
	Teams    bool             `json:"teams"`
	Stake    int64            `json:"stake"`
	Phase    string           `json:"phase"`
	Revision int              `json:"revision"`
	Players  []loungePlayer   `json:"players"`
	Created  int64            `json:"created"`
	Updated  int64            `json:"updated"`
	Started  int64            `json:"started"`
	Deadline int64            `json:"deadline"`
	Turn     int              `json:"turn"`
	Round    int              `json:"round"`
	Level    int              `json:"level"`
	Seed     int64            `json:"seed"`
	Pot      int64            `json:"pot"`
	Deck     []int            `json:"deck,omitempty"`
	Dealer   []int            `json:"dealer,omitempty"`
	Memory   []int            `json:"memory,omitempty"`
	Matched  map[int]bool     `json:"matched,omitempty"`
	Open     []int            `json:"open,omitempty"`
	HideAt   int64            `json:"hide_at,omitempty"`
	Board    []int            `json:"board,omitempty"`
	Chain    int              `json:"chain"`
	Moves    int              `json:"moves"`
	Power    map[int]string   `json:"power,omitempty"`
	Bonuses  map[int]string   `json:"bonuses,omitempty"`
	Blocked  map[int]int      `json:"blocked,omitempty"`
	Sequence []int            `json:"sequence,omitempty"`
	Progress int              `json:"progress"`
	Errors   int              `json:"errors"`
	Bets     []rouletteBet    `json:"bets,omitempty"`
	History  []int            `json:"history,omitempty"`
	Result   int              `json:"result"`
	Gains    map[string]int64 `json:"gains,omitempty"`
	Winners  []string         `json:"winners,omitempty"`
	Payouts  map[string]int64 `json:"payouts,omitempty"`
	Caught   map[string]bool  `json:"caught,omitempty"`
	Message  string           `json:"message"`
}

type loungeAction struct {
	Ready bool `json:"ready"`

	Training   bool `json:"training"`
	MemorySize int  `json:"memory_size"`

	ID        string `json:"room_id"`
	Action    string `json:"action"`
	Operation string `json:"operation_key"`
	Revision  int    `json:"revision"`
	Game      string `json:"game"`
	Capacity  int    `json:"capacity"`
	Teams     bool   `json:"teams"`
	Stake     int64  `json:"stake"`
	Index     int    `json:"index"`
	To        int    `json:"to"`
	Field     string `json:"field"`
	Amount    int64  `json:"amount"`
	Level     int    `json:"level"`
}

func loungeTeamsAllowed(game string) bool { return game == "memory" || game == "bug_hunt" }
func loungeCapacity(game string, n int) int {
	switch game {
	case "defuse":
		return 3
	case "checkers":
		if n == 4 {
			return 4
		}
		return 2
	case "roulette":
		return 30
	default:
		if n >= 1 && n <= 6 {
			return n
		}
		return 6
	}
}
func loungeGame(game string) bool {
	switch game {
	case "blackjack", "roulette", "checkers", "defuse", "memory", "bug_hunt":
		return true
	}
	return false
}
func (r *loungeRoom) player(id string) int {
	for i, p := range r.Players {
		if p.ID == id {
			return i
		}
	}
	return -1
}
func (r *loungeRoom) nextTurn() {
	for n := 0; n < len(r.Players); n++ {
		r.Turn = (r.Turn + 1) % len(r.Players)
		if !r.Players[r.Turn].Eliminated {
			return
		}
	}
}
func (r *loungeRoom) shuffle(n int) []int {
	cards := make([]int, n)
	for i := range cards {
		cards[i] = i
	}
	rng := seededRand(randomKey())
	rng.Shuffle(n, func(i, j int) { cards[i], cards[j] = cards[j], cards[i] })
	return cards
}
func (r *loungeRoom) pay(id string, amount int64) {
	if r.Payouts == nil {
		r.Payouts = map[string]int64{}
	}
	r.Payouts[id] += amount
	if r.Awards == nil {
		r.Awards = map[string]int64{}
	}
	r.Awards[id] += amount
}
func (r *loungeRoom) finish(winners []int) {
	r.Phase = "finished"
	for i := range r.Players {
		r.Players[i].Ready = false
	}
	r.Winners = []string{}
	if len(winners) == 0 {
		if r.Pot > 0 && len(r.Players) > 0 {
			for _, p := range r.Players {
				r.pay(p.ID, r.Stake)
			}
			r.Pot = 0
		}
		return
	}
	// Split once; shuffle determines recipients of the indivisible remainder.
	rng := seededRand(fmt.Sprintf("split|%s|%d", r.ID, r.Round))
	rng.Shuffle(len(winners), func(i, j int) { winners[i], winners[j] = winners[j], winners[i] })
	for i, p := range winners {
		r.Winners = append(r.Winners, r.Players[p].ID)
		amount := r.Pot / int64(len(winners))
		if int64(i) < r.Pot%int64(len(winners)) {
			amount++
		}
		r.pay(r.Players[p].ID, amount)
	}
	r.Pot = 0
}
func (r *loungeRoom) scoreWinners() []int {
	best := -1
	w := []int{}
	scores := map[int]int{}
	for i, p := range r.Players {
		if p.Eliminated {
			continue
		}
		key := i
		if r.Teams {
			key = p.Team
		}
		scores[key] += p.Score
	}
	for key, score := range scores {
		if score > best {
			best = score
			w = []int{key}
		} else if score == best {
			w = append(w, key)
		}
	}
	if !r.Teams {
		sort.Ints(w)
		return w
	}
	result := []int{}
	for i, p := range r.Players {
		for _, team := range w {
			if p.Team == team {
				result = append(result, i)
			}
		}
	}
	return result
}
func (r *loungeRoom) begin(now int64) string {
	n := len(r.Players)
	if n == 0 || (r.Game == "defuse" && n != 3) || (r.Game == "checkers" && n != r.Capacity) || (r.Game == "bug_hunt" && n < 2) {
		return "not_enough_players"
	}
	if r.Teams && (n != 4 && n != 6) {
		return "invalid_teams"
	}
	for i := range r.Players {
		if !r.Players[i].Ready {
			return "not_ready"
		}
		r.Players[i].Score = 0
		r.Players[i].Eliminated = false
		r.Players[i].Team = i % 2
	}
	r.TieBreaks = 0
	r.Phase = "playing"
	r.Started = now
	r.Round++
	r.Turn = 0
	r.Winners = nil
	r.Gains = nil
	r.Message = ""
	r.Payouts = nil
	r.Awards = nil
	switch r.Game {
	case "blackjack":
		r.deal(nil, now)
	case "roulette":
		r.Phase = "betting"
		r.Deadline = now + 20
		r.Bets = nil
	case "memory":
		if r.MemorySize != 12 && r.MemorySize != 36 {
			r.MemorySize = 24
		}
		r.Memory = r.shuffle(r.MemorySize)
		for i := range r.Memory {
			r.Memory[i] /= 2
		}
		r.Matched = map[int]bool{}
		r.Open = nil
		r.HideAt = 0
		r.Deadline = now + 15
	case "bug_hunt":
		r.Deadline = now + 90
		r.Caught = map[string]bool{}
	case "defuse":
		r.startDefuse(now)
	case "checkers":
		r.initCheckers()
		r.Deadline = now + 60
	}
	return ""
}
func (r *loungeRoom) act(id string, a loungeAction, now int64) string {
	p := r.player(id)
	if p < 0 {
		return "not_in_room"
	}
	if a.Action == "ready" {
		if r.Phase != "waiting" && r.Phase != "finished" {
			return "round_started"
		}
		r.Players[p].Ready = a.Ready
		return ""
	}
	if a.Action == "start" {
		if id != r.Host {
			return "host_only"
		}
		if r.Phase != "waiting" && r.Phase != "finished" {
			return "round_started"
		}
		return r.begin(now)
	}
	switch r.Game {
	case "blackjack":
		return r.blackjackAction(p, a.Action, now)
	case "memory":
		return r.memoryAction(p, a, now)
	case "checkers":
		return r.checkersAction(p, a, now)
	case "defuse":
		return r.defuseAction(p, a, now)
	case "bug_hunt":
		if r.Players[p].Eliminated || r.Phase != "playing" || a.Action != "catch" || a.Index < 0 || a.Index >= 24 {
			return "invalid_action"
		}
		wave := int((now - r.Started) / 30)
		if a.Index/8 != wave {
			return "wrong_wave"
		}
		key := fmt.Sprintf("%s|%d", id, a.Index)
		if r.Caught[key] {
			return "already_caught"
		}
		// A server time boundary prevents replaying catches or submitting an entire wave at once.
		if now-r.Players[p].Seen < 1 {
			return "too_fast"
		}
		r.Players[p].Seen = now
		r.Caught[key] = true
		points := 1
		if a.Index%8 == 7 {
			points = 3
		}
		r.Players[p].Score += points
		return ""
	}
	return "invalid_action"
}
func (r *loungeRoom) advance(now int64) bool {
	if r.Game == "defuse" && r.Level >= 4 && r.Phase == "playing" && !r.Training && now-r.HeatAt >= 3 {
		r.Heat += int((now - r.HeatAt) / 3)
		r.HeatAt = now
		if r.Heat >= 100 {
			r.Message = "Система перегрелась"
			r.finish(nil)
		}
		return true
	}
	if r.Deadline == 0 || now < r.Deadline || r.Phase == "finished" || r.Phase == "waiting" {
		return false
	}
	switch r.Game {
	case "roulette":
		r.advanceRoulette(now)
	case "blackjack":
		allDone := true
		for i := range r.Players {
			p := &r.Players[i]
			if !p.Done && now >= p.DecisionAt {
				p.Done = true
			}
			if !p.Done {
				allDone = false
			}
		}
		if allDone {
			r.resolveBlackjack(now)
		} else {
			r.blackjackDeadline()
		}
	case "memory":
		if r.HideAt > 0 {
			r.Open = nil
			r.HideAt = 0
			r.nextTurn()
		} else {
			r.Open = nil
			r.nextTurn()
		}
		r.Deadline = now + 15
	case "checkers":
		r.Players[r.Turn].Eliminated = true
		r.clearEliminated()
		r.nextTurn()
		r.finishCheckers()
		r.Deadline = now + 60
	case "defuse":
		r.Message = "Время истекло"
		r.finish(nil)
	case "bug_hunt":
		r.resolveScore(now)
	}
	return true
}
func (r *loungeRoom) view(id string, now int64) map[string]any {
	players := make([]map[string]any, len(r.Players))
	for i, p := range r.Players {
		v := map[string]any{"id": p.ID, "name": p.Name, "avatar": p.Avatar, "character_avatar": p.CharacterAvatar, "outfit": p.Outfit, "ready": p.Ready, "team": p.Team, "score": p.Score, "done": p.Done, "passed": p.Passed, "eliminated": p.Eliminated, "departed": p.Departed}
		if r.Game == "blackjack" && (p.ID == id || r.Phase == "finished" || p.Eliminated) {
			v["cards"] = publicInts(p.Cards)
			v["total"] = cardTotal(p.Cards)
		} else {
			v["card_count"] = len(p.Cards)
		}
		players[i] = v
	}
	v := map[string]any{"id": r.ID, "game": r.Game, "host": r.Host, "capacity": r.Capacity, "teams": r.Teams, "stake": r.Stake, "phase": r.Phase, "revision": r.Revision, "players": players, "turn": r.Turn, "round": r.Round, "level": r.Level, "training": r.Training, "pot": r.Pot, "left": max(int64(0), r.Deadline-now), "started": r.Started, "server_time": now, "message": r.Message, "winners": publicStrings(r.Winners)}
	awards := r.Awards
	if awards == nil {
		awards = map[string]int64{}
	}
	v["awards"] = awards
	switch r.Game {
	case "blackjack":
		if p := r.player(id); p >= 0 && !r.Players[p].Done && r.Phase == "playing" {
			v["left"] = max(int64(0), r.Players[p].DecisionAt-now)
		}
		if len(r.Players) == 1 {
			if r.Phase == "finished" {
				v["dealer"] = r.Dealer
			} else if len(r.Dealer) > 0 {
				v["dealer"] = r.Dealer[:1]
			}
		}
	case "memory":
		cards := make([]int, len(r.Memory))
		for i := range cards {
			cards[i] = -1
			if r.Matched[i] || containsInt(r.Open, i) {
				cards[i] = r.Memory[i]
			}
		}
		v["cards"] = cards
		v["matched"] = r.Matched
		v["open"] = publicInts(r.Open)
	case "roulette":
		bets := r.Bets
		if bets == nil {
			bets = []rouletteBet{}
		}
		gains := r.Gains
		if gains == nil {
			gains = map[string]int64{}
		}
		v["bets"] = bets
		v["history"] = publicInts(r.History)
		v["gains"] = gains
		if r.Phase == "result" {
			v["result"] = r.Result
		}
	// No result is sent before spinning has ended: clients cannot know the winning sector while betting.
	case "defuse":
		v["heat"] = r.Heat
		v["progress"] = r.Progress
		v["modules"] = len(r.Sequence)
		v["errors"] = r.Errors
		v["operator"] = (r.Level - 1) % 3
		v["instructor"] = r.Level % 3
		if r.player(id) == r.Level%3 {
			v["instruction"] = r.Sequence
		}
	case "checkers":
		v["board"] = r.Board
		v["chain"] = r.Chain
		v["powers"] = r.Power
		v["portal_entries"] = r.PortalEntry
		v["bonuses"] = r.Bonuses
		blocked := map[int]int{}
		for cell, until := range r.Blocked {
			if until > r.Moves {
				blocked[cell] = until
			}
		}
		v["blocked"] = blocked
	case "bug_hunt":
		v["seed"] = r.Seed
		v["wave"] = max(0, min(2, int((now-r.Started)/30)))
		caught := []int{}
		for i := 0; i < 24; i++ {
			if r.Caught[fmt.Sprintf("%s|%d", id, i)] {
				caught = append(caught, i)
			}
		}
		v["caught"] = caught
	}
	return v
}
func containsInt(a []int, n int) bool {
	for _, v := range a {
		if v == n {
			return true
		}
	}
	return false
}

func (tx *gameTx) loungeLoad(id string) (*loungeRoom, string, error) {
	if len(id) != 12 {
		return nil, "", errInvalidPayload
	}
	loaded, err := tx.loungeRead(id)
	if err != nil {
		return nil, "", err
	}
	return loaded.room, loaded.version, nil
}
func (tx *gameTx) loungeSettle(r *loungeRoom) error {
	for id, amount := range r.Payouts {
		if amount <= 0 {
			continue
		}
		doc, err := tx.other(id)
		if err != nil {
			return err
		}
		tx.credit(doc, amount, "lounge_payout", r.ID+":"+strconv.Itoa(r.Round))
	}
	r.Payouts = nil
	return nil
}
func rpcLoungeList(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		objects, _, err := nk.StorageList(ctx, "", systemUserID, loungeCollection, 100, "")
		if err != nil {
			return nil, errInternal
		}
		rooms := []any{}
		for _, o := range objects {
			var r loungeRoom
			if json.Unmarshal([]byte(o.GetValue()), &r) != nil || time.Now().Unix()-r.Updated > 3600 {
				continue
			}
			if r.Phase == "waiting" || r.Game == "roulette" && r.activeCount() > 0 || r.player(tx.me.userID) >= 0 {
				rooms = append(rooms, map[string]any{"id": r.ID, "game": r.Game, "phase": r.Phase, "count": r.activeCount(), "capacity": r.Capacity, "teams": r.Teams, "stake": r.Stake})
			}
		}
		return map[string]any{"ok": true, "rooms": rooms, "balance": tx.me.balance}, nil
	})
}
func rpcLoungeAction(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var a loungeAction
	if err := decodePayload(payload, &a); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		now := time.Now().Unix()
		var r *loungeRoom
		version := "*"
		var err error
		if a.Action == "create" {
			if !loungeGame(a.Game) || a.Stake < 0 || a.Stake > 1000000 || a.Teams && !loungeTeamsAllowed(a.Game) {
				return fail("invalid_mode"), nil
			}
			if a.Game != "defuse" {
				a.Training = false
			}
			if a.Game == "roulette" || a.Game == "defuse" {
				a.Stake = 0
			}
			if a.Game == "blackjack" && a.Stake%2 != 0 {
				return fail("even_stake_required"), nil
			}
			r = &loungeRoom{ID: randomKey()[:12], Game: a.Game, Host: tx.me.userID, Capacity: loungeCapacity(a.Game, a.Capacity), Teams: a.Teams, Stake: a.Stake, Phase: "waiting", Created: now, Updated: now, Seed: int64(seededRand(randomKey()).Int64N(2147483647)), Level: max(1, min(a.Level, 5)), Training: a.Training, MemorySize: a.MemorySize, Chain: -1}
		} else {
			r, version, err = tx.loungeLoad(a.ID)
			if err != nil {
				return nil, err
			}
		}
		if a.Action != "create" && a.Action != "join" && r.player(tx.me.userID) < 0 {
			return fail("not_in_room"), nil
		}
		changed := r.advance(now)
		if err := tx.loungeSettle(r); err != nil {
			return nil, err
		}
		errorKey := ""
		if a.Action != "get" {
			if changed && a.Action != "join" && r.Phase == "finished" {
				errorKey = "stale_room"
			} else {
				claimed, err := tx.claimOperation(a.Operation)
				if err != nil {
					return nil, err
				}
				if !claimed {
					errorKey = "duplicate_operation"
				} else {
					switch a.Action {
					case "create", "join":
						if p := r.player(tx.me.userID); p >= 0 {
							if r.Players[p].Departed && r.Phase != "betting" {
								errorKey = "round_started"
							} else {
								r.Players[p].Departed = false
							}
						}
						if r.player(tx.me.userID) < 0 {
							if len(r.Players) >= r.Capacity {
								errorKey = "room_full"
							} else if r.Phase != "waiting" && !(r.Game == "roulette" && r.Phase == "betting") {
								errorKey = "round_started"
							} else {
								r.Players = append(r.Players, loungePlayer{ID: tx.me.userID, Name: tx.me.displayName(), CharacterAvatar: tx.me.state.Avatar == defaultAvatar, Avatar: publicAvatar(tx.me.userID, tx.me.state.Avatar, tx.content.Rules.AvatarTemplates), Outfit: tx.me.state.Outfit, Team: len(r.Players) % 2, Seen: now})
							}
						}
					case "leave":
						if r.Phase != "waiting" && r.Phase != "finished" && r.Game != "roulette" {
							errorKey = "round_started"
						} else if r.Game == "roulette" && r.Phase != "waiting" && r.Phase != "finished" {
							r.Players[r.player(tx.me.userID)].Departed = true
						} else {
							p := r.player(tx.me.userID)
							r.Players = append(r.Players[:p], r.Players[p+1:]...)
							if len(r.Players) > 0 {
								r.Host = r.Players[0].ID
							} else {
								r.Phase = "finished"
							}
						}
					case "bet":
						fieldOK := a.Field == "red" || a.Field == "black" || a.Field == "green"
						if strings.HasPrefix(a.Field, "n") {
							n, e := strconv.Atoi(a.Field[1:])
							fieldOK = e == nil && n >= 0 && n <= 36
						}
						if r.Game != "roulette" || r.Phase != "betting" || r.Players[r.player(tx.me.userID)].Departed || !fieldOK || a.Amount < 1 || a.Amount > 1000000 || len(r.Bets) >= 300 {
							errorKey = "invalid_bet"
						} else if tx.me.balance < a.Amount {
							errorKey = "not_enough_coins"
						} else {
							tx.credit(tx.me, -a.Amount, "roulette_bet", r.ID)
							r.Bets = append(r.Bets, rouletteBet{Player: r.player(tx.me.userID), Field: a.Field, Amount: a.Amount})
						}
					default:
						if a.Action != "ready" && a.Revision != r.Revision {
							errorKey = "stale_room"
						} else {
							if a.Action == "start" {
								for i, p := range r.Players {
									doc, e := tx.other(p.ID)
									if e != nil {
										return nil, e
									}
									if doc.banned() {
										errorKey = "player_unavailable"
										break
									}
									r.Players[i].Outfit = doc.state.Outfit
									r.Players[i].CharacterAvatar = doc.state.Avatar == defaultAvatar
									r.Players[i].Avatar = publicAvatar(p.ID, doc.state.Avatar, tx.content.Rules.AvatarTemplates)
									r.Players[i].Name = doc.displayName()
									if doc.balance < r.Stake {
										errorKey = "not_enough_coins"
										break
									}
								}
							}
							if errorKey == "" {
								errorKey = r.act(tx.me.userID, a, now)
								if errorKey == "" && a.Action == "start" {
									r.Pot = r.Stake * int64(len(r.Players))
									for _, p := range r.Players {
										doc, _ := tx.other(p.ID)
										tx.credit(doc, -r.Stake, "lounge_stake", r.ID)
									}
								}
							}
						}
					}
					changed = changed || errorKey == ""
				}
			}
		}
		if err := tx.loungeSettle(r); err != nil {
			return nil, err
		}
		if changed {
			r.Revision++
			r.Updated = now
			tx.loungeSave(r, version)
		}
		return map[string]any{"ok": errorKey == "", "error": errorKey, "room": r.view(tx.me.userID, now), "balance": tx.me.balance}, nil
	})
}

func publicInts(values []int) []int {
	if values == nil {
		return []int{}
	}
	return values
}
func publicStrings(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}
