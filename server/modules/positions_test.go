package main

import "testing"

func TestMapPositionCountsOnlyTodayInTheSameOffice(t *testing.T) {
	position := mapPosition{Day: 10, Office: "hq", Room: "kitchen"}
	if room, ok := position.roomFor(10, "hq"); !ok || room != "kitchen" {
		t.Fatalf("today in hq: got %q %v", room, ok)
	}
	if _, ok := position.roomFor(11, "hq"); ok {
		t.Fatal("yesterday's position must not count")
	}
	if _, ok := position.roomFor(10, "office_2"); ok {
		t.Fatal("a position in another office must not count")
	}
	position.Room = "Bad Room!"
	if _, ok := position.roomFor(10, "hq"); ok {
		t.Fatal("an invalid room id must not count")
	}
}
