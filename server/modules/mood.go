package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"image/png"

	"github.com/heroiclabs/nakama-common/runtime"
)

// "Mood of the day": the player draws today's mood with a finger, wears it on the forehead in the
// front camera (AR) and completes the task. The drawing becomes the player's story for the day:
// colleagues in the same office tap the avatar on the office map and see it. One drawing a day; the
// next day's drawing replaces it, and a story of an earlier day is never shown.

const (
	moodMinigame   = "mood_doodle"
	moodSide       = 64
	moodMaxBytes   = 24 * 1024
	moodCollection = "mood"
	moodKey        = "today"
	// The office map shows at most this many colleagues.
	maxOfficePlayers = 30
)

// validMoodPNG: a square PNG of moodSide pixels, at most moodMaxBytes.
func validMoodPNG(encoded string) ([]byte, string) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) == 0 || len(data) > moodMaxBytes {
		return nil, "mood_invalid"
	}
	config, err := png.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width != moodSide || config.Height != moodSide {
		return nil, "mood_invalid"
	}
	return data, ""
}

// saveMood stores today's drawing of the player (server-only object: colleagues read it via get_mood).
func (tx *gameTx) saveMood(data []byte) {
	value, _ := json.Marshal(map[string]any{"png": base64.StdEncoding.EncodeToString(data), "day": tx.today})
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: moodCollection, Key: moodKey, UserID: tx.me.userID, Value: string(value),
		PermissionRead: permissionNone, PermissionWrite: permissionNone,
	})
	tx.me.state.MoodDay = tx.today
}

// rpcGetMood: {"user_id"} -> {"png": base64 or "", "day"}. Today's story of the player or of a
// colleague in the same office today; nothing for anyone else.
func rpcGetMood(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		empty := map[string]any{"png": "", "day": 0}
		if !isUUID(request.UserID) {
			return empty, nil
		}
		if request.UserID != tx.me.userID {
			players, err := readPlayers(tx.ctx, tx.nk, []string{request.UserID}, tx.today)
			if err != nil {
				return nil, err
			}
			player, ok := players[request.UserID]
			if !ok || player.office != tx.office() || !player.hasMood {
				return empty, nil
			}
		} else if tx.me.state.MoodDay != tx.today {
			return empty, nil
		}
		objects, err := tx.nk.StorageRead(tx.ctx, []*runtime.StorageRead{{Collection: moodCollection, Key: moodKey, UserID: request.UserID}})
		if err != nil {
			return nil, errInternal
		}
		var value struct {
			PNG string `json:"png"`
			Day int    `json:"day"`
		}
		if len(objects) == 0 || json.Unmarshal([]byte(objects[0].GetValue()), &value) != nil || value.Day != tx.today {
			return empty, nil
		}
		return map[string]any{"png": value.PNG, "day": value.Day}, nil
	})
}

type officePlayerView struct {
	colleagueView
	Streak  int               `json:"streak"`
	Outfit  map[string]string `json:"outfit"`
	HasMood bool              `json:"has_mood"`
	// The avatar is the player's own character: draw it from the outfit instead of `avatar`.
	CharacterAvatar bool `json:"character_avatar"`
}

// rpcOfficePlayers: -> {"players": [officePlayerView]}: everyone in the player's office now (entry
// code scanned, day not ended) except the player, for the office map: name, department, avatar,
// status, streak, the outfit to draw the character with and whether today's story exists.
func rpcOfficePlayers(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		presence, err := officePresence(tx.ctx, tx.nk, tx.today, tx.office())
		if err != nil {
			return nil, err
		}
		ids := make([]string, 0, len(presence))
		for id := range presence {
			if id != tx.me.userID && len(ids) < maxOfficePlayers {
				ids = append(ids, id)
			}
		}
		players, err := readPlayers(tx.ctx, tx.nk, ids, tx.today)
		if err != nil {
			return nil, err
		}
		views := []officePlayerView{}
		for _, player := range players {
			// The index says where the colleague entered; a trip may have moved them since.
			if player.office != tx.office() {
				continue
			}
			outfit := player.outfit
			if outfit == nil {
				outfit = map[string]string{}
			}
			views = append(views, officePlayerView{
				colleagueView: tx.colleagueView(player, presence),
				Streak:        player.streak, Outfit: outfit, HasMood: player.hasMood,
				CharacterAvatar: player.avatar == defaultAvatar,
			})
		}
		return map[string]any{"players": views}, nil
	})
}
