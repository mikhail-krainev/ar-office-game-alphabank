package main

// Where each player's character is on the office map, so every colleague sees them in the same room.
// The character walks by itself and by the player's taps; the client reports each room change
// (report_position) and office_players hands it out as `map_room`. It is only a picture: tasks,
// room codes and anti-fraud use the room of the last door code (presence.go), never this one.

import (
	"context"
	"database/sql"
	"encoding/json"

	"github.com/heroiclabs/nakama-common/runtime"
)

const positionsCollection = "office_positions"

// mapPosition is one system object per player: the room of the character today in that office.
type mapPosition struct {
	Day    int    `json:"day"`
	Office string `json:"office"`
	Room   string `json:"room"`
	At     int64  `json:"at"`
}

// rpcReportPosition: {"room_id"}. The player's character entered a room of the office map. Only
// while the player is in the office (entry code scanned) and in its network.
func rpcReportPosition(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		RoomID string `json:"room_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if !roomIDPattern.MatchString(request.RoomID) {
		return "", errInvalidPayload
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		position := mapPosition{Day: tx.today, Office: tx.office(), Room: request.RoomID, At: tx.now}
		return okResult, tx.writeSystem(positionsCollection, tx.me.userID, position, "")
	})
}

// mapRooms: user id -> the room of their character today in `office`; players without a report
// today (or from another office) are left out.
func mapRooms(ctx context.Context, nk runtime.NakamaModule, ids []string, today int, office string) (map[string]string, error) {
	result := map[string]string{}
	if len(ids) == 0 {
		return result, nil
	}
	reads := make([]*runtime.StorageRead, 0, len(ids))
	for _, id := range ids {
		reads = append(reads, &runtime.StorageRead{Collection: positionsCollection, Key: id, UserID: systemUserID})
	}
	objects, err := nk.StorageRead(ctx, reads)
	if err != nil {
		return nil, errInternal
	}
	for _, object := range objects {
		var position mapPosition
		if json.Unmarshal([]byte(object.GetValue()), &position) != nil {
			continue
		}
		if room, ok := position.roomFor(today, office); ok {
			result[object.GetKey()] = room
		}
	}
	return result, nil
}

// roomFor: the room when the report is from `today` in `office`.
func (p mapPosition) roomFor(today int, office string) (string, bool) {
	if p.Day != today || p.Office != office || !roomIDPattern.MatchString(p.Room) {
		return "", false
	}
	return p.Room, true
}
