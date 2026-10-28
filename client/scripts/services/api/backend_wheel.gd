class_name BackendWheel
extends Node
## Server API of the fortune wheel (Backend.wheel): today's sectors, the spin and the exchange of a
## win that could not be given. The server picks the sector; the client only animates it.

const CHOICE_RESPIN: String = "respin"
const CHOICE_COINS: String = "coins"

var _backend: BackendService


func _init(backend: BackendService) -> void:
	name = "Wheel"
	_backend = backend


func get_wheel() -> BackendModels.WheelState:
	var response: ServerSession.RpcResult = await _backend.call_rpc("get_wheel")
	return BackendParser.wheel(response.data)


func spin() -> BackendModels.SpinResult:
	var payload: Dictionary = {"operation_key": _backend.operation_key()}
	var response: ServerSession.RpcResult = await _backend.call_rpc("spin_wheel", payload)
	var result: BackendModels.SpinResult = BackendParser.spin(response.data, response.error)
	_backend.apply_balance(result.balance)
	return result


## `choice`: CHOICE_RESPIN (the spin back) or CHOICE_COINS (the item's price in coins).
func resolve(choice: String) -> BackendModels.SpinResult:
	var payload: Dictionary = {"choice": choice, "operation_key": _backend.operation_key()}
	var response: ServerSession.RpcResult = await _backend.call_rpc("resolve_wheel", payload)
	var result: BackendModels.SpinResult = BackendParser.spin(response.data, response.error)
	_backend.apply_balance(result.balance)
	return result
