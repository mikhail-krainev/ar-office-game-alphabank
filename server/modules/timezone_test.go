package main

import "testing"

func TestOfficeZones(t *testing.T) {
	if _, ok := loadZone("Mars/Olympus"); ok {
		t.Fatal("unknown zone accepted")
	}
	if _, ok := loadZone("Local"); ok {
		t.Fatal("server-local zone accepted")
	}
	rememberOfficeZone("tz_ekb", "Asia/Yekaterinburg")
	rememberOfficeZone("tz_msk", "Europe/Moscow")
	defer officeZones.Delete("tz_ekb")
	defer officeZones.Delete("tz_msk")

	// 2026-03-02 20:30 UTC: already Tuesday in Yekaterinburg (UTC+5), still Monday 23:30 in Moscow.
	const unix int64 = 1772483400
	if got := officeOffsetAt("tz_ekb", unix); got != 5*3600 {
		t.Fatalf("Yekaterinburg offset %d", got)
	}
	if got := officeOffsetAt("tz_msk", unix); got != 3*3600 {
		t.Fatalf("Moscow offset %d", got)
	}

	home := accountMetadata{Role: rolePlayer, OfficeID: "tz_ekb"}
	ekbDay, _ := home.localDay(unix)
	if ekbDay != dayOf(unix, 5*3600) {
		t.Fatalf("home day %d", ekbDay)
	}
	tripper := accountMetadata{Role: rolePlayer, OfficeID: "tz_ekb", Trip: &Trip{OfficeID: "tz_msk", Until: ekbDay + 3}}
	day, offset := tripper.localDay(unix)
	if offset != 3*3600 || day != ekbDay-1 {
		t.Fatalf("trip day %d offset %d, want %d and Moscow offset", day, offset, ekbDay-1)
	}
}
