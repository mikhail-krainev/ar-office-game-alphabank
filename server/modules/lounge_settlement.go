package main

import (
	"encoding/json"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

type loadedLounge struct {
	room    *loungeRoom
	version string
	dirty   bool
}

func (tx *gameTx) loungeSave(room *loungeRoom, version string) {
	if tx.lounges == nil {
		tx.lounges = map[string]*loadedLounge{}
	}
	tx.lounges[room.ID] = &loadedLounge{room: room, version: version, dirty: true}
}

// Before a player's next game action, settle expired rooms they took part in, even if they closed
// the table. The cache ensures the action and the sweep never enqueue two writes to the same room.
func (tx *gameTx) loungeSweep() error {
	if tx.db == nil {
		return nil
	}
	member, _ := json.Marshal([]map[string]string{{"id": tx.me.userID}})
	rows, err := tx.db.QueryContext(tx.ctx, `SELECT key FROM storage WHERE collection=$1 AND user_id=$2 AND value->>'phase' NOT IN ('waiting','finished') AND value->'deadline'>'0'::jsonb AND value->'deadline'<=to_jsonb($3::bigint) AND value->'players' @> $4::jsonb LIMIT 20`, loungeCollection, systemUserID, time.Now().Unix(), string(member))
	if err != nil {
		return errInternal
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) != nil {
			rows.Close()
			return errInternal
		}
		ids = append(ids, id)
	}
	readErr := rows.Err()
	rows.Close()
	if readErr != nil {
		return errInternal
	}
	now := time.Now().Unix()
	for _, id := range ids {
		room, version, err := tx.loungeLoad(id)
		if err != nil {
			return err
		}
		if room.advance(now) {
			if err := tx.loungeSettle(room); err != nil {
				return err
			}
			room.Revision++
			room.Updated = now
			tx.loungeSave(room, version)
		}
	}
	return nil
}

func (tx *gameTx) loungeRead(id string) (*loadedLounge, error) {
	loaded, err := tx.loungeFind(id)
	if err != nil {
		return nil, err
	}
	if loaded == nil {
		return nil, runtime.NewError("room_not_found", codeInvalidArgument)
	}
	return loaded, nil
}

// loungeFind: the room, or nil when it does not exist yet.
func (tx *gameTx) loungeFind(id string) (*loadedLounge, error) {
	if tx.lounges == nil {
		tx.lounges = map[string]*loadedLounge{}
	}
	if loaded := tx.lounges[id]; loaded != nil {
		return loaded, nil
	}
	objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: loungeCollection, Key: id, UserID: systemUserID}})
	if err != nil {
		return nil, errInternal
	}
	if len(objects) == 0 {
		return nil, nil
	}
	var room loungeRoom
	if json.Unmarshal([]byte(objects[0].GetValue()), &room) != nil {
		return nil, errInternal
	}
	loaded := &loadedLounge{room: &room, version: objects[0].GetVersion()}
	tx.lounges[id] = loaded
	return loaded, nil
}
