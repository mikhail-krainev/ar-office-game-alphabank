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
	if !loungeTeamsAllowed("memory") || !loungeTeamsAllowed("bug_hunt") {
		t.Fatal("missing team games")
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
	r.resolveBlackjack(100)
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
	r.resolveBlackjack(100)
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
