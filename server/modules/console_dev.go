package main

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// Admin console commands that change the game; they run only with APP_ENV=dev (console.go).

const (
	consoleMaxCoins      = 1_000_000
	consoleMaxOfficeDays = 366
	consoleMaxSpins      = 100
)

func consoleDevCommands() []consoleCommand {
	commands := []consoleCommand{
		{Name: "give_coins", Args: "<логин> <N>", Help: "начислить N монет (через леджер)", minArgs: 2, run: consoleGiveCoins},
		{Name: "take_coins", Args: "<логин> <N>", Help: "списать N монет, баланс не уходит ниже нуля", minArgs: 2, run: consoleTakeCoins},
		{Name: "set_coins", Args: "<логин> <N>", Help: "поставить баланс ровно N", minArgs: 2, run: consoleSetCoins},
		{Name: "complete_task", Args: "<логин> <id задания>", Help: "засчитать задание сегодня с обычной наградой (id: tasks)", minArgs: 2, run: consoleCompleteTask},
		{Name: "reset_task", Args: "<логин> <id задания>", Help: "вернуть задание сегодня в «открыто»", minArgs: 2, run: consoleResetTask},
		{Name: "reset_day", Args: "<логин>", Help: "открыть все задания сегодня заново, сбросить паузу и заработок дня", minArgs: 1, run: consoleResetDay},
		{Name: "reset_cooldown", Args: "<логин>", Help: "убрать паузу до следующего задания", minArgs: 1, run: consoleResetCooldown},
		{Name: "task_limits", Args: "<логин> on|off", Help: "off — задания в любой час и без паузы между ними", minArgs: 2, run: consoleTaskLimits},
		{Name: "check_in", Args: "<логин>", Help: "отметить вход в офис без кода (засчитывает день)", minArgs: 1, run: consoleCheckIn},
		{Name: "check_out", Args: "<логин>", Help: "отметить выход из офиса", minArgs: 1, run: consoleCheckOut},
		{Name: "room", Args: "<логин> <id комнаты>", Help: "поставить игрока в комнату, как после скана эмблемы", minArgs: 2, run: consoleRoom},
		{Name: "office_days", Args: "<логин> <N>", Help: "отметить последние N дней в офисе (серия, розыгрыш)", minArgs: 2, run: consoleOfficeDays},
		{Name: "play_state", Args: "<логин> ok|warning|deferred|resting|blocked", Help: "состояние лимита игры прямо сейчас", minArgs: 2, run: consolePlayState},
		{Name: "wheel_spins", Args: "<логин> <N>", Help: "вернуть бесплатный спин колеса и дать N дополнительных", minArgs: 2, run: consoleWheelSpins},
		{Name: "give_item", Args: "<логин> <id награды>", Help: "выдать награду из каталога бесплатно (id: items)", minArgs: 2, run: consoleGiveItem},
		{Name: "set_stock", Args: "<id награды> <в неделю> [осталось]", Help: "запас награды; 0 в неделю — без лимита", minArgs: 2, run: consoleSetStock},
		{Name: "raffle_draw", Args: "<логин>", Help: "разыграть парковку домашнего офиса игрока сейчас", minArgs: 1, run: consoleRaffleDraw},
		{Name: "ban", Args: "<логин>", Help: "заблокировать игрока", minArgs: 1, run: consoleBan},
		{Name: "unban", Args: "<логин>", Help: "разблокировать игрока, дни блокировки не штрафуются", minArgs: 1, run: consoleUnban},
		{Name: "time_add", Args: "<длительность>", Help: "сдвинуть игровое время вперёд: 90, 45m, 12h, 3d, 1d12h", minArgs: 1, run: consoleTimeAdd},
		{Name: "time_set", Args: "<длительность>", Help: "поставить сдвиг игрового времени от реального", minArgs: 1, run: consoleTimeSet},
		{Name: "time_reset", Help: "вернуть реальное время", run: consoleTimeReset},
	}
	for i := range commands {
		commands[i].Dev = true
	}
	return commands
}

// --- Coins ----------------------------------------------------------------------------

func consoleGiveCoins(c *consoleCall, args []string) (string, error) {
	return c.moveCoins(args, 1)
}

func consoleTakeCoins(c *consoleCall, args []string) (string, error) {
	return c.moveCoins(args, -1)
}

func (c *consoleCall) moveCoins(args []string, sign int64) (string, error) {
	amount, err := parseConsoleInt(args[1], 1, consoleMaxCoins)
	if err != nil {
		return "", err
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		applied := tx.credit(tx.me, sign*amount, consoleLedgerReason, c.line)
		return fmt.Sprintf("%+d монет, баланс %d", applied, tx.me.balance), nil
	})
}

func consoleSetCoins(c *consoleCall, args []string) (string, error) {
	target, err := parseConsoleInt(args[1], 0, consoleMaxCoins)
	if err != nil {
		return "", err
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		applied := tx.credit(tx.me, target-tx.me.balance, consoleLedgerReason, c.line)
		return fmt.Sprintf("%+d монет, баланс %d", applied, tx.me.balance), nil
	})
}

// --- Tasks ----------------------------------------------------------------------------

func consoleTask(tx *gameTx, id string) (*Task, error) {
	task := tx.content.task(id)
	if task == nil {
		return nil, consoleErrorf("Нет задания %q (список: task_list)", id)
	}
	if !tx.isTodaysTask(task) {
		return nil, consoleErrorf("Задания %q нет в наборе игрока на сегодня (tasks <логин>)", id)
	}
	return task, nil
}

func consoleCompleteTask(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		task, err := consoleTask(tx, args[1])
		if err != nil {
			return "", err
		}
		if contains(dayList(tx.me.state.Completed, tx.today), task.ID) {
			return "", consoleError("Задание уже выполнено сегодня")
		}
		if task.Minigame == presenceMinigame {
			if err := tx.enterOffice(); err != nil {
				return "", err
			}
		}
		removeFromDay(tx.me.state.Skipped, tx.today, task.ID)
		reward := max(0, min(taskReward(task, tx.multiplier()), capLeft(tx.me.state, tx.today, &tx.content.Rules)))
		tx.grantTask(tx.me, task, tx.today, reward)
		return fmt.Sprintf("Задание %s выполнено: +%d монет, баланс %d", task.ID, reward, tx.me.balance), nil
	})
}

func consoleResetTask(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		task, err := consoleTask(tx, args[1])
		if err != nil {
			return "", err
		}
		state := tx.me.state
		for _, lists := range []map[string][]string{state.Completed, state.Skipped, state.Pending, state.Taken} {
			removeFromDay(lists, tx.today, task.ID)
		}
		if assignments := state.Assignments[dayKey(tx.today)]; assignments != nil {
			delete(assignments, task.ID)
		}
		return fmt.Sprintf("Задание %s снова открыто (монеты за него не списаны)", task.ID), nil
	})
}

func consoleResetDay(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		state := tx.me.state
		key := dayKey(tx.today)
		for _, lists := range []map[string][]string{state.Completed, state.Skipped, state.Pending, state.Taken, state.Met} {
			delete(lists, key)
		}
		delete(state.Assignments, key)
		delete(state.Earned, key)
		state.LastTaskAt = 0
		return "Задания дня открыты заново, пауза и заработок дня сброшены", nil
	})
}

func consoleResetCooldown(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		tx.me.state.LastTaskAt = 0
		return "Пауза между заданиями сброшена", nil
	})
}

func consoleTaskLimits(c *consoleCall, args []string) (string, error) {
	on, err := parseOnOff(args[1])
	if err != nil {
		return "", err
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		tx.me.state.DevNoTaskLimits = !on
		if on {
			return "Часы заданий и пауза снова действуют", nil
		}
		return "Задания засчитываются в любой час и без паузы", nil
	})
}

// --- Presence -------------------------------------------------------------------------

func consoleCheckIn(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		if inOffice(tx.me.state, tx.today) {
			return "", consoleError("Игрок уже в офисе")
		}
		if err := tx.enterOffice(); err != nil {
			return "", err
		}
		return "Вход в офис " + tx.office() + " отмечен", nil
	})
}

func consoleCheckOut(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		if !inOffice(tx.me.state, tx.today) {
			return "", consoleError("Игрок не в офисе")
		}
		if err := tx.leaveOffice(visitOutCode); err != nil {
			return "", err
		}
		return "Выход из офиса отмечен", nil
	})
}

func consoleRoom(c *consoleCall, args []string) (string, error) {
	room := strings.ToLower(args[1])
	if !roomIDPattern.MatchString(room) {
		return "", consoleErrorf("Неверный id комнаты %q", args[1])
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		if !inOffice(tx.me.state, tx.today) {
			return "", consoleError("Игрок не в офисе: сначала check_in")
		}
		tx.me.state.Room = room
		tx.logActivity(tx.me, activityRoom, map[string]any{"room": room})
		return "Игрок в комнате " + room, tx.writePresence(true, room)
	})
}

func consoleOfficeDays(c *consoleCall, args []string) (string, error) {
	days, err := parseConsoleInt(args[1], 1, consoleMaxOfficeDays)
	if err != nil {
		return "", err
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		state := tx.me.state
		for day := tx.today - int(days) + 1; day <= tx.today; day++ {
			state.PresenceDays[dayKey(day)] = true
			state.FirstDay = min(state.FirstDay, day)
		}
		state.BestStreak = max(state.BestStreak, streak(state.PresenceDays, state.keptDays(), tx.today, state.FirstDay))
		return fmt.Sprintf("Отмечено %d дн. в офисе", days), nil
	})
}

// --- Play limit, wheel, rewards, raffle ----------------------------------------------

func consolePlayState(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		status, err := tx.setPlayState(strings.ToLower(args[1]))
		if err == errInvalidPayload {
			return "", consoleErrorf("Состояние: ok, warning, deferred, resting или blocked, а не %q", args[1])
		}
		if err != nil {
			return "", err
		}
		return "Лимит игры: " + status.State, nil
	})
}

func consoleWheelSpins(c *consoleCall, args []string) (string, error) {
	extra, err := parseConsoleInt(args[1], 0, consoleMaxSpins)
	if err != nil {
		return "", err
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		tx.me.state.WheelDay = 0
		tx.me.state.WheelExtraSpins = int(extra)
		return fmt.Sprintf("Спинов колеса сегодня: %d", spinsLeft(tx.me.state, tx.today)), nil
	})
}

func consoleGiveItem(c *consoleCall, args []string) (string, error) {
	item := gameContent.catalogItem(args[1])
	if item == nil {
		return "", consoleErrorf("Нет награды %q (список: items)", args[1])
	}
	return c.change(args[0], func(tx *gameTx) (string, error) {
		result, err := tx.grantItem(item, consoleLedgerReason, 0)
		if err != nil {
			return "", err
		}
		text := fmt.Sprintf("Выдано: %s (%s)", item.Name, result.Status)
		if result.Voucher != "" {
			text += ", промокод " + result.Voucher
		}
		return text, nil
	})
}

func consoleSetStock(c *consoleCall, args []string) (string, error) {
	weekly, err := parseConsoleInt(args[1], 0, maxStock)
	if err != nil {
		return "", err
	}
	left := weekly
	if len(args) > 2 {
		if left, err = parseConsoleInt(args[2], 0, maxStock); err != nil {
			return "", err
		}
	}
	payload, _ := json.Marshal(map[string]any{"item_id": args[0], "weekly_stock": weekly, "left": left})
	if _, err := rpcAdminSetRewardStock(c.ctx, c.logger, c.db, c.nk, string(payload)); err != nil {
		if err == errInvalidPayload {
			return "", consoleErrorf("Нет награды %q (список: items)", args[0])
		}
		return "", err
	}
	if weekly == 0 {
		return args[0] + ": без лимита", nil
	}
	return fmt.Sprintf("%s: %d в неделю, осталось %d", args[0], weekly, left), nil
}

func consoleRaffleDraw(c *consoleCall, args []string) (string, error) {
	return c.change(args[0], func(tx *gameTx) (string, error) {
		loaded, err := tx.currentDraw()
		if err != nil {
			return "", err
		}
		if loaded.draw.Drawn {
			return "", consoleError("Этот розыгрыш уже разыгран")
		}
		if len(loaded.draw.Tickets) == 0 {
			return "", consoleError("В розыгрыше нет билетов")
		}
		loaded.draw.DrawAt = tx.now
		loaded.dirty = true
		if err := tx.runDueDraw(); err != nil {
			return "", err
		}
		return fmt.Sprintf("Розыгрыш %s: билетов %d, победитель %s", loaded.draw.ID, len(loaded.draw.Tickets), loaded.draw.Winner), nil
	})
}

// --- Account --------------------------------------------------------------------------

func consoleBan(c *consoleCall, args []string) (string, error) {
	userID, err := c.player(args[0])
	if err != nil {
		return "", err
	}
	if _, err := banPlayer(c.ctx, c.logger, c.db, c.nk, userID); err != nil {
		return "", err
	}
	return args[0] + " заблокирован", nil
}

func consoleUnban(c *consoleCall, args []string) (string, error) {
	userID, err := c.player(args[0])
	if err != nil {
		return "", err
	}
	if _, err := unbanPlayer(c.ctx, c.logger, c.db, c.nk, userID); err != nil {
		return "", err
	}
	return args[0] + " разблокирован", nil
}

// --- Time -------------------------------------------------------------------------------

func consoleTimeAdd(c *consoleCall, args []string) (string, error) {
	seconds, err := parseConsoleDuration(args[0])
	if err != nil {
		return "", err
	}
	return c.setClockShift(currentClockView().ShiftSeconds + seconds)
}

func consoleTimeSet(c *consoleCall, args []string) (string, error) {
	seconds, err := parseConsoleDuration(args[0])
	if err != nil {
		return "", err
	}
	return c.setClockShift(seconds)
}

func consoleTimeReset(c *consoleCall, _ []string) (string, error) {
	return c.setClockShift(0)
}

func (c *consoleCall) setClockShift(seconds int64) (string, error) {
	if seconds < 0 || seconds > maxClockShiftSeconds {
		return "", consoleErrorf("Сдвиг: от 0 до %s", formatSeconds(maxClockShiftSeconds))
	}
	payload := `{"shift_seconds":` + strconv.FormatInt(seconds, 10) + `}`
	if _, err := rpcAdminSetClock(c.ctx, c.logger, c.db, c.nk, payload); err != nil {
		return "", err
	}
	return consoleTime(c, nil)
}
