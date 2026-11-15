package main

import "testing"

func TestCoopRoomID(t *testing.T) {
	id := coopRoomID("host", "bug_hunt", 100)
	if len(id) != 12 || id != coopRoomID("host", "bug_hunt", 100) {
		t.Fatalf("room id %q must be stable and 12 characters", id)
	}
	if id == coopRoomID("host", "bug_hunt", 101) || id == coopRoomID("other", "bug_hunt", 100) {
		t.Fatal("room id must differ per day and host")
	}
}

func TestCoopRoomFinishesWithoutTieBreak(t *testing.T) {
	room := &loungeRoom{Game: "bug_hunt", Task: "bug_hunt", Phase: "playing", Players: []loungePlayer{{ID: "a", Score: 3}, {ID: "b", Score: 3}}}
	room.resolveScore(0)
	if room.Phase != "finished" || room.TieBreaks != 0 {
		t.Fatalf("joint task room must finish on a tie, got phase %q, tie breaks %d", room.Phase, room.TieBreaks)
	}
	if room.Players[0].Score != 3 || room.Players[1].Score != 3 {
		t.Fatal("scores must stay for the task reward")
	}
}
