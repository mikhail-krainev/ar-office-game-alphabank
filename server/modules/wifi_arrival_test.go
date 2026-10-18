package main

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/png"
	"testing"
)

func TestWifiArrivalKeepsTheStreakWithoutGrowingIt(t *testing.T) {
	// Present Monday and Tuesday, Wednesday only in the office Wi-Fi without the entry code.
	state := &PlayerState{PresenceDays: days(0, 1), ExcusedDays: map[string]bool{}, WifiArrivals: map[string]int64{dayKey(monday + 2): 1}}
	kept := state.keptDays()
	expectInt(t, "streak on Thursday", int64(streak(state.PresenceDays, kept, monday+3, monday-30)), 2)
	expectInt(t, "missed on Wednesday", int64(missedInRow(state.PresenceDays, kept, monday+2, monday-30)), 0)
	// Without the Wi-Fi arrival Wednesday breaks the streak.
	expectInt(t, "streak without it", int64(streak(state.PresenceDays, state.ExcusedDays, monday+3, monday-30)), 0)
	if len(state.ExcusedDays) != 0 {
		t.Error("keptDays must not change the excused days the admin sees")
	}
}

func TestMoodDrawingMustBeASmallSquarePNG(t *testing.T) {
	encode := func(side int) string {
		var buffer bytes.Buffer
		_ = png.Encode(&buffer, image.NewRGBA(image.Rect(0, 0, side, side)))
		return base64.StdEncoding.EncodeToString(buffer.Bytes())
	}
	if _, problem := validMoodPNG(encode(moodSide)); problem != "" {
		t.Errorf("a valid drawing rejected: %s", problem)
	}
	for name, encoded := range map[string]string{"wrong size": encode(48), "empty": "", "garbage": "not base64!"} {
		if _, problem := validMoodPNG(encoded); problem != "mood_invalid" {
			t.Errorf("%s: problem = %q", name, problem)
		}
	}
}
