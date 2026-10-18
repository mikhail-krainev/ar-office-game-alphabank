package main

// Arrival by the office Wi-Fi. The entry code at the reception confirms the office day (reward,
// streak growth), but a player who came in and opened the game in the office Wi-Fi without
// scanning it must not lose the streak or be fined for that day. The first game request from the
// office network on a day without the entry code records the arrival time; such a day keeps the
// streak like an excused one and does not add to it. Until the code is scanned, the game reminds the
// player to scan it (needs_entry_code in the profile and the heartbeat).

const activityWifiArrival = "wifi_arrival"

// keptDays: workdays that do not break the streak although the player has no entry code for them:
// days the admin excused (an unban) and arrivals by the office Wi-Fi.
func (s *PlayerState) keptDays() map[string]bool {
	if len(s.WifiArrivals) == 0 {
		return s.ExcusedDays
	}
	kept := make(map[string]bool, len(s.ExcusedDays)+len(s.WifiArrivals))
	for key, on := range s.ExcusedDays {
		kept[key] = on
	}
	for key, at := range s.WifiArrivals {
		if at > 0 {
			kept[key] = true
		}
	}
	return kept
}

// noteWifiArrival records the first request from the office network today when the entry code of
// today's office is not scanned yet. The caller has checked the network.
func (tx *gameTx) noteWifiArrival() {
	key := dayKey(tx.today)
	state := tx.me.state
	if tx.checkedInToday() || state.WifiArrivals[key] > 0 {
		return
	}
	state.WifiArrivals[key] = tx.now
	tx.logActivity(tx.me, activityWifiArrival, map[string]any{"office": tx.office()})
}

// needsEntryCode: the player is in the office Wi-Fi today but has not scanned the entry code.
func (tx *gameTx) needsEntryCode() bool {
	return tx.me.state.WifiArrivals[dayKey(tx.today)] > 0 && !tx.checkedInToday()
}
