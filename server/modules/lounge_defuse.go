package main

import "fmt"

func (r *loungeRoom) startDefuse(now int64) {
	r.Progress = 0
	r.Errors = 0
	r.Heat = 0
	r.HeatAt = now
	r.Deadline = now + int64(120+r.Level*60)
	switch r.Level {
	case 2:
		r.Sequence = r.shuffle(8)[:4]
	case 3:
		r.Sequence = r.shuffle(8)[:6]
	case 5:
		r.Sequence = r.shuffle(24)[:7]
	default:
		r.Sequence = r.shuffle(8)[:r.Level+2]
	}
	if r.Training {
		r.Deadline = 0
	}
}
func (r *loungeRoom) defuseAction(p int, a loungeAction, now int64) string {
	if r.Phase != "playing" {
		return "round_not_started"
	}
	if p != (r.Level-1)%3 {
		return "wrong_role"
	}
	if a.Action == "hint" {
		if !r.Training {
			r.Deadline -= 20
		}
		// A hint identifies a category, not the next answer: the silent instructor remains necessary.
		r.Message = "Инструктор: покажи следующий символ по частям, связной повторяет его оператору"
		return ""
	}
	if a.Action == "cool" && r.Level >= 4 {
		r.Heat = max(0, r.Heat-35)
		if !r.Training {
			r.Deadline -= 5
		}
		r.Message = "Охлаждение: −35 температуры, −5 секунд"
		return ""
	}
	if a.Action != "defuse" || a.Index < 0 || a.Index > 7 {
		return "invalid_action"
	}
	answer := a.Index
	if r.Level == 2 {
		if a.To != r.Progress {
			return "wrong_channel"
		}
	} // Channels must be restored in order.
	if r.Level == 5 {
		if a.To < 0 || a.To > 2 {
			return "invalid_node"
		}
		answer = a.To*8 + a.Index
	}
	if answer != r.Sequence[r.Progress] {
		r.Errors++
		r.Message = "Неверное соединение"
		if r.Level >= 4 {
			r.Heat += 20
		}
		if r.Errors >= 3 && !r.Training {
			r.finish(nil)
		}
		return ""
	}
	r.Progress++
	r.Message = fmt.Sprintf("Восстановлено модулей: %d", r.Progress)
	if r.Level >= 4 {
		r.Heat += 22
	}
	if r.Heat >= 100 && !r.Training {
		r.Message = "Система перегрелась"
		r.finish(nil)
	} else if r.Progress == len(r.Sequence) {
		if !r.Training {
			r.Pot = 150
		}
		r.Message = "Система восстановлена"
		r.finish([]int{0, 1, 2})
	}
	return ""
}
