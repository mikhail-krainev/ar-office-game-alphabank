class_name BugHuntMinigame
extends Minigame
## "Bug hunt" (AR): bugs hang in the air all around the player. The back camera shows the office and
## the gyroscope turns the view (BugSwarm), so the player turns around with the phone, finds a bug
## over the real room and taps it. An arrow at the edge shows where the nearest bug is. Only turning
## counts, not walking. The frames stay on the phone.

const DEFAULT_BUGS: int = 8
const DEFAULT_TIME_LIMIT: float = 60.0
const VIEW_RECT: Rect2 = Rect2(16, 34, 288, 270)
const BUG_SIZE: float = 9.0
const ARROW_INSET: float = 14.0
const CATCH_EFFECT_SECONDS: float = 0.6
const BUG_COLORS: Array[Color] = [
	Color("#39ff7a"), Color("#ff2e88"), Color("#2ef2ff"), Color("#f7c948")
]

var _needed: int = DEFAULT_BUGS
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _swarm: BugSwarm
var _ar_time: float = 0.0
## Recent catches for the effect: [view position, seconds since].
var _catches: Array[Array] = []

var _view: CameraView
var _count_label: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_needed = int(task.params.get("bugs", DEFAULT_BUGS))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	_swarm = BugSwarm.new(_needed)
	add_hint(tr("MG_BUG_HUNT_HINT"))
	_view = add_camera_view(VIEW_RECT)
	_view.overlay = _draw_bugs
	_count_label = add_big_label(VIEW_RECT.end.y - 30, 16, Color.WHITE)
	_status = add_status()
	PlatformServices.start_camera(PlatformBackend.CameraMode.PREVIEW, false)


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	for entry: Array in _catches:
		entry[1] = float(entry[1]) + delta
	_catches = _catches.filter(
		func(entry: Array) -> bool: return float(entry[1]) < CATCH_EFFECT_SECONDS
	)
	if not is_done():
		_swarm.update(delta, PlatformServices.get_rotation_rate())
		_time_left -= delta
		if _time_left <= 0.0:
			finish(false)
	_count_label.text = "%d / %d" % [_swarm.caught_count(), _needed]
	_status.text = tr("MG_TIME") % ceili(maxf(_time_left, 0.0))
	_view.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var press: Variant = Minigame.press_position(event)
	if press == null or is_done():
		return
	var tap: Vector2 = (press as Vector2) - VIEW_RECT.position
	var bug: BugSwarm.Bug = _swarm.catch_at(tap, VIEW_RECT.size)
	if bug == null:
		return
	_catches.append([_swarm.project(bug, VIEW_RECT.size), 0.0])
	accept_event()
	if _swarm.caught_count() >= _needed:
		set_score(_time_left / _time_limit)
		proof["bugs"] = _swarm.caught_count()
		finish(true)


func _draw_bugs(view: CameraView, _image_rect: Rect2) -> void:
	var size: Vector2 = view.size
	for index: int in _swarm.bugs.size():
		var bug: BugSwarm.Bug = _swarm.bugs[index]
		if bug.caught or not _swarm.is_visible(bug, size):
			continue
		_draw_bug(
			view, _swarm.project(bug, size), bug.heading, BUG_COLORS[index % BUG_COLORS.size()]
		)
	for entry: Array in _catches:
		var age: float = float(entry[1]) / CATCH_EFFECT_SECONDS
		ArPainter.burst(view, entry[0], 24.0, age, UiStyle.GOLD)
		ArPainter.pop_text(view, entry[0], tr("MG_BUG_HUNT_CAUGHT"), age)
	_draw_arrow(view, size)


## A pixel bug: body, head, wiggling legs and antennae, with a neon glow.
func _draw_bug(view: CameraView, at: Vector2, heading: float, color: Color) -> void:
	view.draw_set_transform(at, heading)
	var wiggle: float = sin(_ar_time * 18.0) * 2.0
	view.draw_circle(Vector2.ZERO, BUG_SIZE + 4.0, Color(color, 0.18))
	for side: float in [-1.0, 1.0]:
		for leg: int in 3:
			var x: float = (leg - 1) * 4.0
			var swing: float = wiggle * (1.0 if leg % 2 == 0 else -1.0)
			view.draw_line(
				Vector2(x, 0), Vector2(x + swing, side * (BUG_SIZE + 3.0)), UiStyle.INK, 2.0
			)
		view.draw_line(
			Vector2(BUG_SIZE, side * 2.0),
			Vector2(BUG_SIZE + 5.0, side * 5.0 + wiggle * 0.5),
			color,
			1.0
		)
	view.draw_set_transform(at, heading, Vector2(1.0, 0.7))
	view.draw_circle(Vector2.ZERO, BUG_SIZE, color)
	view.draw_set_transform(at, heading)
	view.draw_circle(Vector2(BUG_SIZE * 0.8, 0), BUG_SIZE * 0.45, UiStyle.INK)
	view.draw_line(Vector2(-BUG_SIZE * 0.8, 0), Vector2(BUG_SIZE * 0.4, 0), UiStyle.INK, 1.0)
	view.draw_set_transform(Vector2.ZERO)


## When no bug is in view: an arrow at the left or right edge towards the nearest one.
func _draw_arrow(view: CameraView, size: Vector2) -> void:
	for bug: BugSwarm.Bug in _swarm.bugs:
		if not bug.caught and _swarm.is_visible(bug, size):
			return
	var turn: float = _swarm.nearest_turn()
	if is_zero_approx(turn):
		return
	var side: float = signf(turn)
	var tip: Vector2 = Vector2(size.x / 2.0 + side * (size.x / 2.0 - ARROW_INSET), size.y / 2.0)
	var pulse: float = 4.0 * absf(sin(_ar_time * 5.0))
	tip.x -= side * pulse
	var points: PackedVector2Array = PackedVector2Array(
		[tip, tip + Vector2(-side * 14.0, -10.0), tip + Vector2(-side * 14.0, 10.0)]
	)
	view.draw_colored_polygon(points, ArPainter.NEON_CYAN)
	ArPainter.neon_polyline(
		view, PackedVector2Array([points[0], points[1], points[2], points[0]]), Color.WHITE, 1.0
	)
