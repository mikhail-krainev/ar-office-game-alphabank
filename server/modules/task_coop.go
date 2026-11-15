package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"sort"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Joint daily tasks: the player who has the task invites colleagues who are in the same office now.
// The game runs in a shared lounge room (lounge.go) that only invited players can join; each player
// who has the task in today's pack completes it with complete_task and the room as the proof, and
// the score comes from the room on the server, never from the client.

const (
	// coopCapacity: the host and up to five colleagues.
	coopCapacity = 6
	// coopMaxPoints: three waves of eight bugs, the last of every wave is golden (3 points).
	coopMaxPoints  = 30
	taskInviteKind = "task_invite"
)

// coopGames: task minigames that can be played together, played as a lounge game of the same name.
var coopGames = map[string]bool{"bug_hunt": true}

type coopPerson struct {
	UserID  string `json:"user_id"`
	Name    string `json:"name"`
	Avatar  string `json:"avatar"`
	Invited bool   `json:"invited"`
	Joined  bool   `json:"joined"`
}

// coopRoomID: one room per host, task and day, so re-inviting reuses it.
func coopRoomID(host, task string, day int) string {
	sum := sha256.Sum256([]byte(fmt.Sprintf("coop|%s|%s|%d", host, task, day)))
	return hex.EncodeToString(sum[:])[:12]
}

// coopTaskError: why the player cannot invite colleagues to this task now, or "".
func (tx *gameTx) coopTaskError(task *Task) (string, error) {
	if task == nil {
		return "unknown_task", nil
	}
	if !coopGames[task.Minigame] {
		return "invalid_mode", nil
	}
	if problem, err := tx.playError(); problem != "" || err != nil {
		return problem, err
	}
	return tx.taskError(task, true, taskProof{})
}

// coopColleagues: players in the caller's office now, except the caller.
func (tx *gameTx) coopColleagues() (map[string]publicPlayer, error) {
	presence, err := officePresence(tx.ctx, tx.nk, tx.today, tx.office())
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(presence))
	for id := range presence {
		if id != tx.me.userID {
			ids = append(ids, id)
		}
	}
	players, err := readPlayers(tx.ctx, tx.nk, ids, tx.today)
	if err != nil {
		return nil, err
	}
	for id, player := range players {
		// The index says where the colleague entered; a trip may have moved them since.
		if player.office != tx.office() {
			delete(players, id)
		}
	}
	return players, nil
}

// rpcTaskCoopPeople: {"task_id"} -> {"ok", "people"}: colleagues the player can invite, by name.
func rpcTaskCoopPeople(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		TaskID string `json:"task_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		task := tx.content.task(request.TaskID)
		if problem, err := tx.coopTaskError(task); problem != "" || err != nil {
			return fail(problem), err
		}
		players, err := tx.coopColleagues()
		if err != nil {
			return nil, err
		}
		loaded, err := tx.loungeFind(coopRoomID(tx.me.userID, task.ID, tx.today))
		if err != nil {
			return nil, err
		}
		people := []coopPerson{}
		for _, player := range players {
			person := coopPerson{UserID: player.userID, Name: player.name, Avatar: publicAvatar(player.userID, player.avatar, tx.content.Rules.AvatarTemplates)}
			if loaded != nil {
				person.Invited = contains(loaded.room.Invited, player.userID)
				person.Joined = loaded.room.player(player.userID) >= 0
			}
			people = append(people, person)
		}
		sort.Slice(people, func(i, j int) bool { return people[i].Name < people[j].Name })
		result := map[string]any{"ok": true, "people": people}
		if loaded != nil {
			result["room"] = loaded.room.view(tx.me.userID, time.Now().Unix())
		}
		return result, nil
	})
}

// rpcTaskInvite: {"task_id", "colleague_id", "operation_key"} -> {"ok", "error", "room"}. Opens the
// player's room for the task (or reuses today's) and sends the colleague an invitation to the inbox.
func rpcTaskInvite(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		TaskID       string `json:"task_id"`
		ColleagueID  string `json:"colleague_id"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		task := tx.content.task(request.TaskID)
		if problem, err := tx.coopTaskError(task); problem != "" || err != nil {
			return fail(problem), err
		}
		if !isUUID(request.ColleagueID) || request.ColleagueID == tx.me.userID {
			return fail("player_unavailable"), nil
		}
		players, err := tx.coopColleagues()
		if err != nil {
			return nil, err
		}
		if _, ok := players[request.ColleagueID]; !ok {
			return fail("player_unavailable"), nil
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil {
			return nil, err
		}
		if !claimed {
			return fail("duplicate_operation"), nil
		}
		now := time.Now().Unix()
		room, version, problem, err := tx.coopRoom(task, now)
		if problem != "" || err != nil {
			return fail(problem), err
		}
		if !contains(room.Invited, request.ColleagueID) {
			colleague, err := tx.other(request.ColleagueID)
			if err != nil {
				return nil, err
			}
			if colleague.banned() {
				return fail("player_unavailable"), nil
			}
			room.Invited = append(room.Invited, request.ColleagueID)
			if _, err := tx.notify(colleague, taskInviteKind, map[string]any{
				"from_id": tx.me.userID, "name": tx.me.displayName(), "room_id": room.ID, "task": task.ID,
				"title": task.Title, "day": tx.today, "avatar": publicAvatar(tx.me.userID, tx.me.state.Avatar, tx.content.Rules.AvatarTemplates),
			}, ""); err != nil {
				return nil, err
			}
		}
		room.Revision++
		room.Updated = now
		tx.loungeSave(room, version)
		return map[string]any{"ok": true, "room": room.view(tx.me.userID, now)}, nil
	})
}

// coopRoom: today's room of the player for the task, created on the first invitation. The player
// takes the seat back and leads the room again if they had left it.
func (tx *gameTx) coopRoom(task *Task, now int64) (*loungeRoom, string, string, error) {
	id := coopRoomID(tx.me.userID, task.ID, tx.today)
	loaded, err := tx.loungeFind(id)
	if err != nil {
		return nil, "", "", err
	}
	if loaded == nil {
		room := &loungeRoom{
			ID: id, Game: task.Minigame, Task: task.ID, TaskDay: tx.today, Host: tx.me.userID, Capacity: coopCapacity,
			Phase: "waiting", Created: now, Updated: now, Seed: int64(seededRand(randomKey()).Int64N(2147483647)), Level: 1, Chain: -1,
		}
		room.Players = []loungePlayer{tx.loungeSeat(0, now)}
		return room, "*", "", nil
	}
	room := loaded.room
	if room.Phase != "waiting" && room.Phase != "finished" {
		return nil, "", "round_started", nil
	}
	if room.player(tx.me.userID) < 0 {
		if len(room.Players) >= room.Capacity {
			return nil, "", "room_full", nil
		}
		room.Players = append(room.Players, tx.loungeSeat(len(room.Players), now))
	}
	room.Host = tx.me.userID
	return room, loaded.version, "", nil
}

// coopScore: the player's share of the points in a finished joint room of this task today.
func (tx *gameTx) coopScore(task *Task, roomID string) (float64, string, error) {
	if len(roomID) != 12 {
		return 0, "invalid_coop_room", nil
	}
	loaded, err := tx.loungeFind(roomID)
	if err != nil {
		return 0, "", err
	}
	if loaded == nil {
		return 0, "invalid_coop_room", nil
	}
	room := loaded.room
	if room.Task != task.ID || room.TaskDay != tx.today || room.Round < 1 || len(room.Players) < 2 {
		return 0, "invalid_coop_room", nil
	}
	if room.Phase != "finished" {
		return 0, "coop_not_finished", nil
	}
	index := room.player(tx.me.userID)
	if index < 0 {
		return 0, "invalid_coop_room", nil
	}
	points := room.Players[index].Score
	if points <= 0 {
		return 0, "task_failed", nil
	}
	return min(1, float64(points)/coopMaxPoints), "", nil
}
