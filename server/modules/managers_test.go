package main

import (
	"encoding/json"
	"errors"
	"testing"
)

var (
	testOffices = []Office{
		{ID: "hq", Name: "Екатеринбург", Networks: []string{"10.20.30.0/24"}},
		{ID: "office_msk", Name: "Москва", Networks: []string{"10.20.40.0/24"}},
		{ID: "office_spb", Name: "Санкт-Петербург", Networks: []string{}},
	}
	testDepartments = []Department{
		{ID: "design", Name: "Дизайн", OfficeID: "hq"},
		{ID: "hr", Name: "HR", OfficeID: "hq"},
		{ID: "dep_msk", Name: "Дизайн", OfficeID: "office_msk"},
		{ID: "dep_spb", Name: "HR", OfficeID: "office_spb"},
	}
)

func TestBuildScopeChecksAndCleansTheTicks(t *testing.T) {
	scope, err := buildScope(scopeRequest{
		Offices: []string{"office_msk", "office_msk"}, Departments: []string{"design", "design"}, CanDelete: true,
	}, testOffices, testDepartments)
	if err != nil {
		t.Fatal(err)
	}
	if len(scope.Offices) != 1 || len(scope.Departments) != 1 || scope.CanCreate || !scope.CanDelete {
		t.Errorf("scope = %+v", scope)
	}
	cases := map[string]struct {
		request scopeRequest
		want    error
	}{
		"empty":              {scopeRequest{}, errInvalidScope},
		"unknown office":     {scopeRequest{Offices: []string{"nowhere"}}, errOfficeNotFound},
		"unknown department": {scopeRequest{Departments: []string{"nothing"}}, errDepartmentNotFound},
		"too many":           {scopeRequest{Departments: make([]string, maxScopeDepartments+1)}, errInvalidScope},
	}
	for name, c := range cases {
		if _, err := buildScope(c.request, testOffices, testDepartments); !errors.Is(err, c.want) {
			t.Errorf("%s: err = %v, want %v", name, err, c.want)
		}
	}
}

func TestManagerScopeCoversWholeOfficesAndSingleDepartments(t *testing.T) {
	scope := ManagerScope{Offices: []string{"office_msk"}, Departments: []string{"design"}}
	for _, c := range []struct {
		office, department string
		want               bool
	}{
		{"office_msk", "dep_msk", true},
		// A department the admin creates later in a ticked office is covered too.
		{"office_msk", "dep_new", true},
		{"hq", "design", true},
		{"hq", "hr", false},
		{"office_spb", "dep_spb", false},
		{"hq", "", false},
	} {
		if got := scope.covers(c.office, c.department); got != c.want {
			t.Errorf("covers(%s, %s) = %t, want %t", c.office, c.department, got, c.want)
		}
	}
}

func TestManagerSeesOnlyTheScope(t *testing.T) {
	scope := ManagerScope{Departments: []string{"design"}}
	offices, departments := visibleOffices(scope, testOffices, testDepartments)
	if len(offices) != 1 || offices[0].ID != "hq" || len(departments) != 1 || departments[0].ID != "design" {
		t.Fatalf("offices = %+v, departments = %+v", offices, departments)
	}
	if len(offices[0].Networks) != 0 {
		t.Error("a manager must not see the office networks")
	}
	players := []playerSummary{
		{ID: "a", OfficeID: "hq", DepartmentID: "design"},
		{ID: "b", OfficeID: "hq", DepartmentID: "hr"},
		// On a trip to Moscow: the statistics follow the home office and department.
		{ID: "c", OfficeID: "hq", DepartmentID: "design", CurrentOfficeID: "office_msk"},
	}
	visible := playersInScope(scope, players)
	if len(visible) != 2 || visible[0].ID != "a" || visible[1].ID != "c" {
		t.Errorf("visible = %+v", visible)
	}
}

func TestManagerActsOnlyOnPlayersOfTheScope(t *testing.T) {
	scope := ManagerScope{Departments: []string{"design"}, CanDelete: true}
	cases := map[string]struct {
		metadata accountMetadata
		want     error
	}{
		"own player":           {accountMetadata{Role: rolePlayer, OfficeID: "hq", DepartmentID: "design"}, nil},
		"old account, no role": {accountMetadata{DepartmentID: "design"}, nil},
		"other department":     {accountMetadata{Role: rolePlayer, OfficeID: "hq", DepartmentID: "hr"}, errOutOfScope},
		"another manager":      {accountMetadata{Role: roleManager, Manager: &ManagerScope{}}, errUserNotFound},
		"the admin":            {accountMetadata{Role: roleAdmin}, errUserNotFound},
		"being deleted":        {accountMetadata{Role: roleRemoved, OfficeID: "hq", DepartmentID: "design"}, errUserNotFound},
	}
	for name, c := range cases {
		if err := requireCovered(scope, c.metadata); !errors.Is(err, c.want) {
			t.Errorf("%s: err = %v, want %v", name, err, c.want)
		}
	}
}

func TestOnlyPlayersCanBeChangedAsPlayers(t *testing.T) {
	change := asPlayer(func(metadata *accountMetadata) error {
		metadata.DepartmentID = "hr"
		return nil
	})
	player := accountMetadata{DepartmentID: "design"}
	if err := change(&player); err != nil || player.Role != rolePlayer || player.DepartmentID != "hr" {
		t.Errorf("player = %+v, err = %v", player, err)
	}
	for _, role := range []string{roleAdmin, roleManager} {
		metadata := accountMetadata{Role: role}
		if err := change(&metadata); !errors.Is(err, errAdminProtected) || metadata.DepartmentID != "" {
			t.Errorf("%s: err = %v, metadata = %+v", role, err, metadata)
		}
	}
	removed := accountMetadata{Role: roleRemoved}
	if err := change(&removed); !errors.Is(err, errUserNotFound) {
		t.Errorf("removed: err = %v", err)
	}
}

func TestManagerMetadataRoundTrip(t *testing.T) {
	metadata := accountMetadata{Role: roleManager, Manager: &ManagerScope{Offices: []string{"hq"}, CanCreate: true}}
	data, err := json.Marshal(metadata.toMap())
	if err != nil {
		t.Fatal(err)
	}
	parsed := parseMetadata(string(data))
	if parsed.Role != roleManager || parsed.Manager == nil || !parsed.Manager.CanCreate || parsed.Manager.CanDelete ||
		len(parsed.Manager.Offices) != 1 || parsed.Manager.Departments == nil {
		t.Errorf("parsed = %+v, scope = %+v", parsed, parsed.Manager)
	}
}

func TestManagerRpcsAreNotGameRpcs(t *testing.T) {
	for _, id := range []string{"manager_get_scope", "manager_delete_user", "admin_list_managers"} {
		if gameRpc(id) {
			t.Errorf("%s must work outside the office network", id)
		}
	}
}
