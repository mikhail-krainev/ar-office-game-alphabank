class_name BackendLounge
extends Node
## Shared rooms, loans and department exercise. All balances and hidden information come from Nakama.

var _backend: BackendService


func _init(backend: BackendService) -> void:
	_backend = backend
	name = "Lounge"


func request(rpc: String, payload: Dictionary = {}, mutate: bool = false) -> Dictionary:
	var data: Dictionary = payload.duplicate(true)
	if mutate:
		data["operation_key"] = _backend.operation_key()
	var response: ServerSession.RpcResult = await _backend.call_rpc(rpc, data)
	if not response.ok:
		return {"ok": false, "error": response.error}
	var result: Dictionary = response.data
	_backend.apply_balance(int(result.get("balance", -1)))
	return result


## Colleagues in the office now whom the player can invite to a joint task: {"ok", "people", "room"}.
func coop_people(task_id: String) -> Dictionary:
	return await request("task_coop_people", {"task_id": task_id})


## Invites a colleague to the player's room for a joint task: {"ok", "error", "room"}.
func invite(task_id: String, colleague_id: String) -> Dictionary:
	return await request("task_invite", {"task_id": task_id, "colleague_id": colleague_id}, true)


func action(action_name: String, room: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = extra.duplicate(true)
	payload["action"] = action_name
	payload["room_id"] = str(room.get("id", ""))
	payload["revision"] = int(room.get("revision", 0))
	return await request("lounge_action", payload, action_name != "get")
