package main

import (
	"strings"
	"sync"
	"time"
)

// Time zones of the offices. Every office keeps its own IANA zone ("Asia/Yekaterinburg"); days,
// streaks, fines, task hours and the raffle of a player follow the zone of the office the player
// counts in today. An office without a zone uses the zone of game_rules.json (office.timezone, or the
// fixed office.utc_offset_minutes when the name is empty). The zones are cached in memory: every read
// or write of an office refreshes its entry, and the module start warms the cache.

const maxTimezoneLength = 64

var officeZones sync.Map // office id -> *time.Location

// loadZone: the location of an IANA zone name; false for an unknown name.
func loadZone(name string) (*time.Location, bool) {
	if name == "" || len(name) > maxTimezoneLength || strings.Contains(name, "..") || name == "Local" {
		return nil, false
	}
	location, err := time.LoadLocation(name)
	if err != nil {
		return nil, false
	}
	return location, true
}

// defaultZone: the zone of game_rules.json.
func defaultZone() *time.Location {
	if gameContent == nil {
		return time.UTC
	}
	if location, ok := loadZone(gameContent.Rules.Office.Timezone); ok {
		return location
	}
	return time.FixedZone("office", gameContent.Rules.Office.UTCOffsetMinutes*60)
}

// rememberOfficeZone caches the zone of an office; an empty or unknown name means the default zone.
func rememberOfficeZone(officeID, timezone string) {
	if location, ok := loadZone(timezone); ok {
		officeZones.Store(officeID, location)
		return
	}
	officeZones.Delete(officeID)
}

func officeZone(officeID string) *time.Location {
	if location, ok := officeZones.Load(officeID); ok {
		return location.(*time.Location)
	}
	return defaultZone()
}

// zoneOffset: seconds east of UTC in `location` at `unix`.
func zoneOffset(location *time.Location, unix int64) int64 {
	_, offset := time.Unix(unix, 0).In(location).Zone()
	return int64(offset)
}

// officeOffsetAt: the UTC offset of the office at `unix`, in seconds.
func officeOffsetAt(officeID string, unix int64) int64 {
	return zoneOffset(officeZone(officeID), unix)
}

// defaultOfficeOffset: the UTC offset of the default office at `unix`.
func defaultOfficeOffset(unix int64) int64 {
	return officeOffsetAt(defaultOfficeID(), unix)
}

// localDay: the player's day and UTC offset at `unix`. The day starts by the home office's zone; on a
// trip or a visit to an office in another zone the day and the offset follow that office.
func (m accountMetadata) localDay(unix int64) (int, int64) {
	offset := officeOffsetAt(m.homeOffice(), unix)
	day := dayOf(unix, offset)
	office, _ := m.placement(day)
	if office == m.homeOffice() {
		return day, offset
	}
	awayOffset := officeOffsetAt(office, unix)
	awayDay := dayOf(unix, awayOffset)
	// Near midnight the other zone may be on another day, where the trip or the visit (stored by day)
	// is not there: keep the home day then, so the day and the office always agree.
	if awayOffice, _ := m.placement(awayDay); awayOffice != office {
		return day, offset
	}
	return awayDay, awayOffset
}
