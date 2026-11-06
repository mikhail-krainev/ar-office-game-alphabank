package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/rtapi"
	"github.com/heroiclabs/nakama-common/runtime"
)

// In-game chat: the office chat (everyone who counts in the player's office today), the department
// chat (the player's department of today) and direct messages. Messages live in Nakama's channel
// message table, but players reach them only through these RPCs: the realtime chat API and the REST
// message list are closed (registerChatHooks), so the office network check and the office rules
// always apply. Like every game RPC, chat works only from the office Wi-Fi. Messages are kept for
// chatRetention; the admin deletes office and department messages from the panel.

const (
	chatOffice     = "office"
	chatDepartment = "department"
	chatDirect     = "direct"

	chatCollection   = "chat"
	chatReadKey      = "read"
	chatDirectKey    = "direct"
	chatRetention    = 7 * 24 * time.Hour
	chatHistoryLimit = 100
	chatMaxText      = 500
	// A player sends at most one message per this interval.
	chatSendInterval = time.Second
	// Old messages are deleted at most once per this interval, on a send.
	chatCleanupInterval = time.Hour
	// Direct conversations shown in the overview, the most recent first.
	chatMaxDirect  = 20
	chatWriteTries = 3
)

var (
	errChatText            = runtime.NewError("chat_text_invalid", codeInvalidArgument)
	errChatTooFast         = runtime.NewError("chat_too_fast", codeResourceExhausted)
	errChatNoChannel       = runtime.NewError("chat_no_channel", codeInvalidArgument)
	errChatRecipient       = runtime.NewError("chat_recipient_unavailable", codeNotFound)
	errChatMessageNotFound = runtime.NewError("chat_message_not_found", codeNotFound)

	chatLastSend    sync.Map // user id -> time.Time of the last message
	chatLastCleanup atomic.Int64
)

type chatMessageView struct {
	ID       string `json:"id"`
	SenderID string `json:"sender_id"`
	Name     string `json:"name"`
	Text     string `json:"text"`
	At       int64  `json:"at"`
	Mine     bool   `json:"mine"`
}

type chatContent struct {
	Text string `json:"text"`
	Name string `json:"name"`
}

type chatRequest struct {
	Channel string `json:"channel"`
	UserID  string `json:"user_id"`
	Text    string `json:"text"`
}

// --- Channels ----------------------------------------------------------------------

// chatChannelID: the Nakama channel of a request for this player, checking who may use it.
func (tx *gameTx) chatChannelID(kind, otherID string) (string, error) {
	switch kind {
	case chatOffice:
		return tx.nk.ChannelIdBuild(tx.ctx, "", "office."+tx.office(), runtime.Room)
	case chatDepartment:
		if tx.department() == "" {
			return "", errChatNoChannel
		}
		return tx.nk.ChannelIdBuild(tx.ctx, "", "department."+tx.department(), runtime.Room)
	case chatDirect:
		if !isUUID(otherID) || otherID == tx.me.userID {
			return "", errChatRecipient
		}
		return tx.nk.ChannelIdBuild(tx.ctx, tx.me.userID, otherID, runtime.DirectMessage)
	}
	return "", errChatNoChannel
}

// chatRecipient: the public card of the person a direct message goes to. Colleagues of the player's
// office today are reachable, and so is anyone the player already has a conversation with.
func (tx *gameTx) chatRecipient(otherID string, partners map[string]int64) (*publicPlayer, error) {
	players, err := readPlayers(tx.ctx, tx.nk, []string{otherID}, tx.today)
	if err != nil {
		return nil, err
	}
	player, ok := players[otherID]
	if !ok {
		return nil, errChatRecipient
	}
	if _, known := partners[otherID]; !known && player.office != tx.office() {
		return nil, errChatRecipient
	}
	return &player, nil
}

// --- Per-player storage: read marks and the list of direct conversations ------------------

func readChatMap(ctx context.Context, nk runtime.NakamaModule, userID, key string) (map[string]int64, string, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: chatCollection, Key: key, UserID: userID}})
	if err != nil {
		return nil, "", errInternal
	}
	values := map[string]int64{}
	if len(objects) == 0 {
		return values, "*", nil
	}
	if json.Unmarshal([]byte(objects[0].GetValue()), &values) != nil {
		values = map[string]int64{}
	}
	return values, objects[0].GetVersion(), nil
}

// updateChatMap changes one per-player map with a version check, retrying on a conflict.
func updateChatMap(ctx context.Context, nk runtime.NakamaModule, userID, key string, change func(map[string]int64)) error {
	for try := 0; ; try++ {
		values, version, err := readChatMap(ctx, nk, userID, key)
		if err != nil {
			return err
		}
		change(values)
		raw, err := json.Marshal(values)
		if err != nil {
			return errInternal
		}
		_, err = nk.StorageWrite(ctx, []*runtime.StorageWrite{{
			Collection: chatCollection, Key: key, UserID: userID, Value: string(raw), Version: version,
			PermissionRead: permissionNone, PermissionWrite: permissionNone,
		}})
		if err == nil {
			return nil
		}
		if try+1 >= chatWriteTries {
			return errInternal
		}
	}
}

// rememberDirect puts the conversation on top of both players' lists, keeping chatMaxDirect.
func rememberDirect(ctx context.Context, nk runtime.NakamaModule, userID, otherID string, at int64) error {
	return updateChatMap(ctx, nk, userID, chatDirectKey, func(partners map[string]int64) {
		partners[otherID] = at
		for len(partners) > chatMaxDirect {
			oldest, oldestAt := "", int64(0)
			for id, seen := range partners {
				if oldest == "" || seen < oldestAt {
					oldest, oldestAt = id, seen
				}
			}
			delete(partners, oldest)
		}
	})
}

func markChatRead(ctx context.Context, nk runtime.NakamaModule, userID, channelID string, at int64) error {
	return updateChatMap(ctx, nk, userID, chatReadKey, func(marks map[string]int64) {
		if marks[channelID] < at {
			marks[channelID] = at
		}
	})
}

// --- Messages ------------------------------------------------------------------------

// cleanChatText trims the message, turns line breaks into spaces and drops control characters.
func cleanChatText(text string) (string, error) {
	text = strings.Map(func(r rune) rune {
		switch {
		case r == '\n' || r == '\r' || r == '\t':
			return ' '
		case unicode.IsControl(r) || r == utf8.RuneError:
			return -1
		}
		return r
	}, text)
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > chatMaxText {
		return "", errChatText
	}
	return text, nil
}

// chatHistory: the channel's messages of the retention period, oldest first.
func chatHistory(ctx context.Context, nk runtime.NakamaModule, channelID, me string) ([]chatMessageView, error) {
	messages, _, _, err := nk.ChannelMessagesList(ctx, channelID, chatHistoryLimit, false, "")
	if err != nil {
		return nil, errInternal
	}
	cutoff := time.Now().Add(-chatRetention).Unix()
	views := make([]chatMessageView, 0, len(messages))
	for _, message := range messages {
		view, ok := chatView(message, me)
		if ok && view.At >= cutoff {
			views = append(views, view)
		}
	}
	sort.SliceStable(views, func(i, j int) bool { return views[i].At < views[j].At })
	return views, nil
}

func chatView(message *api.ChannelMessage, me string) (chatMessageView, bool) {
	var content chatContent
	if json.Unmarshal([]byte(message.GetContent()), &content) != nil || content.Text == "" {
		return chatMessageView{}, false
	}
	return chatMessageView{
		ID: message.GetMessageId(), SenderID: message.GetSenderId(), Name: content.Name, Text: content.Text,
		At: message.GetCreateTime().GetSeconds(), Mine: message.GetSenderId() == me,
	}, true
}

type chatChannelSummary struct {
	Kind   string           `json:"kind"`
	UserID string           `json:"user_id,omitempty"`
	Name   string           `json:"name"`
	Avatar string           `json:"avatar,omitempty"`
	Unread int              `json:"unread"`
	Last   *chatMessageView `json:"last"`
}

// summarize: the last message and the number of colleagues' messages after the read mark.
func chatSummarize(ctx context.Context, nk runtime.NakamaModule, channelID, me string, readAt int64, summary *chatChannelSummary) error {
	history, err := chatHistory(ctx, nk, channelID, me)
	if err != nil {
		return err
	}
	for i := range history {
		if !history[i].Mine && history[i].At > readAt {
			summary.Unread++
		}
	}
	if len(history) > 0 {
		summary.Last = &history[len(history)-1]
	}
	return nil
}

// cleanupChat deletes room and direct messages older than the retention period, at most once per
// chatCleanupInterval.
func cleanupChat(ctx context.Context, logger runtime.Logger, db *sql.DB) {
	now := time.Now()
	last := chatLastCleanup.Load()
	if now.Unix()-last < int64(chatCleanupInterval.Seconds()) || !chatLastCleanup.CompareAndSwap(last, now.Unix()) {
		return
	}
	// Stream modes of Nakama: 2 = room channel, 4 = direct messages.
	result, err := db.ExecContext(ctx, `DELETE FROM message WHERE stream_mode IN (2, 4) AND create_time < $1`, now.Add(-chatRetention))
	if err != nil {
		logger.Error("chat cleanup: %v", err)
		return
	}
	if removed, _ := result.RowsAffected(); removed > 0 {
		logger.Info("chat cleanup: %d old messages deleted", removed)
	}
}

// --- Player RPCs ----------------------------------------------------------------------

// runChatCall loads the calling player without a game transaction: chat never changes the game
// state, so nothing is committed and nothing is retried (a retry would post a message twice).
func runChatCall(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, fn func(tx *gameTx) (any, error)) (string, error) {
	userID, err := callerID(ctx)
	if err != nil {
		return "", err
	}
	tx, err := newGameTx(ctx, logger, db, nk, userID)
	if err != nil {
		return "", err
	}
	if tx.me.metadata.Role != rolePlayer {
		return "", errNotPlayer
	}
	if tx.me.banned() {
		return "", errUnauthenticated
	}
	result, err := fn(tx)
	if err != nil {
		return "", err
	}
	return encodeResponse(result)
}

// rpcChatOverview: -> {"office", "department", "direct": [chatChannelSummary]}. The chats of the
// player with their unread counts; "department" is null for a player without a department.
func rpcChatOverview(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runChatCall(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		marks, _, err := readChatMap(tx.ctx, tx.nk, tx.me.userID, chatReadKey)
		if err != nil {
			return nil, err
		}
		result := map[string]any{"department": nil}
		office, err := tx.currentOffice()
		if err != nil {
			return nil, err
		}
		officeSummary := &chatChannelSummary{Kind: chatOffice}
		if office != nil {
			officeSummary.Name = office.Name
		}
		if err := tx.summarizeChat(chatOffice, "", marks, officeSummary); err != nil {
			return nil, err
		}
		result["office"] = officeSummary
		if tx.department() != "" {
			department := &chatChannelSummary{Kind: chatDepartment, Name: tx.departmentName()}
			if err := tx.summarizeChat(chatDepartment, "", marks, department); err != nil {
				return nil, err
			}
			result["department"] = department
		}
		direct, err := tx.directSummaries(marks)
		if err != nil {
			return nil, err
		}
		result["direct"] = direct
		return result, nil
	})
}

func (tx *gameTx) summarizeChat(kind, otherID string, marks map[string]int64, summary *chatChannelSummary) error {
	channelID, err := tx.chatChannelID(kind, otherID)
	if err != nil {
		return err
	}
	return chatSummarize(tx.ctx, tx.nk, channelID, tx.me.userID, marks[channelID], summary)
}

// directSummaries: the player's conversations, the most recent first.
func (tx *gameTx) directSummaries(marks map[string]int64) ([]chatChannelSummary, error) {
	partners, _, err := readChatMap(tx.ctx, tx.nk, tx.me.userID, chatDirectKey)
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(partners))
	for id := range partners {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return partners[ids[i]] > partners[ids[j]] })
	players, err := readPlayers(tx.ctx, tx.nk, ids, tx.today)
	if err != nil {
		return nil, err
	}
	summaries := []chatChannelSummary{}
	for _, id := range ids {
		player, ok := players[id]
		if !ok {
			// A deleted account or one that is no longer a player.
			continue
		}
		summary := chatChannelSummary{
			Kind: chatDirect, UserID: id, Name: player.name,
			Avatar: publicAvatar(id, player.avatar, tx.content.Rules.AvatarTemplates),
		}
		if err := tx.summarizeChat(chatDirect, id, marks, &summary); err != nil {
			return nil, err
		}
		summaries = append(summaries, summary)
	}
	return summaries, nil
}

// departmentName: the name of the player's department of today, or its id when it is gone.
func (tx *gameTx) departmentName() string {
	department, err := findOfficeDepartment(tx.ctx, tx.nk, tx.office(), tx.department())
	if err != nil {
		return tx.department()
	}
	return department.Name
}

// rpcChatHistory: {"channel", "user_id" for "direct"} -> {"messages": [chatMessageView]}, oldest
// first. Marks the chat read.
func rpcChatHistory(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request chatRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	return runChatCall(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		channelID, err := tx.chatChannelID(request.Channel, request.UserID)
		if err != nil {
			return nil, err
		}
		history, err := chatHistory(tx.ctx, tx.nk, channelID, tx.me.userID)
		if err != nil {
			return nil, err
		}
		if len(history) > 0 {
			if err := markChatRead(tx.ctx, tx.nk, tx.me.userID, channelID, history[len(history)-1].At); err != nil {
				return nil, err
			}
		}
		return map[string]any{"messages": history}, nil
	})
}

// rpcChatSend: {"channel", "user_id" for "direct", "text"} -> {"message": chatMessageView}.
func rpcChatSend(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var request chatRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	text, err := cleanChatText(request.Text)
	if err != nil {
		return "", err
	}
	return runChatCall(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		channelID, err := tx.chatChannelID(request.Channel, request.UserID)
		if err != nil {
			return nil, err
		}
		if request.Channel == chatDirect {
			partners, _, err := readChatMap(tx.ctx, tx.nk, tx.me.userID, chatDirectKey)
			if err != nil {
				return nil, err
			}
			if _, err := tx.chatRecipient(request.UserID, partners); err != nil {
				return nil, err
			}
		}
		now := time.Now()
		if last, ok := chatLastSend.Load(tx.me.userID); ok && now.Sub(last.(time.Time)) < chatSendInterval {
			return nil, errChatTooFast
		}
		chatLastSend.Store(tx.me.userID, now)
		name := tx.me.account.GetUser().GetDisplayName()
		content := map[string]any{"text": text, "name": name}
		ack, err := tx.nk.ChannelMessageSend(tx.ctx, channelID, content, tx.me.userID, tx.me.account.GetUser().GetUsername(), true)
		if err != nil {
			tx.logger.Error("chat send by %s: %v", tx.me.userID, err)
			return nil, errInternal
		}
		at := ack.GetCreateTime().GetSeconds()
		if request.Channel == chatDirect {
			if err := rememberDirect(tx.ctx, tx.nk, tx.me.userID, request.UserID, at); err != nil {
				return nil, err
			}
			if err := rememberDirect(tx.ctx, tx.nk, request.UserID, tx.me.userID, at); err != nil {
				return nil, err
			}
		}
		if err := markChatRead(tx.ctx, tx.nk, tx.me.userID, channelID, at); err != nil {
			return nil, err
		}
		cleanupChat(tx.ctx, tx.logger, tx.db)
		message := chatMessageView{ID: ack.GetMessageId(), SenderID: tx.me.userID, Name: name, Text: text, At: at, Mine: true}
		return map[string]any{"message": message}, nil
	})
}

// --- Admin RPCs ---------------------------------------------------------------------

type adminChatRequest struct {
	OfficeID     string `json:"office_id"`
	DepartmentID string `json:"department_id"`
	MessageID    string `json:"message_id"`
}

// roomChannel: the office chat, or the department chat when "department_id" is set. Direct
// messages stay private: the admin never reads them.
func (r adminChatRequest) roomChannel(ctx context.Context, nk runtime.NakamaModule) (string, error) {
	if _, err := findOffice(ctx, nk, r.OfficeID); err != nil {
		return "", err
	}
	if r.DepartmentID == "" {
		return nk.ChannelIdBuild(ctx, "", "office."+r.OfficeID, runtime.Room)
	}
	if _, err := findOfficeDepartment(ctx, nk, r.OfficeID, r.DepartmentID); err != nil {
		return "", err
	}
	return nk.ChannelIdBuild(ctx, "", "department."+r.DepartmentID, runtime.Room)
}

// rpcAdminChatMessages: {"office_id", "department_id"?} -> {"messages": [chatMessageView]}.
func rpcAdminChatMessages(ctx context.Context, _ runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request adminChatRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	channelID, err := request.roomChannel(ctx, nk)
	if err != nil {
		return "", err
	}
	history, err := chatHistory(ctx, nk, channelID, "")
	if err != nil {
		return "", err
	}
	return encodeResponse(map[string]any{"messages": history})
}

// rpcAdminChatDelete: {"office_id", "department_id"?, "message_id"} -> {}. Removes one message.
func rpcAdminChatDelete(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := requireAdmin(ctx, nk); err != nil {
		return "", err
	}
	var request adminChatRequest
	if err := decodePayload(payload, &request); err != nil {
		return "", err
	}
	if !isUUID(request.MessageID) {
		return "", errInvalidPayload
	}
	channelID, err := request.roomChannel(ctx, nk)
	if err != nil {
		return "", err
	}
	// Nakama removes a message only on behalf of its sender.
	history, err := chatHistory(ctx, nk, channelID, "")
	if err != nil {
		return "", err
	}
	senderID := ""
	for _, message := range history {
		if message.ID == request.MessageID {
			senderID = message.SenderID
		}
	}
	if senderID == "" {
		return "", errChatMessageNotFound
	}
	if _, err := nk.ChannelMessageRemove(ctx, channelID, request.MessageID, senderID, "", true); err != nil {
		logger.Error("delete chat message %s: %v", request.MessageID, err)
		return "", errInternal
	}
	adminID, _ := callerID(ctx)
	logger.Info("admin %s deleted chat message %s in %s", adminID, request.MessageID, channelID)
	return encodeResponse(map[string]any{})
}

// --- Closing Nakama's own chat API -----------------------------------------------------

var errChatClosed = runtime.NewError("chat_through_rpc_only", codePermissionDenied)

// registerChatHooks closes the realtime chat and the REST message list: players chat only through
// the RPCs above, which check the office network and who may read a channel.
func registerChatHooks(initializer runtime.Initializer) error {
	for _, id := range []string{"ChannelJoin", "ChannelLeave", "ChannelMessageSend", "ChannelMessageUpdate", "ChannelMessageRemove"} {
		if err := initializer.RegisterBeforeRt(id, func(context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule, *rtapi.Envelope) (*rtapi.Envelope, error) {
			return nil, errChatClosed
		}); err != nil {
			return err
		}
	}
	return initializer.RegisterBeforeListChannelMessages(func(context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule, *api.ListChannelMessagesRequest) (*api.ListChannelMessagesRequest, error) {
		return nil, errChatClosed
	})
}
