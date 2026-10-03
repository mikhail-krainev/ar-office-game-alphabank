package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"hash/fnv"
	"math/big"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Other players: colleagues picked for tasks, profile-code checks, joint photo confirmations and
// the inbox. A colleague counts only while they are in the office (the presence index), and only in
// the office the player is in today: joint tasks never pair people from different offices.

const minPhotoFaces = 2

type colleagueView struct {
	UserID     string `json:"user_id"`
	Name       string `json:"name"`
	Department string `json:"department"`
	Office     string `json:"office"`
	Avatar     string `json:"avatar"`
	Status     string `json:"status"`
	Room       string `json:"room"`
	Present    bool   `json:"present"`
}

// publicPlayer is what other players may see of someone: account and the public part of the state.
type publicPlayer struct {
	userID     string
	name       string
	department string
	office     string
	avatar     string
	status     string
}

// readPlayers loads the public cards of players (admins and unknown ids are left out), with the
// office and department they count in on `today`.
func readPlayers(ctx context.Context, nk runtime.NakamaModule, userIDs []string, today int) (map[string]publicPlayer, error) {
	result := map[string]publicPlayer{}
	if len(userIDs) == 0 {
		return result, nil
	}
	accounts, err := nk.AccountsGetId(ctx, userIDs, nil)
	if err != nil {
		return nil, errInternal
	}
	reads := []*runtime.StorageRead{}
	for _, account := range accounts {
		metadata := parseMetadata(account.GetUser().GetMetadata())
		if metadata.Role != rolePlayer {
			continue
		}
		id := account.GetUser().GetId()
		office, department := metadata.placement(today)
		result[id] = publicPlayer{userID: id, name: account.GetUser().GetDisplayName(), department: department, office: office, avatar: defaultAvatar}
		reads = append(reads, &runtime.StorageRead{Collection: gameCollection, Key: stateKey, UserID: id})
	}
	if len(reads) == 0 {
		return result, nil
	}
	objects, err := nk.StorageRead(ctx, reads)
	if err != nil {
		return nil, errInternal
	}
	for _, object := range objects {
		var state PlayerState
		if json.Unmarshal([]byte(object.GetValue()), &state) != nil {
			continue
		}
		player := result[object.GetUserId()]
		player.status = state.Status
		if state.Avatar != "" {
			player.avatar = state.Avatar
		}
		result[object.GetUserId()] = player
	}
	return result, nil
}

// publicAvatar: "me" is the owner's own character, which other phones cannot draw, so they see a
// template picked from the user id instead.
func publicAvatar(userID, avatar string, templates []string) string {
	if avatar != defaultAvatar || len(templates) < 2 {
		return avatar
	}
	hash := fnv.New32a()
	hash.Write([]byte(userID))
	return templates[1+int(hash.Sum32()%uint32(len(templates)-1))]
}

func (tx *gameTx) colleagueView(player publicPlayer, presence map[string]presenceEntry) colleagueView {
	entry, present := presence[player.userID]
	return colleagueView{
		UserID: player.userID, Name: player.name, Department: player.department, Office: player.office,
		Avatar: publicAvatar(player.userID, player.avatar, tx.content.Rules.AvatarTemplates),
		Status: player.status, Room: entry.Room, Present: present,
	}
}

// rpcAssignColleague: {"task_id"}. Picks someone in the player's office now (from another
// department when the task says so) whom the player has not met in a task today. The choice stays
// for the day while that colleague is in the office.
func rpcAssignColleague(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		TaskID string `json:"task_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		task := tx.content.task(request.TaskID)
		if task == nil || task.Assignment == "" {
			return fail("unknown_task"), nil
		}
		if !tx.isTodaysTask(task) {
			return fail("task_not_today"), nil
		}
		state := tx.me.state
		if problem, err := tx.playError(); problem != "" || err != nil {
			return fail(problem), err
		}
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		if problem, err := tx.taskTimeError(task); problem != "" || err != nil {
			return fail(problem), err
		}
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
		assignments := state.Assignments[dayKey(tx.today)]
		if assignments == nil {
			assignments = map[string]string{}
			state.Assignments[dayKey(tx.today)] = assignments
		}
		current, ok := players[assignments[task.ID]]
		if !ok {
			candidates := []publicPlayer{}
			for _, player := range players {
				if contains(dayList(state.Met, tx.today), player.userID) {
					continue
				}
				if task.Assignment == "other_department" && player.department == tx.department() {
					continue
				}
				candidates = append(candidates, player)
			}
			if len(candidates) == 0 {
				return fail("no_colleague_available"), nil
			}
			current = candidates[randomIndex(len(candidates))]
			assignments[task.ID] = current.userID
		}
		return map[string]any{"ok": true, "colleague": tx.colleagueView(current, presence)}, nil
	})
}

// rpcLookupColleague: {"user_id"}. Public card of the player behind a scanned profile code. A
// player of another office is not found: they cannot take part in this player's tasks.
func rpcLookupColleague(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		UserID string `json:"user_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		card, err := tx.lookup(request.UserID)
		if err != nil || card == nil || card.Office != tx.office() {
			return map[string]any{"found": false}, err
		}
		return map[string]any{"found": true, "colleague": card}, nil
	})
}

func (tx *gameTx) lookup(userID string) (*colleagueView, error) {
	if !isUUID(userID) {
		return nil, nil
	}
	players, err := readPlayers(tx.ctx, tx.nk, []string{userID}, tx.today)
	if err != nil {
		return nil, err
	}
	player, ok := players[userID]
	if !ok {
		return nil, nil
	}
	presence, err := officePresence(tx.ctx, tx.nk, tx.today, player.office)
	if err != nil {
		return nil, err
	}
	card := tx.colleagueView(player, presence)
	return &card, nil
}

// verifySocial checks the colleague part of a proof. "" when fine.
func (tx *gameTx) verifySocial(task *Task, proof taskProof) (string, error) {
	switch task.Minigame {
	case photoMinigame:
		return tx.verifyPhoto(task, proof)
	case meetMinigame:
		assigned := tx.me.state.Assignments[dayKey(tx.today)][task.ID]
		if task.Assignment != "" && proof.ColleagueID != assigned {
			return "colleague_not_assigned", nil
		}
		_, problem, err := tx.verifyColleague(proof.ColleagueID, task.Assignment != "present_colleague")
		return problem, err
	case bingoMinigame:
		return tx.verifyBingo(task, proof)
	}
	return "", nil
}

// verifyPhoto: the colleague the server assigned, in the player's office, and two faces in the frame.
func (tx *gameTx) verifyPhoto(task *Task, proof taskProof) (string, error) {
	if proof.PartnerID == "" || proof.PartnerID != tx.me.state.Assignments[dayKey(tx.today)][task.ID] {
		return "colleague_not_assigned", nil
	}
	card, err := tx.lookup(proof.PartnerID)
	if err != nil {
		return "", err
	}
	if card == nil {
		return "colleague_invalid", nil
	}
	if card.Office != tx.office() {
		return "colleague_other_office", nil
	}
	if !card.Present {
		return "colleague_not_present", nil
	}
	if proof.Faces < minPhotoFaces {
		return "not_enough_faces", nil
	}
	return "", nil
}

// verifyBingo: `count` different colleagues, each from another department, each department once.
func (tx *gameTx) verifyBingo(task *Task, proof taskProof) (string, error) {
	needed := 3
	if count, ok := task.Params["count"].(float64); ok {
		needed = int(count)
	}
	departments := map[string]bool{}
	seen := map[string]bool{}
	for _, id := range proof.ColleagueIDs {
		if seen[id] {
			return "colleague_already_used", nil
		}
		card, problem, err := tx.verifyColleague(id, true)
		if err != nil || problem != "" {
			return problem, err
		}
		if departments[card.Department] {
			return "same_department_twice", nil
		}
		seen[id] = true
		departments[card.Department] = true
	}
	if len(seen) < needed {
		return "not_enough_colleagues", nil
	}
	return "", nil
}

func (tx *gameTx) verifyColleague(userID string, otherDepartment bool) (*colleagueView, string, error) {
	if userID == tx.me.userID {
		return nil, "colleague_invalid", nil
	}
	card, err := tx.lookup(userID)
	switch {
	case err != nil:
		return nil, "", err
	case card == nil:
		return nil, "colleague_invalid", nil
	case card.Office != tx.office():
		return nil, "colleague_other_office", nil
	case otherDepartment && card.Department == tx.department():
		return nil, "same_department", nil
	case !card.Present:
		return nil, "colleague_not_present", nil
	case contains(dayList(tx.me.state.Met, tx.today), userID):
		return nil, "colleague_already_used", nil
	}
	return card, "", nil
}

// submitPhoto makes the task pending and asks the colleague to confirm the photo. Returns their name.
func (tx *gameTx) submitPhoto(task *Task, partnerID string, reward int) (string, error) {
	partner, err := tx.other(partnerID)
	if err != nil {
		return "", err
	}
	state := tx.me.state
	addToDay(state.Met, tx.today, partnerID)
	addToDay(state.Pending, tx.today, task.ID)
	tx.logActivity(tx.me, activityTaskPending, map[string]any{"task": task.ID, "partner": partnerID})
	requestID := randomKey()
	inboxID, err := tx.notify(partner, "photo_request", map[string]any{
		"from_id": tx.me.userID, "name": tx.me.displayName(), "request_id": requestID, "day": tx.today,
		"avatar": publicAvatar(tx.me.userID, state.Avatar, tx.content.Rules.AvatarTemplates),
	}, "pending")
	if err != nil {
		return "", err
	}
	state.PhotoRequests = append(state.PhotoRequests, PhotoRequest{
		ID: requestID, Day: tx.today, Task: task.ID, Partner: partnerID, T: tx.now, State: "pending", Reward: reward, PartnerIn: inboxID,
	})
	return partner.displayName(), nil
}

// rpcRespondPhotoRequest: {"item_id", "confirm", "operation_key"}. Answer to "<colleague> took a
// photo with you, is it true?". Confirming pays the colleague's task and a small bonus to the
// player; declining tells the colleague and marks the attempt as suspicious.
func rpcRespondPhotoRequest(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		ItemID       int    `json:"item_id"`
		Confirm      bool   `json:"confirm"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.playError(); problem != "" || err != nil {
			return fail(problem), err
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return fail("duplicate_operation"), err
		}
		inbox, err := tx.inboxOf(tx.me)
		if err != nil {
			return nil, err
		}
		var item *InboxItem
		for i := range inbox.Items {
			if inbox.Items[i].ID == request.ItemID {
				item = &inbox.Items[i]
			}
		}
		if item == nil || item.Kind != "photo_request" {
			return fail("unknown_request"), nil
		}
		if item.State != "pending" {
			return fail("request_closed"), nil
		}
		fromID, _ := item.Params["from_id"].(string)
		requestID, _ := item.Params["request_id"].(string)
		item.Read = true
		tx.me.inboxDirty = true
		if request.Confirm {
			item.State = "confirmed"
		} else {
			item.State = "declined"
		}
		tx.logActivity(tx.me, activityPhotoAnswer, map[string]any{"from": fromID, "confirm": request.Confirm})
		if err := tx.resolvePhotoRequest(fromID, requestID, request.Confirm); err != nil {
			return nil, err
		}
		if request.Confirm {
			bonus := min(tx.content.Rules.Photo.PartnerBonus, max(0, capLeft(tx.me.state, tx.today, &tx.content.Rules)))
			if bonus > 0 {
				tx.me.state.Earned[dayKey(tx.today)] += bonus
				tx.credit(tx.me, int64(bonus), "photo_partner_bonus", fromID)
			}
		}
		return map[string]any{"ok": true, "balance": tx.me.balance}, nil
	})
}

// resolvePhotoRequest pays or declines the requester's pending photo task.
func (tx *gameTx) resolvePhotoRequest(requesterID, requestID string, confirmed bool) error {
	requester, err := tx.other(requesterID)
	if err != nil {
		return nil // the account is gone; nothing to pay
	}
	for i := range requester.state.PhotoRequests {
		photo := &requester.state.PhotoRequests[i]
		if photo.ID != requestID || photo.State != "pending" {
			continue
		}
		task := tx.content.task(photo.Task)
		if photo.Day != tx.today || task == nil {
			photo.State = "expired"
			removeFromDay(requester.state.Pending, photo.Day, photo.Task)
			return nil
		}
		if !confirmed {
			photo.State = "declined"
			removeFromDay(requester.state.Pending, photo.Day, photo.Task)
			tx.logSuspicious(photoMinigame, "photo_declined_by_partner:"+requesterID)
			_, err := tx.notify(requester, "photo_declined", map[string]any{"name": tx.me.displayName()}, "")
			return err
		}
		photo.State = "confirmed"
		reward := max(0, min(photo.Reward, capLeft(requester.state, photo.Day, &tx.content.Rules)))
		tx.grantTask(requester, task, photo.Day, reward)
		_, err := tx.notify(requester, "photo_confirmed", map[string]any{"name": tx.me.displayName(), "reward": reward}, "")
		return err
	}
	return nil
}

// expirePhotoRequests ends unanswered requests at the end of their day, on both sides.
func (tx *gameTx) expirePhotoRequests() error {
	state := tx.me.state
	for i := range state.PhotoRequests {
		photo := &state.PhotoRequests[i]
		if photo.State == "pending" && photo.Day != tx.today {
			photo.State = "expired"
			removeFromDay(state.Pending, photo.Day, photo.Task)
		}
	}
	inbox, err := tx.inboxOf(tx.me)
	if err != nil {
		return err
	}
	for i := range inbox.Items {
		item := &inbox.Items[i]
		if item.Kind == "photo_request" && item.State == "pending" {
			if day, ok := item.Params["day"].(float64); ok && int(day) != tx.today {
				item.State = "expired"
				tx.me.inboxDirty = true
			}
		}
	}
	return nil
}

type inboxView struct {
	ID        int            `json:"id"`
	Kind      string         `json:"kind"`
	CreatedAt int64          `json:"created_at"`
	Params    map[string]any `json:"params"`
	Read      bool           `json:"read"`
	State     string         `json:"state"`
}

// rpcGetInbox: newest first, with the balance (other players' actions may have changed it).
func rpcGetInbox(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if err := tx.tick(); err != nil {
			return nil, err
		}
		inbox, err := tx.inboxOf(tx.me)
		if err != nil {
			return nil, err
		}
		items := []inboxView{}
		for i := len(inbox.Items) - 1; i >= 0; i-- {
			item := inbox.Items[i]
			items = append(items, inboxView{ID: item.ID, Kind: item.Kind, CreatedAt: item.T, Params: item.Params, Read: item.Read, State: item.State})
		}
		return map[string]any{"items": items, "balance": tx.me.balance}, nil
	})
}

// rpcMarkInboxRead: everything except unanswered photo requests.
func rpcMarkInboxRead(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		inbox, err := tx.inboxOf(tx.me)
		if err != nil {
			return nil, err
		}
		for i := range inbox.Items {
			item := &inbox.Items[i]
			if (item.Kind != "photo_request" || item.State != "pending") && !item.Read {
				item.Read = true
				tx.me.inboxDirty = true
			}
		}
		return okResult, nil
	})
}

func randomIndex(n int) int {
	value, err := rand.Int(rand.Reader, big.NewInt(int64(n)))
	if err != nil {
		return 0
	}
	return int(value.Int64())
}
