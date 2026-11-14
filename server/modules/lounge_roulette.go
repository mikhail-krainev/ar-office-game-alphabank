package main

func (r *loungeRoom) activeCount() int {
	n := 0
	for _, p := range r.Players {
		if !p.Departed {
			n++
		}
	}
	return n
}

// Delayed reads apply each expired phase against its original deadline, so leaving the page does
// not extend the lifetime of a placed bet. The payout remains part of the room's atomic commit.
func (r *loungeRoom) advanceRoulette(now int64) {
	for step := 0; step < 3 && now >= r.Deadline; step++ {
		switch r.Phase {
		case "betting":
			if r.activeCount() == 0 && len(r.Bets) == 0 {
				r.Players = []loungePlayer{}
				r.finish(nil)
				return
			}
			r.Result = seededRand(randomKey()).IntN(37)
			r.Phase = "spinning"
			r.Deadline += 8
		case "spinning":
			r.Gains = map[string]int64{}
			for _, b := range r.Bets {
				id := r.Players[b.Player].ID
				paid := b.Amount * rouletteMultiplier(b.Field, r.Result)
				r.pay(id, paid)
				r.Gains[id] += paid - b.Amount
			}
			r.History = append([]int{r.Result}, r.History...)
			if len(r.History) > 20 {
				r.History = r.History[:20]
			}
			r.Phase = "result"
			r.Deadline += 7
		case "result":
			players := []loungePlayer{}
			for _, p := range r.Players {
				if !p.Departed {
					players = append(players, p)
				}
			}
			r.Players = players
			r.Bets = nil
			r.Awards = nil
			if len(players) == 0 {
				r.finish(nil)
				return
			}
			r.Host = players[0].ID
			r.Round++
			r.Phase = "betting"
			r.Deadline = now + 20
			return
		default:
			return
		}
	}
}
