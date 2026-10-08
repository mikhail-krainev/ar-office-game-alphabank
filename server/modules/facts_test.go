package main

import (
	"strings"
	"testing"
)

func sampleFacts() []Fact {
	return []Fact{
		{Text: "Был в Антарктиде", True: false},
		{Text: "  Играю   на гитаре ", True: true},
		{Text: "Есть кот", True: true},
		{Text: "Прыгал с парашютом", True: false},
		{Text: "Люблю кофе", True: true},
	}
}

func TestNormalizeFactsTrimsAndKeepsAnswers(t *testing.T) {
	facts, problem := normalizeFacts(sampleFacts())
	if problem != "" {
		t.Fatalf("problem = %q", problem)
	}
	if facts[1].Text != "Играю на гитаре" || !facts[1].True {
		t.Errorf("fact 1 = %+v", facts[1])
	}
}

func TestNormalizeFactsRejectsWrongShape(t *testing.T) {
	long := strings.Repeat("я", maxFactLength+1)
	cases := map[string]func([]Fact) []Fact{
		"four facts":   func(f []Fact) []Fact { return f[:4] },
		"empty text":   func(f []Fact) []Fact { f[0].Text = "   "; return f },
		"four truths":  func(f []Fact) []Fact { f[0].True = true; return f },
		"two truths":   func(f []Fact) []Fact { f[1].True = false; return f },
		"control char": func(f []Fact) []Fact { f[2].Text = "кот\x07пёс"; return f },
		"too long":     func(f []Fact) []Fact { f[3].Text = long; return f },
	}
	for name, change := range cases {
		if _, problem := normalizeFacts(change(sampleFacts())); problem != "facts_invalid" {
			t.Errorf("%s: problem = %q, want facts_invalid", name, problem)
		}
	}
}

func TestScoreGuesses(t *testing.T) {
	facts := sampleFacts()
	correct, ok := scoreGuesses(facts, []bool{false, true, true, false, true})
	if !ok || correct != 5 {
		t.Errorf("all right: correct = %d, ok = %v", correct, ok)
	}
	// Swapping one truth and one lie gets two facts wrong.
	correct, ok = scoreGuesses(facts, []bool{true, false, true, false, true})
	if !ok || correct != 3 {
		t.Errorf("one swap: correct = %d, ok = %v", correct, ok)
	}
	if _, ok := scoreGuesses(facts, []bool{true, true, true, true, false}); ok {
		t.Error("a guess with four truths must be rejected")
	}
	if _, ok := scoreGuesses(facts, []bool{true, true, true}); ok {
		t.Error("a short guess must be rejected")
	}
}

func TestFactsScoreRewardsFooling(t *testing.T) {
	if factsScore(5) != 0 || factsScore(1) != 0.8 {
		t.Errorf("factsScore(5) = %v, factsScore(1) = %v", factsScore(5), factsScore(1))
	}
}
