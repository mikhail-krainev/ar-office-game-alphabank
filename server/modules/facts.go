package main

import (
	"context"
	"database/sql"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/heroiclabs/nakama-common/runtime"
)

// "Three truths, two lies": the player writes five facts about themselves after the check-in, three
// true and two false. The server assigns a colleague; the colleague gets the facts (without the
// answers) in their inbox, marks which ones are true and sends the guess. Then the player scans the
// colleague's "My QR" and the task counts. The truths never leave the server before the guess.

const (
	factsMinigame  = "two_truths"
	factsCount     = 5
	factsTrueCount = 3
	maxFactLength  = 100
	// Old quizzes are dropped from the state; the activity log keeps the history.
	maxFactsQuizzes = 20
	factsQuizKind   = "facts_quiz"
)

type Fact struct {
	Text string `json:"text"`
	True bool   `json:"true"`
}

// FactsQuiz is one colleague's guess about the player's facts, kept in the player's state.
// State: pending (sent to the colleague) | answered | expired. The completed task closes it.
type FactsQuiz struct {
	ID        string `json:"id"`
	Day       int    `json:"day"`
	Task      string `json:"task"`
	Partner   string `json:"partner"`
	T         int64  `json:"t"`
	State     string `json:"state"`
	Correct   int    `json:"correct"`
	PartnerIn int    `json:"partner_inbox_id"`
}

// normalizeFacts trims the texts and checks the shape: five facts, three of them true. "" when fine.
func normalizeFacts(facts []Fact) ([]Fact, string) {
	if len(facts) != factsCount {
		return nil, "facts_invalid"
	}
	result := make([]Fact, 0, factsCount)
	truths := 0
	for _, fact := range facts {
		text := strings.Join(strings.Fields(fact.Text), " ")
		length := utf8.RuneCountInString(text)
		if length == 0 || length > maxFactLength || strings.IndexFunc(text, unicode.IsControl) >= 0 {
			return nil, "facts_invalid"
		}
		if fact.True {
			truths++
		}
		result = append(result, Fact{Text: text, True: fact.True})
	}
	if truths != factsTrueCount {
		return nil, "facts_invalid"
	}
	return result, ""
}

// scoreGuesses: how many facts the colleague marked right. ok is false for a malformed guess; the
// colleague knows the rule, so the guess must also mark exactly three facts as true.
func scoreGuesses(facts []Fact, guesses []bool) (correct int, ok bool) {
	if len(facts) != factsCount || len(guesses) != factsCount {
		return 0, false
	}
	truths := 0
	for i, guess := range guesses {
		if guess {
			truths++
		}
		if guess == facts[i].True {
			correct++
		}
	}
	return correct, truths == factsTrueCount
}

// factsScore: the share of facts the colleague got wrong. Fooling them pays the score bonus.
func factsScore(correct int) float64 {
	return float64(factsCount-correct) / factsCount
}

func factTexts(facts []Fact) []string {
	texts := make([]string, 0, len(facts))
	for _, fact := range facts {
		texts = append(texts, fact.Text)
	}
	return texts
}

func factTruths(facts []Fact) []bool {
	truths := make([]bool, 0, len(facts))
	for _, fact := range facts {
		truths = append(truths, fact.True)
	}
	return truths
}

// todaysQuiz: the player's live quiz (pending or answered) for the task today, or nil.
func (tx *gameTx) todaysQuiz(taskID string) *FactsQuiz {
	quizzes := tx.me.state.FactsQuizzes
	for i := len(quizzes) - 1; i >= 0; i-- {
		quiz := &quizzes[i]
		if quiz.Day == tx.today && quiz.Task == taskID && quiz.State != "expired" {
			return quiz
		}
	}
	return nil
}

// hasFactsToday: the facts were written (or confirmed) today.
func (s *PlayerState) hasFactsToday(today int) bool {
	return s.FactsDay == today && len(s.Facts) == factsCount
}

// rpcGetFacts -> {"facts", "today", "needed"}: the player's last facts (to edit them), whether they
// were written today, and whether today's pack has an open facts task that still needs them.
func rpcGetFacts(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		state := tx.me.state
		facts := state.Facts
		if facts == nil {
			facts = []Fact{}
		}
		needed := false
		for i := range tx.content.Tasks {
			task := &tx.content.Tasks[i]
			if task.Minigame == factsMinigame && tx.isTodaysTask(task) && !tx.isClosed(task) {
				needed = true
			}
		}
		return map[string]any{"facts": facts, "today": state.hasFactsToday(tx.today), "needed": needed}, nil
	})
}

// isClosed: completed, skipped or waiting for a colleague today.
func (tx *gameTx) isClosed(task *Task) bool {
	state := tx.me.state
	return contains(dayList(state.Completed, tx.today), task.ID) ||
		contains(dayList(state.Skipped, tx.today), task.ID) ||
		contains(dayList(state.Pending, tx.today), task.ID)
}

// rpcSetFacts: {"facts": [{"text", "true"}] x5}. Saves today's facts. Once a colleague has them,
// they are locked for the day: changing the answers after the guess would be cheating.
func rpcSetFacts(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		Facts []Fact `json:"facts"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		facts, problem := normalizeFacts(request.Facts)
		if problem != "" {
			return fail(problem), nil
		}
		for i := range tx.content.Tasks {
			task := &tx.content.Tasks[i]
			if task.Minigame == factsMinigame && tx.todaysQuiz(task.ID) != nil {
				return fail("facts_locked"), nil
			}
		}
		tx.me.state.Facts = facts
		tx.me.state.FactsDay = tx.today
		return okResult, nil
	})
}

// rpcSendFacts: {"task_id"} -> {"ok", "colleague_name", "answered"}. Sends today's facts to the
// assigned colleague. Sending again to the same colleague changes nothing and tells whether they
// have answered; a new colleague (the first one left the office) gets a new request and the old
// one expires.
func rpcSendFacts(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		TaskID string `json:"task_id"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		task := tx.content.task(request.TaskID)
		if task == nil || task.Minigame != factsMinigame {
			return fail("unknown_task"), nil
		}
		if problem, err := tx.sendFactsError(task); problem != "" || err != nil {
			return fail(problem), err
		}
		partnerID := tx.me.state.Assignments[dayKey(tx.today)][task.ID]
		card, problem, err := tx.verifyColleague(partnerID, task.Assignment == "other_department")
		if problem != "" || err != nil {
			return fail(problem), err
		}
		if quiz := tx.todaysQuiz(task.ID); quiz != nil {
			if quiz.Partner == partnerID {
				return map[string]any{"ok": true, "colleague_name": card.Name, "answered": quiz.State == "answered"}, nil
			}
			if err := tx.expireQuiz(quiz); err != nil {
				return nil, err
			}
		}
		if err := tx.sendQuiz(task, partnerID); err != nil {
			return nil, err
		}
		return map[string]any{"ok": true, "colleague_name": card.Name, "answered": false}, nil
	})
}

// sendFactsError: why the facts can't go to a colleague now, or "" when they can.
func (tx *gameTx) sendFactsError(task *Task) (string, error) {
	switch {
	case !tx.isTodaysTask(task):
		return "task_not_today", nil
	case tx.isClosed(task):
		return "already_completed", nil
	case !tx.isTaken(task):
		return "task_not_taken", nil
	case !tx.me.state.hasFactsToday(tx.today):
		return "facts_missing", nil
	case tx.me.state.Assignments[dayKey(tx.today)][task.ID] == "":
		return "colleague_not_assigned", nil
	}
	if problem, err := tx.playError(); problem != "" || err != nil {
		return problem, err
	}
	if problem, err := tx.presenceError(); problem != "" || err != nil {
		return problem, err
	}
	return tx.taskTimeError(task)
}

func (tx *gameTx) sendQuiz(task *Task, partnerID string) error {
	partner, err := tx.other(partnerID)
	if err != nil {
		return err
	}
	state := tx.me.state
	quizID := randomKey()
	inboxID, err := tx.notify(partner, factsQuizKind, map[string]any{
		"from_id": tx.me.userID, "name": tx.me.displayName(), "request_id": quizID, "day": tx.today,
		"avatar": publicAvatar(tx.me.userID, state.Avatar, tx.content.Rules.AvatarTemplates),
		"facts":  factTexts(state.Facts),
	}, "pending")
	if err != nil {
		return err
	}
	state.FactsQuizzes = append(state.FactsQuizzes, FactsQuiz{
		ID: quizID, Day: tx.today, Task: task.ID, Partner: partnerID, T: tx.now, State: "pending", PartnerIn: inboxID,
	})
	if len(state.FactsQuizzes) > maxFactsQuizzes {
		state.FactsQuizzes = state.FactsQuizzes[len(state.FactsQuizzes)-maxFactsQuizzes:]
	}
	tx.logActivity(tx.me, activityFactsSent, map[string]any{"task": task.ID, "partner": partnerID})
	return nil
}

// expireQuiz closes a quiz on both sides: the player's state and the colleague's inbox item.
func (tx *gameTx) expireQuiz(quiz *FactsQuiz) error {
	quiz.State = "expired"
	partner, err := tx.other(quiz.Partner)
	if err != nil {
		return nil // the account is gone; nothing to close there
	}
	inbox, err := tx.inboxOf(partner)
	if err != nil {
		return err
	}
	for i := range inbox.Items {
		item := &inbox.Items[i]
		if item.ID == quiz.PartnerIn && item.Kind == factsQuizKind && item.State == "pending" {
			item.State = "expired"
			partner.inboxDirty = true
		}
	}
	return nil
}

// rpcAnswerFacts: {"item_id", "guesses": [bool] x5, "operation_key"} -> {"ok", "correct", "truths",
// "balance"}. The colleague's guess. It is final: the player sees the result and the truths are
// revealed to the colleague. The colleague gets a small bonus for taking part.
func rpcAnswerFacts(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request struct {
		ItemID       int    `json:"item_id"`
		Guesses      []bool `json:"guesses"`
		OperationKey string `json:"operation_key"`
	}
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.playError(); problem != "" || err != nil {
			return fail(problem), err
		}
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return fail(problem), err
		}
		claimed, err := tx.claimOperation(request.OperationKey)
		if err != nil || !claimed {
			return fail("duplicate_operation"), err
		}
		item, err := tx.pendingInboxItem(request.ItemID, factsQuizKind)
		if err != nil || item == nil {
			return fail("unknown_request"), err
		}
		if item.State != "pending" {
			return fail("request_closed"), nil
		}
		fromID, _ := item.Params["from_id"].(string)
		requestID, _ := item.Params["request_id"].(string)
		author, err := tx.other(fromID)
		if err != nil {
			return fail("request_closed"), nil
		}
		quiz := findQuiz(author.state, requestID)
		if quiz == nil || quiz.State != "pending" || quiz.Day != tx.today || !author.state.hasFactsToday(tx.today) {
			return fail("request_closed"), nil
		}
		correct, ok := scoreGuesses(author.state.Facts, request.Guesses)
		if !ok {
			return fail("guesses_invalid"), nil
		}
		truths := factTruths(author.state.Facts)
		quiz.State = "answered"
		quiz.Correct = correct
		item.State = "answered"
		item.Read = true
		item.Params["correct"] = correct
		item.Params["truths"] = truths
		item.Params["guesses"] = request.Guesses
		tx.me.inboxDirty = true
		tx.logActivity(tx.me, activityFactsAnswer, map[string]any{"from": fromID, "correct": correct})
		if _, err := tx.notify(author, "facts_answered", map[string]any{"name": tx.me.displayName(), "correct": correct}, ""); err != nil {
			return nil, err
		}
		bonus := min(tx.content.Rules.Facts.PartnerBonus, max(0, capLeft(tx.me.state, tx.today, &tx.content.Rules)))
		if bonus > 0 {
			tx.me.state.Earned[dayKey(tx.today)] += bonus
			tx.credit(tx.me, int64(bonus), "facts_partner_bonus", fromID)
		}
		return map[string]any{"ok": true, "correct": correct, "truths": truths, "balance": tx.me.balance}, nil
	})
}

// pendingInboxItem finds the caller's inbox item by id and kind; nil when there is none.
func (tx *gameTx) pendingInboxItem(itemID int, kind string) (*InboxItem, error) {
	inbox, err := tx.inboxOf(tx.me)
	if err != nil {
		return nil, err
	}
	for i := range inbox.Items {
		if inbox.Items[i].ID == itemID && inbox.Items[i].Kind == kind {
			return &inbox.Items[i], nil
		}
	}
	return nil, nil
}

func findQuiz(state *PlayerState, id string) *FactsQuiz {
	for i := range state.FactsQuizzes {
		if state.FactsQuizzes[i].ID == id {
			return &state.FactsQuizzes[i]
		}
	}
	return nil
}

// verifyFacts: the scanned colleague is the assigned one, still a valid partner, and has answered.
func (tx *gameTx) verifyFacts(task *Task, proof taskProof) (string, error) {
	if proof.ColleagueID == "" || proof.ColleagueID != tx.me.state.Assignments[dayKey(tx.today)][task.ID] {
		return "colleague_not_assigned", nil
	}
	if _, problem, err := tx.verifyMetColleague(proof.ColleagueID, task.Assignment == "other_department"); problem != "" || err != nil {
		return problem, err
	}
	quiz := tx.todaysQuiz(task.ID)
	if quiz == nil || quiz.Partner != proof.ColleagueID {
		return "facts_not_sent", nil
	}
	if quiz.State != "answered" {
		return "facts_not_answered", nil
	}
	return "", nil
}

// factsQuizScore: the server's score of today's answered quiz for the task.
func (tx *gameTx) factsQuizScore(task *Task) float64 {
	quiz := tx.todaysQuiz(task.ID)
	if quiz == nil {
		return 0
	}
	return factsScore(quiz.Correct)
}

// expireFactsQuizzes ends quizzes of past days on the player's side; the inbox side expires in
// expirePhotoRequests together with photo requests.
func (tx *gameTx) expireFactsQuizzes() {
	for i := range tx.me.state.FactsQuizzes {
		quiz := &tx.me.state.FactsQuizzes[i]
		if quiz.Day != tx.today && (quiz.State == "pending" || quiz.State == "answered") {
			quiz.State = "expired"
		}
	}
}
