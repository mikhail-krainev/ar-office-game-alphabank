package main

import (
	"encoding/json"
	"testing"
)

func TestTheOfficeNetworkFindsTheOffice(t *testing.T) {
	if office := officeByNetwork(testOffices, "10.20.40.7"); office == nil || office.ID != "office_msk" {
		t.Errorf("office = %+v", office)
	}
	// Saint Petersburg has no network: it does not catch every address.
	if office := officeByNetwork(testOffices, "198.51.100.8"); office != nil {
		t.Errorf("an address of no office network found %s", office.ID)
	}
}

func TestAnUnplannedTripMovesThePlayerForTheDay(t *testing.T) {
	metadata := accountMetadata{Role: rolePlayer, OfficeID: "hq", DepartmentID: "design"}
	followVisit(&metadata, "office_msk", monday)
	office, department := metadata.placement(monday)
	if office != "office_msk" || department != "design" {
		t.Errorf("placement in Moscow = %s, %s", office, department)
	}
	if metadata.guestOffice(monday) != "office_msk" || metadata.homeOffice() != "hq" {
		t.Errorf("guest = %q, home = %q", metadata.guestOffice(monday), metadata.homeOffice())
	}
	// The next day the player counts at home again until a network says otherwise.
	if office, _ := metadata.placement(monday + 1); office != "hq" || metadata.guestOffice(monday+1) != "" {
		t.Errorf("placement the next day = %s", office)
	}
	// Back in the home network the same day: the visit ends.
	followVisit(&metadata, "hq", monday)
	if metadata.Visit != nil {
		t.Errorf("visit = %+v", metadata.Visit)
	}
}

func TestTheNetworkWinsOverAPlannedTrip(t *testing.T) {
	metadata := accountMetadata{
		Role: rolePlayer, OfficeID: "hq", DepartmentID: "design",
		Trip: &Trip{OfficeID: "office_msk", DepartmentID: "dep_msk", Until: monday + 4},
	}
	followVisit(&metadata, "office_msk", monday)
	if metadata.Visit != nil {
		t.Error("the trip office is the planned one: no visit")
	}
	if office, department := metadata.placement(monday); office != "office_msk" || department != "dep_msk" {
		t.Errorf("placement on the trip = %s, %s", office, department)
	}
	// The trip was cut short: the player is back at home.
	followVisit(&metadata, "hq", monday+1)
	if office, department := metadata.placement(monday + 1); office != "hq" || department != "design" {
		t.Errorf("placement back home = %s, %s", office, department)
	}
}

func TestVisitRoundTrip(t *testing.T) {
	metadata := accountMetadata{Role: rolePlayer, OfficeID: "hq", Visit: &Visit{OfficeID: "office_msk", Day: monday}}
	data, err := json.Marshal(metadata.toMap())
	if err != nil {
		t.Fatal(err)
	}
	if parsed := parseMetadata(string(data)); parsed.Visit == nil || *parsed.Visit != *metadata.Visit {
		t.Errorf("parsed = %+v", parsed)
	}
}

func TestOfficeNetworksMustNotOverlap(t *testing.T) {
	cases := map[string]struct {
		networks []string
		except   string
		want     bool
	}{
		"inside Moscow":           {[]string{"10.20.40.128/25"}, "", true},
		"wider than Ekaterinburg": {[]string{"10.20.0.0/16"}, "", true},
		"a free network":          {[]string{"10.20.50.0/24"}, "", false},
		"Moscow itself":           {[]string{"10.20.40.0/24"}, "office_msk", false},
		"no network":              {[]string{}, "", false},
	}
	for name, c := range cases {
		if got := networksOverlap(testOffices, c.networks, c.except); got != c.want {
			t.Errorf("%s: overlap = %t, want %t", name, got, c.want)
		}
	}
}
