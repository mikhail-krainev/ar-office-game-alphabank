package main

import (
	"encoding/json"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"
)

// gRPC status codes used by runtime.NewError; Nakama maps them to HTTP statuses.
const (
	codeInvalidArgument    = 3
	codeNotFound           = 5
	codeFailedPrecondition = 9
	codeAlreadyExists      = 6
	codePermissionDenied   = 7
	codeInternal           = 13
	codeUnauthenticated    = 16
)

// Error messages are stable keys: the game client and the admin panel translate them.
var (
	errInvalidPayload     = runtime.NewError("invalid_payload", codeInvalidArgument)
	errInvalidUsername    = runtime.NewError("invalid_username", codeInvalidArgument)
	errInvalidPassword    = runtime.NewError("invalid_password", codeInvalidArgument)
	errInvalidName        = runtime.NewError("invalid_name", codeInvalidArgument)
	errUsernameTaken      = runtime.NewError("username_taken", codeAlreadyExists)
	errDepartmentExists   = runtime.NewError("department_exists", codeAlreadyExists)
	errDepartmentNotFound = runtime.NewError("department_not_found", codeNotFound)
	errUserNotFound       = runtime.NewError("user_not_found", codeNotFound)
	errOfficeExists       = runtime.NewError("office_exists", codeAlreadyExists)
	errOfficeNotFound     = runtime.NewError("office_not_found", codeNotFound)
	errInvalidNetworks    = runtime.NewError("invalid_networks", codeInvalidArgument)
	errDepartmentOffice   = runtime.NewError("department_not_in_office", codeInvalidArgument)
	errInvalidTrip        = runtime.NewError("invalid_trip", codeInvalidArgument)
	errUnauthenticated    = runtime.NewError("unauthenticated", codeUnauthenticated)
	errNotAdmin           = runtime.NewError("not_admin", codePermissionDenied)
	errNotPlayer          = runtime.NewError("not_player", codePermissionDenied)
	errAdminProtected     = runtime.NewError("admin_protected", codePermissionDenied)
	errAuthMethodDisabled = runtime.NewError("auth_method_disabled", codePermissionDenied)
	errInternal           = runtime.NewError("internal", codeInternal)
)

// decodePayload parses an RPC payload strictly: unknown fields are an error.
func decodePayload(payload string, target any) error {
	decoder := json.NewDecoder(strings.NewReader(payload))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return errInvalidPayload
	}
	return nil
}

func encodeResponse(value any) (string, error) {
	data, err := json.Marshal(value)
	if err != nil {
		return "", errInternal
	}
	return string(data), nil
}
