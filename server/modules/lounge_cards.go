package main

import "strconv"

func cardTotal(cards []int) int {
	total, aces := 0, 0
	for _, c := range cards {
		rank := c % 13
		if rank == 0 {
			total += 11
			aces++
		} else {
			total += min(rank+1, 10)
		}
	}
	for total > 21 && aces > 0 {
		total -= 10
		aces--
	}
	return total
}
func (r *loungeRoom) drawCard() int {
	if len(r.Deck) == 0 {
		r.Deck = r.shuffle(52)
	}
	c := r.Deck[0]
	r.Deck = r.Deck[1:]
	return c
}
func (r *loungeRoom) deal(eligible []int, now int64) {
	r.Deck = r.shuffle(52)
	r.Dealer = nil
	r.Deadline = now + 60
	r.Phase = "playing"
	for i := range r.Players {
		p := &r.Players[i]
		p.Cards = nil
		p.Done = false
		p.DecisionAt = now + 60
		if eligible != nil && !containsInt(eligible, i) {
			p.Eliminated = true
			p.Done = true
			continue
		}
		p.Eliminated = false
		p.Passed = false
		p.Cards = []int{r.drawCard(), r.drawCard()}
	}
	if len(r.Players) == 1 {
		r.Dealer = []int{r.drawCard(), r.drawCard()}
	}
}
func (r *loungeRoom) blackjackAction(p int, action string, now int64) string {
	if r.Phase != "playing" || r.Players[p].Done || r.Players[p].Eliminated {
		return "turn_finished"
	}
	switch action {
	case "hit":
		r.Players[p].Cards = append(r.Players[p].Cards, r.drawCard())
		r.Players[p].DecisionAt = now + 60
		r.blackjackDeadline()
		if cardTotal(r.Players[p].Cards) >= 21 {
			r.Players[p].Done = true
		}
	case "stand":
		r.Players[p].Done = true
	case "pass":
		r.Players[p].Done = true
		r.Players[p].Passed = true
	default:
		return "invalid_action"
	}
	for _, player := range r.Players {
		if !player.Done {
			r.blackjackDeadline()
			return ""
		}
	}
	r.resolveBlackjack(now)
	return ""
}
func (r *loungeRoom) resolveBlackjack(now int64) {
	if len(r.Players) == 1 {
		r.Players[0].Ready = false
		p := r.Players[0]
		for cardTotal(r.Dealer) < 17 {
			r.Dealer = append(r.Dealer, r.drawCard())
		}
		mine, dealer := cardTotal(p.Cards), cardTotal(r.Dealer)
		natural := len(p.Cards) == 2 && mine == 21
		dealerNatural := len(r.Dealer) == 2 && dealer == 21
		paid := int64(0)
		switch {
		case p.Passed || mine > 21:
			r.Message = "В этот раз удача у дилера"
		case natural && !dealerNatural:
			paid = r.Stake * 5 / 2
			r.Message = "Блэкджек! Отличная раздача"
		case dealerNatural && !natural:
			r.Message = "Блэкджек у дилера"
		case mine == dealer:
			paid = r.Stake
			r.Message = "Ровно. Ставка возвращается"
		case dealer > 21 || mine > dealer:
			paid = r.Stake * 2
			r.Message = "Твоя победа! Ещё партию?"
		default:
			r.Message = "Сегодня карты на моей стороне"
		}
		r.Phase = "finished"
		r.Pot = 0
		r.Gains = map[string]int64{p.ID: paid - r.Stake}
		r.pay(p.ID, paid)
		if paid > r.Stake {
			r.Winners = []string{p.ID}
		}
		return
	}
	best := -1
	w := []int{}
	active := []int{}
	for i, p := range r.Players {
		if p.Eliminated || p.Passed {
			continue
		}
		active = append(active, i)
		total := cardTotal(p.Cards)
		if total > 21 {
			continue
		}
		if total > best {
			best = total
			w = []int{i}
		} else if total == best {
			w = append(w, i)
		}
	}
	if len(active) == 0 {
		for _, p := range r.Players {
			r.pay(p.ID, r.Stake)
		}
		r.Pot = 0
		r.Phase = "finished"
		for i := range r.Players {
			r.Players[i].Ready = false
		}
		r.Message = "Все выбрали пас. Ставки возвращены"
		return
	}
	if len(w) == 1 {
		r.finish(w)
		return
	}
	r.Round++
	if len(w) == 0 {
		w = active
		r.Message = "У всех перебор. Новая раздача"
	} else {
		r.Message = "Равный результат. Дополнительная раздача"
	}
	r.deal(w, now)
}
func rouletteMultiplier(field string, sector int) int64 {
	if field == "green" {
		if sector == 0 {
			return 36
		}
		return 0
	}
	if field == "n"+strconv.Itoa(sector) {
		return 36
	}
	if sector == 0 {
		return 0
	}
	red := containsInt([]int{1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}, sector)
	if (field == "red" && red) || (field == "black" && !red) {
		return 2
	}
	return 0
}
func (r *loungeRoom) memoryAction(p int, a loungeAction, now int64) string {
	if r.Phase != "playing" || r.Turn != p || r.HideAt > 0 {
		return "not_your_turn"
	}
	if a.Action != "flip" || a.Index < 0 || a.Index >= len(r.Memory) || r.Matched[a.Index] || containsInt(r.Open, a.Index) {
		return "invalid_card"
	}
	r.Open = append(r.Open, a.Index)
	if len(r.Open) == 1 {
		return ""
	}
	x, y := r.Open[0], r.Open[1]
	if r.Memory[x] == r.Memory[y] {
		r.Matched[x] = true
		r.Matched[y] = true
		r.Players[p].Score++
		r.Open = nil
		r.Deadline = now + 15
		if len(r.Matched) == len(r.Memory) {
			r.resolveScore(now)
		}
	} else {
		r.HideAt = now + 2
		r.Deadline = r.HideAt
	}
	return ""
}

// A tied competition receives a short additional round before a shared final payout.
func (r *loungeRoom) resolveScore(now int64) {
	winners := r.scoreWinners()
	sides := len(winners)
	if r.Teams {
		teams := map[int]bool{}
		for _, i := range winners {
			teams[r.Players[i].Team] = true
		}
		sides = len(teams)
	}
	if sides <= 1 || r.TieBreaks >= 2 || len(r.Players) == 1 {
		r.finish(winners)
		return
	}
	r.TieBreaks++
	r.Round++
	r.Message = "Ничья. Дополнительный раунд без новой ставки"
	for i := range r.Players {
		r.Players[i].Eliminated = !containsInt(winners, i)
		r.Players[i].Score = 0
	}
	r.Turn = winners[0]
	if r.Game == "memory" {
		r.Memory = r.shuffle(8)
		for i := range r.Memory {
			r.Memory[i] /= 2
		}
		r.Matched = map[int]bool{}
		r.Open = nil
		r.HideAt = 0
		r.Deadline = now + 15
	} else {
		r.Started = now
		r.Deadline = now + 30
		r.Seed++
		r.Caught = map[string]bool{}
	}
}

func (r *loungeRoom) blackjackDeadline() {
	r.Deadline = 0
	for _, p := range r.Players {
		if !p.Done && (r.Deadline == 0 || p.DecisionAt < r.Deadline) {
			r.Deadline = p.DecisionAt
		}
	}
}
