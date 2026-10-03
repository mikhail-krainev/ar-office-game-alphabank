package main

import (
	"encoding/json"
	"testing"
)

func TestHomeOfficeOfOldAccounts(t *testing.T) {
	metadata := parseMetadata(`{"role":"player","department":"design"}`)
	if metadata.homeOffice() != defaultOfficeID() {
		t.Errorf("an account without an office must belong to the default office, got %q", metadata.homeOffice())
	}
	office, department := metadata.placement(monday)
	if office != defaultOfficeID() || department != "design" {
		t.Errorf("placement = %s, %s", office, department)
	}
}

func TestBusinessTripMovesThePlayerUntilItsLastDay(t *testing.T) {
	metadata := accountMetadata{
		Role: rolePlayer, OfficeID: "hq", DepartmentID: "design",
		Trip: &Trip{OfficeID: "office_msk", DepartmentID: "dep_msk", Until: monday + 2},
	}
	for day, want := range map[int]string{monday: "office_msk", monday + 2: "office_msk", monday + 3: "hq"} {
		if office, _ := metadata.placement(day); office != want {
			t.Errorf("office on day %d = %s, want %s", day-monday, office, want)
		}
	}
	if _, department := metadata.placement(monday); department != "dep_msk" {
		t.Errorf("department on the trip = %s", department)
	}
	if metadata.homeOffice() != "hq" {
		t.Error("the trip must not change the home office")
	}
	if tripOf(metadata, monday) == nil || tripOf(metadata, monday+3) != nil {
		t.Error("an ended trip must not be shown")
	}
	if until := tripOf(metadata, monday).Until; until != "2026-09-16" {
		t.Errorf("until = %s", until)
	}
}

func TestMetadataRoundTrip(t *testing.T) {
	metadata := accountMetadata{
		Role: rolePlayer, OfficeID: "hq", DepartmentID: "design",
		Trip: &Trip{OfficeID: "office_msk", DepartmentID: "dep_msk", Until: monday},
	}
	data, err := json.Marshal(metadata.toMap())
	if err != nil {
		t.Fatal(err)
	}
	parsed := parseMetadata(string(data))
	if parsed.OfficeID != "hq" || parsed.Trip == nil || *parsed.Trip != *metadata.Trip {
		t.Errorf("parsed = %+v", parsed)
	}
	if got := (accountMetadata{Role: rolePlayer, DepartmentID: "design"}).toMap(); got["trip"] != nil || got["office"] != nil {
		t.Errorf("empty fields must stay out of the metadata: %v", got)
	}
}

func TestTripDates(t *testing.T) {
	day, ok := parseTripDate("2026-09-16")
	if !ok || day != monday+2 {
		t.Errorf("parseTripDate = %d, %v", day, ok)
	}
	for _, text := range []string{"", "16.09.2026", "2026-13-01"} {
		if _, ok := parseTripDate(text); ok {
			t.Errorf("%q must be refused", text)
		}
	}
	if !validTripEnd(monday, monday) || validTripEnd(monday-1, monday) || validTripEnd(monday+maxTripDays+1, monday) {
		t.Error("a trip ends today or later, within a year")
	}
}

func TestPresenceCountsOnlyInTodaysOffice(t *testing.T) {
	state := &PlayerState{}
	state.normalize()
	state.CheckinAt[dayKey(monday)] = 100
	if presenceOffice(state) != defaultOfficeID() {
		t.Error("an entry made before offices existed belongs to the default office")
	}
	state.PresenceOffice = "office_msk"
	tx := &gameTx{me: &playerDoc{state: state, metadata: accountMetadata{Role: rolePlayer, OfficeID: "hq"}}, today: monday}
	if tx.inMyOffice() {
		t.Error("an entry in another office must not count in the home office")
	}
	tx.me.metadata.Trip = &Trip{OfficeID: "office_msk", DepartmentID: "dep_msk", Until: monday}
	if !tx.inMyOffice() {
		t.Error("on the trip the entry in the trip office counts")
	}
	if (presenceEntry{}).office() != defaultOfficeID() || (presenceEntry{Office: "office_msk"}).office() != "office_msk" {
		t.Error("presence entry office")
	}
}

func TestEntryCodesOfAnotherOfficeAreRefused(t *testing.T) {
	now := int64(1_800_000_000)
	token := presenceToken("secret-secret-secret", purposeEntry, "office_msk", presenceStep(now))
	if problem := verifyPresenceToken("secret-secret-secret", purposeEntry, "hq", token, now); problem != "presence_token_invalid" {
		t.Errorf("a code of another office = %q", problem)
	}
	if problem := verifyPresenceToken("secret-secret-secret", purposeEntry, "office_msk", token, now); problem != "" {
		t.Errorf("a code of the own office = %q", problem)
	}
}

func TestOfficeNetworksAndIDs(t *testing.T) {
	networks, err := normalizeNetworks([]string{" 203.0.113.0/24", "198.51.100.7"})
	if err != nil || len(networks) != 2 || networks[1] != "198.51.100.7/32" {
		t.Errorf("networks = %v, %v", networks, err)
	}
	for _, bad := range [][]string{{"office"}, {"10.0.0.0/8,10.1.0.0/16"}} {
		if _, err := normalizeNetworks(bad); err == nil {
			t.Errorf("%v must be refused", bad)
		}
	}
	office := Office{Networks: networks}
	if !inOfficeNetwork(office.prefixes(), "203.0.113.9") || inOfficeNetwork(office.prefixes(), "192.0.2.1") {
		t.Error("office network check")
	}
	id, err := newOfficeID()
	if err != nil || !officeIDPattern.MatchString(id) {
		t.Errorf("newOfficeID = %q, %v", id, err)
	}
	if officeIDPattern.MatchString("hq.1") {
		t.Error("an office id must not contain a dot: it is a part of the entry code")
	}
	if !officeNameTaken([]Office{{ID: "hq", Name: "Главный офис"}}, "главный ОФИС", "") {
		t.Error("case-insensitive duplicate office name")
	}
}

func TestOfficeLimits(t *testing.T) {
	if gameContent == nil {
		content, err := loadContent("../content")
		if err != nil {
			t.Fatal(err)
		}
		gameContent = content
		defer func() { gameContent = nil }()
	}
	var none *Office
	if none.limits() != gameContent.Rules.Limits {
		t.Error("a missing office follows the default limits")
	}
	own := gameContent.Rules.Limits
	own.RestMinutes++
	if (&Office{Limits: &own}).limits() != own {
		t.Error("an office follows its own limits")
	}
}
