package main

import "fmt"

func (r *loungeRoom) boardSize() int {
	if r.Capacity == 4 {
		return 12
	}
	return 8
}
func (r *loungeRoom) cellOK(i int) bool {
	n := r.boardSize()
	if i < 0 || i >= n*n {
		return false
	}
	x, y := i%n, i/n
	return (x+y)%2 == 1 && (n == 8 || (x >= 4 && x < 8) || (y >= 4 && y < 8))
}
func (r *loungeRoom) initCheckers() {
	n := r.boardSize()
	r.Board = make([]int, n*n)
	r.Chain = -1
	r.Moves = 0
	r.QuietKings = 0
	r.Positions = map[string]int{}
	r.PortalEntry = map[int]int{}
	r.Power = map[int]string{}
	r.Bonuses = map[int]string{}
	r.Blocked = map[int]int{}
	for i := range r.Board {
		if !r.cellOK(i) {
			continue
		}
		x, y := i%n, i/n
		if n == 8 {
			if y < 3 {
				r.Board[i] = 2
			}
			if y >= 5 {
				r.Board[i] = 1
			}
		} else {
			switch {
			case y >= 8:
				r.Board[i] = 1
			case y < 4:
				r.Board[i] = 2
			case x < 4:
				r.Board[i] = 3
			case x >= 8:
				r.Board[i] = 4
			}
		}
	}
	r.Positions[fmt.Sprintf("0:%v", r.Board)] = 1
}
func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func pieceOwner(v int) int { return (v - 1) % 4 }
func (r *loungeRoom) moveCapture(from, to, p int) (int, bool) {
	if !r.cellOK(from) || !r.cellOK(to) || r.Board[from] == 0 || r.Board[to] != 0 || pieceOwner(r.Board[from]) != p || r.blocked(to) {
		return -1, false
	}
	n := r.boardSize()
	dx, dy := to%n-from%n, to/n-from/n
	if absInt(dx) != absInt(dy) || dx == 0 {
		return -1, false
	}
	king := r.Board[from] > 4
	distance := absInt(dx)
	if !king && distance > 2 {
		return -1, false
	}
	sx, sy := dx/distance, dy/distance
	hit := -1
	for step := 1; step < distance; step++ {
		i := (from/n+sy*step)*n + from%n + sx*step
		if !r.cellOK(i) || r.blocked(i) || containsInt(r.Captured, i) {
			return -1, false
		}
		v := r.Board[i]
		if v == 0 {
			continue
		}
		if pieceOwner(v) == p || hit >= 0 {
			return -1, false
		}
		hit = i
	}
	if hit >= 0 {
		if !king && distance != 2 {
			return -1, false
		}
		return hit, true
	}
	if !king {
		if distance != 1 {
			return -1, false
		}
		if p == 0 && dy != -1 || p == 1 && dy != 1 || p == 2 && dx != 1 || p == 3 && dx != -1 {
			return -1, false
		}
	}
	return -1, true
}
func (r *loungeRoom) blocked(i int) bool { return r.Blocked[i] > r.Moves }
func (r *loungeRoom) captureAvailable(p, only int) bool {
	for from, v := range r.Board {
		if v == 0 || pieceOwner(v) != p || only >= 0 && from != only {
			continue
		}
		for to := range r.Board {
			hit, ok := r.moveCapture(from, to, p)
			if ok && hit >= 0 {
				return true
			}
		}
	}
	return false
}
func (r *loungeRoom) anyMove(p int) bool {
	for from, v := range r.Board {
		if v == 0 || pieceOwner(v) != p {
			continue
		}
		for to := range r.Board {
			if _, ok := r.moveCapture(from, to, p); ok {
				return true
			}
		}
	}
	return false
}
func (r *loungeRoom) clearEliminated() {
	for i, v := range r.Board {
		if v > 0 && r.Players[pieceOwner(v)].Eliminated {
			r.Board[i] = 0
		}
	}
}
func (r *loungeRoom) finishCheckers() {
	w := []int{}
	for i := range r.Players {
		if !r.Players[i].Eliminated && !r.anyMove(i) {
			r.Players[i].Eliminated = true
		}
		if !r.Players[i].Eliminated {
			w = append(w, i)
		}
	}
	r.clearEliminated()
	if len(w) <= 1 {
		r.finish(w)
	}
}
func (r *loungeRoom) checkersAction(p int, a loungeAction, now int64) string {
	if r.Phase != "playing" || r.Turn != p {
		return "not_your_turn"
	}
	if a.Action == "power" {
		if r.Capacity != 4 || r.Chain >= 0 || r.captureAvailable(p, -1) {
			return "capture_required"
		}
		power := r.Power[p]
		if power == "barrier" {
			if !r.cellOK(a.To) || r.Board[a.To] != 0 || r.blocked(a.To) {
				return "invalid_move"
			}
			r.Blocked[a.To] = r.Moves + len(r.Players) + 1
		} else if power == "portal" {
			if !r.cellOK(a.Index) || !r.cellOK(a.To) || r.Board[a.Index] == 0 || pieceOwner(r.Board[a.Index]) != p || r.Board[a.To] != 0 || r.blocked(a.To) || r.Bonuses[a.To] != "portal" || r.PortalEntry[p] != a.Index {
				return "invalid_move"
			}
			r.Board[a.To] = r.Board[a.Index]
			r.Board[a.Index] = 0
		} else {
			return "no_power"
		}
		delete(r.Power, p)
		delete(r.PortalEntry, p)
		r.endCheckersTurn(now)
		return ""
	}
	if a.Action != "move" || r.Chain >= 0 && a.Index != r.Chain {
		return "invalid_move"
	}
	hit, ok := r.moveCapture(a.Index, a.To, p)
	if !ok {
		return "invalid_move"
	}
	if hit < 0 && r.captureAvailable(p, -1) {
		return "capture_required"
	}
	if r.Chain < 0 {
		r.TurnIrreversible = r.Board[a.Index] <= 4
	}
	if hit >= 0 {
		r.TurnIrreversible = true
	}
	r.Board[a.To] = r.Board[a.Index]
	r.Board[a.Index] = 0
	if hit >= 0 {
		r.Captured = append(r.Captured, hit)
	}
	n := r.boardSize()
	x, y := a.To%n, a.To/n
	if r.Board[a.To] <= 4 && (p == 0 && y == 0 || p == 1 && y == n-1 || p == 2 && x == n-1 || p == 3 && x == 0) {
		r.Board[a.To] += 4
	}
	if power := r.Bonuses[a.To]; power != "" && r.Power[p] == "" {
		r.Power[p] = power
		if power == "portal" {
			r.PortalEntry[p] = a.To
		}
		delete(r.Bonuses, a.To)
	}
	if hit >= 0 && r.captureAvailable(p, a.To) {
		r.Chain = a.To
		r.Deadline = now + 60
		return ""
	}
	r.Chain = -1
	r.endCheckersTurn(now)
	return ""
}
func (r *loungeRoom) endCheckersTurn(now int64) {
	for _, i := range r.Captured {
		r.Board[i] = 0
	}
	r.Captured = nil
	r.Moves++
	if r.TurnIrreversible {
		r.QuietKings = 0
		r.Positions = map[string]int{}
	} else {
		r.QuietKings++
	}
	r.finishCheckers()
	if r.Phase == "finished" {
		return
	}
	r.nextTurn()
	if r.Capacity == 2 {
		key := fmt.Sprintf("%d:%v", r.Turn, r.Board)
		if r.Positions == nil {
			r.Positions = map[string]int{}
		}
		r.Positions[key]++
		if r.Positions[key] >= 3 || r.QuietKings >= 30 {
			r.Message = "Ничья: повтор позиции или 15 ходов только дамками без взятий"
			r.finish([]int{0, 1})
			return
		}
	}
	r.Deadline = now + 60
	if r.Capacity == 4 && r.Moves%4 == 0 {
		for i, end := range r.Blocked {
			if end <= r.Moves {
				delete(r.Blocked, i)
			}
		}
		candidates := []int{}
		for i, v := range r.Board {
			if r.cellOK(i) && v == 0 && !r.blocked(i) {
				candidates = append(candidates, i)
			}
		}
		if len(candidates) > 0 {
			idx := seededRand(randomKey()).IntN(len(candidates))
			power := "portal"
			if r.Moves%8 == 0 {
				power = "barrier"
			}
			r.Bonuses[candidates[idx]] = power
		}
	}
	if r.Capacity == 4 && r.Moves >= 200 {
		w := []int{}
		for i, p := range r.Players {
			if !p.Eliminated {
				w = append(w, i)
			}
		}
		r.Message = "Лимит ходов: ничья"
		r.finish(w)
	}
}
