package main

import "testing"

func TestParseOfficeNetworks(t *testing.T) {
	networks, err := parseOfficeNetworks(" 203.0.113.0/24, 198.51.100.7 ,2001:db8:10::/48,")
	if err != nil {
		t.Fatal(err)
	}
	if len(networks) != 3 || networks[1].String() != "198.51.100.7/32" {
		t.Errorf("networks = %v", networks)
	}
	if networks, err := parseOfficeNetworks(""); err != nil || len(networks) != 0 {
		t.Errorf("empty value: %v, %v", networks, err)
	}
	for _, value := range []string{"office", "10.0.0.0/33", "10.0.0.300"} {
		if _, err := parseOfficeNetworks(value); err == nil {
			t.Errorf("%q must be refused", value)
		}
	}
}

func TestInOfficeNetwork(t *testing.T) {
	networks, err := parseOfficeNetworks("203.0.113.0/24,198.51.100.7,2001:db8:10::/48")
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string]bool{
		"203.0.113.45":        true,
		"::ffff:203.0.113.45": true,
		"198.51.100.7":        true,
		"198.51.100.8":        false,
		"2001:db8:10:5::1":    true,
		"2001:db8:11::1":      false,
		"10.20.30.10":        false,
		"":                    false,
		"not an address":      false,
		"203.0.113.45:54321":  false,
	}
	for ip, want := range cases {
		if got := inOfficeNetwork(networks, ip); got != want {
			t.Errorf("inOfficeNetwork(%q) = %v, want %v", ip, got, want)
		}
	}
	if !inOfficeNetwork(nil, "10.20.30.10") {
		t.Error("an empty list turns the check off")
	}
}

func TestGameRpcsNeedTheOfficeNetwork(t *testing.T) {
	for _, id := range []string{"login", "list_tasks", "complete_task", "play_heartbeat", "get_shop", "get_inbox"} {
		if !gameRpc(id) {
			t.Errorf("%s must need the office network", id)
		}
	}
	for _, id := range []string{"get_profile", "list_departments", "admin_list_users", "dev_skip_day", "get_notification_plan", "kiosk_codes"} {
		if gameRpc(id) {
			t.Errorf("%s must work from anywhere", id)
		}
	}
}
