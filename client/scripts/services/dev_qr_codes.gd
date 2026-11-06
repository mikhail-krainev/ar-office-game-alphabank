class_name DevQrCodes
extends RefCounted
## DEV-ONLY: codes the desktop sensor emulator can "show" to the camera. The entry and exit codes
## and the other players come from the dev RPCs of a server running with DEV_MODE=true; the secret
## that signs the codes never leaves the server.

## [label, QR text] pairs from the last refresh().
static var _entries: Array[Array] = []


## Reloads the list: fresh office screen codes (they rotate every 30 s) and the players.
static func refresh() -> void:
	var result: Array[Array] = []
	var codes: ServerSession.RpcResult = await Backend.dev_call("dev_presence_codes")
	if codes.ok:
		result.append(["office IN", QrPayload.presence(str(codes.data.get("entry", "")))])
		result.append(["office OUT", QrPayload.checkout(str(codes.data.get("exit", "")))])
	for floor_id: StringName in OfficeFloors.ORDER:
		for room: MapLayout.Room in OfficeFloors.layout(floor_id).rooms:
			result.append(["room " + room.id, QrPayload.room(room.id)])
	# Other players' "My QR" codes; "*" marks who is in the office now.
	var players: ServerSession.RpcResult = await Backend.dev_call("dev_list_players")
	for player: Variant in players.data.get("players", []):
		if player is Dictionary:
			var card: Dictionary = player
			var label: String = str(card.get("name", "?")) + ("*" if bool(card.get("present", false)) else "")
			result.append([label, QrPayload.user(str(card.get("code", "")))])
	result.append(["expired", QrPayload.presence("hq.1.00000000000000000000")])
	result.append(["wifi", "WIFI:S:Guest;T:WPA;P:example;;"])
	_entries = result


static func suggestions() -> Array[Array]:
	return _entries


## Text of the entry at `index` with rotating codes refreshed first, so a pressed code is never stale:
## the office codes rotate every 30 s, the players' "My QR" every 10 s.
static func fresh_text(index: int) -> String:
	var label: String = str(_entries[index][0]) if index < _entries.size() else ""
	if not label.begins_with("room") and label not in ["expired", "wifi"]:
		await refresh()
	for entry: Array in _entries:
		if str(entry[0]) == label:
			return str(entry[1])
	return ""
