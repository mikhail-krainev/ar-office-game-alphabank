class_name BackendClicker
extends Node
## Cat clicker: taps, upgrades, rebirth and the leaderboard. Points are counted only by the server;
## they never become wallet coins.

var _backend: BackendService


func _init(backend: BackendService) -> void:
	_backend = backend
	name = "Clicker"


## action: get, sync, buy or rebirth. `seq` above the last applied one makes the request count once.
func send(action_name: String, seq: int, taps: int, extra: Dictionary = {}) -> Dictionary:
	var data: Dictionary = extra.duplicate(true)
	data["action"] = action_name
	data["seq"] = seq
	data["taps"] = taps
	data["open"] = data.get("open", true)
	var response: ServerSession.RpcResult = await _backend.call_rpc("clicker", data)
	if not response.ok:
		return {"ok": false, "error": response.error}
	return response.data


func top() -> Dictionary:
	var response: ServerSession.RpcResult = await _backend.call_rpc("clicker_top", {})
	if not response.ok:
		return {"ok": false, "error": response.error}
	return response.data
