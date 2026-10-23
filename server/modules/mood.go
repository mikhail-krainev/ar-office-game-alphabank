package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"image/jpeg"
	"image/png"

	"github.com/heroiclabs/nakama-common/runtime"
)

// "Mood of the day": the player draws today's mood with a finger, wears it on the forehead in the
// front camera (AR) and takes a photo with it, which completes the task. The photo (or, on a phone
// without face detection, the drawing alone) becomes the player's story: colleagues in the office tap
// the player's name or avatar, open the mini profile and watch it like a story in a messenger. The
// story lives until the end of the working day (the end of the task window); one story a day, the
// next one replaces it.

const (
	moodMinigame   = "mood_doodle"
	moodSide       = 64
	moodMaxBytes   = 24 * 1024
	moodCollection = "mood"
	moodKey        = "today"
	// The photo with the drawing on the forehead: a small JPEG made on the phone.
	moodPhotoMaxBytes = 64 * 1024
	moodPhotoMinSide  = 64
	moodPhotoMaxSide  = 480
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

// validMoodPhoto: the optional photo, a JPEG of at most moodPhotoMaxBytes with sides between
// moodPhotoMinSide and moodPhotoMaxSide. No photo is fine (nil, "").
func validMoodPhoto(encoded string) ([]byte, string) {
	if encoded == "" {
		return nil, ""
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) == 0 || len(data) > moodPhotoMaxBytes {
		return nil, "mood_invalid"
	}
	config, err := jpeg.DecodeConfig(bytes.NewReader(data))
	if err != nil || !between(config.Width, moodPhotoMinSide, moodPhotoMaxSide) || !between(config.Height, moodPhotoMinSide, moodPhotoMaxSide) {
		return nil, "mood_invalid"
	}
	return data, ""
}

func between(value, low, high int) bool {
	return value >= low && value <= high
}

// storyOpen: stories are shown until the end of the working day, the end of the task window.
func storyOpen(limits Limits, now, offset int64) bool {
	end, _ := clockMinutes(limits.TaskWindowEnd)
	return localMinute(now, offset) < end
}

func (tx *gameTx) storiesOpen() (bool, error) {
	if devMode && tx.me.state.DevNoTaskLimits {
		return true, nil
	}
	limits, err := tx.limits()
	if err != nil {
		return false, err
	}
	return storyOpen(limits, tx.now, tx.offset), nil
}

// saveMood stores today's story of the player: the drawing and the photo with it, when there is one
// (server-only object: colleagues read it via get_mood).
func (tx *gameTx) saveMood(drawing, photo []byte) {
	story := map[string]any{"png": base64.StdEncoding.EncodeToString(drawing), "day": tx.today}
	if photo != nil {
		story["photo"] = base64.StdEncoding.EncodeToString(photo)
	}
	value, _ := json.Marshal(story)
	tx.writes = append(tx.writes, &runtime.StorageWrite{
		Collection: moodCollection, Key: moodKey, UserID: tx.me.userID, Value: string(value),
		PermissionRead: permissionNone, PermissionWrite: permissionNone,
	})
	tx.me.state.MoodDay = tx.today
}

// rpcGetMood: {"user_id"} -> {"png": base64 or "", "photo": base64 JPEG or "", "day"}. Today's story
// of the player, or of a colleague in the same office today while the player is in the office too and
// the working day has not ended; nothing for anyone else.
func rpcGetMood(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		empty := map[string]any{"png": "", "photo": "", "day": 0}
		if !isUUID(request.UserID) {
			return empty, nil
		}
		if request.UserID != tx.me.userID {
			open, err := tx.storiesOpen()
			if err != nil || !open || !tx.inMyOffice() {
				return empty, err
			}
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
			PNG   string `json:"png"`
			Photo string `json:"photo"`
			Day   int    `json:"day"`
		}
		if len(objects) == 0 || json.Unmarshal([]byte(objects[0].GetValue()), &value) != nil || value.Day != tx.today {
			return empty, nil
		}
		return map[string]any{"png": value.PNG, "photo": value.Photo, "day": value.Day}, nil
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

// officePlayerView: the mini profile of a colleague. `storiesOpen` hides stories after the working day.
func (tx *gameTx) officePlayerView(player publicPlayer, presence map[string]presenceEntry, storiesOpen bool) officePlayerView {
	outfit := player.outfit
	if outfit == nil {
		outfit = map[string]string{}
	}
	return officePlayerView{
		colleagueView: tx.colleagueView(player, presence),
		Streak:        player.streak, Outfit: outfit, HasMood: player.hasMood && storiesOpen,
		CharacterAvatar: player.avatar == defaultAvatar,
	}
}

// rpcOfficePlayers: -> {"players": [officePlayerView]}: everyone in the player's office now (entry
// code scanned, day not ended) except the player, for the office map: name, department, avatar,
// status, streak, the outfit to draw the character with and whether today's story exists.
func rpcOfficePlayers(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		open, err := tx.storiesOpen()
		if err != nil {
			return nil, err
		}
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
			views = append(views, tx.officePlayerView(player, presence, open))
		}
		return map[string]any{"players": views}, nil
	})
}

// rpcPlayerCard: {"user_id"} -> {"found", "player": officePlayerView}. The mini profile of a
// colleague whose name or avatar the player tapped (a task card, the inbox, the office map). Only
// players of the office the player is in today are found, in the office now or not.
func rpcPlayerCard(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		notFound := map[string]any{"found": false}
		if !isUUID(request.UserID) || request.UserID == tx.me.userID {
			return notFound, nil
		}
		players, err := readPlayers(tx.ctx, tx.nk, []string{request.UserID}, tx.today)
		if err != nil {
			return nil, err
		}
		player, ok := players[request.UserID]
		if !ok || player.office != tx.office() {
			return notFound, nil
		}
		open, err := tx.storiesOpen()
		if err != nil {
			return nil, err
		}
		presence, err := officePresence(tx.ctx, tx.nk, tx.today, player.office)
		if err != nil {
			return nil, err
		}
		return map[string]any{"found": true, "player": tx.officePlayerView(player, presence, open)}, nil
	})
}
