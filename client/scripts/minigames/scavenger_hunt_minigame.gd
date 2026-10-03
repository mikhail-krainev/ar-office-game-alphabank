class_name ScavengerHuntMinigame
extends Minigame
## "Scavenger hunt": find the printed ArUco markers (DICT_4X4_50) stuck to office objects: the water
## cooler, a plant, the logo. The web build detects them with js-aruco2.

const DEFAULT_TIME_LIMIT: float = 300.0
const HOLD_SECONDS: float = 0.5
const DEFAULT_TARGETS: Array[Dictionary] = [
	{"marker": 1, "name": "MG_HUNT_COOLER"},
	{"marker": 2, "name": "MG_HUNT_PLANT"},
	{"marker": 3, "name": "MG_HUNT_LOGO"},
]
const LIST_TOP: float = 232.0
const ROW_HEIGHT: float = 22.0

var _targets: Array[Dictionary] = []
var _found: Array[int] = []
var _visible: PackedInt32Array = PackedInt32Array()
var _hold: Dictionary[int, float] = {}
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT

var _view: CameraView
var _status: Label
var _rows: Array[Label] = []


func _ready() -> void:
	_targets = DEFAULT_TARGETS.duplicate(true)
	if task != null:
		if task.params.get("targets") is Array:
			_targets.clear()
			for entry: Variant in task.params["targets"]:
				if entry is Dictionary:
					_targets.append(entry)
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	add_hint(tr("MG_HUNT_HINT"))
	_view = add_camera_view(Rect2(60, 36, 200, 150))
	_view.overlay = _draw_overlay
	for i: int in _targets.size():
		var row: Label = UiStyle.make_label("", 13)
		row.position = Vector2(70, LIST_TOP - 40 + i * ROW_HEIGHT)
		add_child(row)
		_rows.append(row)
	_status = add_status()
	PlatformServices.markers_detected.connect(_on_markers)
	PlatformServices.start_camera(PlatformBackend.CameraMode.MARKERS, false)


func _exit_tree() -> void:
	super()
	PlatformServices.markers_detected.disconnect(_on_markers)


func _on_markers(marker_ids: PackedInt32Array) -> void:
	_visible = marker_ids


func _process(delta: float) -> void:
	super(delta)
	if not is_done():
		_time_left -= delta
		for target: Dictionary in _targets:
			var marker: int = int(target["marker"])
			if _found.has(marker):
				continue
			_hold[marker] = _hold.get(marker, 0.0) + delta if _visible.has(marker) else 0.0
			if _hold[marker] >= HOLD_SECONDS:
				_found.append(marker)
		if _found.size() >= _targets.size():
			set_score(_time_left / _time_limit)
			proof["markers"] = _found.duplicate()
			finish(true)
		elif _time_left <= 0.0:
			finish(false)
	for i: int in _targets.size():
		var found: bool = _found.has(int(_targets[i]["marker"]))
		_rows[i].text = "%s  %s" % ["[x]" if found else "[ ]", tr(str(_targets[i]["name"]))]
		_rows[i].label_settings.font_color = UiStyle.MUTED if found else UiStyle.INK
	_status.text = "%s   %s" % [tr("MG_FOUND") % [_found.size(), _targets.size()], tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	_view.queue_redraw()


func _draw_overlay(view: CameraView, _image_rect: Rect2) -> void:
	var known: bool = false
	for marker: int in _visible:
		if _targets.any(func(target: Dictionary) -> bool: return int(target["marker"]) == marker):
			known = true
	if known:
		view.draw_rect(Rect2(Vector2(4, 4), view.size - Vector2(8, 8)), UiStyle.RED, false, 3.0)
