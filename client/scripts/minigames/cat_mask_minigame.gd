class_name CatMaskMinigame
extends Minigame
## "Cat mask" (AR): the front camera puts the Alfa red cat on your face: ears, a nose and whiskers
## that follow and tilt with the head. The cat gives commands (smile, wink, open your mouth, tilt your
## head); show each one for a moment. The face detector's expression scores check it (FaceCommands).
## The frames stay on the phone.

const DEFAULT_COMMANDS: int = 5
const DEFAULT_TIME_LIMIT: float = 60.0
const HOLD_SECONDS: float = 0.5
const LOST_FACE_SECONDS: float = 0.8
const DONE_EFFECT_SECONDS: float = 0.7
const VIEW_RECT: Rect2 = Rect2(40, 34, 240, 200)
const CAT_WHITE: Color = Color("#fbfaf8")

var _count: int = DEFAULT_COMMANDS
var _commands: Array[StringName] = []
var _index: int = 0
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _held: float = 0.0
var _since_face: float = LOST_FACE_SECONDS
var _since_done: float = DONE_EFFECT_SECONDS
var _face: SensorModels.Face
var _shows: bool = false
var _ar_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _view: CameraView
var _command_label: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_count = int(task.params.get("commands", DEFAULT_COMMANDS))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	_rng.randomize()
	add_hint(tr("MG_CAT_MASK_HINT"))
	_view = add_camera_view(VIEW_RECT)
	_view.overlay = _draw_overlay
	_command_label = add_big_label(VIEW_RECT.end.y + 6, 15, UiStyle.RED)
	_status = add_status()
	PlatformServices.faces_detected.connect(_on_faces)
	PlatformServices.start_camera(PlatformBackend.CameraMode.FACES, true)


func _exit_tree() -> void:
	super()
	PlatformServices.faces_detected.disconnect(_on_faces)


func _on_faces(faces: Array[SensorModels.Face]) -> void:
	if faces.is_empty():
		return
	_face = faces[0]
	_since_face = 0.0
	# The commands are chosen from what this detector can see, on the first face.
	if _commands.is_empty():
		_commands = FaceCommands.sequence(FaceCommands.available(_face), _count, _rng)
	if _index < _commands.size():
		var roll: float = ArAnchor.of_face(_face, Rect2(Vector2.ZERO, VIEW_RECT.size)).roll()
		_shows = FaceCommands.shows(_commands[_index], _face, roll)


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	_since_face += delta
	_since_done += delta
	if not is_done():
		_update_hold(delta)
		_time_left -= delta
		if _time_left <= 0.0:
			finish(false)
	if _commands.is_empty():
		_command_label.text = tr("MG_CAT_MASK_FIND_FACE")
	else:
		var shown: int = mini(_index, _commands.size() - 1)
		_command_label.text = "%d / %d  %s" % [mini(_index + 1, _commands.size()), _commands.size(), tr("MG_CAT_" + String(_commands[shown]).to_upper())]
	var state: String = tr("MG_CAT_MASK_NO_FACE") if _since_face >= LOST_FACE_SECONDS else ""
	_status.text = "%s   %s" % [state, tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	_view.queue_redraw()


func _update_hold(delta: float) -> void:
	if _commands.is_empty() or not _shows or _since_face >= LOST_FACE_SECONDS:
		_held = 0.0
		return
	_held += delta
	if _held < HOLD_SECONDS:
		return
	_held = 0.0
	_shows = false
	_since_done = 0.0
	_index += 1
	if _index >= _commands.size():
		set_score(_time_left / _time_limit)
		proof["commands"] = _commands.size()
		finish(true)


func _draw_overlay(view: CameraView, image_rect: Rect2) -> void:
	if _face == null or _since_face >= LOST_FACE_SECONDS:
		return
	var anchor: ArAnchor = ArAnchor.of_face(_face, image_rect)
	draw_cat(view, anchor, _ar_time, _held > 0.0)
	var age: float = _since_done / DONE_EFFECT_SECONDS
	ArPainter.burst(view, anchor.top, 30.0, age, UiStyle.GOLD)
	ArPainter.pop_text(view, anchor.top + Vector2(0, -8), tr("MG_CAT_MASK_MEOW"), age)


## The red cat on a face: ears on the forehead, a nose and whiskers under the eyes, all tilted with
## the head and sized by the eye span. `is_happy` lights the ears while a command is held.
static func draw_cat(canvas: CanvasItem, anchor: ArAnchor, time: float, is_happy: bool) -> void:
	var span: float = anchor.eye_span()
	if span < 2.0:
		return
	var roll: float = anchor.roll()
	var up: Vector2 = Vector2(0, -1).rotated(roll)
	var forehead: float = anchor.eye_center().distance_to(anchor.top)
	var ear_base: Vector2 = anchor.eye_center() + up * forehead * 0.85
	canvas.draw_set_transform(ear_base, roll)
	var wiggle: float = sin(time * 6.0) * span * 0.04
	for side: float in [-1.0, 1.0]:
		var outer: PackedVector2Array = PackedVector2Array([
			Vector2(side * span * 0.25, 0), Vector2(side * span * 0.85, 0), Vector2(side * span * 0.62 + wiggle * side, -span * 0.75),
		])
		canvas.draw_colored_polygon(outer, UiStyle.RED)
		var inner: PackedVector2Array = PackedVector2Array([
			Vector2(side * span * 0.38, -span * 0.05), Vector2(side * span * 0.72, -span * 0.05), Vector2(side * span * 0.6 + wiggle * side, -span * 0.52),
		])
		canvas.draw_colored_polygon(inner, UiStyle.GOLD if is_happy else CAT_WHITE)
		ArPainter.neon_polyline(canvas, PackedVector2Array([outer[0], outer[2], outer[1]]), ArPainter.NEON_PINK if is_happy else UiStyle.RED_DARK, 1.5)
	canvas.draw_set_transform(anchor.eye_center(), roll)
	var nose: Vector2 = Vector2(0, span * 0.42)
	canvas.draw_colored_polygon(PackedVector2Array([nose + Vector2(-span * 0.1, -span * 0.06), nose + Vector2(span * 0.1, -span * 0.06), nose + Vector2(0, span * 0.06)]), UiStyle.RED)
	for side: float in [-1.0, 1.0]:
		for row: int in 3:
			var start: Vector2 = nose + Vector2(side * span * 0.14, span * (row - 1) * 0.06)
			canvas.draw_line(start, start + Vector2(side * span * 0.45, span * (row - 1) * 0.1), CAT_WHITE, 1.5)
	canvas.draw_set_transform(Vector2.ZERO)
