package main

import (
	"encoding/json"
	"testing"
)

func TestLoungeModes(t *testing.T) {
	for _, game := range []string{"blackjack", "roulette", "defuse"} {
		if loungeTeamsAllowed(game) {
			t.Errorf("teams allowed in %s", game)
		}
	}
	if !loungeTeamsAllowed("memory") {
		t.Fatal("missing team games")
	}
	// The bug hunt is a joint daily task now, not an entertainment room (task_coop.go).
	if loungeGame("bug_hunt") || loungeTeamsAllowed("bug_hunt") || !coopGames["bug_hunt"] {
		t.Fatal("bug hunt must be a task game only")
	}
	if loungeCapacity("defuse", 6) != 3 || loungeCapacity("checkers", 4) != 4 {
		t.Fatal("wrong capacity")
	}
}

func TestBlackjackAces(t *testing.T) {
	for _, c := range []struct {
		cards []int
		want  int
	}{{[]int{0, 13, 8}, 21}, {[]int{0, 13, 26, 39}, 14}, {[]int{9, 10, 12}, 30}} {
		if got := cardTotal(c.cards); got != c.want {
			t.Errorf("%v = %d, want %d", c.cards, got, c.want)
		}
	}
}

func TestRoulettePayouts(t *testing.T) {
	if rouletteMultiplier("red", 0) != 0 || rouletteMultiplier("black", 0) != 0 || rouletteMultiplier("green", 0) != 36 {
		t.Fatal("zero payouts")
	}
	if rouletteMultiplier("red", 1) != 2 || rouletteMultiplier("black", 2) != 2 || rouletteMultiplier("n17", 17) != 36 {
		t.Fatal("wrong payout")
	}
}

func TestMemoryPairKeepsTurnAndHidesDeck(t *testing.T) {
	r := &loungeRoom{Game: "memory", Phase: "playing", Turn: 0, Deadline: 115, Memory: []int{2, 3, 2, 3}, Matched: map[int]bool{}, Players: []loungePlayer{{ID: "a"}, {ID: "b"}}}
	if e := r.act("a", loungeAction{Action: "flip", Index: 0}, 100); e != "" {
		t.Fatal(e)
	}
	v := r.view("a", 100)
	if _, ok := v["deck"]; ok {
		t.Fatal("private deck exposed")
	}
	if e := r.act("a", loungeAction{Action: "flip", Index: 2}, 101); e != "" {
		t.Fatal(e)
	}
	if r.Turn != 0 || r.Players[0].Score != 1 || len(r.Matched) != 2 {
		t.Fatal("pair must keep turn")
	}
}

func TestDefuseInstructionIsPrivate(t *testing.T) {
	r := &loungeRoom{Game: "defuse", Phase: "playing", Level: 1, Sequence: []int{2, 1, 3}, Players: []loungePlayer{{ID: "a"}, {ID: "b"}, {ID: "c"}}}
	if _, ok := r.view("a", 0)["instruction"]; ok {
		t.Fatal("operator sees instruction")
	}
	if _, ok := r.view("c", 0)["instruction"]; ok {
		t.Fatal("relay sees instruction")
	}
	if _, ok := r.view("b", 0)["instruction"]; !ok {
		t.Fatal("instructor missing instruction")
	}
	if e := r.act("b", loungeAction{Action: "defuse", Index: 2}, 0); e != "wrong_role" {
		t.Fatalf("instructor action: %s", e)
	}
}

func TestSquatHelpRewardHasNoPersonalCap(t *testing.T) {
	for _, reps := range []int{1, 30, 100, 500} {
		accepted, reward := squatHelpReward(reps, 2000, 0)
		if accepted != reps || reward != int64(reps*15) {
			t.Fatalf("%d reps: %d %d", reps, accepted, reward)
		}
	}
	n, pay := squatHelpReward(10, 100, 97)
	if n != 3 || pay != 45 {
		t.Fatal("reward must stop at department goal")
	}
}

func TestRouletteViewNeverLeaksFutureResult(t *testing.T) {
	r := &loungeRoom{Game: "roulette", Phase: "betting", Result: 17, Seed: 123, Players: []loungePlayer{{ID: "a"}}}
	for _, phase := range []string{"betting", "spinning"} {
		r.Phase = phase
		v := r.view("a", 0)
		for _, key := range []string{"result", "seed", "deck"} {
			if _, ok := v[key]; ok {
				t.Fatalf("%s leaks in %s", key, phase)
			}
		}
	}
}

func TestBlackjackWinnerGetsWholePotOnce(t *testing.T) {
	r := &loungeRoom{Game: "blackjack", Phase: "playing", Pot: 60, Stake: 20, Players: []loungePlayer{{ID: "a", Cards: []int{0, 9}, Done: true}, {ID: "b", Cards: []int{8, 9}, Done: true}, {ID: "c", Cards: []int{9, 10, 3}, Done: true}}}
	r.resolveBlackjack()
	if r.Phase != "finished" || r.Payouts["a"] != 60 || r.Pot != 0 {
		t.Fatalf("wrong settlement: %+v", r)
	}
	before := r.Payouts["a"]
	if r.advance(200) {
		t.Fatal("finished game advanced")
	}
	if r.Payouts["a"] != before {
		t.Fatal("double payout")
	}
	for _, p := range r.Players {
		if p.Ready {
			t.Fatal("rematch needs fresh consent")
		}
	}
}

func TestCheckersMandatoryCaptureAndFlyingKing(t *testing.T) {
	r := &loungeRoom{Game: "checkers", Capacity: 2, Phase: "playing", Players: []loungePlayer{{ID: "a"}, {ID: "b"}}}
	r.Board = make([]int, 64)
	r.Chain = -1
	r.Board[42] = 1
	r.Board[35] = 2
	r.Board[46] = 1
	r.Board[1] = 2
	if e := r.checkersAction(0, loungeAction{Action: "move", Index: 46, To: 37}, 100); e != "capture_required" {
		t.Fatalf("non capture allowed: %s", e)
	}
	if e := r.checkersAction(0, loungeAction{Action: "move", Index: 42, To: 28}, 100); e != "" {
		t.Fatal(e)
	}
	if r.Board[35] != 0 || r.Board[28] != 1 {
		t.Fatal("capture failed")
	}
	r.Board = make([]int, 64)
	r.Board[56] = 5
	r.Board[35] = 2
	if hit, ok := r.moveCapture(56, 14, 0); !ok || hit != 35 {
		t.Fatalf("flying king: %d %v", hit, ok)
	}
}

func TestFourPlayerCheckersStartsWithEightEach(t *testing.T) {
	r := &loungeRoom{Capacity: 4}
	r.initCheckers()
	counts := map[int]int{}
	for i, v := range r.Board {
		if v != 0 {
			if !r.cellOK(i) {
				t.Fatal("piece outside cross")
			}
			counts[v]++
		}
	}
	for i := 1; i <= 4; i++ {
		if counts[i] != 8 {
			t.Fatalf("side %d has %d", i, counts[i])
		}
	}
}

func TestTeamPrizeIsConserved(t *testing.T) {
	r := &loungeRoom{Pot: 101, Players: []loungePlayer{{ID: "a"}, {ID: "b"}, {ID: "c"}, {ID: "d"}}}
	r.finish([]int{0, 2})
	if r.Payouts["a"]+r.Payouts["c"] != 101 || absInt(int(r.Payouts["a"]-r.Payouts["c"])) != 1 {
		t.Fatal("incorrect team split")
	}
}

func TestPublicEmptyCollectionsAreArraysAndObjects(t *testing.T) {
	r := &loungeRoom{Game: "roulette", Phase: "betting"}
	raw, _ := json.Marshal(r.view("a", 0))
	var v map[string]any
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"bets", "history", "winners", "players"} {
		if _, ok := v[key].([]any); !ok {
			t.Fatalf("%s is not an array: %s", key, raw)
		}
	}
	if _, ok := v["gains"].(map[string]any); !ok {
		t.Fatalf("gains is not an object: %s", raw)
	}
}

func TestSoloBlackjackRequiresFreshRematchConsent(t *testing.T) {
	r := &loungeRoom{Game: "blackjack", Host: "a", Phase: "playing", Stake: 20, Pot: 20, Dealer: []int{9, 6}, Players: []loungePlayer{{ID: "a", Ready: true, Cards: []int{9, 7}, Done: true}}}
	r.resolveBlackjack()
	if r.Phase != "finished" {
		t.Fatal("not finished")
	}
	if problem := r.act("a", loungeAction{Action: "start"}, 101); problem != "not_ready" {
		t.Fatalf("rematch without consent: %s", problem)
	}
}

func TestRouletteSettlesAbsentPlayersAndReleasesSeats(t *testing.T) {
	r := &loungeRoom{Game: "roulette", Phase: "spinning", Deadline: 108, Result: 1, Players: []loungePlayer{{ID: "a"}, {ID: "b", Departed: true}}, Bets: []rouletteBet{{Player: 0, Field: "red", Amount: 10}, {Player: 1, Field: "black", Amount: 10}}}
	if !r.advance(200) {
		t.Fatal("expired spin not settled")
	}
	if r.Payouts["a"] != 20 || len(r.History) != 1 || r.Phase != "betting" || len(r.Players) != 1 || r.Players[0].ID != "a" {
		t.Fatalf("bad delayed settlement: %+v", r)
	}
	if r.advance(201) || r.Payouts["a"] != 20 {
		t.Fatal("repeated delayed payout")
	}
}

func TestDefuseLevelsHaveSolvableDistinctActions(t *testing.T) {
	for level := 1; level <= 5; level++ {
		r := &loungeRoom{Game: "defuse", Phase: "playing", Level: level, Training: true, Players: []loungePlayer{{ID: "a"}, {ID: "b"}, {ID: "c"}}}
		r.startDefuse(100)
		operator := (level - 1) % 3
		sequence := append([]int{}, r.Sequence...)
		for i, value := range sequence {
			to := 0
			index := value
			if level == 2 {
				to = i
			}
			if level == 5 {
				to = value / 8
				index = value % 8
			}
			if problem := r.defuseAction(operator, loungeAction{Action: "defuse", Index: index, To: to}, 101); problem != "" {
				t.Fatalf("level %d: %s", level, problem)
			}
		}
		if r.Phase != "finished" || r.Progress != len(sequence) {
			t.Fatalf("level %d not solved", level)
		}
		if r.Pot != 0 {
			t.Fatal("training must not mint a prize")
		}
	}
}

func TestReadyIsAnExplicitStateNotAToggle(t *testing.T) {
	r := &loungeRoom{Phase: "waiting", Players: []loungePlayer{{ID: "a"}}}
	for i := 0; i < 2; i++ {
		if problem := r.act("a", loungeAction{Action: "ready", Ready: true}, 100); problem != "" {
			t.Fatal(problem)
		}
	}
	if !r.Players[0].Ready {
		t.Fatal("repeated ready must not cancel consent")
	}
	if problem := r.act("a", loungeAction{Action: "ready", Ready: false}, 101); problem != "" {
		t.Fatal(problem)
	}
	if r.Players[0].Ready {
		t.Fatal("cannot withdraw consent")
	}
}

func TestBlackjackStakeChangesAtTable(t *testing.T) {
	r := &loungeRoom{Game: "blackjack", Host: "a", Phase: "waiting", Stake: 20, Players: []loungePlayer{{ID: "a", Ready: true}, {ID: "b", Ready: true}}}
	for _, amount := range []int64{40, 10, 0} {
		if problem := r.act("a", loungeAction{Action: "stake", Stake: amount}, 100); problem != "" {
			t.Fatalf("change stake: %s", problem)
		}
		if r.Stake != amount || r.Players[0].Ready || r.Players[1].Ready {
			t.Fatal("stake change must reset everyone's consent")
		}
	}
	for _, tc := range []struct {
		id, phase string
		amount    int64
		want      string
	}{
		{"b", "waiting", 20, "host_only"},
		{"a", "playing", 20, "round_started"},
		{"a", "waiting", 3, "even_stake_required"},
		{"a", "waiting", -2, "invalid_bet"},
		{"a", "waiting", 1000002, "invalid_bet"},
	} {
		r.Phase = tc.phase
		if got := r.act(tc.id, loungeAction{Action: "stake", Stake: tc.amount}, 100); got != tc.want {
			t.Errorf("%+v: got %q", tc, got)
		}
	}
	r.Phase = "finished"
	if got := r.act("a", loungeAction{Action: "stake", Stake: 30}, 101); got != "" || r.Stake != 30 {
		t.Fatal("next round stake must be adjustable")
	}
}

func TestBlackjackDecisionsDoNotCancelEachOther(t *testing.T) {
	r := &loungeRoom{Game: "blackjack", Phase: "playing", Revision: 7, DealRevision: 5, Players: []loungePlayer{{ID: "a", Cards: []int{1, 2}}, {ID: "b", Cards: []int{3, 4}}}}
	// Both players decided on revision 5; the first decision has already moved the room on.
	for _, action := range []string{"hit", "stand"} {
		if !r.acceptsStale(loungeAction{Action: action, Revision: 5}) {
			t.Fatalf("simultaneous %s refused", action)
		}
	}
	if r.acceptsStale(loungeAction{Action: "hit", Revision: 4}) {
		t.Fatal("a decision made before this deal must be refused")
	}
	if r.acceptsStale(loungeAction{Action: "start", Revision: 5}) {
		t.Fatal("only table decisions may skip the revision check")
	}
	if problem := r.act("a", loungeAction{Action: "pass"}, 100); problem != "invalid_action" {
		t.Fatalf("pass is not a decision any more: %q", problem)
	}
}

func TestBlackjackTieSplitsPotWithoutRedeal(t *testing.T) {
	r := &loungeRoom{Game: "blackjack", Phase: "playing", Round: 1, Pot: 60, Stake: 20, Players: []loungePlayer{{ID: "a", Cards: []int{9, 8}, Done: true}, {ID: "b", Cards: []int{22, 21}, Done: true}, {ID: "c", Cards: []int{9, 10, 3}, Done: true}}}
	r.resolveBlackjack()
	if r.Phase != "finished" || r.Round != 1 || r.Payouts["a"] != 30 || r.Payouts["b"] != 30 || r.Payouts["c"] != 0 {
		t.Fatalf("tie must split the pot at once: %+v", r)
	}
	if r.Outcomes["a"] != "win" || r.Outcomes["b"] != "win" || r.Outcomes["c"] != "lose" {
		t.Fatalf("wrong outcomes: %v", r.Outcomes)
	}
	if outcomes := r.view("c", 0)["outcomes"].(map[string]string); outcomes["a"] != "win" || outcomes["c"] != "lose" {
		t.Fatalf("every client must get the same outcomes: %v", outcomes)
	}
}

func TestBlackjackAllBustOrAllEqualReturnsStakes(t *testing.T) {
	for _, hands := range [][][]int{{{9, 10, 3}, {22, 23, 5}}, {{9, 8}, {22, 21}}} {
		r := &loungeRoom{Game: "blackjack", Phase: "playing", Pot: 40, Stake: 20, Players: []loungePlayer{{ID: "a", Cards: hands[0], Done: true}, {ID: "b", Cards: hands[1], Done: true}}}
		r.resolveBlackjack()
		if r.Phase != "finished" || r.Payouts["a"] != 20 || r.Payouts["b"] != 20 || r.Outcomes["a"] != "push" || r.Outcomes["b"] != "push" || len(r.Winners) != 0 {
			t.Fatalf("stakes must return: %+v", r)
		}
	}
}

func TestBlackjackNaturalBeatsLongTwentyOne(t *testing.T) {
	r := &loungeRoom{Game: "blackjack", Phase: "playing", Pot: 40, Stake: 20, Players: []loungePlayer{{ID: "a", Cards: []int{0, 9}, Done: true}, {ID: "b", Cards: []int{9, 4, 5}, Done: true}}}
	r.resolveBlackjack()
	if r.Payouts["a"] != 40 || r.Outcomes["b"] != "lose" {
		t.Fatalf("natural must win: %+v", r)
	}
}

func TestBlackjackDealNeverRepeatsACardAndSettlesFromThePot(t *testing.T) {
	for range 200 {
		r := &loungeRoom{Game: "blackjack", Host: "a", Phase: "waiting", Stake: 20, Players: []loungePlayer{{ID: "a", Ready: true}, {ID: "b", Ready: true}, {ID: "c", Ready: true}}}
		if problem := r.begin(100); problem != "" {
			t.Fatal(problem)
		}
		seen := map[int]bool{}
		for _, p := range r.Players {
			for _, c := range p.Cards {
				if c < 0 || c > 51 || seen[c] {
					t.Fatalf("bad card %d", c)
				}
				seen[c] = true
			}
			if p.Done != (cardTotal(p.Cards) == 21) {
				t.Fatal("only a dealt 21 needs no decision")
			}
		}
		for _, c := range r.Deck {
			if seen[c] {
				t.Fatalf("card %d is both dealt and in the deck", c)
			}
		}
		paid := int64(0)
		for _, amount := range r.Payouts {
			paid += amount
		}
		if r.Phase == "finished" && paid != 60 || r.Phase == "playing" && r.Pot != 60 {
			t.Fatalf("pot must exist from the deal: %+v", r)
		}
	}
}

// Chi-square goodness of fit: with 36 degrees of freedom a fair wheel exceeds 90 about once in
// several hundred million runs, while a biased or patterned one fails every time.
func TestRoulettePocketsAreUniform(t *testing.T) {
	const spins = 370000
	counts := make([]float64, 37)
	pairs := make([]float64, 37*37)
	previous := secureIntN(37)
	for range spins {
		pocket := secureIntN(37)
		counts[pocket]++
		pairs[previous*37+pocket]++
		previous = pocket
	}
	chi := 0.0
	for _, n := range counts {
		chi += (n - spins/37.0) * (n - spins/37.0) / (spins / 37.0)
	}
	if chi > 90 {
		t.Fatalf("pockets are not uniform: chi2=%.1f", chi)
	}
	// Consecutive spins must be independent: no pocket may predict the next one (1368 degrees of freedom).
	expected := float64(spins) / (37 * 37)
	chi = 0
	for _, n := range pairs {
		chi += (n - expected) * (n - expected) / expected
	}
	if chi > 1700 {
		t.Fatalf("consecutive spins are related: chi2=%.1f", chi)
	}
}

func TestRouletteDrawsResultOnlyAfterBetsClose(t *testing.T) {
	r := &loungeRoom{Game: "roulette", Phase: "betting", Deadline: 120, Result: -1, Players: []loungePlayer{{ID: "a"}}, Bets: []rouletteBet{{Player: 0, Field: "n5", Amount: 10}}}
	if r.advance(119) || r.Result != -1 {
		t.Fatal("no pocket may exist while bets are open")
	}
	if !r.advance(120) || r.Phase != "spinning" || r.Result < 0 || r.Result > 36 {
		t.Fatalf("bad spin: %+v", r)
	}
}

func TestShuffleReachesEveryPosition(t *testing.T) {
	r := &loungeRoom{}
	first := make([]int, 52)
	for range 5200 {
		deck := r.shuffle(52)
		seen := map[int]bool{}
		for _, c := range deck {
			seen[c] = true
		}
		if len(seen) != 52 {
			t.Fatal("deck is not a permutation")
		}
		first[deck[0]]++
	}
	for card, n := range first {
		if n < 40 || n > 180 {
			t.Fatalf("card %d on top %d times of 5200 (expected about 100)", card, n)
		}
	}
}
