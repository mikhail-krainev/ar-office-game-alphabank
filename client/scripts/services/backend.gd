class_name BackendService
extends Node
## Game-facing server API (autoload "Backend"). Every call is an RPC to the Nakama Go module
## (server/modules); the client never changes balance, unlocks or ownership itself. The game needs
## the network: a failed call returns a result with the error "network" and emits request_failed.
## Tasks, shop, wardrobe, garage and presence are here; the other groups are `social` (colleagues,
## joint photos, inbox), `account` (profile page, status, avatar) and `raffle` (parking draw).

signal balance_changed(balance: int)
signal outfit_changed(outfit: Dictionary)
signal car_changed(car_id: String)
## Status or avatar of the player changed.
signal profile_changed(profile: BackendModels.Profile)
## Something happened that may have added messages to the inbox (a check-in, a finished task).
signal inbox_may_have_changed
## A call did not reach the server or the server failed; `error` is a ServerSession error key.
signal request_failed(error: String)
## The server refused a game call: the player is not in the office network (PlayTime shows it).
signal office_network_required

const LOGIN_SCENE: String = "res://scenes/login/login.tscn"

var profile: BackendModels.Profile
var server: ServerSession
var social: BackendSocial
var account: BackendAccount
var raffle: BackendRaffle
## When tasks count (cooldown, task hours); updated by list_tasks().
var task_schedule: BackendModels.TaskSchedule = BackendModels.TaskSchedule.new()

var _account_loaded: bool = false


func _ready() -> void:
	server = ServerSession.new()
	server.name = "Server"
	add_child(server)
	server.session_lost.connect(_on_session_lost)
	social = BackendSocial.new(self)
	account = BackendAccount.new(self)
	raffle = BackendRaffle.new(self)
	for api: Node in [social, account, raffle]:
		add_child(api)
	if OS.is_debug_build() and OS.has_feature("pc"):
		var keys: Node = load("res://scripts/services/dev_backend_keys.gd").new()
		add_child(keys)


## Calls an RPC; transport and server failures are reported through request_failed.
func call_rpc(id: String, payload: Dictionary = {}) -> ServerSession.RpcResult:
	var result: ServerSession.RpcResult = await server.call_rpc(id, payload)
	if not result.ok and result.error in [ServerSession.ERROR_NETWORK, ServerSession.ERROR_SERVER]:
		request_failed.emit(result.error)
	elif result.error == "office_network_required":
		office_network_required.emit()
	return result


# --- Account ---------------------------------------------------------------------


## Loads the signed-in account: name and department, plus department names for colleague cards.
## Resolves to "" or a ServerSession error key ("not_player" for the admin account).
func load_account() -> String:
	var identity: ServerSession.RpcResult = await server.call_rpc("get_profile")
	if not identity.ok:
		return identity.error
	var departments: ServerSession.RpcResult = await server.call_rpc("list_departments")
	if not departments.ok:
		return departments.error
	var names: Dictionary[String, String] = {}
	for department: Variant in departments.data.get("departments", []):
		if department is Dictionary:
			names[str(department.get("id", ""))] = str(department.get("name", ""))
	NotificationTexts.department_names = names
	profile = null
	_account_loaded = true
	return ""


## A player is signed in and their account is loaded.
func is_account_loaded() -> bool:
	return _account_loaded


func sign_out() -> void:
	await server.sign_out()
	_account_loaded = false
	profile = null
	get_tree().change_scene_to_file(LOGIN_SCENE)


## Start of a game session: welcome bonus, absence fines and the lost streak for the morning card.
func login() -> BackendModels.Profile:
	if not _account_loaded:
		# A scene was opened directly (e.g. from the editor): sign in first.
		_on_session_lost()
	var result: ServerSession.RpcResult = await call_rpc("login")
	profile = BackendParser.profile(result.data)
	balance_changed.emit(profile.balance)
	outfit_changed.emit(profile.outfit)
	car_changed.emit(profile.car_id)
	profile_changed.emit(profile)
	inbox_may_have_changed.emit()
	return profile


## Re-reads the player's profile (status, avatar, streak, presence) after a change.
func refresh_profile() -> void:
	var result: ServerSession.RpcResult = await call_rpc("get_my_profile")
	if not result.ok:
		return
	var fresh: BackendModels.Profile = BackendParser.profile(result.data)
	_ensure_profile()
	profile.display_name = fresh.display_name
	profile.department = fresh.department
	profile.status = fresh.status
	profile.avatar = fresh.avatar
	profile.streak_days = fresh.streak_days
	profile.present_today = fresh.present_today
	profile.in_office = fresh.in_office
	profile.multiplier = fresh.multiplier
	apply_balance(fresh.balance)
	profile_changed.emit(profile)


# --- Tasks and presence ----------------------------------------------------------


## Today's tasks: the check-in and the player's pack. Also refreshes `task_schedule`.
func list_tasks() -> Array[BackendModels.TaskInfo]:
	var result: ServerSession.RpcResult = await call_rpc("list_tasks")
	var tasks: Array[BackendModels.TaskInfo] = []
	for entry: Variant in result.data.get("tasks", []):
		if entry is Dictionary:
			tasks.append(BackendParser.task(entry))
	if result.ok:
		task_schedule = BackendParser.task_schedule(result.data.get("schedule"))
		if profile != null:
			profile.in_office = bool(result.data.get("in_office", profile.in_office))
	return tasks


## `proof` carries the minigame evidence (presence token, colleague id, score); the server validates it.
func complete_task(task_id: String, success: bool, proof: Dictionary = {}) -> BackendModels.TaskResult:
	var payload: Dictionary = {"task_id": task_id, "success": success, "operation_key": operation_key(), "proof": proof}
	var response: ServerSession.RpcResult = await call_rpc("complete_task", payload)
	var result: BackendModels.TaskResult = BackendParser.task_result(response.data, response.error)
	apply_balance(result.balance)
	if result.ok:
		refresh_profile()
		inbox_may_have_changed.emit()
	return result


func skip_task(task_id: String) -> BackendModels.ActionResult:
	var response: ServerSession.RpcResult = await call_rpc("skip_task", {"task_id": task_id})
	return BackendParser.action(response.data, response.error)


## Entry code scanned again after the check-in task (e.g. back from lunch).
func check_in(token: String) -> BackendModels.ActionResult:
	return await _presence_action("office_check_in", {"token": token})


## Exit code: tasks and room codes stop counting until the next entry.
func check_out(token: String) -> BackendModels.ActionResult:
	return await _presence_action("office_check_out", {"token": token})


## Static room code: accepted only inside the office.
func enter_room(room_id: String) -> BackendModels.ActionResult:
	var response: ServerSession.RpcResult = await call_rpc("enter_room", {"room_id": room_id})
	return BackendParser.action(response.data, response.error)


func _presence_action(id: String, payload: Dictionary) -> BackendModels.ActionResult:
	var response: ServerSession.RpcResult = await call_rpc(id, payload)
	var result: BackendModels.ActionResult = BackendParser.action(response.data, response.error)
	if result.ok:
		await refresh_profile()
	return result


# --- Shop, wardrobe, garage --------------------------------------------------------


func get_shop() -> BackendModels.ShopState:
	var response: ServerSession.RpcResult = await call_rpc("get_shop")
	return BackendParser.shop(response.data)


func buy(offer_id: String) -> BackendModels.PurchaseResult:
	var response: ServerSession.RpcResult = await call_rpc("buy", {"offer_id": offer_id, "operation_key": operation_key()})
	var result: BackendModels.PurchaseResult = BackendParser.purchase(response.data, response.error)
	apply_balance(result.balance)
	return result


func get_wardrobe() -> BackendModels.WardrobeState:
	var response: ServerSession.RpcResult = await call_rpc("get_wardrobe")
	return BackendParser.wardrobe(response.data)


func save_outfit(outfit: Dictionary) -> BackendModels.ActionResult:
	var clean: Dictionary = {}
	for key: Variant in outfit:
		clean[str(key)] = str(outfit[key])
	var response: ServerSession.RpcResult = await call_rpc("save_outfit", {"outfit": clean})
	var result: BackendModels.ActionResult = BackendParser.action(response.data, response.error)
	if result.ok:
		_ensure_profile()
		profile.outfit = BackendParser.outfit(clean)
		outfit_changed.emit(profile.outfit)
	return result


func get_garage() -> BackendModels.GarageState:
	var response: ServerSession.RpcResult = await call_rpc("get_garage")
	return BackendParser.garage(response.data)


func buy_car(car_id: String) -> BackendModels.PurchaseResult:
	var response: ServerSession.RpcResult = await call_rpc("buy_car", {"car_id": car_id, "operation_key": operation_key()})
	var result: BackendModels.PurchaseResult = BackendParser.purchase(response.data, response.error)
	apply_balance(result.balance)
	return result


func select_car(car_id: String) -> BackendModels.ActionResult:
	var response: ServerSession.RpcResult = await call_rpc("select_car", {"car_id": car_id})
	var result: BackendModels.ActionResult = BackendParser.action(response.data, response.error)
	if result.ok and response.data.get("car") is Dictionary:
		var car: Dictionary = response.data["car"]
		_ensure_profile()
		profile.car_id = car_id
		profile.car_name = str(car.get("name", car_id))
		profile.car_speed_kmh = int(car.get("speed_kmh", 110))
		car_changed.emit(car_id)
	return result


# --- Play time -------------------------------------------------------------------


## The game is on screen, with the minigame of `minigame_task` ("" = none). The answer says whether
## the player may go on, must rest or is locked.
func play_heartbeat(minigame_task: String = "") -> BackendModels.PlayStatus:
	var response: ServerSession.RpcResult = await server.call_rpc("play_heartbeat", {"minigame": minigame_task})
	return BackendParser.play_status(response.data, response.error)


## The warned player goes to rest right away.
func play_rest() -> BackendModels.PlayStatus:
	var response: ServerSession.RpcResult = await call_rpc("play_rest")
	return BackendParser.play_status(response.data, response.error)


## Loads the outfit for screens shown before login() (the rest screen draws the character).
func load_outfit() -> void:
	var result: ServerSession.RpcResult = await call_rpc("get_my_profile")
	if result.ok:
		outfit_changed.emit(BackendParser.profile(result.data).outfit)


# --- Notifications ---------------------------------------------------------------


## Reminders and announcements for the OS scheduler, replacing any earlier plan.
func get_notification_plan() -> Array[BackendModels.PlannedNotification]:
	var response: ServerSession.RpcResult = await call_rpc("get_notification_plan")
	return BackendParser.notification_plan(response.data)


# --- Local state -----------------------------------------------------------------


func get_balance() -> int:
	return profile.balance if profile != null else 0


func get_car_id() -> String:
	return profile.car_id if profile != null else VehicleCatalog.DEFAULT_CAR


func get_user_id() -> String:
	return profile.user_id if profile != null else ""


## Takes the balance the server reported and tells the UI. Negative = not reported.
func apply_balance(balance: int) -> void:
	if balance < 0:
		return
	_ensure_profile()
	if profile.balance != balance:
		profile.balance = balance
		balance_changed.emit(balance)


## Idempotency key for balance-changing calls.
func operation_key() -> String:
	return "%d-%08x" % [Time.get_ticks_usec(), randi()]


## DEV-ONLY: calls a dev RPC (the server must run with DEV_MODE=true).
func dev_call(id: String, payload: Dictionary = {}) -> ServerSession.RpcResult:
	assert(OS.is_debug_build())
	var result: ServerSession.RpcResult = await server.call_rpc(id, payload)
	if not result.ok:
		push_warning("[dev] %s failed: %s (is DEV_MODE=true on the server?)" % [id, result.error])
	return result


func _on_session_lost() -> void:
	_account_loaded = false
	var current: Node = get_tree().current_scene
	if current == null or current.scene_file_path != LOGIN_SCENE:
		get_tree().change_scene_to_file.call_deferred(LOGIN_SCENE)


func _ensure_profile() -> void:
	if profile == null:
		profile = BackendModels.Profile.new()
