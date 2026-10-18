class_name MoodDoodleMinigame
extends Minigame
## "Mood of the day": the player draws today's mood with a finger, then tries it on in the front
## camera: the drawing sits on the forehead and turns with the head (AR, scripts/ar). The drawing goes
## to the server as the proof and becomes the player's story for today: colleagues in the office see
## it by tapping the avatar on the map. Without face detection the try-on step is skipped.

const SIDE: int = MoodCanvas.SIDE
const CANVAS_SCALE: int = 3
const CANVAS_POSITION: Vector2 = Vector2(64, 34)
const PALETTE: Array[Color] = [
	Color("#1d1d1f"),
	Color("#ef3124"),
	Color("#f7c948"),
	Color("#39ff7a"),
	Color("#2ef2ff"),
	Color("#ff2e88"),
]
const SWATCH: float = 22.0
const BRUSH: int = 2
## The face must stay in the camera this long with the drawing on it before saving.
const TRY_ON_SECONDS: float = 1.5
## The drawing on the forehead is this many eye spans wide.
const FOREHEAD_SCALE: float = 1.3

var _canvas: MoodCanvas = MoodCanvas.new()
var _texture: ImageTexture
var _color: Color = PALETTE[1]
var _drawing: bool = false
var _last_point: Vector2i = Vector2i(-1, -1)
var _trying_on: bool = false
var _faces: Array[SensorModels.Face] = []
var _hold: float = 0.0
var _ar_time: float = 0.0

var _hint: Label
var _status: Label
var _tools: HBoxContainer
var _next: Button
var _view: CameraView


func _ready() -> void:
	_texture = ImageTexture.create_from_image(_canvas.image)
	_hint = add_hint(tr("MG_MOOD_HINT"))
	_status = add_status()
	_build_tools()


func _exit_tree() -> void:
	super()
	if PlatformServices.faces_detected.is_connected(_on_faces):
		PlatformServices.faces_detected.disconnect(_on_faces)


func _build_tools() -> void:
	_tools = HBoxContainer.new()
	_tools.position = Vector2(8, CANVAS_POSITION.y + SIDE * CANVAS_SCALE + 8)
	_tools.add_theme_constant_override("separation", 6)
	add_child(_tools)
	for color: Color in PALETTE:
		var swatch: Button = Button.new()
		swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
		var style: StyleBoxFlat = UiStyle.panel(color, 4, 0)
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", style)
		swatch.add_theme_stylebox_override("pressed", style)
		swatch.pressed.connect(func() -> void: _color = color)
		_tools.add_child(swatch)
	var clear: Button = UiStyle.make_button(tr("MG_MOOD_CLEAR"), false, 10)
	clear.pressed.connect(_clear)
	_tools.add_child(clear)
	_next = UiStyle.make_button(tr("MG_MOOD_TRY_ON"), true, 12)
	_next.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 30)
	_next.position = Vector2(8, STATUS_Y - 38)
	_next.disabled = true
	_next.pressed.connect(_on_next)
	add_child(_next)


func _clear() -> void:
	_canvas.clear()
	_texture.update(_canvas.image)
	_next.disabled = true
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _trying_on or is_done():
		return
	var press: Variant = Minigame.press_position(event)
	if press != null:
		_drawing = _canvas_cell(press as Vector2) != Vector2i(-1, -1)
		_last_point = Vector2i(-1, -1)
		_paint_at(press as Vector2)
		return
	if Minigame.is_release(event):
		_drawing = false
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _drawing:
		_paint_at(motion.position)
		accept_event()


func _paint_at(point: Vector2) -> void:
	var cell: Vector2i = _canvas_cell(point)
	if cell == Vector2i(-1, -1):
		return
	_canvas.stroke(_last_point if _last_point != Vector2i(-1, -1) else cell, cell, BRUSH, _color)
	_last_point = cell
	_texture.update(_canvas.image)
	_next.disabled = _canvas.is_empty()
	queue_redraw()


## Drawing cell under a point of the play area, or (-1, -1) outside the canvas.
func _canvas_cell(point: Vector2) -> Vector2i:
	var local: Vector2 = (point - CANVAS_POSITION) / CANVAS_SCALE
	if local.x < 0.0 or local.y < 0.0 or local.x >= SIDE or local.y >= SIDE:
		return Vector2i(-1, -1)
	return Vector2i(local)


func _on_next() -> void:
	if _canvas.is_empty():
		return
	if not _trying_on and PlatformServices.has_feature(PlatformBackend.Feature.FACE_DETECTION):
		_start_try_on()
		return
	_save()


## Second step: the front camera with the drawing on the forehead.
func _start_try_on() -> void:
	_trying_on = true
	_tools.visible = false
	_next.visible = false
	_hint.text = tr("MG_MOOD_TRY_ON_HINT")
	_view = add_camera_view(Rect2(40, 34, 240, 240))
	_view.overlay = _draw_on_forehead
	PlatformServices.faces_detected.connect(_on_faces)
	PlatformServices.start_camera(PlatformBackend.CameraMode.FACES, true)
	queue_redraw()


func _on_faces(faces: Array[SensorModels.Face]) -> void:
	_faces = faces


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	if not _trying_on or is_done():
		return
	_hold = _hold + delta if not _faces.is_empty() else 0.0
	_status.text = (
		tr("MG_MOOD_HOLD")
		if _faces.is_empty()
		else tr("MG_MOOD_KEEP") % ceili(maxf(0.0, TRY_ON_SECONDS - _hold))
	)
	if _hold >= TRY_ON_SECONDS:
		_save()
	_view.queue_redraw()


func _save() -> void:
	proof["mood_png"] = Marshalls.raw_to_base64(_canvas.image.save_png_to_buffer())
	set_score(1.0)
	finish(true)


func _draw_on_forehead(view: CameraView, image_rect: Rect2) -> void:
	for face: SensorModels.Face in _faces:
		var anchor: ArAnchor = ArAnchor.of_face(face, image_rect)
		var width: float = anchor.eye_span() * FOREHEAD_SCALE
		if width < 4.0:
			continue
		# Between the eye line and the top of the forehead, a little above the middle.
		var at: Vector2 = anchor.top.lerp(anchor.eye_center(), 0.35)
		view.draw_set_transform(at, anchor.roll())
		var rect: Rect2 = Rect2(-Vector2(width, width) / 2.0, Vector2(width, width))
		view.draw_rect(rect.grow(2.0), Color(ArPainter.NEON_PINK, 0.35), false, 2.0)
		view.draw_texture_rect(_texture, rect, false)
		view.draw_set_transform(Vector2.ZERO)
		ArPainter.sparks(view, at, width * 0.75, _ar_time, UiStyle.GOLD)


func _draw() -> void:
	if _trying_on:
		return
	var rect: Rect2 = Rect2(CANVAS_POSITION, Vector2(SIDE, SIDE) * CANVAS_SCALE)
	draw_rect(rect.grow(2), UiStyle.INK)
	draw_rect(rect, UiStyle.PAPER)
	draw_texture_rect(_texture, rect, false)
