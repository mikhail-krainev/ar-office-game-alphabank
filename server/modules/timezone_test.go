package main

import (
	"testing"
	"time"
)

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

// The parking draw belongs to the home office: a colleague on a trip to another zone neither moves
// its day nor its hour. 22:00 in Yekaterinburg is 20:00 in Moscow.
func TestRaffleFollowsHomeOfficeZone(t *testing.T) {
	rememberOfficeZone("tz_ekb", "Asia/Yekaterinburg")
	rememberOfficeZone("tz_msk", "Europe/Moscow")
	defer officeZones.Delete("tz_ekb")
	defer officeZones.Delete("tz_msk")

	rules := &Rules{}
	rules.Raffle.DrawHour = 22
	// 2026-09-25, the last Friday of September, 12:30 UTC: 17:30 in Yekaterinburg. The September
	// draw is at 22:00 there, 17:00 UTC, which is 20:00 in Moscow.
	const noon int64 = 1790339400
	id, drawAt := officeRaffleSchedule("tz_ekb", noon, rules)
	if id != "parking-tz_ekb-2026-09" || drawAt != 1790355600 {
		t.Fatalf("September draw %s at %d", id, drawAt)
	}
	if ekb := time.Unix(drawAt, 0).In(officeZone("tz_ekb")); ekb.Hour() != 22 || ekb.Minute() != 0 {
		t.Fatalf("draw at %v in Yekaterinburg, want 22:00", ekb)
	}
	if msk := time.Unix(drawAt, 0).In(officeZone("tz_msk")); msk.Hour() != 20 || msk.Minute() != 0 {
		t.Fatalf("a colleague in Moscow sees the draw at %v, want 20:00", msk)
	}
	// 19:30 UTC: already Saturday 00:30 in Yekaterinburg, still Friday 22:30 in Moscow. The draw day
	// of the home office is over, so the October draw is current even for a colleague in Moscow.
	id, drawAt = officeRaffleSchedule("tz_ekb", noon+7*3600, rules)
	if ekb := time.Unix(drawAt, 0).In(officeZone("tz_ekb")); id != "parking-tz_ekb-2026-10" || ekb.Day() != 30 || ekb.Hour() != 22 {
		t.Fatalf("October draw %s at %v", id, ekb)
	}
}
