extends WorldScene
## Office gameplay on the current floor (OfficeFloors): the character lives by itself (walks between
## rooms, chats with colleagues), the player picks tasks with minigames, opens the reward shop, the
## inbox and the profile. A task is taken in its room: when the last room code is another room, the
## game asks to scan the code of the task's room first. Then the minigame starts right away: the
## player does it in the real office, so the character does not walk anywhere.
## After the check-in the player can go home at any time: tasks only add coins and gifts.
## "QR" scans a room door code (the character walks to that room, on any floor), the office screen
## code (starts the check-in) or a colleague's profile code.
## On arrival from the commute the entry code scan opens by itself until the player checks in.
## Right after the check-in the game asks for the facts of "Three truths, two lies" when that task is
## in today's pack.

## NPCs can be talked to from this many cells away, e.g. across the reception desk.
const TALK_REACH_CELLS: int = 2
## Lines of a chat with a colleague, shown as speech bubbles, and the time each one stays.
const CHAT_MAX_LINES: int = 4
const CHAT_LINE_SECONDS: float = 2.8
## Activity weights of the character: chat with a colleague, then visit a room, else a short stroll.
const CHAT_CHANCE: float = 0.45
const ROOM_CHANCE: float = 0.4
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

var _busy: bool = false
var _leaving: bool = false
var _dialogues: DialogueRepository = DialogueRepository.new()
var _tasks: Array[BackendModels.TaskInfo] = []
var _pins: Dictionary[String, TaskPin] = {}
var _home_button: Button
## Room reached physically while a modal was open; the character walks there once it closes.
var _pending_room: StringName = &""
var _corner: PlayerCorner
var _task_list: TaskList
var _facts_panel: FactsPanel

@onready var _task_panel: TaskPanel = $TaskPanel
@onready var _shop_panel: ShopPanel = $ShopPanel
@onready var _minigame_panel: MinigamePanel = $MinigamePanel
@onready var _choice: ChoicePrompt = $ChoicePrompt
@onready var _fade: ColorRect = $Fade/Rect


func _ready() -> void:
	var floor_id: StringName = OfficeFloors.current
	var by_lift: bool = OfficeFloors.arrived_by_lift
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
	_facts_panel = FactsPanel.new()
	add_child(_facts_panel)
	_task_list = TaskList.new()
	_task_list.task_pressed.connect(_on_task_list_pressed)
	_hud.add_corner_panel(_task_list)
	Notifications.banner_pressed.connect(_on_banner_pressed)
	Presence.zone_changed.connect(_on_zone_changed)
	Backend.request_failed.connect(_on_request_failed)
	_task_panel.go_requested.connect(_go_to_task)
	_task_panel.skip_requested.connect(_skip_task)
	if Backend.profile == null:
		await Backend.login()
	await _refresh_tasks()
	_update_room()
	if not by_lift and await _auto_check_in():
		return
	_resume_after_lift()


func _process(delta: float) -> void:
	super(delta)
	if _pending_room != &"" and not _is_modal_open():
		var room_id: StringName = _pending_room
		_pending_room = &""
		_walk_to_room(room_id)


func _is_modal_open() -> bool:
	return (
		_busy or _leaving or _task_panel.is_open() or _shop_panel.is_open()
		or _minigame_panel.is_open() or _choice.is_open() or (_corner != null and _corner.is_open())
		or (_facts_panel != null and _facts_panel.is_open())
	)


## Only task markers react to taps: the character is not steered.
func _on_tap(world_position: Vector2) -> void:
	for pin: TaskPin in _pins.values():
		if pin.visible and pin.is_hit(world_position):
			_go_to_task(pin.task)
			return


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
	_task_list.set_tasks(_tasks)
	_update_go_home()


# --- The character's own life ----------------------------------------------------


func _run_activity() -> void:
	var npcs: Array[Npc] = []
	for child: Node in _entities.get_children():
		if child is Npc:
			npcs.append(child as Npc)
	var roll: float = randf()
	if roll < CHAT_CHANCE and not npcs.is_empty():
		await _chat_with(npcs.pick_random())
	elif roll < CHAT_CHANCE + ROOM_CHANCE:
		await _visit_room()
	else:
		await _wander()


## Walks up to a colleague and has a short chat in speech bubbles.
func _chat_with(npc: Npc) -> void:
	var cell: Vector2i = _cell_near(npc)
	if cell == WorldMap.INVALID_CELL:
		return
	if cell != _player_cell() and not await _auto_walk(cell):
		return
	var npc_cell: Vector2i = _map.world_to_cell(npc.global_position)
	if WorldScene.chebyshev(_player_cell(), npc_cell) > TALK_REACH_CELLS:
		# The colleague walked away meanwhile.
		return
	_player.face(npc.global_position - _player.global_position)
	npc.begin_talk(_player.global_position)
	var lines: Array[DialogueRepository.Line] = _dialogues.next_conversation(npc.definition.id)
	for i: int in mini(lines.size(), CHAT_MAX_LINES):
		if lines[i].is_player:
			_player.say(lines[i].text, CHAT_LINE_SECONDS)
		else:
			npc.say(lines[i].text, CHAT_LINE_SECONDS)
		if not await _auto_wait(CHAT_LINE_SECONDS):
			break
	if is_instance_valid(npc):
		npc.end_talk()


## The closest reachable cell next to the NPC; a cell two steps away is fine when furniture such as
## the reception desk is in between.
func _cell_near(npc: Npc) -> Vector2i:
	var npc_cell: Vector2i = _map.world_to_cell(npc.global_position)
	if WorldScene.chebyshev(_player_cell(), npc_cell) <= 1:
		return _player_cell()
	var best_cell: Vector2i = WorldMap.INVALID_CELL
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
				best_cell = cell
	return best_cell


## Walks into a random room of the floor and looks around there for a while.
func _visit_room() -> void:
	var rooms: Array[MapLayout.Room] = _map.layout.rooms
	if rooms.is_empty():
		return
	var room: MapLayout.Room = rooms.pick_random()
	var floor_rect: Rect2i = room.floor_rect()
	var target: Vector2i = floor_rect.position + Vector2i(randi_range(0, floor_rect.size.x - 1), randi_range(0, floor_rect.size.y - 1))
	var cell: Vector2i = _map.find_nearest_walkable(_map.cell_to_world(target), maxi(floor_rect.size.x, floor_rect.size.y))
	if cell != WorldMap.INVALID_CELL and await _auto_walk(cell):
		_player.face(Vector2.from_angle(randf() * TAU))
		await _auto_wait(randf_range(1.5, 4.0))


# --- Tasks and shop --------------------------------------------------------------


func _open_tasks() -> void:
	if _is_modal_open():
		return
	_busy = true
	await _refresh_tasks()
	_busy = false
	_task_panel.open(_tasks, Backend.profile)


func _open_shop() -> void:
	if _is_modal_open():
		return
	_shop_panel.open()


func _on_task_list_pressed(task: BackendModels.TaskInfo) -> void:
	if not _is_modal_open():
		_go_to_task(task)


func _go_to_task(task: BackendModels.TaskInfo) -> void:
	_task_panel.close_panel()
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
	if not task.taken and not await _take_task(task):
		return
	# The minigame happens in the real office, so the character does not have to walk to the marker.
	_stop_player()
	_start_task(task)


## Takes the task on the server. Away from the task's room the player scans its door code first.
## Returns true when the task can start here and now.
func _take_task(task: BackendModels.TaskInfo) -> bool:
	_busy = true
	var taken: BackendModels.ActionResult = await Backend.take_task(task.id)
	_busy = false
	if taken.ok:
		task.taken = true
		return true
	if taken.error != "wrong_room":
		_hud.flash_message(tr("ERROR_" + taken.error.to_upper()))
		return false
	var room_name: String = tr(TaskPanel.room_key(task.room))
	if not await _choice.ask(tr("TASK_ROOM_QUESTION") % room_name, tr("TASK_ROOM_SCAN"), tr("TASK_ROOM_CANCEL")):
		return false
	var payload: QrPayload = await _scan_payload()
	if payload == null:
		return false
	if payload.kind != QrPayload.Kind.ROOM or StringName(payload.value) != task.room:
		_hud.flash_message(tr("TASK_ROOM_WRONG_CODE") % room_name)
		return false
	if not await _enter_room(task.room):
		return false
	_busy = true
	taken = await Backend.take_task(task.id)
	_busy = false
	if not taken.ok:
		_hud.flash_message(tr("ERROR_" + taken.error.to_upper()))
		return false
	task.taken = true
	if OfficeFloors.floor_of_room(task.room) != OfficeFloors.current:
		# The room is on another floor: the game follows the player there, the task waits taken.
		_move_to_room(task.room)
		return false
	return true


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
	if result.ok and task.is_check_in():
		await _ask_facts()


## After the check-in: the facts for "Three truths, two lies" when today's pack has the task and
## they are not written yet today.
func _ask_facts() -> void:
	var state: BackendModels.FactsState = await Backend.social.get_facts()
	if state.ok and state.needed and not state.written_today and not _is_modal_open():
		_facts_panel.open(state)


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
	var payload: QrPayload = await _scan_payload()
	if payload == null:
		return
	match payload.kind:
		QrPayload.Kind.ROOM:
			var room_id: StringName = StringName(payload.value)
			if await _enter_room(room_id):
				_hint_room_tasks(room_id)
				_move_to_room(room_id)
		QrPayload.Kind.PRESENCE:
			await _start_check_in(payload.value)
		QrPayload.Kind.CHECKOUT:
			_busy = true
			var left: BackendModels.ActionResult = await Backend.check_out(payload.value)
			_busy = false
			_hud.flash_message(tr("QR_CHECKED_OUT") if left.ok else tr("ERROR_" + left.error.to_upper()))
		QrPayload.Kind.USER:
			_hud.flash_message(tr("QR_COLLEAGUE_HINT"))


## Opens the camera for any QR code; null when the player closed it.
func _scan_payload() -> QrPayload:
	_busy = true
	PlayTime.begin_minigame()
	var payload: QrPayload = await _minigame_panel.scan_code()
	PlayTime.end_minigame()
	_busy = false
	return payload


## Sends a room door code to the server. Door codes are static, so they count only after the entry
## code at the reception. Returns true when the server accepted it.
func _enter_room(room_id: StringName) -> bool:
	if OfficeFloors.floor_of_room(room_id) == &"":
		_hud.flash_message(tr("QR_UNKNOWN_ROOM"))
		return false
	_busy = true
	var entered: BackendModels.ActionResult = await Backend.enter_room(String(room_id))
	_busy = false
	if not entered.ok:
		_hud.flash_message(tr("ERROR_" + entered.error.to_upper()))
		return false
	Presence.set_zone_from_qr(room_id)
	return true


## The character walks to the room the player is physically in, riding the lift to another floor.
func _move_to_room(room_id: StringName) -> void:
	var floor_id: StringName = OfficeFloors.floor_of_room(room_id)
	if floor_id != OfficeFloors.current:
		OfficeFloors.pending_room = room_id
		_travel(floor_id)
		return
	_walk_to_room(room_id)


## After a room code: tells how many open tasks of today can be taken in this room.
func _hint_room_tasks(room_id: StringName) -> void:
	var count: int = _tasks.filter(
		func(task: BackendModels.TaskInfo) -> bool: return task.room == room_id and not task.is_closed() and not task.is_check_in()
	).size()
	if count > 0:
		_hud.flash_message(tr("QR_ROOM_TASKS") % count)


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


## Arrival at the office: the entry code scan opens right away, no need to pick the check-in task.
## Returns true when the check-in started.
func _auto_check_in() -> bool:
	if Backend.profile == null or Backend.profile.in_office:
		return false
	for task: BackendModels.TaskInfo in _tasks:
		if task.minigame == CHECK_IN_MINIGAME and not task.is_closed() and task.floor_id == OfficeFloors.current:
			_stop_player()
			await _start_task(task)
			return true
	return false


func _on_request_failed(error: String) -> void:
	_hud.flash_message(tr("ERROR_" + error.to_upper()))


func _on_zone_changed(room_id: StringName) -> void:
	if _is_modal_open() and OfficeFloors.floor_of_room(room_id) == OfficeFloors.current:
		_pending_room = room_id


func _on_banner_pressed(kind: String) -> void:
	if not kind.is_empty() and not _is_modal_open():
		_corner.open_inbox()


# --- Floors ------------------------------------------------------------------------


## Fades out and reloads the office on the other floor; the player steps out of the lift there.
func _travel(floor_id: StringName) -> void:
	if _leaving:
		return
	_leaving = true
	_hud.flash_message(tr("LIFT_RIDING") % OfficeFloors.title(floor_id))
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished
	OfficeFloors.current = floor_id
	OfficeFloors.arrived_by_lift = true
	get_tree().change_scene_to_file(OFFICE_SCENE)


## After a lift ride: walk to the room that sent the player here.
func _resume_after_lift() -> void:
	var room_id: StringName = OfficeFloors.pending_room
	OfficeFloors.pending_room = &""
	if room_id != &"":
		_walk_to_room(room_id)


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


## The office visit counts from the check-in, so from then on the player can leave at any time.
func _update_go_home() -> void:
	var profile: BackendModels.Profile = Backend.profile
	if _home_button != null or profile == null or not (profile.present_today or profile.in_office):
		return
	var all_closed: bool = not _has_open_tasks()
	_home_button = _hud.add_wide_action(tr("HUD_GO_HOME"), all_closed)
	_home_button.pressed.connect(_go_home)
	if all_closed:
		_hud.flash_message(tr("HUD_ALL_DONE"))


func _has_open_tasks() -> bool:
	return _tasks.any(func(task: BackendModels.TaskInfo) -> bool: return not task.is_closed())


## Closes the office interval on the server, walks the player out through the entrance, then plays
## the evening cutscene. Open tasks simply stay undone: the visit already counts.
func _go_home() -> void:
	if _is_modal_open():
		return
	if _has_open_tasks() and not await _choice.ask(tr("HUD_GO_HOME_QUESTION"), tr("HUD_GO_HOME_CONFIRM"), tr("HUD_GO_HOME_CANCEL")):
		return
	if Backend.profile != null and Backend.profile.in_office:
		_busy = true
		# A failure is no reason to stay: an interval left open ends with the day.
		await Backend.leave_office()
		_busy = false
	_leaving = true
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
