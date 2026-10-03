package main

import (
	"context"
	"testing"

	"github.com/heroiclabs/nakama-common/api"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestBeforeAuthenticateEmailForcesUsernameLoginWithoutCreation(t *testing.T) {
	in := &api.AuthenticateEmailRequest{
		Account:  &api.AccountEmail{Email: "someone@example.com", Password: "secret123"},
		Username: " Ivanov ",
		Create:   wrapperspb.Bool(true),
	}
	out, err := beforeAuthenticateEmail(context.Background(), nil, nil, nil, in)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.GetAccount().GetEmail() != "" {
		t.Errorf("email = %q, want empty (username login)", out.GetAccount().GetEmail())
	}
	if out.GetUsername() != "ivanov" {
		t.Errorf("username = %q, want %q", out.GetUsername(), "ivanov")
	}
	if out.GetCreate().GetValue() {
		t.Error("create = true, want false")
	}
	if out.GetAccount().GetPassword() != "secret123" {
		t.Error("password changed")
	}
}

func TestBeforeAuthenticateEmailRejectsMissingAccount(t *testing.T) {
	if _, err := beforeAuthenticateEmail(context.Background(), nil, nil, nil, &api.AuthenticateEmailRequest{}); err != errInvalidPayload {
		t.Errorf("error = %v, want errInvalidPayload", err)
	}
}

func TestBeforeUpdateAccountKeepsAdminFields(t *testing.T) {
	in := &api.UpdateAccountRequest{
		Username:    wrapperspb.String("hacker"),
		DisplayName: wrapperspb.String("Boss"),
		AvatarUrl:   wrapperspb.String("avatar"),
	}
	out, err := beforeUpdateAccount(context.Background(), nil, nil, nil, in)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.Username != nil || out.DisplayName != nil {
		t.Error("username or display name can still be changed by the player")
	}
	if out.GetAvatarUrl().GetValue() != "avatar" {
		t.Error("other fields must pass through")
	}
}

func TestParseMetadata(t *testing.T) {
	metadata := parseMetadata(`{"role":"player","department":"design"}`)
	if metadata.Role != rolePlayer || metadata.DepartmentID != "design" {
		t.Errorf("parseMetadata = %+v", metadata)
	}
	if parseMetadata(`not json`).Role != "" {
		t.Error("malformed metadata must give no role")
	}
	if got := (accountMetadata{Role: roleAdmin}).toMap(); len(got) != 1 || got["role"] != roleAdmin {
		t.Errorf("admin metadata map = %v", got)
	}
}

func TestDepartmentNames(t *testing.T) {
	departments := []Department{{ID: "b", Name: "дизайн", OfficeID: "hq"}, {ID: "a", Name: "Аналитика", OfficeID: "hq"}, {ID: "c", Name: "HR", OfficeID: "hq"}}
	sortDepartments(departments)
	if departments[0].ID != "c" || departments[1].ID != "a" || departments[2].ID != "b" {
		t.Errorf("sorted = %+v", departments)
	}
	if !nameTaken(departments, "hq", "ДИЗАЙН", "") {
		t.Error("case-insensitive duplicate not found")
	}
	if nameTaken(departments, "hq", "Дизайн", "b") {
		t.Error("renaming a department to its own name must be allowed")
	}
	if nameTaken(departments, "office_msk", "Дизайн", "") {
		t.Error("another office may have a department with the same name")
	}
	id, err := newDepartmentID()
	if err != nil || len(id) != len("dep_")+8 {
		t.Errorf("newDepartmentID = %q, %v", id, err)
	}
}
