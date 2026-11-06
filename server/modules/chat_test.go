package main

import (
	"strings"
	"testing"
)

func TestCleanChatText(t *testing.T) {
	cases := map[string]string{
		"  привет  ":      "привет",
		"две\nстроки":     "две строки",
		"звонок\x07здесь": "звонокздесь",
	}
	for input, want := range cases {
		got, err := cleanChatText(input)
		if err != nil || got != want {
			t.Fatalf("cleanChatText(%q) = %q, %v; want %q", input, got, err, want)
		}
	}
	for _, input := range []string{"", "   \n ", strings.Repeat("я", chatMaxText+1)} {
		if _, err := cleanChatText(input); err != errChatText {
			t.Fatalf("cleanChatText(%q...) accepted", input[:min(len(input), 10)])
		}
	}
	if _, err := cleanChatText(strings.Repeat("я", chatMaxText)); err != nil {
		t.Fatal("a message of the maximum length refused")
	}
}
