class_name ServerSession
extends Node
## Connection to the Nakama server: sign-in with the username and password the admin issued, the
## saved session (it lives 7 days, then the player signs in again) and RPC calls.
## Accounts are created only in the admin panel; the server refuses self-registration.

## The session is gone (expired, signed out elsewhere, account blocked): show the sign-in form.
signal session_lost

## Stable error keys for the UI (see LOGIN_ERROR_* strings).
const ERROR_INVALID_CREDENTIALS: String = "invalid_credentials"
const ERROR_BLOCKED: String = "blocked"
const ERROR_NETWORK: String = "network"
const ERROR_SESSION: String = "unauthenticated"
const ERROR_SERVER: String = "server"

const SESSION_PATH: String = "user://session.cfg"
const TIMEOUT_SECONDS: int = 10
## gRPC codes Nakama puts in error responses.
const GRPC_NOT_FOUND: int = 5
const GRPC_PERMISSION_DENIED: int = 7
const GRPC_UNAUTHENTICATED: int = 16
const HTTP_UNAUTHORIZED: int = 401


class RpcResult:
	extends RefCounted

	var ok: bool = false
	var data: Dictionary = {}
	## Server error key (server/modules/errors.go) or one of the ERROR_* constants.
	var error: String = ""


var config: ServerConfig

var _client: NakamaClient
var _session: NakamaSession


func _ready() -> void:
	config = ServerConfig.from_environment(OS.get_cmdline_user_args(), PlatformServices.get_page_origin())
	_client = Nakama.create_client(config.server_key, config.host, config.port, config.scheme, TIMEOUT_SECONDS, NakamaLogger.LOG_LEVEL.ERROR)


## True when the server answers at all, whatever the status: it is reachable only from the office
## network, so false means the phone is not on the office Wi-Fi (or the server is down).
func is_reachable() -> bool:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	add_child(request)
	if request.request("%s://%s:%d/healthcheck" % [config.scheme, config.host, config.port]) != OK:
		request.queue_free()
		return false
	var response: Array = await request.request_completed
	request.queue_free()
	return int(response[0]) == HTTPRequest.RESULT_SUCCESS


func is_signed_in() -> bool:
	return _session != null and _session.is_valid() and not _session.is_expired()


func get_username() -> String:
	return _session.username if is_signed_in() else ""


## Picks up the session saved by an earlier sign-in. False when there is none or it expired.
func restore() -> bool:
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(SESSION_PATH) != OK:
		return false
	var token: String = str(saved.get_value("session", "token", ""))
	var session: NakamaSession = NakamaClient.restore_session(token)
	if token.is_empty() or not session.is_valid() or session.is_expired():
		_forget()
		return false
	_session = session
	return true


## Resolves to "" on success or to an ERROR_* key.
func sign_in(username: String, password: String) -> String:
	var session: NakamaSession = await _client.authenticate_email_async("", password, username.strip_edges().to_lower(), false)
	if session.is_exception():
		return _auth_error(session.get_exception())
	_session = session
	var saved: ConfigFile = ConfigFile.new()
	saved.set_value("session", "token", session.token)
	if saved.save(SESSION_PATH) != OK:
		push_warning("Cannot save the session; the player will sign in again next time.")
	return ""


func sign_out() -> void:
	if _session != null:
		await _client.session_logout_async(_session)
	_forget()


## Calls a server RPC with a JSON object payload.
func call_rpc(id: String, payload: Dictionary = {}) -> RpcResult:
	var result: RpcResult = RpcResult.new()
	if not is_signed_in():
		result.error = ERROR_SESSION
		_lose_session()
		return result
	var response: NakamaAPI.ApiRpc = await _client.rpc_async(_session, id, JSON.stringify(payload))
	if response.is_exception():
		var exception: NakamaException = response.get_exception()
		result.error = _rpc_error(exception)
		if result.error == ERROR_SESSION:
			_lose_session()
		return result
	var parsed: Variant = JSON.parse_string(response.payload) if not response.payload.is_empty() else {}
	# Game rule refusals come back as {"ok": false, "error": ...} with the data; the caller reads both.
	result.ok = parsed is Dictionary
	result.data = parsed if parsed is Dictionary else {}
	result.error = "" if result.ok else ERROR_SERVER
	return result


## Calls an RPC with the server's HTTP key instead of a player session (the office screen).
func call_rpc_with_key(id: String, http_key: String, payload: Dictionary = {}) -> RpcResult:
	var result: RpcResult = RpcResult.new()
	var response: NakamaAPI.ApiRpc = await _client.rpc_async_with_key(http_key, id, JSON.stringify(payload))
	if response.is_exception():
		var exception: NakamaException = response.get_exception()
		result.error = ERROR_NETWORK if _is_transport_error(exception) else ERROR_SERVER
		return result
	var parsed: Variant = JSON.parse_string(response.payload) if not response.payload.is_empty() else {}
	result.ok = parsed is Dictionary
	result.data = parsed if parsed is Dictionary else {}
	return result


func _auth_error(exception: NakamaException) -> String:
	match exception.grpc_status_code:
		GRPC_UNAUTHENTICATED, GRPC_NOT_FOUND:
			return ERROR_INVALID_CREDENTIALS
		GRPC_PERMISSION_DENIED:
			return ERROR_BLOCKED
	return ERROR_NETWORK if _is_transport_error(exception) else ERROR_SERVER


func _rpc_error(exception: NakamaException) -> String:
	if exception.status_code == HTTP_UNAUTHORIZED or exception.grpc_status_code == GRPC_UNAUTHENTICATED:
		return ERROR_SESSION
	if _is_transport_error(exception):
		return ERROR_NETWORK
	return exception.message if not exception.message.is_empty() else ERROR_SERVER


## Transport failures carry the HTTPRequest result code instead of an HTTP status.
func _is_transport_error(exception: NakamaException) -> bool:
	return exception.status_code < 100


func _lose_session() -> void:
	_forget()
	session_lost.emit()


func _forget() -> void:
	_session = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
