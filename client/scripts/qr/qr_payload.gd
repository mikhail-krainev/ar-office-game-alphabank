class_name QrPayload
extends RefCounted
## Game QR codes. Four kinds share one URI scheme:
##   alfaoffice://room/<room_id>        static code at a room door; counts only inside the office
##   alfaoffice://presence/<token>      rotating entry code on the office screen, proof of presence
##   alfaoffice://checkout/<token>      rotating exit code on the office screen
##   alfaoffice://user/<code>           "My QR" on a colleague's phone: "<user id>.<step>.<signature>",
##                                      rotates every 10 s, only the server can make and check it
## Wi-Fi join codes are infrastructure and are not parsed by the game.

enum Kind { UNKNOWN, ROOM, PRESENCE, USER, CHECKOUT }

const SCHEME: String = "alfaoffice://"
const KIND_NAMES: Dictionary[Kind, String] = {
	Kind.ROOM: "room", Kind.PRESENCE: "presence", Kind.USER: "user", Kind.CHECKOUT: "checkout",
}
const MAX_VALUE_LENGTH: int = 128

var kind: Kind = Kind.UNKNOWN
var value: String = ""


static func parse(text: String) -> QrPayload:
	var payload: QrPayload = QrPayload.new()
	var trimmed: String = text.strip_edges()
	if not trimmed.to_lower().begins_with(SCHEME):
		return payload
	var parts: PackedStringArray = trimmed.substr(SCHEME.length()).split("/", false)
	if parts.size() != 2 or parts[1].length() > MAX_VALUE_LENGTH or not _is_safe(parts[1]):
		return payload
	for candidate: Kind in KIND_NAMES:
		if KIND_NAMES[candidate] == parts[0].to_lower():
			payload.kind = candidate
			payload.value = parts[1]
	return payload


static func make(payload_kind: Kind, payload_value: String) -> String:
	return "%s%s/%s" % [SCHEME, KIND_NAMES[payload_kind], payload_value]


static func room(room_id: String) -> String:
	return make(Kind.ROOM, room_id)


static func user(code: String) -> String:
	return make(Kind.USER, code)


## User id inside a "My QR" code, for early feedback such as "that's your own code". Only the server
## can tell whether the code is genuine and fresh.
static func user_id_of(code: String) -> String:
	return code.get_slice(".", 0)


static func presence(token: String) -> String:
	return make(Kind.PRESENCE, token)


static func checkout(token: String) -> String:
	return make(Kind.CHECKOUT, token)


func is_valid() -> bool:
	return kind != Kind.UNKNOWN


static func _is_safe(text: String) -> bool:
	for character: String in text:
		var code: int = character.unicode_at(0)
		var allowed: bool = (
			(code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)
			or character == "_" or character == "-" or character == "."
		)
		if not allowed:
			return false
	return not text.is_empty()
