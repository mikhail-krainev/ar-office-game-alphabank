package main

import "testing"

func TestVisitsOfDayCloseSilentVisitAtLastHeartbeat(t *testing.T) {
	state := &PlayerState{}
	state.normalize()
	const away = 15 * 60
	startVisit(state, monday, 1000)
	visit := openVisit(state, monday)
	visit.Seen = 2000

	visits := visitsOfDay(state, monday, monday, 2000+away, away)
	if len(visits) != 1 || !visits[0].open() {
		t.Errorf("a visit with a fresh heartbeat must stay open: %+v", visits)
	}
	visits = visitsOfDay(state, monday, monday, 2001+away, away)
	if visits[0].Out != 2000 || visits[0].How != visitOutAway {
		t.Errorf("a silent visit must end at its last heartbeat: %+v", visits)
	}
	if !openVisit(state, monday).open() {
		t.Error("the admin view must not change the state")
	}
	visits = visitsOfDay(state, monday, monday+1, 2001, away)
	if visits[0].Out != 2000 {
		t.Errorf("a visit left open ends with its day at the last heartbeat: %+v", visits)
	}
	expectInt(t, "left at the last heartbeat", leftAt(state, visits, monday), 2000)
}

func TestStartVisitClosesTheOpenOne(t *testing.T) {
	state := &PlayerState{}
	state.normalize()
	startVisit(state, monday, 1000)
	startVisit(state, monday, 3000)
	visits := state.Visits[dayKey(monday)]
	if len(visits) != 2 || visits[0].Out != 3000 || visits[0].How != visitOutOffice || !visits[1].open() {
		t.Errorf("visits = %+v", visits)
	}
	if openVisit(state, monday+1) != nil {
		t.Error("a visit belongs to its day only")
	}
}

func TestLeftAtPrefersTheExitCode(t *testing.T) {
	state := &PlayerState{}
	state.normalize()
	key := dayKey(monday)
	state.CheckinAt[key] = 1000
	visits := []OfficeVisit{{In: 1000, Seen: 2000, Out: 2000, How: visitOutNetwork}, {In: 3000, Seen: 4000}}
	expectInt(t, "still in the office", leftAt(state, visits, monday), 0)
	state.CheckoutAt[key] = 5000
	expectInt(t, "exit code", leftAt(state, visits, monday), 5000)
}

func TestComeBackTodayAfterGoingHome(t *testing.T) {
	state := &PlayerState{}
	state.normalize()
	state.PresenceOffice = "hq"
	key := dayKey(monday)
	tx := &gameTx{me: &playerDoc{state: state, metadata: accountMetadata{Role: rolePlayer, OfficeID: "hq"}}, today: monday}

	if tx.comeBackToday() {
		t.Fatal("without an entry code today nobody comes back")
	}
	state.CheckinAt[key] = 1000
	if tx.comeBackToday() {
		t.Fatal("a player still in the office is not coming back")
	}
	state.CheckoutAt[key] = 2000 // "Go home"
	if inOffice(state, monday) {
		t.Fatal("after going home the player is out")
	}
	if !tx.comeBackToday() || !inOffice(state, monday) {
		t.Fatal("back in the office network the same day, the player is in again")
	}
	if state.CheckinAt[key] != 1000 {
		t.Error("the first arrival of the day must stay")
	}

	state.CheckoutAt[key] = 3000
	tx.today = monday + 1
	if tx.comeBackToday() {
		t.Error("the next day needs a new entry code")
	}
	tx.today = monday
	state.PresenceOffice = "office_2"
	if tx.comeBackToday() {
		t.Error("the network of another office does not bring the player back here")
	}
}
