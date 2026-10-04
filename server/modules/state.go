package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"time"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

// Player progress lives in two server-only storage objects per user (game/state and game/inbox);
// coins live in the Nakama wallet. A gameTx loads what an RPC needs, the rules change it in memory,
// and commit writes storage and wallet in one MultiUpdate, so a crash never leaves coins without
// the matching state. Versions guard against concurrent RPCs; a conflict retries the whole RPC.

const (
	gameCollection       = "game"
	stateKey             = "state"
	inboxKey             = "inbox"
	operationsCollection = "operations"
	presenceCollection   = "office_presence"
	suspiciousCollection = "suspicious"
	rewardsCollection    = "reward_requests"
	walletCurrency       = "coins"
	maxInboxItems        = 100
	maxOperationKey      = 64
	txAttempts           = 3
)

type TaskLogEntry struct {
	ID     string `json:"id"`
	Title  string `json:"title"`
	Reward int    `json:"reward"`
	// Unix time of the reward; 0 in entries written before it was recorded.
	T int64 `json:"t,omitempty"`
}

type PhotoRequest struct {
	ID        string `json:"id"`
	Day       int    `json:"day"`
	Task      string `json:"task"`
	Partner   string `json:"partner"`
	T         int64  `json:"t"`
	State     string `json:"state"`
	Reward    int    `json:"reward"`
	PartnerIn int    `json:"partner_inbox_id"`
}

type MorningReport struct {
	Fined      int64 `json:"fined"`
	LostStreak int   `json:"lost_streak"`
}

type PlayerState struct {
	FirstDay     int                 `json:"first_day"`
	LastLoginDay int                 `json:"last_login_day"`
	ProcessedDay int                 `json:"processed_day"`
	BestStreak   int                 `json:"best_streak"`
	DevDayShift  int                 `json:"dev_day_shift,omitempty"`
	PresenceDays map[string]bool     `json:"presence_days"`
	ExcusedDays  map[string]bool     `json:"excused_days"`
	CheckinAt    map[string]int64    `json:"checkin_at"`
	CheckoutAt   map[string]int64    `json:"checkout_at"`
	Completed    map[string][]string `json:"completed"`
	Skipped      map[string][]string `json:"skipped"`
	Pending      map[string][]string `json:"pending"`
	// Tasks taken in their room (tasks.go: rpcTakeTask); only taken tasks can be completed.
	Taken              map[string][]string          `json:"taken"`
	Earned             map[string]int               `json:"earned"`
	TaskLog            map[string][]TaskLogEntry    `json:"task_log"`
	Met                map[string][]string          `json:"met"`
	Assignments        map[string]map[string]string `json:"assignments"`
	Purchases          map[string][]string          `json:"purchases"`
	OwnedItems         []string                     `json:"owned_items"`
	Cars               []string                     `json:"cars"`
	Car                string                       `json:"car"`
	Outfit             map[string]string            `json:"outfit"`
	Status             string                       `json:"status"`
	Avatar             string                       `json:"avatar"`
	HasCustomAvatar    bool                         `json:"has_custom_avatar"`
	UsedPresenceTokens []string                     `json:"used_presence_tokens"`
	// Office of the last entry code; "" in states written before offices existed (the default office).
	PresenceOffice string `json:"presence_office,omitempty"`
	// Room of the last room code inside the office interval; "" right after the entry and the exit.
	Room          string         `json:"room,omitempty"`
	PhotoRequests []PhotoRequest `json:"photo_requests"`
	MorningReport MorningReport  `json:"morning_report"`
	CoinsEarned   int            `json:"coins_earned"`
	WelcomeGiven  bool           `json:"welcome_given"`
	// Unix time the admin banned the player; 0 when not banned (users.go: rpcAdminSetBanned).
	BannedAt int64 `json:"banned_at,omitempty"`
	// Unix time of the last task that started the cooldown (limits.go).
	LastTaskAt int64 `json:"last_task_at,omitempty"`
	// DEV_MODE only: tasks count at any hour and without the pause (dev.go: dev_task_limits).
	DevNoTaskLimits bool `json:"dev_no_task_limits,omitempty"`
	// Continuous play (play.go) and play seconds per day.
	Play        PlaySession    `json:"play"`
	PlaySeconds map[string]int `json:"play_seconds"`
}

func (s *PlayerState) normalize() {
	if s.PresenceDays == nil {
		s.PresenceDays = map[string]bool{}
	}
	if s.ExcusedDays == nil {
		s.ExcusedDays = map[string]bool{}
	}
	if s.CheckinAt == nil {
		s.CheckinAt = map[string]int64{}
	}
	if s.CheckoutAt == nil {
		s.CheckoutAt = map[string]int64{}
	}
	for _, m := range []*map[string][]string{&s.Completed, &s.Skipped, &s.Pending, &s.Taken, &s.Met, &s.Purchases} {
		if *m == nil {
			*m = map[string][]string{}
		}
	}
	if s.Earned == nil {
		s.Earned = map[string]int{}
	}
	if s.PlaySeconds == nil {
		s.PlaySeconds = map[string]int{}
	}
	if s.TaskLog == nil {
		s.TaskLog = map[string][]TaskLogEntry{}
	}
	if s.Assignments == nil {
		s.Assignments = map[string]map[string]string{}
	}
	if s.Outfit == nil {
		s.Outfit = map[string]string{}
	}
	if s.Cars == nil {
		s.Cars = []string{}
	}
	if s.Car == "" {
		s.Car = starterCar
	}
	if s.Avatar == "" {
		s.Avatar = defaultAvatar
	}
}

// dayList returns the per-day list `lists[day]`.
func dayList(lists map[string][]string, day int) []string {
	return lists[dayKey(day)]
}

func addToDay(lists map[string][]string, day int, value string) {
	key := dayKey(day)
	if !contains(lists[key], value) {
		lists[key] = append(lists[key], value)
	}
}

func removeFromDay(lists map[string][]string, day int, value string) {
	key := dayKey(day)
	lists[key] = removeValue(lists[key], value)
}

func contains(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

func removeValue(values []string, value string) []string {
	result := values[:0]
	for _, v := range values {
		if v != value {
			result = append(result, v)
		}
	}
	return result
}

type InboxItem struct {
	ID     int            `json:"id"`
	Kind   string         `json:"kind"`
	T      int64          `json:"t"`
	Params map[string]any `json:"params"`
	Read   bool           `json:"read"`
	State  string         `json:"state"`
}

type Inbox struct {
	NextID int         `json:"next_id"`
	Items  []InboxItem `json:"items"`
}

// playerDoc is one player's account, state and (on demand) inbox inside a transaction.
type playerDoc struct {
	userID       string
	account      *api.Account
	metadata     accountMetadata
	balance      int64
	state        *PlayerState
	stateVersion string
	inbox        *Inbox
	inboxVersion string
	inboxDirty   bool
}

func (d *playerDoc) displayName() string {
	return d.account.GetUser().GetDisplayName()
}

type gameTx struct {
	ctx     context.Context
	logger  runtime.Logger
	db      *sql.DB
	nk      runtime.NakamaModule
	me      *playerDoc
	others  map[string]*playerDoc
	writes  []*runtime.StorageWrite
	wallet  []*runtime.WalletUpdate
	now     int64
	today   int
	offset  int64
	content *Content
	// Parking draw read in this transaction (raffle.go).
	draw *loadedDraw
	// Admin limits and today's task pack, read once per transaction (limits.go).
	loadedLimits *Limits
	pack         map[string]bool
	// Today's office of the player, read once per transaction (offices.go).
	loadedOffice *Office
	officeLoaded bool
}

// runPlayerTx runs `fn` for the calling player and commits its changes, retrying on version conflicts.
// A banned player is refused on every attempt: the ban writes the state first, so an RPC already
// running when the ban lands loses its version check, retries and stops here.
func runPlayerTx(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, fn func(tx *gameTx) (any, error)) (string, error) {
	userID, err := callerID(ctx)
	if err != nil {
		return "", err
	}
	return runUserTx(ctx, logger, db, nk, userID, func(tx *gameTx) (any, error) {
		if tx.me.metadata.Role != rolePlayer {
			return nil, errNotPlayer
		}
		if tx.me.banned() {
			return nil, errUnauthenticated
		}
		return fn(tx)
	})
}

// runUserTx runs `fn` with `userID` as tx.me; admin RPCs use it to change a player's state safely.
func runUserTx(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, userID string, fn func(tx *gameTx) (any, error)) (string, error) {
	for attempt := 1; ; attempt++ {
		tx := &gameTx{ctx: ctx, logger: logger, db: db, nk: nk, others: map[string]*playerDoc{}, content: gameContent}
		var err error
		tx.me, err = tx.loadPlayer(userID)
		if err != nil {
			return "", err
		}
		tx.offset = gameContent.officeOffset()
		tx.now = gameNow()
		if devMode {
			tx.now += int64(tx.me.state.DevDayShift) * secondsPerDay
		}
		tx.today = dayOf(tx.now, tx.offset)
		result, err := fn(tx)
		if err != nil {
			return "", err
		}
		commitErr := tx.commit()
		if commitErr == nil {
			return encodeResponse(result)
		}
		if attempt >= txAttempts {
			logger.Error("commit for %s failed: %v", userID, commitErr)
			return "", errInternal
		}
	}
}

// banned: the ban is in the game state or on the account (bans made before the state recorded it).
func (d *playerDoc) banned() bool {
	return d.state.BannedAt != 0 || d.account.GetDisableTime().GetSeconds() > 0
}

// banStart: unix time the current ban began, 0 when the player is not banned.
func (d *playerDoc) banStart() int64 {
	if d.state.BannedAt != 0 {
		return d.state.BannedAt
	}
	return d.account.GetDisableTime().GetSeconds()
}

func (tx *gameTx) loadPlayer(userID string) (*playerDoc, error) {
	account, err := tx.nk.AccountGetId(tx.ctx, userID)
	if err != nil {
		return nil, errUserNotFound
	}
	doc := &playerDoc{userID: userID, account: account, metadata: parseMetadata(account.GetUser().GetMetadata())}
	doc.balance = walletBalance(account.GetWallet())
	objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: gameCollection, Key: stateKey, UserID: userID}})
	if err != nil {
		return nil, errInternal
	}
	doc.state = &PlayerState{}
	if len(objects) > 0 {
		if err := json.Unmarshal([]byte(objects[0].GetValue()), doc.state); err != nil {
			return nil, errInternal
		}
		doc.stateVersion = objects[0].GetVersion()
	} else {
		doc.stateVersion = "*"
	}
	doc.state.normalize()
	return doc, nil
}

// other loads another player for a cross-player change (photo confirmation, raffle notice).
func (tx *gameTx) other(userID string) (*playerDoc, error) {
	if userID == tx.me.userID {
		return tx.me, nil
	}
	if doc, ok := tx.others[userID]; ok {
		return doc, nil
	}
	doc, err := tx.loadPlayer(userID)
	if err != nil {
		return nil, err
	}
	tx.others[userID] = doc
	return doc, nil
}

func (tx *gameTx) inboxOf(doc *playerDoc) (*Inbox, error) {
	if doc.inbox != nil {
		return doc.inbox, nil
	}
	objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: gameCollection, Key: inboxKey, UserID: doc.userID}})
	if err != nil {
		return nil, errInternal
	}
	doc.inbox = &Inbox{}
	doc.inboxVersion = "*"
	if len(objects) > 0 {
		if err := json.Unmarshal([]byte(objects[0].GetValue()), doc.inbox); err != nil {
			return nil, errInternal
		}
		doc.inboxVersion = objects[0].GetVersion()
	}
	return doc.inbox, nil
}

// notify adds a message to a player's inbox (a push notification will be sent from here later).
func (tx *gameTx) notify(doc *playerDoc, kind string, params map[string]any, itemState string) (int, error) {
	inbox, err := tx.inboxOf(doc)
	if err != nil {
		return 0, err
	}
	inbox.NextID++
	inbox.Items = append(inbox.Items, InboxItem{ID: inbox.NextID, Kind: kind, T: tx.now, Params: params, State: itemState})
	if len(inbox.Items) > maxInboxItems {
		inbox.Items = inbox.Items[len(inbox.Items)-maxInboxItems:]
	}
	doc.inboxDirty = true
	return inbox.NextID, nil
}

// credit changes a player's coins through the wallet ledger. The balance never goes below zero.
// Returns the amount applied.
func (tx *gameTx) credit(doc *playerDoc, amount int64, reason, reference string) int64 {
	applied := max(amount, -doc.balance)
	if applied == 0 {
		return 0
	}
	doc.balance += applied
	tx.wallet = append(tx.wallet, &runtime.WalletUpdate{
		UserID:    doc.userID,
		Changeset: map[string]int64{walletCurrency: applied},
		Metadata:  map[string]any{"reason": reason, "ref": reference},
	})
	return applied
}

// claimOperation makes a balance-changing RPC idempotent: false when the key was already used.
func (tx *gameTx) claimOperation(key string) (bool, error) {
	if key == "" || len(key) > maxOperationKey {
		return false, errInvalidPayload
	}
	objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: operationsCollection, Key: key, UserID: tx.me.userID}})
	if err != nil {
		return false, errInternal
	}
	if len(objects) > 0 {
		return false, nil
	}
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: operationsCollection, Key: key, UserID: tx.me.userID,
		Value: `{"t":` + jsonInt(tx.now) + `}`, Version: "*",
	})
	return true, nil
}

func (tx *gameTx) logSuspicious(task, reason string) {
	value, _ := json.Marshal(map[string]any{"user_id": tx.me.userID, "t": tx.now, "task": task, "reason": reason, "ip": tx.clientIP()})
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: suspiciousCollection, Key: randomKey(), UserID: systemUserID, Value: string(value),
	})
	tx.logger.Warn("suspicious: user %s task %s from %s: %s", tx.me.userID, task, tx.clientIP(), reason)
}

func (tx *gameTx) writeSystem(collection, key string, value any, version string) error {
	data, err := json.Marshal(value)
	if err != nil {
		return errInternal
	}
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: collection, Key: key, UserID: systemUserID, Value: string(data), Version: version,
	})
	return nil
}

func (tx *gameTx) commit() error {
	if tx.draw != nil && tx.draw.dirty {
		if err := tx.writeSystem(rafflesCollection, tx.draw.draw.ID, tx.draw.draw, tx.draw.version); err != nil {
			return err
		}
	}
	writes := append([]*runtime.StorageWrite{}, tx.writes...)
	// Day bookkeeping changes the state on nearly every call, so every loaded state is written.
	for _, doc := range tx.allDocs() {
		value, err := json.Marshal(doc.state)
		if err != nil {
			return err
		}
		writes = append(writes, &runtime.StorageWrite{
			Collection: gameCollection, Key: stateKey, UserID: doc.userID, Value: string(value), Version: doc.stateVersion,
		})
		if doc.inboxDirty {
			value, err := json.Marshal(doc.inbox)
			if err != nil {
				return err
			}
			writes = append(writes, &runtime.StorageWrite{
				Collection: gameCollection, Key: inboxKey, UserID: doc.userID, Value: string(value), Version: doc.inboxVersion,
			})
		}
	}
	_, _, err := tx.nk.MultiUpdate(tx.ctx, nil, writes, nil, tx.wallet, true)
	return err
}

func (tx *gameTx) allDocs() []*playerDoc {
	docs := []*playerDoc{tx.me}
	for _, doc := range tx.others {
		docs = append(docs, doc)
	}
	return docs
}

func walletBalance(raw string) int64 {
	var wallet map[string]int64
	if raw == "" || json.Unmarshal([]byte(raw), &wallet) != nil {
		return 0
	}
	return wallet[walletCurrency]
}

func randomKey() string {
	bytes := make([]byte, 12)
	if _, err := rand.Read(bytes); err != nil {
		return time.Now().Format("20060102150405.000000000")
	}
	return hex.EncodeToString(bytes)
}

func jsonInt(value int64) string {
	data, _ := json.Marshal(value)
	return string(data)
}
