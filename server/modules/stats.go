package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"sort"
	"strconv"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Admin statistics: read-only views of every player's progress for the audit in the admin panel.
// They read the same objects the game writes (game/state, the activity journal, the wallet ledger,
// the suspicious log and reward requests) and never change them.

const (
	statsMaxDays     = 366
	statsMaxEvents   = 1000
	statsMaxLedger   = 1000
	statsMaxFlagged  = 300
	statsMaxRequests = 300
)

type playerSummary struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	DisplayName string `json:"display_name"`
	// Home office and department: the statistics and the parking draw follow them.
	OfficeID     string `json:"office_id"`
	DepartmentID string `json:"department_id"`
	// Office the player counts in today (another one on a business trip) and the trip.
	CurrentOfficeID string    `json:"current_office_id"`
	Trip            *tripView `json:"trip"`
	Banned          bool      `json:"banned"`
	CreatedAt       int64     `json:"created_at"`
	Balance         int64     `json:"balance"`
	Streak          int       `json:"streak"`
	BestStreak      int       `json:"best_streak"`
	OfficeDays      int       `json:"office_days"`
	ExcusedDays     int       `json:"excused_days"`
	TasksTotal      int       `json:"tasks_total"`
	SkippedTotal    int       `json:"skipped_total"`
	CoinsEarned     int       `json:"coins_earned"`
	Colleagues      int       `json:"colleagues"`
	FirstDay        int       `json:"first_day"`
	LastLoginDay    int       `json:"last_login_day"`
	PresentToday    bool      `json:"present_today"`
	InOffice        bool      `json:"in_office"`
	Today           int       `json:"today"`
	LastActivity    int64     `json:"last_activity"`
	Car             string    `json:"car"`
	Status          string    `json:"status"`
	// Play today and the play-limit state (play.go): ok, warning, resting or blocked.
	PlaySecondsToday int    `json:"play_seconds_today"`
	PlayState        string `json:"play_state"`
	// In the office Wi-Fi now: inside the office day with a visit that is not silent (visits.go).
	OnSite bool `json:"on_site"`
	// The player's time and the silence that counts as gone out, for the visits of the day history.
	now         int64
	awaySeconds int64
}

// summarize computes a player's totals. `today` is the player's own day (dev clock included).
func summarize(summary *playerSummary, state *PlayerState, today int) {
	summary.Today = today
	summary.FirstDay = state.FirstDay
	summary.LastLoginDay = state.LastLoginDay
	summary.Streak = streak(state.PresenceDays, state.ExcusedDays, today, state.FirstDay)
	summary.BestStreak = max(state.BestStreak, summary.Streak)
	summary.OfficeDays = len(state.PresenceDays)
	summary.ExcusedDays = len(state.ExcusedDays)
	summary.CoinsEarned = state.CoinsEarned
	summary.PresentToday = state.PresenceDays[dayKey(today)]
	summary.InOffice = inOffice(state, today)
	summary.Car = state.Car
	summary.Status = state.Status
	summary.PlaySecondsToday = state.PlaySeconds[dayKey(today)]
	for _, done := range state.Completed {
		summary.TasksTotal += len(done)
	}
	for _, skipped := range state.Skipped {
		summary.SkippedTotal += len(skipped)
	}
	met := map[string]bool{}
	for _, ids := range state.Met {
		for _, id := range ids {
			met[id] = true
		}
	}
	summary.Colleagues = len(met)
}

// playerNow: the time the game uses for this player (the test clock, and the dev clock in DEV_MODE).
func playerNow(state *PlayerState) int64 {
	now := gameNow()
	if devMode {
		now += int64(state.DevDayShift) * secondsPerDay
	}
	return now
}

func parseState(raw sql.NullString) *PlayerState {
	state := &PlayerState{}
	if raw.Valid && raw.String != "" {
		_ = json.Unmarshal([]byte(raw.String), state)
	}
	state.normalize()
	return state
}

const playerRowsQuery = `
	SELECT u.id, u.username, u.display_name, u.metadata, u.wallet, u.disable_time, u.create_time, s.value,
		(SELECT max(a.create_time) FROM storage a WHERE a.collection = 'activity' AND a.user_id = u.id)
	FROM users u
	LEFT JOIN storage s ON s.collection = 'game' AND s.key = 'state' AND s.user_id = u.id
	WHERE u.id <> $1`

// loadPlayerRows reads players (not admins) with their state. An empty `userID` means all players.
func loadPlayerRows(ctx context.Context, db *sql.DB, nk runtime.NakamaModule, userID string) ([]playerSummary, map[string]*PlayerState, error) {
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return nil, nil, err
	}
	officeLimits := map[string]Limits{}
	for i := range offices {
		officeLimits[offices[i].ID] = offices[i].limits()
	}
	query, args := playerRowsQuery+` ORDER BY u.create_time DESC`, []any{systemUserID}
	if userID != "" {
		query, args = playerRowsQuery+` AND u.id = $2`, []any{systemUserID, userID}
	}
	rows, err := db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	summaries := []playerSummary{}
	states := map[string]*PlayerState{}
	for rows.Next() {
		var (
			summary      playerSummary
			displayName  sql.NullString
			metadata     string
			wallet       string
			disabled     time.Time
			created      time.Time
			stateValue   sql.NullString
			lastActivity sql.NullTime
		)
		if err := rows.Scan(&summary.ID, &summary.Username, &displayName, &metadata, &wallet, &disabled, &created, &stateValue, &lastActivity); err != nil {
			return nil, nil, err
		}
		parsed := parseMetadata(metadata)
		if parsed.Role == roleAdmin {
			continue
		}
		state := parseState(stateValue)
		summary.DisplayName = displayName.String
		summary.OfficeID = parsed.homeOffice()
		summary.DepartmentID = parsed.DepartmentID
		summary.Banned = disabled.Unix() > 0
		summary.CreatedAt = created.Unix()
		summary.Balance = walletBalance(wallet)
		if lastActivity.Valid {
			summary.LastActivity = lastActivity.Time.Unix()
		}
		now := playerNow(state)
		offset := gameContent.officeOffset()
		today := dayOf(now, offset)
		summarize(&summary, state, today)
		summary.CurrentOfficeID, _ = parsed.placement(today)
		summary.Trip = tripOf(parsed, today)
		limits, ok := officeLimits[summary.CurrentOfficeID]
		if !ok {
			limits = gameContent.Rules.Limits
		}
		summary.PlayState = currentPlayStatus(&state.Play, now, offset, limits).State
		summary.now, summary.awaySeconds = now, awaySeconds(limits)
		visit := openVisit(state, today)
		summary.OnSite = summary.InOffice && visit != nil && !visit.stale(now, summary.awaySeconds)
		summaries = append(summaries, summary)
		states[summary.ID] = state
	}
	return summaries, states, rows.Err()
}

// rpcAdminStatsOverview: -> {"players": [playerSummary]}, newest account first.
func rpcAdminStatsOverview(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	players, _, err := loadPlayerRows(ctx, db, nk, "")
	if err != nil {
		logger.Error("stats overview: %v", err)
		return "", errInternal
	}
	return encodeResponse(map[string]any{"players": players})
}

type namedID struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type statsDay struct {
	Day        int            `json:"day"`
	Workday    bool           `json:"workday"`
	Present    bool           `json:"present"`
	Excused    bool           `json:"excused"`
	CheckinAt  int64          `json:"checkin_at"`
	CheckoutAt int64          `json:"checkout_at"`
	Tasks      []TaskLogEntry `json:"tasks"`
	Skipped    []namedID      `json:"skipped"`
	Pending    []namedID      `json:"pending"`
	Met        []string       `json:"met"`
	Purchases  []string       `json:"purchases"`
	Earned     int            `json:"earned"`
	// Seconds the game was on screen that day.
	PlaySeconds int `json:"play_seconds"`
	// Every visit by the office Wi-Fi, and when the player left: the exit code or "Go home"
	// (CheckoutAt), else the end of the last visit; 0 while the player is still in.
	Visits []OfficeVisit `json:"visits"`
	LeftAt int64         `json:"left_at"`
}

type ledgerEntry struct {
	T      int64  `json:"t"`
	Change int64  `json:"change"`
	Reason string `json:"reason"`
	Ref    string `json:"ref"`
}

type flaggedEntry struct {
	T      int64  `json:"t"`
	Task   string `json:"task"`
	Reason string `json:"reason"`
}

type rewardRequest struct {
	T      int64  `json:"t"`
	ItemID string `json:"item_id"`
	Price  int    `json:"price"`
	Status string `json:"status"`
}

// rpcAdminPlayerStats: {"user_id"} -> the player's summary, day-by-day history (newest first),
// activity journal, wallet ledger, suspicious actions, reward requests and photo requests.
// `names` resolves the ids used in them (tasks, items, cars, colleagues) to display names.
func rpcAdminPlayerStats(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if _, err := playerMetadata(ctx, nk, request.UserID); err != nil {
		return "", err
	}
	players, states, err := loadPlayerRows(ctx, db, nk, request.UserID)
	if err != nil {
		logger.Error("stats of %s: %v", request.UserID, err)
		return "", errInternal
	}
	if len(players) == 0 {
		return "", errUserNotFound
	}
	player, state := players[0], states[request.UserID]
	names := newNameBook(gameContent)
	offices, err := listOffices(ctx, nk)
	if err != nil {
		return "", err
	}
	for _, office := range offices {
		names.names[office.ID] = office.Name
	}

	activity, err := loadActivity(ctx, db, request.UserID)
	names.addUsersFromActivity(activity)
	var (
		ledger   []ledgerEntry
		flagged  []flaggedEntry
		requests []rewardRequest
	)
	if err == nil {
		ledger, err = loadLedger(ctx, db, request.UserID)
	}
	if err == nil {
		flagged, err = loadFlagged(ctx, db, request.UserID)
	}
	if err == nil {
		requests, err = loadRewardRequests(ctx, db, request.UserID)
	}
	if err != nil {
		logger.Error("stats of %s: %v", request.UserID, err)
		return "", errInternal
	}
	days := statsDays(state, player, names)
	for _, photo := range state.PhotoRequests {
		names.user(photo.Partner)
	}
	for _, entry := range ledger {
		if entry.Reason == "photo_partner_bonus" || entry.Reason == "facts_partner_bonus" {
			names.user(entry.Ref)
		}
	}
	if err := names.resolveUsers(ctx, nk); err != nil {
		logger.Error("stats names for %s: %v", request.UserID, err)
		return "", errInternal
	}
	photos := state.PhotoRequests
	if photos == nil {
		photos = []PhotoRequest{}
	}
	return encodeResponse(map[string]any{
		"player": player, "days": days, "activity": activity, "ledger": ledger, "suspicious": flagged,
		"reward_requests": requests, "photo_requests": photos, "names": names.names,
		"excused_days": sortedDays(state.ExcusedDays),
	})
}

// statsDays: every day from the player's first day to today, newest first, that is a workday or
// has any activity. Weekends without activity are left out.
func statsDays(state *PlayerState, player playerSummary, names *nameBook) []statsDay {
	today := player.Today
	days := []statsDay{}
	if state.FirstDay == 0 {
		return days
	}
	for day := today; day >= state.FirstDay && today-day < statsMaxDays; day-- {
		key := dayKey(day)
		record := statsDay{
			Day: day, Workday: isWorkday(day), Present: state.PresenceDays[key], Excused: state.ExcusedDays[key],
			CheckinAt: state.CheckinAt[key], CheckoutAt: state.CheckoutAt[key],
			Tasks: state.TaskLog[key], Skipped: names.tasks(state.Skipped[key]), Pending: names.tasks(state.Pending[key]),
			Met: state.Met[key], Purchases: state.Purchases[key], Earned: state.Earned[key],
			PlaySeconds: state.PlaySeconds[key],
			Visits:      visitsOfDay(state, day, today, player.now, player.awaySeconds),
		}
		record.LeftAt = leftAt(state, record.Visits, day)
		if record.Tasks == nil {
			record.Tasks = []TaskLogEntry{}
		}
		if record.Met == nil {
			record.Met = []string{}
		}
		if record.Purchases == nil {
			record.Purchases = []string{}
		}
		for _, id := range record.Met {
			names.user(id)
		}
		idle := !record.Present && len(record.Tasks) == 0 && len(record.Skipped) == 0 && len(record.Pending) == 0 &&
			len(record.Purchases) == 0 && record.Earned == 0 && record.PlaySeconds == 0
		if !record.Workday && idle {
			continue
		}
		days = append(days, record)
	}
	return days
}

func sortedDays(set map[string]bool) []int {
	days := []int{}
	for key, on := range set {
		if day, err := strconv.Atoi(key); on && err == nil {
			days = append(days, day)
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(days)))
	return days
}

func loadActivity(ctx context.Context, db *sql.DB, userID string) ([]activityEvent, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT value FROM storage WHERE collection = $1 AND user_id = $2
		ORDER BY key DESC LIMIT $3`, activityCollection, userID, statsMaxEvents)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	events := []activityEvent{}
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			return nil, err
		}
		var event activityEvent
		if json.Unmarshal([]byte(value), &event) == nil {
			events = append(events, event)
		}
	}
	return events, rows.Err()
}

func loadLedger(ctx context.Context, db *sql.DB, userID string) ([]ledgerEntry, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT changeset, metadata, create_time FROM wallet_ledger WHERE user_id = $1
		ORDER BY create_time DESC LIMIT $2`, userID, statsMaxLedger)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	entries := []ledgerEntry{}
	for rows.Next() {
		var (
			changeset string
			metadata  string
			created   time.Time
		)
		if err := rows.Scan(&changeset, &metadata, &created); err != nil {
			return nil, err
		}
		var change map[string]int64
		var meta struct {
			Reason string `json:"reason"`
			Ref    string `json:"ref"`
		}
		_ = json.Unmarshal([]byte(changeset), &change)
		_ = json.Unmarshal([]byte(metadata), &meta)
		entries = append(entries, ledgerEntry{T: created.Unix(), Change: change[walletCurrency], Reason: meta.Reason, Ref: meta.Ref})
	}
	return entries, rows.Err()
}

// systemRowsOf reads system-owned objects of `collection` that name the player in "user_id".
func systemRowsOf(ctx context.Context, db *sql.DB, collection, userID string, limit int) ([]string, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT value FROM storage WHERE collection = $1 AND user_id = $2 AND value->>'user_id' = $3
		ORDER BY create_time DESC LIMIT $4`, collection, systemUserID, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	values := []string{}
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, rows.Err()
}

func loadFlagged(ctx context.Context, db *sql.DB, userID string) ([]flaggedEntry, error) {
	values, err := systemRowsOf(ctx, db, suspiciousCollection, userID, statsMaxFlagged)
	if err != nil {
		return nil, err
	}
	entries := []flaggedEntry{}
	for _, value := range values {
		var entry flaggedEntry
		if json.Unmarshal([]byte(value), &entry) == nil {
			entries = append(entries, entry)
		}
	}
	return entries, nil
}

func loadRewardRequests(ctx context.Context, db *sql.DB, userID string) ([]rewardRequest, error) {
	values, err := systemRowsOf(ctx, db, rewardsCollection, userID, statsMaxRequests)
	if err != nil {
		return nil, err
	}
	requests := []rewardRequest{}
	for _, value := range values {
		var request rewardRequest
		if json.Unmarshal([]byte(value), &request) == nil {
			requests = append(requests, request)
		}
	}
	return requests, nil
}

// nameBook collects the ids a stats answer mentions and their display names.
type nameBook struct {
	names   map[string]string
	userIDs map[string]bool
	content *Content
}

func newNameBook(content *Content) *nameBook {
	book := &nameBook{names: map[string]string{}, userIDs: map[string]bool{}, content: content}
	for _, task := range content.Tasks {
		book.names[task.ID] = task.Title
	}
	for _, item := range content.Catalog {
		book.names[item.ID] = item.Name
	}
	for _, car := range content.Cars {
		book.names[car.ID] = car.Name
	}
	return book
}

func (b *nameBook) user(id string) {
	if id != "" {
		b.userIDs[id] = true
	}
}

func (b *nameBook) tasks(ids []string) []namedID {
	result := []namedID{}
	for _, id := range ids {
		name := id
		if task := b.content.task(id); task != nil {
			name = task.Title
		}
		result = append(result, namedID{ID: id, Name: name})
	}
	return result
}

func (b *nameBook) addUsersFromActivity(events []activityEvent) {
	for _, event := range events {
		for _, key := range []string{"partner", "from"} {
			if id, ok := event.Params[key].(string); ok {
				b.user(id)
			}
		}
		if ids, ok := event.Params["colleagues"].([]any); ok {
			for _, id := range ids {
				if text, ok := id.(string); ok {
					b.user(text)
				}
			}
		}
	}
}

// resolveUsers looks up the display names of the collected user ids. Deleted accounts stay unnamed.
func (b *nameBook) resolveUsers(ctx context.Context, nk runtime.NakamaModule) error {
	ids := []string{}
	for id := range b.userIDs {
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		return nil
	}
	users, err := nk.UsersGetId(ctx, ids, nil)
	if err != nil {
		return err
	}
	for _, user := range users {
		name := user.GetDisplayName()
		if name == "" {
			name = user.GetUsername()
		}
		b.names[user.GetId()] = name
	}
	return nil
}
