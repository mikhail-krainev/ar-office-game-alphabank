class_name BackendSocial
extends Node
## Server API about other players (Backend.social): colleagues picked for tasks, profile-code
## lookups, joint photo confirmations, "Three truths, two lies" and the inbox.

var _backend: BackendService


func _init(backend: BackendService) -> void:
	name = "Social"
	_backend = backend


## Colleague the server picked for a task (joint photo, blind coffee). Only players in the office now.
func assign_colleague(task_id: String) -> BackendModels.ColleagueResult:
	var response: ServerSession.RpcResult = await _backend.call_rpc("assign_colleague", {"task_id": task_id})
	return BackendParser.colleague_result(response.data, response.error)


## Public card of the player behind a scanned "My QR" code. The server accepts only a live code and
## remembers the scan for today's tasks; an expired or foreign code comes back with an error.
func lookup_colleague(code: String) -> BackendModels.ColleagueResult:
	var response: ServerSession.RpcResult = await _backend.call_rpc("lookup_colleague", {"code": code})
	var result: BackendModels.ColleagueResult = BackendModels.ColleagueResult.new()
	result.error = response.error if not response.error.is_empty() else str(response.data.get("error", ""))
	if bool(response.data.get("found", false)) and response.data.get("colleague") is Dictionary:
		result.colleague = BackendParser.colleague(response.data["colleague"])
	result.ok = result.colleague != null
	if not result.ok and result.error.is_empty():
		result.error = "colleague_invalid"
	return result


## The player's current "My QR" code: {"code", "expires_in"} (seconds until it rotates), or an error.
func my_colleague_code() -> ServerSession.RpcResult:
	return await _backend.call_rpc("my_colleague_code")


## Newest first. Other players' actions (a confirmed photo, a draw) may have changed the balance.
func get_inbox() -> Array[BackendModels.InboxItem]:
	var response: ServerSession.RpcResult = await _backend.call_rpc("get_inbox")
	if response.ok:
		_backend.apply_balance(int(response.data.get("balance", -1)))
	return BackendParser.inbox(response.data)


func mark_inbox_read() -> void:
	await _backend.call_rpc("mark_inbox_read")


## Answer to "<colleague> took a photo with you. Is it true?".
func respond_photo_request(item_id: int, confirm: bool) -> BackendModels.ActionResult:
	var payload: Dictionary = {"item_id": item_id, "confirm": confirm, "operation_key": _backend.operation_key()}
	var response: ServerSession.RpcResult = await _backend.call_rpc("respond_photo_request", payload)
	_backend.apply_balance(int(response.data.get("balance", -1)))
	return BackendParser.action(response.data, response.error)


## The player's facts for "Three truths, two lies" and whether today's pack still needs them.
func get_facts() -> BackendModels.FactsState:
	var response: ServerSession.RpcResult = await _backend.call_rpc("get_facts")
	return BackendParser.facts_state(response.data, response.error)


## Saves today's five facts (three true). Locked once a colleague has them.
func set_facts(facts: Array[BackendModels.Fact]) -> BackendModels.ActionResult:
	var payload: Array[Dictionary] = []
	for fact: BackendModels.Fact in facts:
		payload.append(fact.to_dict())
	var response: ServerSession.RpcResult = await _backend.call_rpc("set_facts", {"facts": payload})
	return BackendParser.action(response.data, response.error)


## Sends today's facts (without the answers) to the colleague the server assigned for the task.
## Sending again to the same colleague only tells whether they have answered.
func send_facts(task_id: String) -> BackendModels.FactsSent:
	var response: ServerSession.RpcResult = await _backend.call_rpc("send_facts", {"task_id": task_id})
	var result: BackendModels.FactsSent = BackendModels.FactsSent.new()
	result.ok = response.error.is_empty() and bool(response.data.get("ok", false))
	result.error = response.error if not response.error.is_empty() else str(response.data.get("error", ""))
	result.answered = bool(response.data.get("answered", false))
	return result


## The guess about a colleague's facts: true = "this one is true". Exactly three must be true.
func answer_facts(item_id: int, guesses: Array[bool]) -> BackendModels.FactsAnswer:
	var payload: Dictionary = {"item_id": item_id, "guesses": guesses, "operation_key": _backend.operation_key()}
	var response: ServerSession.RpcResult = await _backend.call_rpc("answer_facts", payload)
	_backend.apply_balance(int(response.data.get("balance", -1)))
	return BackendParser.facts_answer(response.data, response.error)
