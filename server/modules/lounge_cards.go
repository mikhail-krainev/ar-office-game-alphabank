package main

import "strconv"

const blackjackDecisionSeconds = 60

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

// deal: a freshly shuffled deck every hand, two cards each. A hand of 21 needs no decision.
func (r *loungeRoom) deal(now int64) {
	r.Deck = r.shuffle(52)
	r.Dealer = nil
	r.Phase = "playing"
	// The room is saved with the next revision: decisions made against an older deal are refused.
	r.DealRevision = r.Revision + 1
	for i := range r.Players {
		p := &r.Players[i]
		p.Eliminated = false
		p.DecisionAt = now + blackjackDecisionSeconds
		p.Cards = []int{r.drawCard(), r.drawCard()}
		p.Done = cardTotal(p.Cards) == 21
	}
	if len(r.Players) == 1 {
		r.Dealer = []int{r.drawCard(), r.drawCard()}
	}
	r.blackjackContinue()
}

// acceptsStale: at 21 everyone decides at once, so another player's decision (a newer revision)
// must not cancel this one. Only a decision made before the current deal is refused.
func (r *loungeRoom) acceptsStale(a loungeAction) bool {
	return r.Game == "blackjack" && r.Phase == "playing" && (a.Action == "hit" || a.Action == "stand") && a.Revision >= r.DealRevision
}

func (r *loungeRoom) blackjackAction(p int, action string, now int64) string {
	if r.Phase != "playing" || r.Players[p].Done || r.Players[p].Eliminated {
		return "turn_finished"
	}
	switch action {
	case "hit":
		r.Players[p].Cards = append(r.Players[p].Cards, r.drawCard())
		r.Players[p].DecisionAt = now + blackjackDecisionSeconds
		if cardTotal(r.Players[p].Cards) >= 21 {
			r.Players[p].Done = true
		}
	case "stand":
		r.Players[p].Done = true
	default:
		return "invalid_action"
	}
	r.blackjackContinue()
	return ""
}

// blackjackContinue: settles the hand once nobody is left to decide, otherwise waits for the
// earliest personal deadline.
func (r *loungeRoom) blackjackContinue() {
	for _, p := range r.Players {
		if !p.Done {
			r.blackjackDeadline()
			return
		}
	}
	r.resolveBlackjack()
}

// blackjackRank orders hands: a bust is 0, a natural (21 on two cards) beats any other 21.
func blackjackRank(cards []int) int {
	total := cardTotal(cards)
	if total > 21 {
		return 0
	}
	if total == 21 && len(cards) == 2 {
		return 22
	}
	return total
}

func (r *loungeRoom) resolveBlackjack() {
	if len(r.Players) == 1 {
		r.resolveSoloBlackjack()
		return
	}
	best := 0
	winners := []int{}
	for i, p := range r.Players {
		rank := blackjackRank(p.Cards)
		if rank == 0 || rank < best {
			continue
		}
		if rank > best {
			best = rank
			winners = winners[:0]
		}
		winners = append(winners, i)
	}
	r.Outcomes = map[string]string{}
	// Nobody beat anybody: every stake goes back. The hand is settled once, without re-deals.
	if len(winners) == 0 || len(winners) == len(r.Players) {
		for _, p := range r.Players {
			r.Outcomes[p.ID] = "push"
		}
		r.Message = "Ничья. Ставки возвращены"
		if len(winners) == 0 {
			r.Message = "У всех перебор. Ставки возвращены"
		}
		r.finish(nil)
		return
	}
	for i, p := range r.Players {
		r.Outcomes[p.ID] = "lose"
		if containsInt(winners, i) {
			r.Outcomes[p.ID] = "win"
		}
	}
	if len(winners) > 1 {
		r.Message = "Равный результат. Фонд поделён"
	}
	r.finish(winners)
}

// resolveSoloBlackjack: the player against the dealer, who draws to 17 and stands on any 17.
func (r *loungeRoom) resolveSoloBlackjack() {
	r.Players[0].Ready = false
	p := r.Players[0]
	mine := cardTotal(p.Cards)
	natural := blackjackRank(p.Cards) == 22
	// As at a real table, the dealer does not draw against a bust or a natural.
	if mine <= 21 && !natural {
		for cardTotal(r.Dealer) < 17 {
			r.Dealer = append(r.Dealer, r.drawCard())
		}
	}
	dealer := cardTotal(r.Dealer)
	dealerNatural := blackjackRank(r.Dealer) == 22
	paid := int64(0)
	outcome := "lose"
	switch {
	case mine > 21:
		r.Message = "В этот раз удача у дилера"
	case natural && !dealerNatural:
		paid = r.Stake * 5 / 2
		outcome = "win"
		r.Message = "Блэкджек! Отличная раздача"
	case dealerNatural && !natural:
		r.Message = "Блэкджек у дилера"
	case mine == dealer:
		paid = r.Stake
		outcome = "push"
		r.Message = "Ровно. Ставка возвращается"
	case dealer > 21 || mine > dealer:
		paid = r.Stake * 2
		outcome = "win"
		r.Message = "Твоя победа! Ещё партию?"
	default:
		r.Message = "Сегодня карты на моей стороне"
	}
	r.Phase = "finished"
	r.Pot = 0
	r.Gains = map[string]int64{p.ID: paid - r.Stake}
	r.Outcomes = map[string]string{p.ID: outcome}
	r.pay(p.ID, paid)
	if outcome == "win" {
		r.Winners = []string{p.ID}
	}
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
	// A joint task has no extra rounds: every player's own catch counts for their task.
	if sides <= 1 || r.TieBreaks >= 2 || len(r.Players) == 1 || r.Task != "" {
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
