package main

import (
	"testing"
	"time"
)

func TestGameNowFollowsTestClock(t *testing.T) {
	defer func() { testClock = false; clockShift.Store(0) }()
	clockShift.Store(3 * secondsPerDay)
	if shift := gameNow() - time.Now().Unix(); shift > 1 {
		t.Fatalf("without TEST_CLOCK the shift must be ignored, got %d s", shift)
	}
	testClock = true
	if shift := gameNow() - time.Now().Unix(); shift < 3*secondsPerDay-1 || shift > 3*secondsPerDay+1 {
		t.Fatalf("game time is %d s ahead, want 3 days", shift)
	}
}
