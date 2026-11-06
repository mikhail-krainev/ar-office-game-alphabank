class_name PaperTossMinigame
extends Minigame
## "Paper basketball" (AR): the phone is tracked in the room (ArTracker: SLAM with real surfaces in
## the phone browser, otherwise its turns and tilts only, with the floor as a plane). The player aims
## the ring at the floor (or a table) and taps: an office bin drops onto that spot and stays there as
## the phone moves and the player walks; an arrow at the edge shows where it is when it is out of the
## picture. Swipe up to throw a paper ball where the phone looks: the swipe length is
## the strength (a farther bin needs a harder throw), its sideways part the aim, and the wind of each
## throw carries the ball. Misses stay lying on the floor. Land the needed hits before the time runs
## out. Without any tracking the phone counts as held still, tilted at the floor. The frames stay on
## the phone.

enum Stage { PLACING, DROPPING, PLAYING }

const DEFAULT_HITS: int = 5
const DEFAULT_TIME_LIMIT: float = 75.0
const VIEW_RECT: Rect2 = Rect2(16, 34, 288, 270)
## The bin falls onto the floor from this height (metres) in this many seconds.
const DROP_HEIGHT: float = 0.5
const DROP_SECONDS: float = 0.45
const FLIGHT_SECONDS: float = 0.9
## A landed ball drops into the bin or hops to its resting place.
const SETTLE_SECONDS: float = 0.35
const RESULT_SECONDS: float = 0.8
const MAX_FLOOR_BALLS: int = 6
## Turns a second of a ball in flight.
const SPIN_SPEED: float = 8.0
## Swipes shorter than this (view pixels) are taps, not throws.
const MIN_SWIPE: float = 18.0
## A hit this little below the lens (metres) is a wall or a shelf, not a place for the bin.
const MIN_DROP_BELOW_EYE: float = 0.4
## The arrow to a bin out of the picture: its size and distance from the edge, pixels.
const ARROW_SIZE: float = 9.0
const ARROW_INSET: float = 16.0

var _needed: int = DEFAULT_HITS
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _toss: PaperToss
var _tracker: ArTracker = ArTracker.new(PaperToss.EYE_HEIGHT, PaperToss.CAMERA_TILT)
## Height (room metres) of the surface the bin stands on: the game's floor (y = 0) is there.
var _ground: float = 0.0
var _stage: Stage = Stage.PLACING
var _dropped_at: float = 0.0
var _hits: int = 0
var _throws: int = 0
var _flight: PaperToss.Throw
var _flight_time: float = 0.0
var _press: Variant = null
## Resting places of the missed balls on the floor.
var _floor_balls: Array[Vector3] = []
## The last landed throw and the seconds since, for the "IN!" / "MISS" effect.
var _landed: PaperToss.Throw
var _since_landed: float = RESULT_SECONDS
var _ar_time: float = 0.0

var _view: CameraView
var _credit: LinkButton
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
	# The bin and the ball must stay over the camera on every phone browser.
	_view.prefers_native = false
	_view.overlay = _draw_scene
	# The counter sits at the top of the view: the ball waits in the hand at the bottom.
	_count_label = add_big_label(VIEW_RECT.position.y + 4, 16, Color.WHITE)
	_status = add_status()
	_tracker.start(VIEW_RECT.size)
	_credit = _tracker.add_credit(self, VIEW_RECT)


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	_since_landed += delta
	_tracker.update(delta)
	_credit.visible = _tracker.uses_engine()
	if _stage == Stage.DROPPING and _ar_time - _dropped_at >= DROP_SECONDS:
		_stage = Stage.PLAYING
	if not is_done() and _stage == Stage.PLAYING:
		_update_flight(delta)
		_time_left -= delta
		if _time_left <= 0.0:
			finish(false)
	_count_label.text = "%d / %d" % [_hits, _needed]
	_status.text = _status_text()
	_view.queue_redraw()


func _status_text() -> String:
	if _stage == Stage.PLACING and _tracker.is_starting():
		return tr("MG_AR_STARTING")
	if _stage == Stage.PLACING:
		return tr("MG_PAPER_TOSS_PLACE") if _aimed_spot() != null else tr("MG_PAPER_TOSS_AIM_FLOOR")
	return "%s   %s" % [_wind_text(), tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]


func _update_flight(delta: float) -> void:
	if _flight == null:
		return
	var was_flying: bool = _flight_time < FLIGHT_SECONDS
	_flight_time += delta
	if was_flying and _flight_time >= FLIGHT_SECONDS:
		_landed = _flight
		_since_landed = 0.0
		if _landed.hit:
			_hits += 1
	if _flight_time < FLIGHT_SECONDS + SETTLE_SECONDS:
		return
	if not _flight.hit:
		_floor_balls.append(_flight.rest)
		if _floor_balls.size() > MAX_FLOOR_BALLS:
			_floor_balls.pop_front()
	_flight = null
	_toss.new_wind()
	if _hits >= _needed:
		set_score(0.5 * _time_left / _time_limit + 0.5 * float(_hits) / maxf(_throws, 1.0))
		proof["hits"] = _hits
		proof["throws"] = _throws
		finish(true)


## Takes the finger itself and the mouse emulated from it (or the touch emulated from a desktop
## mouse): whichever release comes first counts, the second finds no press and is ignored. A tap puts
## the bin on the floor, a swipe up throws.
func _gui_input(event: InputEvent) -> void:
	if is_done():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var press: Variant = Minigame.press_position(event)
	if touch != null and touch.index == 0 and touch.pressed:
		press = touch.position
	if press != null:
		_press = (press as Vector2) - VIEW_RECT.position
		accept_event()
		return
	var release: Variant = null
	if touch != null and touch.index == 0 and not touch.pressed:
		release = touch.position
	elif Minigame.is_release(event):
		release = (event as InputEventMouseButton).position
	if release == null or _press == null:
		return
	var swipe: Vector2 = (release as Vector2) - VIEW_RECT.position - (_press as Vector2)
	_press = null
	accept_event()
	if _stage == Stage.PLACING:
		_place_bin()
	elif _stage == Stage.PLAYING:
		_throw(swipe)


func _place_bin() -> void:
	var spot: Variant = _aimed_spot()
	if spot == null:
		return
	_ground = (spot as Vector3).y
	_toss.bin = Vector3((spot as Vector3).x, 0.0, (spot as Vector3).z)
	_stage = Stage.DROPPING
	_dropped_at = _ar_time


func _throw(swipe: Vector2) -> void:
	if _flight != null or swipe.length() < MIN_SWIPE or swipe.y >= 0.0:
		return
	var camera: ArCamera = _camera_over(_view.get_image_rect(), _ground)
	_throws += 1
	var from: Vector2 = Vector2(camera.eye.x, camera.eye.z)
	_flight = _toss.throw(swipe, VIEW_RECT.size, camera.heading(), PaperToss.hand_point(camera), from)
	_flight_time = 0.0


## The camera of the phone as it is held now over the camera picture `frame`, with the game's floor
## at the surface `ground` metres high.
func _camera_over(frame: Rect2, ground: float) -> ArCamera:
	var camera: ArCamera = _tracker.camera(frame)
	camera.eye.y -= ground
	return camera


## The surface point (room metres) in the middle of the view where the bin may stand, or null: a real
## surface with world tracking, the floor plane without it.
func _aimed_spot() -> Variant:
	var middle: Vector2 = VIEW_RECT.size / 2.0
	var camera: ArCamera = _tracker.camera(_view.get_image_rect())
	var spot: Variant = null
	if _tracker.is_tracking_world():
		spot = _tracker.hit(middle, VIEW_RECT.size)
		if spot != null and camera.eye.y - (spot as Vector3).y < MIN_DROP_BELOW_EYE:
			spot = null
	elif not _tracker.is_starting():
		spot = camera.floor_point(middle)
	if spot == null or not PaperToss.can_place(spot as Vector3, Vector2(camera.eye.x, camera.eye.z)):
		return null
	return spot


func _wind_text() -> String:
	var arrow: String = "→" if _toss.wind > 0.0 else "←"
	return tr("MG_PAPER_TOSS_WIND") % [arrow, absf(_toss.wind)]


## The bin's base: hanging while it falls onto the floor, then on it.
func _bin_base() -> Vector3:
	var fall: float = minf((_ar_time - _dropped_at) / DROP_SECONDS, 1.0) if _stage == Stage.DROPPING else 1.0
	return _toss.bin + Vector3.UP * DROP_HEIGHT * (1.0 - fall * fall)


## Where the thrown ball is now, or null when none is flying.
func _ball_point() -> Variant:
	if _flight == null:
		return null
	if _flight_time < FLIGHT_SECONDS:
		return PaperToss.flight_point(_flight, _flight_time / FLIGHT_SECONDS)
	return PaperToss.settle_point(_flight, minf((_flight_time - FLIGHT_SECONDS) / SETTLE_SECONDS, 1.0))


## Painter's order: shadows on the floor, what the bin hides, the bin with a ball falling in between
## its two passes, then everything in front of it.
func _draw_scene(view: CameraView, image_rect: Rect2) -> void:
	if _stage == Stage.PLACING:
		var spot: Variant = _aimed_spot()
		if spot != null:
			var surface: Vector3 = spot as Vector3
			var on_surface: ArCamera = _camera_over(image_rect, surface.y)
			PaperTossPainter.floor_reticle(view, on_surface, Vector3(surface.x, 0.0, surface.z), true, _ar_time)
		return
	var camera: ArCamera = _camera_over(image_rect, _ground)
	var base: Vector3 = _bin_base()
	var ball: Variant = _ball_point()
	var in_bin: bool = ball != null and _flight.hit and _flight_time >= FLIGHT_SECONDS
	PaperTossPainter.bin_shadow(view, camera, base)
	for rest: Vector3 in _floor_balls:
		PaperTossPainter.ball_shadow(view, camera, rest)
	if ball != null and not in_bin:
		PaperTossPainter.ball_shadow(view, camera, ball as Vector3)
	_draw_floor_balls(view, camera, true)
	if ball != null and not in_bin and PaperTossPainter.is_behind_bin(ball as Vector3, _toss.bin, camera.eye):
		_draw_thrown_ball(view, camera, ball as Vector3)
	PaperTossPainter.bin_back(view, camera, base)
	if in_bin:
		_draw_thrown_ball(view, camera, ball as Vector3)
	PaperTossPainter.bin_front(view, camera, base)
	_draw_floor_balls(view, camera, false)
	if ball != null and not in_bin and not PaperTossPainter.is_behind_bin(ball as Vector3, _toss.bin, camera.eye):
		_draw_thrown_ball(view, camera, ball as Vector3)
	if ball == null and not is_done() and _stage == Stage.PLAYING:
		# The next ball waits in the hand below the lens.
		PaperTossPainter.ball(view, camera, PaperToss.hand_point(camera), 0.0, _throws + 1)
	_draw_arrow_to_bin(view, camera)
	_draw_result(view, camera)


func _draw_floor_balls(view: CameraView, camera: ArCamera, behind_bin: bool) -> void:
	for index: int in _floor_balls.size():
		var rest: Vector3 = _floor_balls[index]
		if PaperTossPainter.is_behind_bin(rest, _toss.bin, camera.eye) == behind_bin:
			PaperTossPainter.ball(view, camera, rest, index * 1.7, index + 101)


func _draw_thrown_ball(view: CameraView, camera: ArCamera, point: Vector3) -> void:
	PaperTossPainter.ball(view, camera, point, _flight_time * SPIN_SPEED, _throws)


## An arrow at the edge of the view towards the bin when it is out of the picture.
func _draw_arrow_to_bin(view: CameraView, camera: ArCamera) -> void:
	var middle: Vector3 = camera.project(_toss.bin + Vector3.UP * PaperToss.BIN_HEIGHT / 2.0)
	var inside: Rect2 = Rect2(Vector2.ZERO, view.size).grow(-ARROW_INSET)
	var at: Vector2 = Vector2(middle.x, middle.y)
	if middle.z > 0.0 and inside.has_point(at):
		return
	var centre: Vector2 = view.size / 2.0
	var direction: Vector2 = (at - centre).normalized()
	if middle.z <= 0.0 or direction.is_zero_approx():
		var turn: float = wrapf(_toss.bin_yaw(Vector2(camera.eye.x, camera.eye.z)) - camera.heading(), -180.0, 180.0)
		direction = Vector2.RIGHT if turn > 0.0 else Vector2.LEFT
	var half: Vector2 = inside.size / 2.0
	var reach: float = minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	var tip: Vector2 = centre + direction * reach
	var side: Vector2 = direction.orthogonal() * ARROW_SIZE * 0.6
	var back: Vector2 = tip - direction * ARROW_SIZE
	var arrow: PackedVector2Array = PackedVector2Array([tip, back + side, back - side, tip])
	view.draw_colored_polygon(arrow, Color(ArPainter.NEON_CYAN, 0.85))
	ArPainter.neon_polyline(view, arrow, ArPainter.NEON_CYAN, 1.0)


func _draw_result(view: CameraView, camera: ArCamera) -> void:
	if _landed == null:
		return
	var age: float = _since_landed / RESULT_SECONDS
	if _landed.hit:
		var opening: Vector3 = camera.project(_toss.bin + Vector3.UP * PaperToss.BIN_HEIGHT)
		var at: Vector2 = Vector2(opening.x, opening.y)
		ArPainter.burst(view, at, 30.0, age, UiStyle.GOLD)
		ArPainter.pop_text(view, at + Vector2(0, -16), tr("MG_PAPER_TOSS_IN"), age)
	else:
		var landed: Vector3 = camera.project(_landed.rest)
		ArPainter.pop_text(view, Vector2(landed.x, landed.y - 8.0), tr("MG_PAPER_TOSS_MISS"), age, ArPainter.NEON_PINK)
