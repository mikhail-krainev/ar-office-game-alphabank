package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Admin console: a developer console in the admin panel, like the console of a Source game. The
// admin types a command line, the server parses and runs it and answers with text. In prod only the
// commands that show data run; APP_ENV=dev also opens the ones that change the game (coins, tasks,
// presence, time; console_dev.go). Every change goes through the same transactions as the game, the
// coins through the wallet ledger, and the player's activity journal records the command line.

const (
	appEnvDev = "dev"

	maxConsoleLine = 500
	// Rows a listing prints by default and at most.
	consoleDefaultRows = 10
	consoleMaxRows     = 200

	activityAdminConsole = "admin_console"
	consoleLedgerReason  = "admin_console"
)

var errConsoleDevOnly = runtime.NewError("console_dev_only", codePermissionDenied)

// consoleError is a message for the admin (a wrong argument, an unknown player), not a failure.
type consoleError string

func (e consoleError) Error() string { return string(e) }

func consoleErrorf(format string, args ...any) error {
	return consoleError(fmt.Sprintf(format, args...))
}

type consoleCall struct {
	ctx    context.Context
	logger runtime.Logger
	db     *sql.DB
	nk     runtime.NakamaModule
	line   string
}

type consoleCommand struct {
	Name string `json:"name"`
	Args string `json:"args"`
	Help string `json:"help"`
	// Changes the game: runs only with APP_ENV=dev.
	Dev     bool `json:"dev"`
	minArgs int
	run     func(c *consoleCall, args []string) (string, error)
}

// Filled in init: help lists the commands, so a package-level initializer would be a cycle.
var consoleCommands []consoleCommand

func init() {
	consoleCommands = append(consoleViewCommands(), consoleDevCommands()...)
}

func findConsoleCommand(name string) *consoleCommand {
	for i := range consoleCommands {
		if consoleCommands[i].Name == name {
			return &consoleCommands[i]
		}
	}
	return nil
}

type consoleInfo struct {
	Env       string           `json:"env"`
	TestClock bool             `json:"test_clock"`
	Commands  []consoleCommand `json:"commands"`
}

func consoleEnv() string {
	if devEnv {
		return appEnvDev
	}
	return "prod"
}

// rpcAdminConsoleInfo: -> consoleInfo, for the help and the autocompletion of the panel.
func rpcAdminConsoleInfo(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	return encodeResponse(consoleInfo{Env: consoleEnv(), TestClock: testClock, Commands: consoleCommands})
}

type consoleResult struct {
	OK     bool   `json:"ok"`
	Output string `json:"output"`
	// Error key the panel translates (messages.ts), when a game rule refused the command.
	Error string `json:"error,omitempty"`
}

// rpcAdminConsole: {"line"} -> consoleResult. Only the admin; dev commands only with APP_ENV=dev.
func rpcAdminConsole(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request struct {
		Line string `json:"line"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	line := strings.TrimSpace(request.Line)
	if line == "" || len(line) > maxConsoleLine {
		return "", errInvalidPayload
	}
	adminID, _ := callerID(ctx)
	call := &consoleCall{ctx: ctx, logger: logger, db: db, nk: nk, line: line}
	output, err := call.execute()
	var message consoleError
	var runtimeErr *runtime.Error
	switch {
	case err == nil:
		logger.Info("console %s: %s", adminID, line)
		return encodeResponse(consoleResult{OK: true, Output: output})
	case errors.As(err, &message):
		return encodeResponse(consoleResult{Output: message.Error()})
	case errors.As(err, &runtimeErr):
		return encodeResponse(consoleResult{Error: runtimeErr.Message})
	default:
		logger.Error("console %s: %s: %v", adminID, line, err)
		return "", errInternal
	}
}

func (c *consoleCall) execute() (string, error) {
	words, err := splitConsoleLine(c.line)
	if err != nil {
		return "", err
	}
	command := findConsoleCommand(strings.ToLower(words[0]))
	if command == nil {
		return "", consoleErrorf("Неизвестная команда %q. Список команд: help", words[0])
	}
	if command.Dev && !devEnv {
		return "", errConsoleDevOnly
	}
	args := words[1:]
	if len(args) < command.minArgs {
		return "", consoleErrorf("Использование: %s %s", command.Name, command.Args)
	}
	return command.run(c, args)
}

// splitConsoleLine splits a line into words; "double quotes" keep spaces inside one word.
func splitConsoleLine(line string) ([]string, error) {
	words := []string{}
	var word strings.Builder
	inQuotes, hasWord := false, false
	for _, r := range line {
		switch {
		case r == '"':
			inQuotes, hasWord = !inQuotes, true
		case (r == ' ' || r == '\t') && !inQuotes:
			if hasWord {
				words = append(words, word.String())
				word.Reset()
				hasWord = false
			}
		default:
			word.WriteRune(r)
			hasWord = true
		}
	}
	if inQuotes {
		return nil, consoleError("Не закрыта кавычка")
	}
	if hasWord {
		words = append(words, word.String())
	}
	if len(words) == 0 {
		return nil, consoleError("Пустая команда")
	}
	return words, nil
}

// --- Arguments -------------------------------------------------------------------

func parseConsoleInt(text string, low, high int64) (int64, error) {
	value, err := strconv.ParseInt(text, 10, 64)
	if err != nil || value < low || value > high {
		return 0, consoleErrorf("Нужно целое число от %d до %d, а не %q", low, high, text)
	}
	return value, nil
}

// optionalRows: the row count of a listing, the default without the argument.
func optionalRows(args []string, index int) (int, error) {
	if len(args) <= index {
		return consoleDefaultRows, nil
	}
	rows, err := parseConsoleInt(args[index], 1, consoleMaxRows)
	return int(rows), err
}

// parseConsoleDuration: "90" (seconds), "45m", "12h", "3d" or a sum like "1d12h".
func parseConsoleDuration(text string) (int64, error) {
	if seconds, err := strconv.ParseInt(text, 10, 64); err == nil {
		return seconds, nil
	}
	units := map[byte]int64{'s': 1, 'm': 60, 'h': 3600, 'd': secondsPerDay}
	total, number, digits := int64(0), int64(0), 0
	for i := 0; i < len(text); i++ {
		ch := text[i]
		if ch >= '0' && ch <= '9' {
			number, digits = number*10+int64(ch-'0'), digits+1
			if number > maxClockShiftSeconds {
				return 0, consoleErrorf("Слишком большая длительность %q", text)
			}
			continue
		}
		unit, ok := units[ch]
		if !ok || digits == 0 {
			return 0, consoleErrorf("Длительность: секунды или 45m, 12h, 3d, 1d12h, а не %q", text)
		}
		total, number, digits = total+number*unit, 0, 0
		if total > maxClockShiftSeconds {
			return 0, consoleErrorf("Слишком большая длительность %q", text)
		}
	}
	if digits != 0 || total == 0 {
		return 0, consoleErrorf("Длительность: секунды или 45m, 12h, 3d, 1d12h, а не %q", text)
	}
	return total, nil
}

func parseOnOff(text string) (bool, error) {
	switch strings.ToLower(text) {
	case "on", "1", "true":
		return true, nil
	case "off", "0", "false":
		return false, nil
	}
	return false, consoleErrorf("Нужно on или off, а не %q", text)
}

// player finds a player account by login; admins and managers are not players.
func (c *consoleCall) player(username string) (string, error) {
	users, err := c.nk.UsersGetUsername(c.ctx, []string{normalizeUsername(username)})
	if err != nil {
		return "", errInternal
	}
	if len(users) == 0 {
		return "", consoleErrorf("Нет пользователя с логином %q (поиск: find)", username)
	}
	if playerOnly(parseMetadata(users[0].GetMetadata())) != nil {
		return "", consoleErrorf("%q — не игрок", username)
	}
	return users[0].GetId(), nil
}

// inspect reads a player at the current game time; nothing is saved.
func (c *consoleCall) inspect(username string, fn func(tx *gameTx) (string, error)) (string, error) {
	userID, err := c.player(username)
	if err != nil {
		return "", err
	}
	tx, err := newGameTx(c.ctx, c.logger, c.db, c.nk, userID)
	if err != nil {
		return "", err
	}
	return fn(tx)
}

// change runs `fn` in a game transaction of the player and records the command line in the
// player's activity journal.
func (c *consoleCall) change(username string, fn func(tx *gameTx) (string, error)) (string, error) {
	userID, err := c.player(username)
	if err != nil {
		return "", err
	}
	var output string
	_, err = runUserTx(c.ctx, c.logger, c.db, c.nk, userID, func(tx *gameTx) (any, error) {
		text, err := fn(tx)
		if err != nil {
			return nil, err
		}
		output = text
		tx.logActivity(tx.me, activityAdminConsole, map[string]any{"command": c.line})
		return nil, nil
	})
	return output, err
}

// --- Formatting --------------------------------------------------------------------

func formatGameTime(unix int64) string {
	if unix == 0 {
		return "—"
	}
	return time.Unix(unix+gameContent.officeOffset(), 0).UTC().Format("02.01.2006 15:04:05")
}

func formatDay(day int) string {
	return time.Unix(int64(day)*secondsPerDay, 0).UTC().Format("02.01.2006")
}

func yesNo(value bool) string {
	if value {
		return "да"
	}
	return "нет"
}

// table aligns rows into columns separated by two spaces.
func table(rows [][]string) string {
	widths := []int{}
	for _, row := range rows {
		for i, cell := range row {
			if i >= len(widths) {
				widths = append(widths, 0)
			}
			widths[i] = max(widths[i], len([]rune(cell)))
		}
	}
	var out strings.Builder
	for _, row := range rows {
		for i, cell := range row {
			out.WriteString(cell)
			if i < len(row)-1 {
				out.WriteString(strings.Repeat(" ", widths[i]-len([]rune(cell))+2))
			}
		}
		out.WriteString("\n")
	}
	return strings.TrimRight(out.String(), "\n")
}

// --- Commands that only show data (prod and dev) ------------------------------------

func consoleViewCommands() []consoleCommand {
	return []consoleCommand{
		{Name: "help", Args: "[команда]", Help: "список команд или описание одной", run: consoleHelp},
		{Name: "status", Help: "окружение, игровое время, игроки в офисе", run: consoleStatus},
		{Name: "time", Help: "игровое время и сдвиг тестовых часов", run: consoleTime},
		{Name: "find", Args: "<текст>", Help: "игроки, у которых логин или имя содержат текст", minArgs: 1, run: consoleFind},
		{Name: "player", Args: "<логин>", Help: "сводка по игроку: офис, баланс, серия, задания, лимит игры", minArgs: 1, run: consolePlayer},
		{Name: "tasks", Args: "<логин>", Help: "задания игрока на сегодня и их состояние", minArgs: 1, run: consoleTasks},
		{Name: "ledger", Args: "<логин> [N]", Help: "последние N движений монет игрока", minArgs: 1, run: consoleLedger},
		{Name: "activity", Args: "<логин> [N]", Help: "последние N действий игрока", minArgs: 1, run: consoleActivity},
		{Name: "offices", Help: "офисы, их сети и лимиты", run: consoleOffices},
		{Name: "departments", Help: "департаменты по офисам", run: consoleDepartments},
		{Name: "task_list", Help: "все задания игры: id, комната, награда", run: consoleTaskList},
		{Name: "items", Help: "каталог наград: id, редкость, цена", run: consoleItems},
		{Name: "stock", Help: "запас наград на эту неделю", run: consoleStock},
		{Name: "raffle", Args: "<логин>", Help: "розыгрыш парковки домашнего офиса игрока", minArgs: 1, run: consoleRaffle},
	}
}

func consoleHelp(_ *consoleCall, args []string) (string, error) {
	if len(args) > 0 {
		command := findConsoleCommand(strings.ToLower(args[0]))
		if command == nil {
			return "", consoleErrorf("Нет команды %q", args[0])
		}
		return describeCommand(command), nil
	}
	rows := [][]string{}
	for i := range consoleCommands {
		command := &consoleCommands[i]
		if command.Dev && !devEnv {
			continue
		}
		rows = append(rows, []string{strings.TrimSpace(command.Name + " " + command.Args), command.Help})
	}
	footer := "\n\nОкружение: " + consoleEnv()
	if !devEnv {
		footer += ". Команды, меняющие игру, работают только с APP_ENV=dev."
	}
	return table(rows) + footer, nil
}

func describeCommand(command *consoleCommand) string {
	text := strings.TrimSpace(command.Name+" "+command.Args) + "\n  " + command.Help
	if command.Dev {
		text += "\n  только APP_ENV=dev"
	}
	return text
}

func consoleStatus(c *consoleCall, _ []string) (string, error) {
	players, _, err := loadPlayerRows(c.ctx, c.db, c.nk, "")
	if err != nil {
		return "", err
	}
	inOffice, onSite, banned := 0, 0, 0
	for _, player := range players {
		inOffice += boolCount(player.InOffice)
		onSite += boolCount(player.OnSite)
		banned += boolCount(player.Banned)
	}
	return table([][]string{
		{"Окружение", consoleEnv()},
		{"DEV_MODE", yesNo(devMode)},
		{"Тестовые часы", yesNo(testClock)},
		{"Игровое время", formatGameTime(gameNow())},
		{"Игроков", strconv.Itoa(len(players))},
		{"В офисе сегодня", strconv.Itoa(inOffice)},
		{"В Wi-Fi офиса сейчас", strconv.Itoa(onSite)},
		{"Заблокировано", strconv.Itoa(banned)},
	}), nil
}

func boolCount(value bool) int {
	if value {
		return 1
	}
	return 0
}

func consoleTime(_ *consoleCall, _ []string) (string, error) {
	view := currentClockView()
	rows := [][]string{
		{"Игровое время", formatGameTime(view.Now)},
		{"Реальное время", formatGameTime(time.Now().Unix())},
		{"Тестовые часы", yesNo(view.Enabled)},
	}
	if view.Enabled {
		rows = append(rows, []string{"Сдвиг", formatSeconds(view.ShiftSeconds)})
	}
	return table(rows), nil
}

// formatSeconds: "2д 5ч 10м" for a duration in seconds.
func formatSeconds(seconds int64) string {
	if seconds == 0 {
		return "0"
	}
	days, hours, minutes := seconds/secondsPerDay, seconds%secondsPerDay/3600, seconds%3600/60
	parts := []string{}
	for _, part := range []struct {
		value int64
		unit  string
	}{{days, "д"}, {hours, "ч"}, {minutes, "м"}, {seconds % 60, "с"}} {
		if part.value != 0 {
			parts = append(parts, fmt.Sprintf("%d%s", part.value, part.unit))
		}
	}
	return strings.Join(parts, " ")
}

func consoleFind(c *consoleCall, args []string) (string, error) {
	needle := strings.ToLower(strings.Join(args, " "))
	players, _, err := loadPlayerRows(c.ctx, c.db, c.nk, "")
	if err != nil {
		return "", err
	}
	rows := [][]string{{"ЛОГИН", "ИМЯ", "ОФИС", "БАЛАНС", "В ОФИСЕ"}}
	for _, player := range players {
		if !strings.Contains(strings.ToLower(player.Username), needle) && !strings.Contains(strings.ToLower(player.DisplayName), needle) {
			continue
		}
		rows = append(rows, []string{player.Username, player.DisplayName, player.CurrentOfficeID, strconv.FormatInt(player.Balance, 10), yesNo(player.InOffice)})
		if len(rows) > consoleMaxRows {
			break
		}
	}
	if len(rows) == 1 {
		return "Никого не нашлось", nil
	}
	return table(rows), nil
}

func consolePlayer(c *consoleCall, args []string) (string, error) {
	userID, err := c.player(args[0])
	if err != nil {
		return "", err
	}
	players, states, err := loadPlayerRows(c.ctx, c.db, c.nk, userID)
	if err != nil || len(players) == 0 {
		return "", errInternal
	}
	player, state := players[0], states[userID]
	return table([][]string{
		{"Логин", player.Username},
		{"Имя", player.DisplayName},
		{"ID", player.ID},
		{"Офис / департамент", player.OfficeID + " / " + player.DepartmentID},
		{"Офис сегодня", player.CurrentOfficeID},
		{"Заблокирован", yesNo(player.Banned)},
		{"Баланс", strconv.FormatInt(player.Balance, 10)},
		{"Заработано всего", strconv.Itoa(player.CoinsEarned)},
		{"Серия / лучшая", fmt.Sprintf("%d / %d", player.Streak, player.BestStreak)},
		{"Дней в офисе", strconv.Itoa(player.OfficeDays)},
		{"Сегодня", formatDay(player.Today)},
		{"Был сегодня / в офисе / в Wi-Fi", fmt.Sprintf("%s / %s / %s", yesNo(player.PresentToday), yesNo(player.InOffice), yesNo(player.OnSite))},
		{"Комната", state.Room},
		{"Заданий выполнено / пропущено", fmt.Sprintf("%d / %d", player.TasksTotal, player.SkippedTotal)},
		{"Заработано сегодня", strconv.Itoa(state.Earned[dayKey(player.Today)])},
		{"Лимит игры", player.PlayState},
		{"Спинов колеса", strconv.Itoa(spinsLeft(state, player.Today))},
		{"Без лимитов заданий", yesNo(state.DevNoTaskLimits)},
	}), nil
}

func consoleTasks(c *consoleCall, args []string) (string, error) {
	return c.inspect(args[0], func(tx *gameTx) (string, error) {
		multiplier := tx.multiplier()
		rows := [][]string{{"ID", "КОМНАТА", "НАГРАДА", "СОСТОЯНИЕ", "НАЗВАНИЕ"}}
		for i := range tx.content.Tasks {
			task := &tx.content.Tasks[i]
			if tx.isTodaysTask(task) {
				rows = append(rows, []string{task.ID, task.Room, strconv.Itoa(taskReward(task, multiplier)), tx.taskState(task), task.Title})
			}
		}
		schedule, err := tx.taskSchedule()
		if err != nil {
			return "", err
		}
		footer := fmt.Sprintf("\n\nЧасы заданий %s–%s, сейчас %s; до следующего задания %s",
			schedule.WindowStart, schedule.WindowEnd, map[bool]string{true: "можно", false: "нельзя"}[schedule.InWindow], formatSeconds(schedule.NextTaskIn))
		return table(rows) + footer, nil
	})
}

// taskState: what the player did with a task of today's pack.
func (tx *gameTx) taskState(task *Task) string {
	state := tx.me.state
	switch {
	case contains(dayList(state.Completed, tx.today), task.ID):
		return "выполнено"
	case contains(dayList(state.Pending, tx.today), task.ID):
		return "ждёт подтверждения"
	case contains(dayList(state.Skipped, tx.today), task.ID):
		return "пропущено"
	case task.Room != "" && contains(dayList(state.Taken, tx.today), task.ID):
		return "взято"
	}
	return "открыто"
}

func consoleLedger(c *consoleCall, args []string) (string, error) {
	userID, err := c.player(args[0])
	if err != nil {
		return "", err
	}
	limit, err := optionalRows(args, 1)
	if err != nil {
		return "", err
	}
	entries, err := loadLedger(c.ctx, c.db, userID)
	if err != nil {
		return "", err
	}
	rows := [][]string{{"ВРЕМЯ", "СУММА", "ПРИЧИНА", "ССЫЛКА"}}
	for _, entry := range entries[:min(limit, len(entries))] {
		rows = append(rows, []string{formatGameTime(entry.T), fmt.Sprintf("%+d", entry.Change), entry.Reason, entry.Ref})
	}
	return table(rows), nil
}

func consoleActivity(c *consoleCall, args []string) (string, error) {
	userID, err := c.player(args[0])
	if err != nil {
		return "", err
	}
	limit, err := optionalRows(args, 1)
	if err != nil {
		return "", err
	}
	events, err := loadActivity(c.ctx, c.db, userID)
	if err != nil {
		return "", err
	}
	rows := [][]string{{"ВРЕМЯ", "СОБЫТИЕ", "ПАРАМЕТРЫ"}}
	for _, event := range events[:min(limit, len(events))] {
		rows = append(rows, []string{formatGameTime(event.T), event.Kind, formatParams(event.Params)})
	}
	return table(rows), nil
}

func formatParams(params map[string]any) string {
	keys := make([]string, 0, len(params))
	for key := range params {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		parts = append(parts, fmt.Sprintf("%s=%v", key, params[key]))
	}
	return strings.Join(parts, " ")
}

func consoleOffices(c *consoleCall, _ []string) (string, error) {
	offices, err := listOffices(c.ctx, c.nk)
	if err != nil {
		return "", err
	}
	rows := [][]string{{"ID", "НАЗВАНИЕ", "ГОРОД", "СЕТИ", "ЧАСЫ ЗАДАНИЙ", "ПАУЗА", "ИГРА/ОТДЫХ"}}
	for i := range offices {
		office := &offices[i]
		limits := office.limits()
		networks := strings.Join(office.Networks, ",")
		if networks == "" {
			networks = "не проверяется"
		}
		rows = append(rows, []string{
			office.ID, office.Name, office.City, networks,
			limits.TaskWindowStart + "–" + limits.TaskWindowEnd,
			fmt.Sprintf("%d мин", limits.TaskCooldownMinutes),
			fmt.Sprintf("%d/%d мин", limits.PlayLimitMinutes, limits.RestMinutes),
		})
	}
	return table(rows), nil
}

func consoleDepartments(c *consoleCall, _ []string) (string, error) {
	departments, err := listDepartments(c.ctx, c.nk)
	if err != nil {
		return "", err
	}
	rows := [][]string{{"ID", "ОФИС", "НАЗВАНИЕ"}}
	for _, department := range departments {
		rows = append(rows, []string{department.ID, department.OfficeID, department.Name})
	}
	return table(rows), nil
}

func consoleTaskList(_ *consoleCall, _ []string) (string, error) {
	rows := [][]string{{"ID", "КОМНАТА", "МИНИ-ИГРА", "НАГРАДА", "НАЗВАНИЕ"}}
	for _, task := range gameContent.Tasks {
		title := task.Title
		if task.Hidden {
			title += " (скрыто)"
		}
		rows = append(rows, []string{task.ID, task.Room, task.Minigame, strconv.Itoa(task.Reward), title})
	}
	return table(rows), nil
}

func consoleItems(_ *consoleCall, _ []string) (string, error) {
	rows := [][]string{{"ID", "РЕДКОСТЬ", "ЦЕНА", "НАЗВАНИЕ"}}
	for _, item := range gameContent.Catalog {
		rows = append(rows, []string{item.ID, item.Rarity, strconv.Itoa(item.Price), item.Name})
	}
	return table(rows), nil
}

func consoleStock(c *consoleCall, _ []string) (string, error) {
	loaded, week, err := adminStock(c.ctx, c.nk)
	if err != nil {
		return "", err
	}
	counts, _, err := loadRewardCounts(c.ctx, c.db, week)
	if err != nil {
		return "", err
	}
	rows := [][]string{{"ID", "В НЕДЕЛЮ", "ОСТАЛОСЬ"}}
	for _, view := range stockViews(&loaded.stock, counts) {
		weekly, left := "без лимита", "—"
		if view.WeeklyStock > 0 {
			weekly, left = strconv.Itoa(view.WeeklyStock), strconv.Itoa(view.Left)
		}
		rows = append(rows, []string{view.ID, weekly, left})
	}
	return table(rows), nil
}

func consoleRaffle(c *consoleCall, args []string) (string, error) {
	return c.inspect(args[0], func(tx *gameTx) (string, error) {
		loaded, err := tx.currentDraw()
		if err != nil {
			return "", err
		}
		draw := &loaded.draw
		winner := "—"
		if draw.Drawn {
			winner = draw.Winner
			if players, err := readPlayers(tx.ctx, tx.nk, []string{draw.Winner}, tx.today); err == nil {
				if player, ok := players[draw.Winner]; ok {
					winner = player.name
				}
			}
		}
		return table([][]string{
			{"Розыгрыш", draw.ID},
			{"Офис", tx.me.metadata.homeOffice()},
			{"Время розыгрыша", formatGameTime(draw.DrawAt)},
			{"Билетов", strconv.Itoa(len(draw.Tickets))},
			{"Разыгран", yesNo(draw.Drawn)},
			{"Победитель", winner},
		}), nil
	})
}
