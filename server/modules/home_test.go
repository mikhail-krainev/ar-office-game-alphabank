package main

import "testing"

func TestHomeContentStartsWithAFreeStudio(t *testing.T) {
	content := testContent(t)
	home := &content.Home
	studio := home.apartment(starterApartment)
	if studio == nil || studio.Price != 0 {
		t.Fatal("the starter studio must exist and be free")
	}
	previous := 0
	for _, apartment := range home.Apartments {
		if apartment.Area <= previous {
			t.Errorf("%s: apartments go from the smallest to the biggest", apartment.ID)
		}
		previous = apartment.Area
	}
	if house := home.apartment("house240"); house == nil || house.Area != 240 {
		t.Error("the 240 m² house must be in the catalog")
	}
}

func TestApartmentBringsItsPalette(t *testing.T) {
	content := testContent(t)
	home := &content.Home
	state := HomeState{}
	state.normalize()
	if !ownsPalette(home, &state, home.palette("scandi")) {
		t.Error("the studio's design comes with the studio")
	}
	if ownsPalette(home, &state, home.palette("minimal")) {
		t.Error("the house's design is not owned without the house")
	}
	state.Apartments = append(state.Apartments, "house240")
	if !ownsPalette(home, &state, home.palette("minimal")) {
		t.Error("buying the house gives its design")
	}
	if !ownsPalette(home, &state, home.palette(originalPalette)) {
		t.Error("the original palette is free")
	}
}

func TestHomeDecorChecksOwnershipAndBounds(t *testing.T) {
	content := testContent(t)
	home := &content.Home
	studio := home.apartment(starterApartment)
	state := HomeState{}
	state.normalize()
	state.Items["plant_big"] = 1
	cases := map[string]ApartmentDecor{
		"":                  {Palette: "scandi", Placed: []PlacedItem{{Item: "plant_big", X: 3, Y: 4}}},
		"unknown_palette":   {Palette: "neon", Placed: []PlacedItem{}},
		"palette_not_owned": {Palette: "deco", Placed: []PlacedItem{}},
		"unknown_item":      {Palette: "scandi", Placed: []PlacedItem{{Item: "throne", X: 3, Y: 4}}},
		"item_not_owned":    {Palette: "scandi", Placed: []PlacedItem{{Item: "plant_big", X: 3, Y: 4}, {Item: "plant_big", X: 5, Y: 4}}},
		"out_of_bounds":     {Palette: "scandi", Placed: []PlacedItem{{Item: "plant_big", X: studio.Width, Y: 4}}},
		"duplicate_item":    {Palette: "original", Placed: []PlacedItem{{Item: "plant_big", X: 3, Y: 4}, {Item: "plant_big", X: 3, Y: 4}}},
	}
	state.Items["plant_big"] = 1
	for want, decor := range cases {
		if want == "duplicate_item" {
			state.Items["plant_big"] = 2
		}
		if got := homeDecorError(home, &state, studio, decor); got != want {
			t.Errorf("%v: got %q, want %q", decor, got, want)
		}
		state.Items["plant_big"] = 1
	}
}

func TestHomeItemStandsInOnePlaceAtATime(t *testing.T) {
	content := testContent(t)
	home := &content.Home
	state := HomeState{}
	state.normalize()
	state.Apartments = append(state.Apartments, "flat40")
	state.Items["aquarium"] = 1
	state.Decor["flat40"] = &ApartmentDecor{Palette: "japandi", Placed: []PlacedItem{{Item: "aquarium", X: 2, Y: 13}}}
	studio := home.apartment(starterApartment)
	decor := ApartmentDecor{Palette: "scandi", Placed: []PlacedItem{{Item: "aquarium", X: 3, Y: 4}}}
	if got := homeDecorError(home, &state, studio, decor); got != "item_not_owned" {
		t.Errorf("the only aquarium stands in the other apartment: got %q", got)
	}
	state.Items["aquarium"] = 2
	if got := homeDecorError(home, &state, studio, decor); got != "" {
		t.Errorf("a second aquarium may stand in the studio: got %q", got)
	}
}

func TestNewApartmentStartsWithItsDesign(t *testing.T) {
	content := testContent(t)
	state := HomeState{}
	state.normalize()
	decor := decorOf(&state, content.Home.apartment("loft120"))
	if decor.Palette != "miami" || len(decor.Placed) != 0 {
		t.Errorf("decor = %+v", decor)
	}
}
