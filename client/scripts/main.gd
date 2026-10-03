extends WorldScene
## Office gameplay on the current floor (OfficeFloors): tap-to-move, NPC conversations, task markers
## with minigames, the reward shop, the inbox and the profile. The lift in the reception goes to the
## other floor; a task on another floor takes the player there first.
## Once every task is completed, skipped or waiting for a colleague, the player can go home.
## "QR" scans a room door code (the character walks to that room, on any floor), the office screen
## code (starts the check-in) or a colleague's profile code.

const TALK_DISTANCE: float = 40.0
## NPCs can be talked to from this many cells away, e.g. across the reception desk.
const TALK_REACH_CELLS: int = 2
const NPC_SCRIPT: GDScript = preload("res://scripts/npc/npc.gd")
const EVENING_SCENE: String = "res://scenes/intro/evening_outro.tscn"
const OFFICE_SCENE: String = "res://scenes/main.tscn"
const FADE_TIME: float = 0.5
## The player fades out over this time while stepping through the entrance.
const EXIT_FADE: float = 0.45
## The walk to the exit can cross the whole floor, so the player hurries.
const EXIT_SPEED_FACTOR: float = 1.8
## Task minigame that reads the office screen code.
const CHECK_IN_MINIGAME: String = "presence_qr"

var _pending_npc: Npc
var _pending_task: BackendModels.TaskInfo
var _talking: bool = false
var _busy: bool = false
var _leaving: bool = false
var _dialogues: DialogueRepository = DialogueRepository.new()
var _tasks: Array[BackendModels.TaskInfo] = []
var _pins: Dictionary[String, TaskPin] = {}
var _home_button: Button
## Room reached physically while a modal was open; the character walks there once it closes.
var _pending_room: StringName = &""
## Floor to ride to once the player reaches the lift.
var _pending_lift: StringName = &""
var _corner: PlayerCorner

@onready var _dialogue: DialogueBox = $DialogueBox
@onready var _task_panel: TaskPanel = $TaskPanel
@onready var _shop_panel: ShopPanel = $ShopPanel
@onready var _minigame_panel: MinigamePanel = $MinigamePanel
@onready var _choice: ChoicePrompt = $ChoicePrompt
@onready var _fade: ColorRect = $Fade/Rect


func _ready() -> void:
	var floor_id: StringName = OfficeFloors.current
	_setup_world(OfficeFloors.create_layout(floor_id))
	if OfficeFloors.arrived_by_lift and _map.layout.has_elevator():
		_player.global_position = _map.cell_to_world(_map.layout.elevator_cell)
		_player.face(Vector2.DOWN)
		_camera.snap_to_target()
	OfficeFloors.arrived_by_lift = false
	($DiscoLights as CanvasItem).visible = floor_id == OfficeFloors.HQ
	for definition: NpcRoster.Definition in NpcRoster.for_floor(floor_id):
		var npc: Npc = NPC_SCRIPT.new()
		_entities.add_child(npc)
		npc.setup(definition, _map)
	_hud.set_title(tr("HUD_TITLE") if floor_id == OfficeFloors.HQ else OfficeFloors.title(floor_id).to_upper())
	_hud.set_hint(tr("HUD_HINT") if floor_id == OfficeFloors.HQ else tr("HUD_HINT_ANALYTICS"))
	_hud.add_action(tr("HUD_TASKS"), true).pressed.connect(_open_tasks)
	_hud.add_action(tr("HUD_SCAN"), false).pressed.connect(_scan_code)
	_hud.add_action(tr("HUD_SHOP"), false).pressed.connect(_open_shop)
	_corner = PlayerCorner.attach(self, _hud)
	Notifications.banner_pressed.connect(_on_banner_pressed)
	Presence.zone_changed.connect(_on_zone_changed)
	Backend.request_failed.connect(_on_request_failed)
	_task_panel.go_requested.connect(_go_to_task)
	_task_panel.skip_requested.connect(_skip_task)
	if Backend.profile == null:
		await Backend.login()
	await _refresh_tasks()
	_update_room()
	_resume_after_lift()


func _process(delta: float) -> void:
	super(delta)
	if _pending_room != &"" and not _is_modal_open():
		var room_id: StringName = _pending_room
		_pending_room = &""
		_walk_to_room(room_id)
	if _pending_npc != null and not _talking and _player.global_position.distance_to(_pending_npc.global_position) <= TALK_DISTANCE:
		_talk_to(_pending_npc)


func _is_modal_open() -> bool:
	return (
		_talking or _busy or _leaving or _dialogue.is_open() or _task_panel.is_open() or _shop_panel.is_open()
		or _minigame_panel.is_open() or _choice.is_open() or (_corner != null and _corner.is_open())
	)


func _on_tap(world_position: Vector2) -> void:
	_cancel_pending_actions()
	for child: Node in _entities.get_children():
		var npc: Npc = child as Npc
		if npc != null and npc.is_hit(world_position):
			_approach(npc)
			return
	for pin: TaskPin in _pins.values():
		if pin.visible and pin.is_hit(world_position):
			_go_to_task(pin.task)
			return
	if _is_lift_hit(world_position):
		_go_to_lift(OfficeFloors.next_floor(OfficeFloors.current), true)
		return
	_walk_to(world_position)


func _cancel_pending_actions() -> void:
	_pending_npc = null
	_pending_task = null
	_pending_lift = &""


func _refresh_tasks() -> void:
	_tasks = await Backend.list_tasks()
	for task: BackendModels.TaskInfo in _tasks:
		if task.floor_id != OfficeFloors.current:
			continue
		if not _map.is_walkable(task.spot):
			push_error("Task '%s' spot %s is not walkable" % [task.id, task.spot])
		var pin: TaskPin = _pins.get(task.id)
		if pin == null:
			pin = TaskPin.new()
			_entities.add_child(pin)
			_pins[task.id] = pin
		pin.setup(task, _map.cell_to_world(task.spot))
	_update_go_home()


# --- NPCs ------------------------------------------------------------------------


func _approach(npc: Npc) -> void:
	_pending_npc = npc
	_hud.hide_hint()
	var npc_cell: Vector2i = _map.world_to_cell(npc.global_position)
	if _player.global_position.distance_to(npc.global_position) <= TALK_DISTANCE or WorldScene.chebyshev(_player_cell(), npc_cell) <= 1:
		return
	# Pick the closest reachable cell near the NPC. Cells right next to it are preferred, but a cell
	# two steps away is fine when furniture such as the reception desk is in between.
	var best_path: PackedVector2Array = PackedVector2Array()
	var best_score: int = 1 << 30
	for dy: int in range(-TALK_REACH_CELLS, TALK_REACH_CELLS + 1):
		for dx: int in range(-TALK_REACH_CELLS, TALK_REACH_CELLS + 1):
			var cell: Vector2i = npc_cell + Vector2i(dx, dy)
			if cell == npc_cell or not _map.is_walkable(cell):
				continue
			var path: PackedVector2Array = _map.find_path(_player.global_position, cell)
			if path.is_empty():
				continue
			var score: int = path.size() + 4 * (WorldScene.chebyshev(cell, npc_cell) - 1) + (0 if dx == 0 or dy == 0 else 1)
			if score < best_score:
				best_score = score
				best_path = path
	if best_path.is_empty():
		_pending_npc = null
		_hud.flash_message(tr("HUD_BLOCKED"))
		return
	_player.walk_path(best_path)
	_marker.show_target(best_path[best_path.size() - 1])


func _talk_to(npc: Npc) -> void:
	_pending_npc = null
	_talking = true
	_stop_player()
	_player.face(npc.global_position - _player.global_position)
	npc.begin_talk(_player.global_position)
	_dialogue.open(npc.definition.display_name, npc.definition.id, _dialogues.next_conversation(npc.definition.id))
	await _dialogue.finished
	npc.end_talk()
	_talking = false


func _on_player_arrived() -> void:
	super()
	if _pending_npc != null and not _talking:
		var npc_cell: Vector2i = _map.world_to_cell(_pending_npc.global_position)
		if WorldScene.chebyshev(_player_cell(), npc_cell) <= TALK_REACH_CELLS:
			_talk_to(_pending_npc)
		else:
			_pending_npc = null
	if _pending_task != null:
		var task: BackendModels.TaskInfo = _pending_task
		_pending_task = null
		if _player_cell() == task.spot:
			_start_task(task)
	if _pending_lift != &"":
		var floor_id: StringName = _pending_lift
		_pending_lift = &""
		if _player_cell() == _map.layout.elevator_cell:
			_ask_lift(floor_id)


# --- Tasks and shop --------------------------------------------------------------


func _open_tasks() -> void:
	if _is_modal_open():
		return
	_busy = true
	await _refresh_tasks()
	_busy = false
	_task_panel.open(_tasks, _player_cell(), Backend.profile)


func _open_shop() -> void:
	if _is_modal_open():
		return
	_shop_panel.open()


func _go_to_task(task: BackendModels.TaskInfo) -> void:
	_task_panel.close_panel()
	_pending_npc = null
	if task.completed:
		_hud.flash_message(tr("ERROR_ALREADY_COMPLETED"))
		return
	if task.skipped:
		_hud.flash_message(tr("ERROR_TASK_SKIPPED"))
		return
	if task.pending:
		_hud.flash_message(tr("ERROR_PENDING_CONFIRMATION"))
		return
	if not task.is_check_in() and not TaskPanel.lock_text().is_empty():
		# The break between tasks or the time outside the task hours: no walking there for nothing.
		_hud.flash_message(TaskPanel.lock_text())
		return
	if not task.is_check_in() and not PlayTime.task_lock_text().is_empty():
		# The play time is up: new tasks wait until after the rest.
		_hud.flash_message(PlayTime.task_lock_text())
		return
	if task.floor_id != OfficeFloors.current:
		# The task is on another floor: ride the lift first, then walk to it there.
		OfficeFloors.pending_task_id = task.id
		_hud.flash_message(tr("LIFT_TASK_ELSEWHERE") % OfficeFloors.title(task.floor_id))
		_go_to_lift(task.floor_id, false)
		return
	if _player_cell() == task.spot:
		_stop_player()
		_start_task(task)
		return
	if _walk_to_cell(task.spot):
		_pending_task = task


## Runs the task's minigame. PlayTime knows a minigame is on screen until its result is handled,
## so the play-time limit never interrupts it (the rest starts right after it instead).
func _start_task(task: BackendModels.TaskInfo) -> void:
	PlayTime.begin_minigame(task.id)
	await _run_task(task)
	PlayTime.end_minigame()


func _run_task(task: BackendModels.TaskInfo) -> void:
	_player.face(Vector2.UP)
	_busy = true
	var context: Dictionary = {}
	if not task.assignment.is_empty():
		# The server picks the colleague (someone who checked in today) before the minigame opens.
		var assigned: BackendModels.ColleagueResult = await Backend.social.assign_colleague(task.id)
		if not assigned.ok:
			_busy = false
			_hud.flash_message(tr("ERROR_" + assigned.error.to_upper()))
			return
		context["colleague"] = assigned.colleague
	var outcome: MinigamePanel.Outcome = await _minigame_panel.run(task, context)
	_busy = false
	if outcome == MinigamePanel.Outcome.UNAVAILABLE:
		_hud.flash_message(tr("MG_UNAVAILABLE"))
		return
	if outcome == MinigamePanel.Outcome.SKIPPED:
		await _skip_task(task)
		return
	if outcome != MinigamePanel.Outcome.SUCCESS:
		return
	_busy = true
	var result: BackendModels.TaskResult = await Backend.complete_task(task.id, true, _minigame_panel.last_proof)
	_busy = false
	if result.ok and result.pending:
		_hud.flash_message(tr("PHOTO_SENT") % result.partner_name)
	elif result.ok:
		_hud.play_reward(get_canvas_transform() * _player.global_position, result.reward)
		_hud.flash_message(tr("TASK_REWARD") % result.reward)
		_camera.shake(3.0)
	else:
		_hud.flash_message(tr("ERROR_" + result.error.to_upper()))
	await _refresh_tasks()


## Asks for confirmation, then lets the server close the task for today without a reward.
func _skip_task(task: BackendModels.TaskInfo) -> void:
	_task_panel.close_panel()
	if not task.skippable or task.is_closed() or _choice.is_open():
		return
	if not await _choice.ask(tr("TASK_SKIP_QUESTION"), tr("TASK_SKIP_CONFIRM"), tr("TASK_SKIP_CANCEL")):
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.skip_task(task.id)
	_busy = false
	_hud.flash_message(tr("TASK_SKIP_DONE") if result.ok else tr("ERROR_" + result.error.to_upper()))
	await _refresh_tasks()


# --- QR codes and rooms ---------------------------------------------------------


func _scan_code() -> void:
	if _is_modal_open():
		return
	_cancel_pending_actions()
	_busy = true
	PlayTime.begin_minigame()
	var payload: QrPayload = await _minigame_panel.scan_code()
	PlayTime.end_minigame()
	_busy = false
	if payload == null:
		return
	match payload.kind:
		QrPayload.Kind.ROOM:
			var room_id: StringName = StringName(payload.value)
			var floor_id: StringName = OfficeFloors.floor_of_room(room_id)
			if floor_id == &"":
				_hud.flash_message(tr("QR_UNKNOWN_ROOM"))
				return
			# Door codes are static, so they count only after the entry code at the reception.
			_busy = true
			var entered: BackendModels.ActionResult = await Backend.enter_room(String(room_id))
			_busy = false
			if not entered.ok:
				_hud.flash_message(tr("ERROR_" + entered.error.to_upper()))
				return
			Presence.set_zone_from_qr(room_id)
			if floor_id != OfficeFloors.current:
				# The player is physically on another floor: the game follows them there.
				OfficeFloors.pending_room = room_id
				_travel(floor_id)
				return
			_walk_to_room(room_id)
		QrPayload.Kind.PRESENCE:
			await _start_check_in(payload.value)
		QrPayload.Kind.CHECKOUT:
			_busy = true
			var left: BackendModels.ActionResult = await Backend.check_out(payload.value)
			_busy = false
			_hud.flash_message(tr("QR_CHECKED_OUT") if left.ok else tr("ERROR_" + left.error.to_upper()))
		QrPayload.Kind.USER:
			_hud.flash_message(tr("QR_COLLEAGUE_HINT"))


## The entry code was scanned outside the task. The first entry of the day is the check-in task
## (it pays a reward): walk to it and start it. Later entries, e.g. after lunch, only reopen the office.
func _start_check_in(token: String) -> void:
	for task: BackendModels.TaskInfo in _tasks:
		if task.minigame == CHECK_IN_MINIGAME and not task.is_closed():
			_go_to_task(task)
			return
	if Backend.profile != null and Backend.profile.in_office:
		_hud.flash_message(tr("QR_ALREADY_CHECKED_IN"))
		return
	_busy = true
	var entered: BackendModels.ActionResult = await Backend.check_in(token)
	_busy = false
	_hud.flash_message(tr("QR_BACK_IN_OFFICE") if entered.ok else tr("ERROR_" + entered.error.to_upper()))


func _on_request_failed(error: String) -> void:
	_hud.flash_message(tr("ERROR_" + error.to_upper()))


func _on_zone_changed(room_id: StringName) -> void:
	if _is_modal_open() and OfficeFloors.floor_of_room(room_id) == OfficeFloors.current:
		_pending_room = room_id


func _on_banner_pressed(kind: String) -> void:
	if not kind.is_empty() and not _is_modal_open():
		_corner.open_inbox()


# --- Lift ------------------------------------------------------------------------


func _is_lift_hit(world_position: Vector2) -> bool:
	var layout: MapLayout = _map.layout
	if not layout.has_elevator():
		return false
	var cell: Vector2i = _map.world_to_cell(world_position)
	return layout.elevator.has_point(cell) or cell == layout.elevator_cell


## Walks to the lift doors; on arrival asks (or, for a task elsewhere, just rides) to `floor_id`.
func _go_to_lift(floor_id: StringName, ask: bool) -> void:
	var layout: MapLayout = _map.layout
	if not layout.has_elevator():
		return
	if _player_cell() == layout.elevator_cell:
		_stop_player()
		if ask:
			_ask_lift(floor_id)
		else:
			_travel(floor_id)
		return
	if _walk_to_cell(layout.elevator_cell):
		if ask:
			_pending_lift = floor_id
		else:
			_pending_lift = &""
			_ride_on_arrival(floor_id)


func _ride_on_arrival(floor_id: StringName) -> void:
	await _player.arrived
	if _player_cell() == _map.layout.elevator_cell:
		_travel(floor_id)


func _ask_lift(floor_id: StringName) -> void:
	_player.face(Vector2.UP)
	if await _choice.ask(tr("LIFT_QUESTION") % OfficeFloors.title(floor_id), tr("LIFT_GO"), tr("LIFT_STAY")):
		_travel(floor_id)


## Fades out and reloads the office on the other floor; the player steps out of the lift there.
func _travel(floor_id: StringName) -> void:
	if _leaving:
		return
	_leaving = true
	_end_drag()
	_cancel_pending_actions()
	_hud.flash_message(tr("LIFT_RIDING") % OfficeFloors.title(floor_id))
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished
	OfficeFloors.current = floor_id
	OfficeFloors.arrived_by_lift = true
	get_tree().change_scene_to_file(OFFICE_SCENE)


## After a lift ride: walk to the task or room that sent the player here.
func _resume_after_lift() -> void:
	var room_id: StringName = OfficeFloors.pending_room
	var task_id: String = OfficeFloors.pending_task_id
	OfficeFloors.pending_room = &""
	OfficeFloors.pending_task_id = ""
	if room_id != &"":
		_walk_to_room(room_id)
		return
	for task: BackendModels.TaskInfo in _tasks:
		if task.id == task_id and task.floor_id == OfficeFloors.current:
			_go_to_task(task)


## The character walks to the walkable cell closest to the room centre.
func _walk_to_room(room_id: StringName) -> void:
	var room: MapLayout.Room = _map.layout.find_room(room_id)
	if room == null:
		return
	var current: MapLayout.Room = _map.get_room_at(_player_cell())
	if current != null and current.id == room_id:
		return
	var floor_rect: Rect2i = room.floor_rect()
	var center: Vector2 = _map.cell_to_world(floor_rect.position + floor_rect.size / 2)
	var cell: Vector2i = _map.find_nearest_walkable(center, maxi(floor_rect.size.x, floor_rect.size.y))
	if cell == WorldMap.INVALID_CELL:
		return
	_hud.flash_message(tr("QR_GOING_TO_ROOM") % tr(room.name_key))
	_walk_to_cell(cell)


# --- End of the day --------------------------------------------------------------


func _update_go_home() -> void:
	if _home_button != null or _tasks.is_empty():
		return
	if not _tasks.all(func(task: BackendModels.TaskInfo) -> bool: return task.is_closed()):
		return
	_home_button = _hud.add_wide_action(tr("HUD_GO_HOME"))
	_home_button.pressed.connect(_go_home)
	_hud.flash_message(tr("HUD_ALL_DONE"))


## Walks the player out through the entrance, then plays the evening cutscene.
func _go_home() -> void:
	if _is_modal_open():
		return
	_leaving = true
	_end_drag()
	_cancel_pending_actions()
	_marker.hide_marker()
	_home_button.visible = false
	_hud.hide_hint()
	_player.say(tr("HUD_GO_HOME_REMARK"))
	var path: PackedVector2Array = _exit_path()
	if not path.is_empty():
		_player.move_speed *= EXIT_SPEED_FACTOR
		_player.walk_path(path)
		var length: float = 0.0
		for i: int in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		length += _player.global_position.distance_to(path[0])
		var fade_out: Tween = create_tween()
		fade_out.tween_interval(maxf(0.0, length / _player.move_speed - EXIT_FADE))
		fade_out.tween_property(_player, "modulate:a", 0.0, EXIT_FADE)
		await _player.arrived
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished
	OfficeFloors.reset()
	get_tree().change_scene_to_file(EVENING_SCENE)


## Path to the floor cell in front of the entrance and on through the glass doors.
func _exit_path() -> PackedVector2Array:
	var layout: MapLayout = _map.layout
	if layout.entrances.is_empty():
		return PackedVector2Array()
	var entrance: Rect2i = layout.entrances[0]
	var tile: float = MapLayout.TILE_SIZE
	var doorway: Vector2 = _map.to_global(Vector2(entrance.position.x + entrance.size.x / 2.0, entrance.position.y + 0.5) * tile)
	var inside: Vector2i = _map.find_nearest_walkable(doorway + Vector2(0, -tile), 1)
	if inside == WorldMap.INVALID_CELL:
		return PackedVector2Array()
	var path: PackedVector2Array = _map.find_path(_player.global_position, inside)
	if path.is_empty():
		return path
	path.append(Vector2(doorway.x, _map.cell_to_world(inside).y))
	path.append(doorway)
	path.append(doorway + Vector2(0, tile))
	return path
