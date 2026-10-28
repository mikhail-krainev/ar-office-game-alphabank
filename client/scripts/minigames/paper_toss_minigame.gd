class_name PaperTossMinigame
extends Minigame
## "Paper basketball" (AR): an Alfa-red bin stands somewhere in the room around you. Turn with the
## phone to find it through the camera, then swipe up to throw a paper ball: the swipe length is the
## strength, its sideways part the aim, and the wind of each throw carries the ball. Land the needed
## hits before the time runs out. The gyroscope turns the view (PaperToss); the frames stay on the phone.

const DEFAULT_HITS: int = 5
const DEFAULT_TIME_LIMIT: float = 75.0
const VIEW_RECT: Rect2 = Rect2(16, 34, 288, 270)
const FLIGHT_SECONDS: float = 0.9
const RESULT_SECONDS: float = 0.8
## Swipes shorter than this (view pixels) are taps, not throws.
const MIN_SWIPE: float = 18.0
const BALL_RADIUS: float = 9.0
const BIN_SIZE: Vector2 = Vector2(30, 36)
const ARROW_INSET: float = 14.0
const PAPER: Color = Color("#f4f1ea")

var _needed: int = DEFAULT_HITS
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _toss: PaperToss
var _hits: int = 0
var _throws: int = 0
var _flight: PaperToss.Throw
var _flight_time: float = 0.0
var _press: Variant = null
## The last landed throw and the seconds since, for the "IN!" / "MISS" effect.
var _landed: PaperToss.Throw
var _since_landed: float = RESULT_SECONDS
var _ar_time: float = 0.0

var _view: CameraView
var _count_label: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_needed = int(task.params.get("hits", DEFAULT_HITS))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	_toss = PaperToss.new()
	add_hint(tr("MG_PAPER_TOSS_HINT"))
	_view = add_camera_view(VIEW_RECT)
	_view.overlay = _draw_scene
	_count_label = add_big_label(VIEW_RECT.end.y - 30, 16, Color.WHITE)
	_status = add_status()
	PlatformServices.start_camera(PlatformBackend.CameraMode.PREVIEW, false)


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	_since_landed += delta
	if not is_done():
		_toss.update(delta, PlatformServices.get_rotation_rate())
		_update_flight(delta)
		_time_left -= delta
		if _time_left <= 0.0:
			finish(false)
	_count_label.text = "%d / %d" % [_hits, _needed]
	_status.text = "%s   %s" % [_wind_text(), tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	_view.queue_redraw()


func _update_flight(delta: float) -> void:
	if _flight == null:
		return
	_flight_time += delta
	if _flight_time < FLIGHT_SECONDS:
		return
	_landed = _flight
	_flight = null
	_since_landed = 0.0
	if _landed.hit:
		_hits += 1
	_toss.new_wind()
	if _hits >= _needed:
		set_score(0.5 * _time_left / _time_limit + 0.5 * float(_hits) / maxf(_throws, 1.0))
		proof["hits"] = _hits
		proof["throws"] = _throws
		finish(true)


func _gui_input(event: InputEvent) -> void:
	if is_done():
		return
	var press: Variant = Minigame.press_position(event)
	if press != null:
		_press = (press as Vector2) - VIEW_RECT.position
		accept_event()
		return
	if not Minigame.is_release(event) or _press == null:
		return
	var release: Vector2 = (event as InputEventMouseButton).position - VIEW_RECT.position
	var swipe: Vector2 = release - (_press as Vector2)
	_press = null
	accept_event()
	if _flight != null or swipe.length() < MIN_SWIPE or swipe.y >= 0.0:
		return
	_throws += 1
	_flight = _toss.throw(swipe, VIEW_RECT.size)
	_flight_time = 0.0


func _wind_text() -> String:
	var arrow: String = "→" if _toss.wind > 0.0 else "←"
	return tr("MG_PAPER_TOSS_WIND") % [arrow, absf(_toss.wind)]


func _draw_scene(view: CameraView, _image_rect: Rect2) -> void:
	var view_size: Vector2 = view.size
	var bin_at: Vector2 = _toss.project(_toss.bin_direction(), view_size)
	var bin_visible: bool = Rect2(Vector2.ZERO, view_size).grow(BIN_SIZE.x).has_point(bin_at)
	if bin_visible:
		_draw_bin(view, bin_at)
	else:
		_draw_arrow(view, view_size)
	if _flight != null:
		var t: float = _flight_time / FLIGHT_SECONDS
		var at: Vector2 = _toss.project(PaperToss.flight_point(_flight, t), view_size)
		_draw_ball(view, at, lerpf(BALL_RADIUS, BALL_RADIUS * 0.45, t), t)
	elif _press != null:
		# The ball waits in the hand at the bottom of the view.
		_draw_ball(view, Vector2(view_size.x / 2.0, view_size.y - 24.0), BALL_RADIUS, 0.0)
	if _landed != null:
		var age: float = _since_landed / RESULT_SECONDS
		var landed_at: Vector2 = _toss.project(Vector2(_landed.landing_yaw, _landed.landing_pitch), view_size)
		if _landed.hit:
			ArPainter.burst(view, bin_at, 30.0, age, UiStyle.GOLD)
			ArPainter.pop_text(view, bin_at + Vector2(0, -BIN_SIZE.y), tr("MG_PAPER_TOSS_IN"), age)
		else:
			ArPainter.pop_text(view, landed_at, tr("MG_PAPER_TOSS_MISS"), age, ArPainter.NEON_PINK)


## A pixel bin with the Alfa red band and a dark opening, standing on the floor point `at`.
func _draw_bin(view: CameraView, at: Vector2) -> void:
	var top: Vector2 = at - Vector2(BIN_SIZE.x / 2.0, BIN_SIZE.y)
	view.draw_rect(Rect2(top + Vector2(3, 6), BIN_SIZE - Vector2(6, 6)), Color("#d9d2c6"))
	view.draw_rect(Rect2(top + Vector2(3, 14), Vector2(BIN_SIZE.x - 6, 8)), UiStyle.RED)
	view.draw_string(ThemeDB.fallback_font, top + Vector2(BIN_SIZE.x / 2.0 - 4, 21), "А", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	view.draw_rect(Rect2(top, Vector2(BIN_SIZE.x, 6)), UiStyle.INK)
	ArPainter.neon_line(view, top, top + Vector2(BIN_SIZE.x, 0), ArPainter.NEON_CYAN, 1.0)


## A crumpled paper ball, spinning in flight.
func _draw_ball(view: CameraView, at: Vector2, radius: float, t: float) -> void:
	view.draw_circle(at, radius + 2.0, Color(0, 0, 0, 0.25))
	view.draw_circle(at, radius, PAPER)
	var spin: float = _ar_time * 8.0 + t * 6.0
	for crease: int in 3:
		var angle: float = spin + crease * TAU / 3.0
		view.draw_line(at, at + Vector2(cos(angle), sin(angle)) * radius * 0.8, UiStyle.PAPER_EDGE, 1.0)


## When the bin is off screen: an arrow at the left or right edge towards it.
func _draw_arrow(view: CameraView, view_size: Vector2) -> void:
	var side: float = signf(_toss.bin_turn())
	if is_zero_approx(side):
		return
	var tip: Vector2 = Vector2(view_size.x / 2.0 + side * (view_size.x / 2.0 - ARROW_INSET), view_size.y / 2.0)
	tip.x -= side * 4.0 * absf(sin(_ar_time * 5.0))
	var points: PackedVector2Array = PackedVector2Array([tip, tip + Vector2(-side * 14.0, -10.0), tip + Vector2(-side * 14.0, 10.0)])
	view.draw_colored_polygon(points, ArPainter.NEON_CYAN)
	ArPainter.neon_polyline(view, PackedVector2Array([points[0], points[1], points[2], points[0]]), Color.WHITE, 1.0)
