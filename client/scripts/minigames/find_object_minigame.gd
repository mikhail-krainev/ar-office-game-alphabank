class_name FindObjectMinigame
extends Minigame
## "Find the object": the game names an everyday office thing - a mug, a plant, a screen - and the
## player shows it to the camera. MediaPipe models recognize it; the frame never leaves the phone.
## Each round asks for a different object, and the camera has to leave it before the next round.

const DEFAULT_ROUNDS: int = 3
const DEFAULT_TIME_LIMIT: float = 120.0
const HOLD_SECONDS: float = 0.8
const METER_RECT: Rect2 = Rect2(40, 256, 240, 10)

var _targets: Array[OfficeObjects.Target] = []
var _round: int = 0
var _rounds: int = DEFAULT_ROUNDS
var _hold: float = 0.0
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _labels: Array[SensorModels.ObjectLabel] = []
var _confidence: float = 0.0
var _flash: float = 0.0

var _view: CameraView
var _target_label: Label
var _seen_label: Label
var _status: Label


func _ready() -> void:
	var pool: Array[OfficeObjects.Target] = OfficeObjects.defaults()
	if task != null:
		pool = OfficeObjects.from_ids(task.params.get("objects", []))
		_rounds = int(task.params.get("rounds", DEFAULT_ROUNDS))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	pool.shuffle()
	_rounds = mini(_rounds, pool.size())
	_targets = pool.slice(0, _rounds)
	_time_left = _time_limit
	add_hint(tr("MG_FIND_OBJECT_HINT"))
	_view = add_camera_view()
	_view.overlay = _draw_overlay
	_target_label = add_big_label(224, 20, UiStyle.RED)
	_seen_label = add_big_label(280, 11, UiStyle.MUTED)
	_status = add_status()
	PlatformServices.labels_detected.connect(_on_labels)
	PlatformServices.start_camera(PlatformBackend.CameraMode.LABELS, false)
	_update_labels()


func _exit_tree() -> void:
	super()
	PlatformServices.labels_detected.disconnect(_on_labels)


func _on_labels(labels: Array[SensorModels.ObjectLabel]) -> void:
	_labels = labels
	_confidence = _current().confidence_in(labels)


func _current() -> OfficeObjects.Target:
	return _targets[mini(_round, _targets.size() - 1)]


func _process(delta: float) -> void:
	super(delta)
	_flash = maxf(0.0, _flash - delta * 2.0)
	if not is_done():
		_time_left -= delta
		_hold = _hold + delta if _confidence >= OfficeObjects.MIN_CONFIDENCE else 0.0
		if _hold >= HOLD_SECONDS:
			_found()
		elif _time_left <= 0.0:
			finish(false)
	_update_labels()
	_view.queue_redraw()
	queue_redraw()


func _found() -> void:
	_hold = 0.0
	_confidence = 0.0
	_flash = 1.0
	_round += 1
	if _round >= _rounds:
		set_score(_time_left / _time_limit)
		proof["objects"] = _targets.map(func(target: OfficeObjects.Target) -> String: return target.id)
		finish(true)


func _update_labels() -> void:
	_target_label.text = tr(_current().name_key).to_upper()
	var seen: PackedStringArray = PackedStringArray()
	for label: SensorModels.ObjectLabel in _labels:
		seen.append("%s %d%%" % [label.id, roundi(label.confidence * 100.0)])
	_seen_label.text = tr("MG_FIND_OBJECT_SEEN") % ", ".join(seen) if not seen.is_empty() else tr("MG_FIND_OBJECT_NOTHING")
	_status.text = "%s   %s" % [tr("MG_ROUND") % [mini(_round + 1, _rounds), _rounds], tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]


func _draw_overlay(view: CameraView, _image_rect: Rect2) -> void:
	var color: Color = UiStyle.RED if _confidence >= OfficeObjects.MIN_CONFIDENCE else Color.WHITE
	view.draw_rect(Rect2(Vector2(4, 4), view.size - Vector2(8, 8)), color, false, 2.0)
	if _flash > 0.0:
		view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(1, 1, 1, _flash * 0.6))


func _draw() -> void:
	draw_rect(METER_RECT.grow(2), UiStyle.INK)
	draw_rect(METER_RECT, UiStyle.PAPER)
	var filled: float = METER_RECT.size.x * clampf(_confidence, 0.0, 1.0)
	draw_rect(Rect2(METER_RECT.position, Vector2(filled, METER_RECT.size.y)), UiStyle.RED)
	# Mark where the object counts as recognized.
	var threshold_x: float = METER_RECT.position.x + METER_RECT.size.x * OfficeObjects.MIN_CONFIDENCE
	draw_rect(Rect2(threshold_x, METER_RECT.position.y - 3, 1, METER_RECT.size.y + 6), UiStyle.INK)
	var hold_width: float = 240.0 * _hold / HOLD_SECONDS
	draw_rect(Rect2(METER_RECT.position + Vector2(0, 14), Vector2(hold_width, 4)), UiStyle.RED)
