package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

// Account metadata has several writers: the main admin, managers and the office network detection
// (network.go). A read through AccountGetId and a write through AccountUpdateId would let one of two
// concurrent edits overwrite the other, for example a trip the admin sets while a manager deletes
// the player. Every change of an existing account's metadata goes through updateMetadata instead:
// it locks the account row, so concurrent changes run one after another and each sees the last.

// Nakama keeps the metadata in users.metadata (JSONB); the runtime has no call that locks it.
const (
	selectMetadataForUpdate = `SELECT metadata FROM users WHERE id = $1 FOR UPDATE`
	updateMetadataQuery     = `UPDATE users SET metadata = $1::jsonb, update_time = now() WHERE id = $2`
	// FOR SHARE: managers acting at the same time do not wait for each other, but the admin's
	// change of the manager's rights waits until the action ends, and the action sees the change
	// when it comes after it.
	selectManagerForShare = `SELECT metadata, disable_time > '1970-01-01 00:00:00 UTC' FROM users WHERE id = $1 FOR SHARE`
)

// updateMetadata applies `change` to the account's metadata under a row lock and writes the result.
// `change` sees the metadata as it is now and may refuse with an error, which writes nothing.
func updateMetadata(ctx context.Context, db *sql.DB, userID string, change func(*accountMetadata) error) (accountMetadata, error) {
	if !isUUID(userID) || userID == systemUserID {
		return accountMetadata{}, errUserNotFound
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return accountMetadata{}, errInternal
	}
	defer func() { _ = tx.Rollback() }()
	var raw string
	if err := tx.QueryRowContext(ctx, selectMetadataForUpdate, userID).Scan(&raw); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return accountMetadata{}, errUserNotFound
		}
		return accountMetadata{}, errInternal
	}
	metadata := parseMetadata(raw)
	if err := change(&metadata); err != nil {
		return accountMetadata{}, err
	}
	value, err := json.Marshal(metadata.toMap())
	if err != nil {
		return accountMetadata{}, errInternal
	}
	if _, err := tx.ExecContext(ctx, updateMetadataQuery, string(value), userID); err != nil {
		return accountMetadata{}, errInternal
	}
	if err := tx.Commit(); err != nil {
		return accountMetadata{}, errInternal
	}
	return metadata, nil
}

// asPlayer: the change applies only to a player account. Admin accounts are managed through the
// server environment, managers through the manager RPCs; a player being deleted is gone already.
func asPlayer(change func(*accountMetadata) error) func(*accountMetadata) error {
	return func(metadata *accountMetadata) error {
		if err := playerOnly(*metadata); err != nil {
			return err
		}
		metadata.Role = rolePlayer
		return change(metadata)
	}
}

// playerOnly refuses accounts that are not players. Accounts made before roles existed have none
// and count as players.
func playerOnly(metadata accountMetadata) error {
	switch metadata.Role {
	case rolePlayer, "":
		return nil
	case roleAdmin, roleManager:
		return errAdminProtected
	default:
		return errUserNotFound
	}
}

// withManager runs `action` while the manager's account row is share-locked, with the manager's
// scope as it is at that moment. The admin's change of the scope waits until `action` ends, so a
// right taken away is never used after the admin's call returns.
func withManager(ctx context.Context, db *sql.DB, managerID string, action func(ManagerScope) (any, error)) (string, error) {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", errInternal
	}
	defer func() { _ = tx.Rollback() }()
	var (
		raw    string
		banned bool
	)
	if err := tx.QueryRowContext(ctx, selectManagerForShare, managerID).Scan(&raw, &banned); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", errUnauthenticated
		}
		return "", errInternal
	}
	metadata := parseMetadata(raw)
	if metadata.Role != roleManager || metadata.Manager == nil || banned {
		return "", errNotManager
	}
	result, err := action(*metadata.Manager)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", errInternal
	}
	return encodeResponse(result)
}
