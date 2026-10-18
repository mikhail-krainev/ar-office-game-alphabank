class_name BugSwarm
extends RefCounted
## Bugs hanging around the player for "Bug hunt": each bug has a direction (yaw, pitch in degrees)
## around the player, and the phone is a window onto them. The gyroscope turns the window, so the
## player turns around with the phone to find the bugs; only turning counts, not walking. Pure math,
## so it is tested without sensors.

## Horizontal field of view of the window, in degrees (a phone camera is about this wide).
const FIELD_OF_VIEW: float = 60.0
## Bugs hang between these pitches: from the desk to just above the eyes.
const PITCH_MIN: float = -25.0
const PITCH_MAX: float = 30.0
## The window cannot look further up or down than this.
const VIEW_PITCH_LIMIT: float = 60.0
## Degrees per second a bug crawls, and how often it changes direction.
const CRAWL_SPEED: float = 6.0
const TURN_SECONDS: float = 1.6
## A tap this close to a bug, in view pixels, catches it (a finger is wider than a bug).
const HIT_RADIUS: float = 22.0
## Bugs are spread at least this far apart in yaw, so they are not all in one spot.
const MIN_SPREAD: float = 25.0


class Bug:
	extends RefCounted

	var yaw: float = 0.0
	var pitch: float = 0.0
	var heading: float = 0.0
	var turn_left: float = 0.0
	var caught: bool = false

	func _init(p_yaw: float, p_pitch: float, p_heading: float) -> void:
		yaw = p_yaw
		pitch = p_pitch
		heading = p_heading


var bugs: Array[Bug] = []
## Where the window looks: yaw grows to the right, pitch upwards.
var view_yaw: float = 0.0
var view_pitch: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## `count` bugs all around the player; `rng_seed` 0 picks a random one.
func _init(count: int = 0, rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	var step: float = 360.0 / maxi(count, 1)
	for i: int in count:
		# Evenly around the circle with some jitter, the first one off to the side: turning is needed.
		var yaw: float = wrapf(
			step * i + _rng.randf_range(0.0, maxf(0.0, step - MIN_SPREAD)) + FIELD_OF_VIEW,
			-180.0,
			180.0
		)
		bugs.append(Bug.new(yaw, _rng.randf_range(PITCH_MIN, PITCH_MAX), _rng.randf() * TAU))


## Turns the window by the gyroscope (degrees per second about the device axes, phone upright in
## portrait) and lets the bugs crawl. Turning left about the device y axis looks to the left.
func update(delta: float, rotation_rate: Vector3) -> void:
	view_yaw = wrapf(view_yaw - rotation_rate.y * delta, -180.0, 180.0)
	view_pitch = clampf(view_pitch + rotation_rate.x * delta, -VIEW_PITCH_LIMIT, VIEW_PITCH_LIMIT)
	for bug: Bug in bugs:
		if bug.caught:
			continue
		bug.turn_left -= delta
		if bug.turn_left <= 0.0:
			bug.turn_left = TURN_SECONDS * _rng.randf_range(0.5, 1.5)
			bug.heading += _rng.randf_range(-1.2, 1.2)
		bug.yaw = wrapf(bug.yaw + cos(bug.heading) * CRAWL_SPEED * delta, -180.0, 180.0)
		bug.pitch += sin(bug.heading) * CRAWL_SPEED * delta
		if bug.pitch < PITCH_MIN or bug.pitch > PITCH_MAX:
			bug.pitch = clampf(bug.pitch, PITCH_MIN, PITCH_MAX)
			bug.heading = -bug.heading


## Pixels per degree in a window `view_size` wide.
static func pixels_per_degree(view_size: Vector2) -> float:
	return view_size.x / FIELD_OF_VIEW


## Where the bug is in the window, in view pixels from the top-left corner (may be outside it).
func project(bug: Bug, view_size: Vector2) -> Vector2:
	var scale_factor: float = pixels_per_degree(view_size)
	var offset: Vector2 = Vector2(
		wrapf(bug.yaw - view_yaw, -180.0, 180.0), -(bug.pitch - view_pitch)
	)
	return view_size / 2.0 + offset * scale_factor


## The bug is inside the window.
func is_visible(bug: Bug, view_size: Vector2) -> bool:
	return Rect2(Vector2.ZERO, view_size).has_point(project(bug, view_size))


## Catches the closest uncaught visible bug within reach of the tap; returns it, or null.
func catch_at(tap: Vector2, view_size: Vector2) -> Bug:
	var best: Bug = null
	var best_distance: float = HIT_RADIUS
	for bug: Bug in bugs:
		if bug.caught or not is_visible(bug, view_size):
			continue
		var distance: float = project(bug, view_size).distance_to(tap)
		if distance <= best_distance:
			best = bug
			best_distance = distance
	if best != null:
		best.caught = true
	return best


func caught_count() -> int:
	return bugs.filter(func(bug: Bug) -> bool: return bug.caught).size()


## Yaw difference (degrees, -180..180) from the window to the closest uncaught bug, for the arrow
## that shows where to turn; 0 when none is left.
func nearest_turn() -> float:
	var best: float = 0.0
	var best_abs: float = INF
	for bug: Bug in bugs:
		if bug.caught:
			continue
		var turn: float = wrapf(bug.yaw - view_yaw, -180.0, 180.0)
		if absf(turn) < best_abs:
			best = turn
			best_abs = absf(turn)
	return best
