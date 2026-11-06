class_name GraffitiMinigame
extends Minigame
## "Graffiti wall" (AR): the phone is tracked in the room (ArTracker: SLAM with real surfaces in the
## phone browser, otherwise its turns and tilts only). The player points the camera at a wall and
## taps: the wall is put there, at the measured distance of the real wall when the world is tracked
## (GraffitiWallPlane), the graffiti that colleagues
## of the office left before shows up on it in perspective and stays on that spot as the phone moves.
## The player sprays their own over it with a can (colour, thin or fat nozzle) for the given seconds
## from the first stroke: the paint lands where the finger's ray meets the wall. The spray layer
## alone goes to the server as the proof; the server paints it over the shared office wall
## (graffiti.go), so the next player sees it. The camera frames stay on the phone.

const DEFAULT_SECONDS: float = 20.0
const VIEW_RECT: Rect2 = Rect2(16, 34, 288, 192)
## The wall is drawn as this many quads, so its texture keeps the perspective.
const WALL_GRID: Vector2i = Vector2i(8, 6)
const PALETTE: Array[Color] = [
	Color("#ef3124"),
	Color("#ffffff"),
	Color("#1d1d1f"),
	Color("#f7c948"),
	Color("#39ff7a"),
	Color("#2ef2ff"),
	Color("#ff2e88"),
]
const SWATCH: float = 22.0
const TOOLS_Y: float = 234.0
## The wall is found (a grid spreads over it), then the old graffiti fades in.
const SCAN_SECONDS: float = 0.8
const REVEAL_SECONDS: float = 0.7
## Paint on a wall lets a little of the wall show through.
const PAINT_ALPHA: float = 0.93
const MIST_DOTS: int = 10
## Coverage of the wall that earns the full score.
const FULL_SCORE_COVERAGE: float = 0.15

var _seconds: float = DEFAULT_SECONDS
var _time_left: float = DEFAULT_SECONDS
var _canvas: GraffitiCanvas = GraffitiCanvas.new()
var _layer: ImageTexture
var _wall: ImageTexture
var _color: Color = PALETTE[0]
var _radius: float = GraffitiCanvas.FAT
var _tracker: ArTracker = ArTracker.new(PaperToss.EYE_HEIGHT, 0.0)
var _is_loaded: bool = false
## Where the wall hangs in the room; null until the player puts it.
var _plane: GraffitiWallPlane
## Seconds since the wall was put; negative before.
var _wall_age: float = -1.0
var _tags: int = 0
var _started: bool = false
var _blocked: bool = false
var _spraying: bool = false
var _last_point: Vector2 = Vector2.ZERO
var _finger: Vector2 = Vector2.ZERO
var _ar_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _view: CameraView
var _credit: LinkButton
var _hint: Label
var _status: Label
var _swatches: Array[Button] = []
var _nozzle: Button
var _done: Button


func _ready() -> void:
	if task != null:
		_seconds = float(task.params.get("seconds", DEFAULT_SECONDS))
	_time_left = _seconds
	_rng.randomize()
	_layer = ImageTexture.create_from_image(_canvas.image)
	_hint = add_hint(tr("MG_GRAFFITI_HINT") % roundi(_seconds))
	_view = add_camera_view(VIEW_RECT)
	_view.prefers_native = false
	_view.overlay = _draw_wall
	_status = add_status()
	_build_tools()
	_tracker.start(VIEW_RECT.size)
	_credit = _tracker.add_credit(self, VIEW_RECT)
	_load_wall()


func _build_tools() -> void:
	var tools: HBoxContainer = HBoxContainer.new()
	tools.position = Vector2(8, TOOLS_Y)
	tools.add_theme_constant_override("separation", 5)
	add_child(tools)
	for color: Color in PALETTE:
		var swatch: Button = Button.new()
		swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
		swatch.pressed.connect(_pick_color.bind(color))
		tools.add_child(swatch)
		_swatches.append(swatch)
	_nozzle = UiStyle.make_button("", false, 10)
	_nozzle.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0 - PALETTE.size() * (SWATCH + 5.0), SWATCH)
	_nozzle.pressed.connect(_toggle_nozzle)
	tools.add_child(_nozzle)
	_done = UiStyle.make_button(tr("MG_GRAFFITI_DONE"), true, 12)
	_done.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 30)
	_done.position = Vector2(8, STATUS_Y - 38)
	_done.disabled = true
	_done.pressed.connect(_submit)
	add_child(_done)
	_style_tools()


func _style_tools() -> void:
	for index: int in _swatches.size():
		var color: Color = PALETTE[index]
		var style: StyleBoxFlat = UiStyle.panel(color, 4, 0)
		style.set_border_width_all(2 if color == _color else 1)
		style.border_color = UiStyle.GOLD if color == _color else UiStyle.PAPER_EDGE
		for state: String in ["normal", "hover", "pressed"]:
			_swatches[index].add_theme_stylebox_override(state, style)
	_nozzle.text = tr("MG_GRAFFITI_FAT") if _radius == GraffitiCanvas.FAT else tr("MG_GRAFFITI_THIN")


func _pick_color(color: Color) -> void:
	_color = color
	_style_tools()


func _toggle_nozzle() -> void:
	_radius = GraffitiCanvas.THIN if _radius == GraffitiCanvas.FAT else GraffitiCanvas.FAT
	_style_tools()


func _load_wall() -> void:
	_status.text = tr("MG_GRAFFITI_LOADING")
	var wall: BackendModels.GraffitiWall = await Backend.social.get_graffiti_wall()
	if is_done() or not is_inside_tree():
		return
	if not wall.ok:
		_blocked = true
		_status.text = ""
		_hint.text = tr("ERROR_" + wall.error.to_upper()) if not wall.error.is_empty() else tr("MG_UNAVAILABLE")
		return
	if wall.image != null:
		_wall = ImageTexture.create_from_image(wall.image)
	_is_loaded = true
	_status.text = tr("MG_GRAFFITI_PLACE")
	_tags = wall.tags


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	_tracker.update(delta)
	_credit.visible = _tracker.uses_engine()
	if _is_loaded and _plane == null and not _blocked:
		_status.text = tr("MG_AR_STARTING") if _tracker.is_starting() else tr("MG_GRAFFITI_PLACE")
	if _wall_age >= 0.0:
		_wall_age += delta
	if _canvas.update(delta):
		_layer.update(_canvas.image)
	if _started and not is_done():
		_time_left -= delta
		_status.text = tr("MG_TIME") % ceili(maxf(_time_left, 0.0))
		if _time_left <= 0.0:
			_spraying = false
			_submit()
	_view.queue_redraw()


func _is_ready_to_paint() -> bool:
	return not _blocked and not is_done() and _wall_age >= SCAN_SECONDS


func _gui_input(event: InputEvent) -> void:
	var press: Variant = Minigame.press_position(event)
	var can_place: bool = _plane == null and _is_loaded and not _blocked and not _tracker.is_starting()
	if press != null and can_place and VIEW_RECT.has_point(press as Vector2):
		_place_wall()
		accept_event()
		return
	if not _is_ready_to_paint():
		return
	if press != null:
		_spraying = VIEW_RECT.has_point(press as Vector2)
		if _spraying:
			_started = true
			_last_point = Vector2.INF
			_spray_to(press as Vector2)
			accept_event()
		return
	if Minigame.is_release(event):
		if _spraying:
			_spraying = false
			_done.disabled = not _canvas.has_enough_paint()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _spraying:
		_spray_to(motion.position)
		accept_event()


## Puts the wall where the phone looks now: on the real wall it hits, or at the usual distance.
func _place_wall() -> void:
	var camera: ArCamera = _camera()
	var view: Rect2 = Rect2(Vector2.ZERO, VIEW_RECT.size)
	var distance: float = GraffitiWallPlane.DISTANCE
	var hit: Variant = _tracker.hit(view.get_center(), view.size)
	if hit != null:
		distance = Vector2((hit as Vector3).x - camera.eye.x, (hit as Vector3).z - camera.eye.z).length()
	_plane = GraffitiWallPlane.facing(camera, view, distance)
	_wall_age = 0.0
	_status.text = tr("MG_GRAFFITI_TAGS") % _tags if _tags > 0 else tr("MG_GRAFFITI_CLEAN")


## Sprays from the last point to the wall pixel under a point of the play area. A finger off the
## wall breaks the stroke.
func _spray_to(point: Vector2) -> void:
	_finger = point - VIEW_RECT.position
	var at: Variant = _plane.pixel_at(_camera(), _finger)
	if at == null:
		_last_point = Vector2.INF
		return
	var pixel: Vector2 = at as Vector2
	_canvas.spray(pixel if _last_point == Vector2.INF else _last_point, pixel, _radius, _color)
	_last_point = pixel
	_layer.update(_canvas.image)


## The camera of the phone as it is held now, over the camera picture.
func _camera() -> ArCamera:
	return _tracker.camera(_view.get_image_rect())


func _submit() -> void:
	if is_done():
		return
	if not _canvas.has_enough_paint():
		finish(false)
		return
	proof["graffiti_png"] = _canvas.to_png_base64()
	var coverage: float = float(_canvas.painted_pixels()) / (GraffitiCanvas.WIDTH * GraffitiCanvas.HEIGHT)
	set_score(coverage / FULL_SCORE_COVERAGE)
	finish(true)


## Before the wall is put, a frame shows where it will hang; then the found wall, the graffiti of
## the office fading in on it in perspective, the player's paint and the mist of the can.
func _draw_wall(view: CameraView, image_rect: Rect2) -> void:
	if not _is_loaded:
		return
	var camera: ArCamera = _tracker.camera(image_rect)
	if _plane == null and _tracker.is_starting():
		return
	if _plane == null:
		_draw_frame(view, camera, GraffitiWallPlane.facing(camera, Rect2(Vector2.ZERO, view.size)), 0.8)
		return
	var age: float = _wall_age / SCAN_SECONDS
	if age < 1.0:
		_draw_frame(view, camera, _plane, 0.8 * (1.0 - age))
	var reveal: float = smoothstep(0.0, 1.0, (_wall_age - SCAN_SECONDS * 0.5) / REVEAL_SECONDS)
	if _wall != null and reveal > 0.0:
		_draw_on_wall(view, camera, _wall, PAINT_ALPHA * reveal)
	_draw_on_wall(view, camera, _layer, PAINT_ALPHA)
	if _spraying:
		_draw_mist(view, camera)


## A texture the size of the wall laid on it: a grid of small quads, each close to the perspective.
func _draw_on_wall(view: CameraView, camera: ArCamera, texture: Texture2D, alpha: float) -> void:
	var wall_size: Vector2 = Vector2(GraffitiCanvas.WIDTH, GraffitiCanvas.HEIGHT)
	var tint: PackedColorArray = PackedColorArray([Color(1, 1, 1, alpha)])
	for column: int in WALL_GRID.x:
		for row: int in WALL_GRID.y:
			var corners: Array[Vector2] = [
				Vector2(column, row), Vector2(column + 1, row), Vector2(column + 1, row + 1), Vector2(column, row + 1)
			]
			var points: PackedVector2Array = PackedVector2Array()
			var uvs: PackedVector2Array = PackedVector2Array()
			for corner: Vector2 in corners:
				var uv: Vector2 = corner / Vector2(WALL_GRID)
				var projected: Vector3 = camera.project(_plane.point(uv * wall_size))
				if projected.z <= 0.0:
					break
				points.append(Vector2(projected.x, projected.y))
				uvs.append(uv)
			if points.size() == corners.size():
				view.draw_polygon(points, tint, uvs, texture)


## The outline of a wall in the room with a grid of dots on it: where it hangs.
func _draw_frame(view: CameraView, camera: ArCamera, plane: GraffitiWallPlane, alpha: float) -> void:
	var color: Color = Color(ArPainter.NEON_CYAN, alpha)
	var wall_size: Vector2 = Vector2(GraffitiCanvas.WIDTH, GraffitiCanvas.HEIGHT)
	var outline: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1), Vector2.ZERO]:
		var projected: Vector3 = camera.project(plane.point(corner * wall_size))
		if projected.z <= 0.0:
			return
		outline.append(Vector2(projected.x, projected.y))
	ArPainter.neon_polyline(view, outline, color, 1.5)
	var step: int = 12
	for x: int in range(step, GraffitiCanvas.WIDTH, step):
		for y: int in range(step, GraffitiCanvas.HEIGHT, step):
			var dot: Vector3 = camera.project(plane.point(Vector2(x, y)))
			if dot.z > 0.0:
				view.draw_rect(Rect2(Vector2(dot.x, dot.y) - Vector2.ONE, Vector2(2, 2)), Color(color, alpha * 0.6))


## Fine paint mist that hangs around the nozzle while spraying, as wide as the nozzle on the wall.
func _draw_mist(view: CameraView, camera: ArCamera) -> void:
	var at: Variant = _plane.pixel_at(camera, _finger)
	if at == null:
		return
	var spread: float = _radius * GraffitiWallPlane.PIXEL * camera.project(_plane.point(at as Vector2)).z * 1.8
	for dot: int in MIST_DOTS:
		var offset: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * spread * sqrt(_rng.randf())
		view.draw_circle(_finger + offset, _rng.randf_range(0.5, 1.5), Color(_color, 0.35))
