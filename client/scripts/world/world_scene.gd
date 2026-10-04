class_name WorldScene
extends Node2D
## Shared gameplay on a 3/4 map: player, camera, tap marker and HUD. The player does not steer the
## character: it lives by itself (the autopilot walks it around, scenes add their own activities in
## _run_activity()), and taps on the map only reach scene objects such as task markers.
## Expects children WorldMap, TapMarker, Entities/Player, GameCamera, Hud and CrtOverlay.

const SNAP_RADIUS_CELLS: int = 2
const CAMERA_MARGIN: float = 48.0
## Pause between two activities of the character, in seconds.
const AUTOPILOT_PAUSE_MIN: float = 2.0
const AUTOPILOT_PAUSE_MAX: float = 6.0
## A walk to a random spot ends within this many cells of the character.
const WANDER_RADIUS_CELLS: int = 10
const WANDER_TRIES: int = 12

var _current_room_id: StringName = &""
var _autopilot_left: float = 1.5
## An activity coroutine is running.
var _autopilot_busy: bool = false

@onready var _map: WorldMap = $WorldMap
@onready var _entities: Node2D = $Entities
@onready var _player: Player = $Entities/Player
@onready var _camera: GameCamera = $GameCamera
@onready var _marker: TapMarker = $TapMarker
@onready var _hud: Hud = $Hud
@onready var _crt: CanvasLayer = $CrtOverlay


func _setup_world(layout: MapLayout) -> void:
	_map.build(layout)
	_player.global_position = _map.cell_to_world(layout.spawn_cell)
	_player.arrived.connect(_on_player_arrived)
	_camera.set_bounds(_map.get_bounds(), CAMERA_MARGIN)
	_camera.snap_to_target()
	_map.populate_props(_entities)


func _unhandled_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.index == 0:
		if touch.pressed and not _is_ui_blocking():
			_on_tap(_screen_to_world(touch.position))
		get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if OS.is_debug_build() and key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_crt.visible = not _crt.visible


func _process(delta: float) -> void:
	_update_autopilot(delta)
	_update_room()


## Overridden by scenes with modal UI; input to the map and the autopilot pause while it returns true.
func _is_modal_open() -> bool:
	return false


func _is_ui_blocking() -> bool:
	return _is_modal_open() or get_viewport().gui_get_hovered_control() != null


## A tap on the map: scenes react to their objects (task markers); the character is not steered.
func _on_tap(_world_position: Vector2) -> void:
	pass


## Overridden by scenes that queue an action on arrival.
func _cancel_pending_actions() -> void:
	pass


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


# --- Autopilot -------------------------------------------------------------------


func _update_autopilot(delta: float) -> void:
	if _autopilot_busy or _is_modal_open() or _player.is_walking() or _player.is_talking():
		return
	_autopilot_left -= delta
	if _autopilot_left > 0.0:
		return
	_autopilot_busy = true
	await _run_activity()
	_autopilot_busy = false
	_autopilot_left = randf_range(AUTOPILOT_PAUSE_MIN, AUTOPILOT_PAUSE_MAX)


## One thing the character does by itself. Scenes override it; the default is a short stroll.
func _run_activity() -> void:
	await _wander()


## Walks to a random reachable spot nearby.
func _wander() -> void:
	var origin: Vector2i = _player_cell()
	for i: int in WANDER_TRIES:
		var offset: Vector2i = Vector2i(randi_range(-WANDER_RADIUS_CELLS, WANDER_RADIUS_CELLS), randi_range(-WANDER_RADIUS_CELLS, WANDER_RADIUS_CELLS))
		if _map.is_walkable(origin + offset) and await _auto_walk(origin + offset):
			return


## Autopilot walk without the tap marker. Resolves once the character stops: true when it reached
## `cell`, false when there is no path or the walk was interrupted (a task started, the scene ends).
func _auto_walk(cell: Vector2i) -> bool:
	if _is_modal_open():
		return false
	var path: PackedVector2Array = _map.find_path(_player.global_position, cell)
	if path.is_empty():
		return false
	_player.walk_path(path)
	while is_inside_tree() and _player.is_walking():
		await get_tree().process_frame
	return is_inside_tree() and _player_cell() == cell and not _is_modal_open()


## Waits `seconds` unless a modal opens; true when the wait ran out undisturbed.
func _auto_wait(seconds: float) -> bool:
	var left: float = seconds
	while left > 0.0:
		if not is_inside_tree() or _is_modal_open():
			return false
		await get_tree().process_frame
		left -= get_process_delta_time()
	return true


func _walk_to_cell(cell: Vector2i, tapped_position: Vector2 = Vector2.INF) -> bool:
	var path: PackedVector2Array = _map.find_path(_player.global_position, cell)
	if path.is_empty():
		_show_blocked(tapped_position if tapped_position != Vector2.INF else _map.cell_to_world(cell))
		return false
	_player.walk_path(path)
	_marker.show_target(_map.cell_to_world(cell))
	_camera.shake(1.0)
	_hud.hide_hint()
	return true


func _show_blocked(world_position: Vector2) -> void:
	_marker.show_blocked(world_position)
	_camera.shake(2.0)
	_hud.flash_message(tr("HUD_BLOCKED"))


func _player_cell() -> Vector2i:
	return _map.world_to_cell(_player.global_position)


func _stop_player() -> void:
	_player.walk_path(PackedVector2Array())
	_marker.hide_marker()


func _on_player_arrived() -> void:
	_marker.hide_marker()


func _update_room() -> void:
	var room: MapLayout.Room = _map.get_room_at(_player_cell())
	if room == null or room.id == _current_room_id:
		return
	_current_room_id = room.id
	_hud.show_room(tr(room.name_key))


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
