package main

import (
	"strings"
	"testing"
)

const (
	testCodeSecret = "test-secret-of-16+chars"
	testCodeUser   = "0b6e4c1e-5a0f-4c51-9d64-2f1e8a7b3c90"
)

func TestColleagueCodeRoundTrip(t *testing.T) {
	now := int64(1_790_000_005)
	code := colleagueCode(testCodeSecret, testCodeUser, colleagueCodeStep(now))
	userID, problem := verifyColleagueCode(testCodeSecret, code, now)
	if problem != "" || userID != testCodeUser {
		t.Fatalf("verify = %q, %q", userID, problem)
	}
	if !strings.HasPrefix(code, testCodeUser+".") || len(code) > 128 {
		t.Errorf("code %q must start with the user id and fit a QR payload", code)
	}
}

func TestColleagueCodeExpiresAfterTwoPeriods(t *testing.T) {
	issued := int64(1_790_000_000)
	code := colleagueCode(testCodeSecret, testCodeUser, colleagueCodeStep(issued))
	if _, problem := verifyColleagueCode(testCodeSecret, code, issued+colleagueCodePeriodSeconds+5); problem != "" {
		t.Errorf("the previous step must still count, got %q", problem)
	}
	if _, problem := verifyColleagueCode(testCodeSecret, code, issued+2*colleagueCodePeriodSeconds); problem != "colleague_code_expired" {
		t.Errorf("an old code must expire, got %q", problem)
	}
	future := colleagueCode(testCodeSecret, testCodeUser, colleagueCodeStep(issued)+1)
	if _, problem := verifyColleagueCode(testCodeSecret, future, issued); problem != "colleague_code_expired" {
		t.Errorf("a code from the future must not count, got %q", problem)
	}
}

func TestColleagueCodeRejectsForgery(t *testing.T) {
	now := int64(1_790_000_000)
	step := colleagueCodeStep(now)
	other := "1c2d3e4f-0000-4000-8000-000000000001"
	cases := map[string]string{
		"other secret":    colleagueCode("another-secret-16chars", testCodeUser, step),
		"swapped user":    strings.Replace(colleagueCode(testCodeSecret, testCodeUser, step), testCodeUser, other, 1),
		"office code":     presenceToken(testCodeSecret, purposeEntry, testCodeUser, step),
		"plain user id":   testCodeUser,
		"not a user id":   colleagueCode(testCodeSecret, "anna", step),
		"broken step":     testCodeUser + ".x.00",
		"empty signature": testCodeUser + "." + "1" + ".",
	}
	for name, code := range cases {
		if _, problem := verifyColleagueCode(testCodeSecret, code, now); problem != "colleague_invalid" {
			t.Errorf("%s: problem = %q, want colleague_invalid", name, problem)
		}
	}
}
