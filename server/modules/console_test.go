package main

import (
	"errors"
	"reflect"
	"testing"
)

func TestSplitConsoleLine(t *testing.T) {
	cases := map[string][]string{
		"give_coins ivan 100":       {"give_coins", "ivan", "100"},
		"  find   \"Иван Петров\" ": {"find", "Иван Петров"},
		"help\tstatus":              {"help", "status"},
		`find ""`:                   {"find", ""},
	}
	for line, want := range cases {
		got, err := splitConsoleLine(line)
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Errorf("splitConsoleLine(%q) = %q, %v; want %q", line, got, err, want)
		}
	}
	for _, line := range []string{"", "   ", `find "open`} {
		var message consoleError
		if _, err := splitConsoleLine(line); !errors.As(err, &message) {
			t.Errorf("splitConsoleLine(%q) error = %v; want a console message", line, err)
		}
	}
}

func TestParseConsoleDuration(t *testing.T) {
	cases := map[string]int64{"0": 0, "90": 90, "45m": 2700, "12h": 43200, "3d": 3 * secondsPerDay, "1d12h": secondsPerDay + 43200, "1h30m15s": 5415}
	for text, want := range cases {
		if got, err := parseConsoleDuration(text); err != nil || got != want {
			t.Errorf("parseConsoleDuration(%q) = %d, %v; want %d", text, got, err, want)
		}
	}
	for _, text := range []string{"", "d", "3x", "12h5", "9999999d"} {
		if _, err := parseConsoleDuration(text); err == nil {
			t.Errorf("parseConsoleDuration(%q) accepted", text)
		}
	}
}

func TestConsoleCommandsAreUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, command := range consoleCommands {
		if seen[command.Name] || command.run == nil || command.Help == "" {
			t.Errorf("command %q: duplicate, no handler or no help", command.Name)
		}
		seen[command.Name] = true
	}
}

// Prod runs only the commands that show data: every command that changes the game is marked Dev.
func TestConsoleDevCommandsBlockedInProd(t *testing.T) {
	saved := devEnv
	defer func() { devEnv = saved }()
	devEnv = false
	for _, command := range consoleDevCommands() {
		if !command.Dev {
			t.Errorf("%s changes the game but is not marked Dev", command.Name)
		}
		call := &consoleCall{line: command.Name + " a b c"}
		if _, err := call.execute(); err != errConsoleDevOnly {
			t.Errorf("%s in prod: error %v; want console_dev_only", command.Name, err)
		}
	}
	for _, command := range consoleViewCommands() {
		if command.Dev {
			t.Errorf("%s only shows data but is marked Dev", command.Name)
		}
	}
}
