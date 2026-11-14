class_name LoungeBugs
extends Control
## Shared seeded AR waves, independent camera orientation on each device, server-authoritative catches.

signal caught(index: int)

var room: Dictionary = {}
var _swarm: BugSwarm
var _wave: int = -1
var _view: CameraView
var _pending: Dictionary[int, bool] = {}
var _label: Label
var _ready_for_camera: bool = false


func _init(data: Dictionary = {}) -> void:
	room = data
	custom_minimum_size = Vector2(288, 310)


func _ready() -> void:
	_view = CameraView.new()
	_view.position = Vector2(0, 24)
	_view.size = Vector2(288, 260)
	_view.overlay = _draw_bugs
	add_child(_view)
	_label = UiStyle.make_label("", 11)
	add_child(_label)
	update_room(room)
	var features: Array[PlatformBackend.Feature] = [PlatformBackend.Feature.CAMERA, PlatformBackend.Feature.ACCELEROMETER]
	if not PlatformServices.has_features(features) or not await PlatformServices.request_access(features):
		_label.text = "Для AR нужны камера и датчики движения."
		return
	PlatformServices.start_camera(PlatformBackend.CameraMode.PREVIEW, false)
	_ready_for_camera = true


func _exit_tree() -> void:
	PlatformServices.stop_all()


func update_room(data: Dictionary) -> void:
	room = data
	var wave: int = int(room.get("wave", 0))
	if wave != _wave:
		var yaw: float = _swarm.view_yaw if _swarm != null else 0.0
		var pitch: float = _swarm.view_pitch if _swarm != null else 0.0
		_swarm = BugSwarm.new(8, maxi(1, int(room.get("seed", 1))) + wave)
		_swarm.view_yaw = yaw
		_swarm.view_pitch = pitch
		_wave = wave
		_pending.clear()
	_pending.clear()
	var confirmed: Array = room.get("caught", [])
	for i: int in _swarm.bugs.size():
		_swarm.bugs[i].caught = confirmed.has(_wave * 8 + i)
		if _swarm.bugs[i].caught:
			_pending.erase(i)
	if _label != null:
		_label.text = "Волна %d/3 · поворачивай телефон, золотой баг: 3 очка" % (_wave + 1)


func _process(delta: float) -> void:
	if _swarm == null or not _ready_for_camera:
		return
	_swarm.update(delta, PlatformServices.get_rotation_rate())
	_view.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var point: Variant = Minigame.press_position(event)
	if point == null or not _ready_for_camera or _swarm == null:
		return
	var bug: BugSwarm.Bug = _swarm.catch_at((point as Vector2) - _view.position, _view.size)
	if bug == null:
		return
	var index: int = _swarm.bugs.find(bug)
	bug.caught = false
	if not _pending.get(index, false):
		_pending[index] = true
		caught.emit(_wave * 8 + index)


func _draw_bugs(view: CameraView, _image_rect: Rect2) -> void:
	if _swarm == null:
		return
	for i: int in _swarm.bugs.size():
		var bug: BugSwarm.Bug = _swarm.bugs[i]
		if bug.caught or not _swarm.is_visible(bug, view.size):
			continue
		var point: Vector2 = _swarm.project(bug, view.size)
		var color: Color = ArPainter.NEON_CYAN if _pending.get(i, false) else (UiStyle.GOLD if i == 7 else ArPainter.NEON_PINK)
		view.draw_circle(point, 11 if i == 7 else 9, color)
		view.draw_circle(point + Vector2(-3, -2), 2, Color.WHITE)
		view.draw_circle(point + Vector2(3, -2), 2, Color.WHITE)
		for side: int in [-1, 1]:
			for leg: int in 3:
				view.draw_line(point + Vector2(side * 6, leg * 5 - 5), point + Vector2(side * 14, leg * 6 - 7), color, 2)
