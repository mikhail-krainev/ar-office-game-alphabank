class_name BackendChat
extends Node
## Server API of the in-game chat (Backend.chat): the office chat, the department chat and direct
## messages (server/modules/chat.go). Like the rest of the office game, it works only in the office
## Wi-Fi; the server keeps messages for a week.

## Unread messages in all chats changed (the HUD badge).
signal unread_changed(count: int)

const OFFICE: String = "office"
const DEPARTMENT: String = "department"
const DIRECT: String = "direct"
const MAX_TEXT: int = 500

## Unread messages in all chats at the last overview.
var unread: int = 0

var _backend: BackendService


class Message:
	extends RefCounted

	var id: String = ""
	var sender_id: String = ""
	var name: String = ""
	var text: String = ""
	var at: int = 0
	var mine: bool = false


## One chat in the list: its kind, the colleague for a direct chat, unread count and last message.
class Channel:
	extends RefCounted

	var kind: String = ""
	var user_id: String = ""
	var name: String = ""
	var avatar: String = ""
	var unread: int = 0
	var last: Message


class Overview:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var office: Channel
	## null for a player without a department.
	var department: Channel
	var direct: Array[Channel] = []

	func total_unread() -> int:
		var total: int = 0
		for channel: Channel in [office, department] + direct:
			if channel != null:
				total += channel.unread
		return total


class History:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var messages: Array[Message] = []


class Sent:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var message: Message


func _init(backend: BackendService) -> void:
	name = "Chat"
	_backend = backend


func overview() -> Overview:
	var response: ServerSession.RpcResult = await _backend.call_rpc("chat_overview")
	var result: Overview = Overview.new()
	result.ok = response.ok
	result.error = response.error
	if not response.ok:
		return result
	result.office = _channel(response.data.get("office"))
	result.department = _channel(response.data.get("department"))
	var direct: Variant = response.data.get("direct")
	if direct is Array:
		for entry: Variant in direct:
			var channel: Channel = _channel(entry)
			if channel != null:
				result.direct.append(channel)
	_set_unread(result.total_unread())
	return result


## The chat's messages, oldest first; the server marks the chat read.
func history(kind: String, user_id: String = "") -> History:
	var response: ServerSession.RpcResult = await _backend.call_rpc(
		"chat_history", {"channel": kind, "user_id": user_id}
	)
	var result: History = History.new()
	result.ok = response.ok
	result.error = response.error
	var messages: Variant = response.data.get("messages")
	if messages is Array:
		for entry: Variant in messages:
			var message: Message = _message(entry)
			if message != null:
				result.messages.append(message)
	return result


func send(kind: String, user_id: String, text: String) -> Sent:
	var payload: Dictionary = {"channel": kind, "user_id": user_id, "text": text}
	var response: ServerSession.RpcResult = await _backend.call_rpc("chat_send", payload)
	var result: Sent = Sent.new()
	result.error = response.error
	result.message = _message(response.data.get("message"))
	result.ok = response.ok and result.message != null
	return result


## The badge drops once the player opened the chats.
func mark_seen(count: int) -> void:
	_set_unread(maxi(0, unread - count))


func _set_unread(count: int) -> void:
	if count != unread:
		unread = count
		unread_changed.emit(count)


func _channel(entry: Variant) -> Channel:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var channel: Channel = Channel.new()
	channel.kind = str(data.get("kind", ""))
	channel.user_id = str(data.get("user_id", ""))
	channel.name = str(data.get("name", ""))
	channel.avatar = str(data.get("avatar", ""))
	channel.unread = int(data.get("unread", 0))
	channel.last = _message(data.get("last"))
	return channel


func _message(entry: Variant) -> Message:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var message: Message = Message.new()
	message.id = str(data.get("id", ""))
	message.sender_id = str(data.get("sender_id", ""))
	message.name = str(data.get("name", ""))
	message.text = str(data.get("text", ""))
	message.at = int(data.get("at", 0))
	message.mine = bool(data.get("mine", false))
	return message
