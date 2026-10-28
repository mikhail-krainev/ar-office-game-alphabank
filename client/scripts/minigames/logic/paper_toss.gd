class_name PaperToss
extends RefCounted
## "Paper basketball": an AR bin stands somewhere around the player and the phone is a window onto it,
## like BugSwarm: the gyroscope turns the view. A swipe up throws a paper ball where the phone looks:
## the swipe length is the strength, its sideways part the aim, and the wind of this throw carries
## the ball sideways. Pure math, tested without sensors.

## Horizontal field of view of the window, in degrees.
const FIELD_OF_VIEW: float = 60.0
const VIEW_PITCH_LIMIT: float = 50.0
## The bin stands below the eyes, this far off to a side (degrees), so the player turns to find it.
const BIN_PITCH: float = -12.0
const BIN_YAW_MIN: float = 25.0
const BIN_YAW_MAX: float = 70.0
## Half the bin opening, in degrees, and the strength that lands in it (a share of the view height).
const BIN_HALF_WIDTH: float = 4.5
const IDEAL_POWER: float = 0.5
const POWER_TOLERANCE: float = 0.17
## A swipe across the whole view aims this many degrees sideways.
const AIM_RANGE: float = 30.0
const WIND_MAX: float = 6.0
## Pitch change of a miss per unit of strength error: too strong flies over the bin.
const PITCH_PER_POWER: float = 30.0


class Throw:
	extends RefCounted

	var power: float = 0.0
	## Yaw and pitch where the ball comes down.
	var landing_yaw: float = 0.0
	var landing_pitch: float = 0.0
	## Where the phone looked when the ball left the hand.
	var start_yaw: float = 0.0
	var start_pitch: float = 0.0
	var hit: bool = false


var bin_yaw: float = 0.0
var view_yaw: float = 0.0
var view_pitch: float = 0.0
## Degrees the wind carries the next ball; positive to the right.
var wind: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## `rng_seed` 0 picks a random one.
func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	bin_yaw = side * _rng.randf_range(BIN_YAW_MIN, BIN_YAW_MAX)
	new_wind()


func new_wind() -> void:
	wind = _rng.randf_range(-WIND_MAX, WIND_MAX)


## Turns the window by the gyroscope (degrees per second about the device axes, phone upright).
func update(delta: float, rotation_rate: Vector3) -> void:
	view_yaw = wrapf(view_yaw - rotation_rate.y * delta, -180.0, 180.0)
	view_pitch = clampf(view_pitch + rotation_rate.x * delta, -VIEW_PITCH_LIMIT, VIEW_PITCH_LIMIT)


## The throw of a swipe (view pixels, up is negative y) in a view `view_size` big.
func throw(swipe: Vector2, view_size: Vector2) -> Throw:
	var result: Throw = Throw.new()
	result.start_yaw = view_yaw
	result.start_pitch = view_pitch
	result.power = maxf(0.0, -swipe.y / maxf(view_size.y, 1.0))
	var aim: float = swipe.x / maxf(view_size.x, 1.0) * AIM_RANGE
	result.landing_yaw = wrapf(view_yaw + aim + wind, -180.0, 180.0)
	result.landing_pitch = BIN_PITCH + (result.power - IDEAL_POWER) * PITCH_PER_POWER
	var off: float = absf(wrapf(result.landing_yaw - bin_yaw, -180.0, 180.0))
	result.hit = off <= BIN_HALF_WIDTH and absf(result.power - IDEAL_POWER) <= POWER_TOLERANCE
	return result


## Yaw and pitch of a ball in flight, `t` from 0 (thrown) to 1 (landed): it leaves from below the view,
## arcs up and drifts with the wind on the way.
static func flight_point(flight: Throw, t: float) -> Vector2:
	var yaw: float = flight.start_yaw + wrapf(flight.landing_yaw - flight.start_yaw, -180.0, 180.0) * t * t
	var start_pitch: float = flight.start_pitch - FIELD_OF_VIEW * 0.45
	var pitch: float = lerpf(start_pitch, flight.landing_pitch, t) + sin(t * PI) * 18.0 * clampf(flight.power * 2.0, 0.3, 1.5)
	return Vector2(yaw, pitch)


static func pixels_per_degree(view_size: Vector2) -> float:
	return view_size.x / FIELD_OF_VIEW


## View pixels of a direction (yaw, pitch), from the top-left corner; may be outside the view.
func project(direction: Vector2, view_size: Vector2) -> Vector2:
	var offset: Vector2 = Vector2(wrapf(direction.x - view_yaw, -180.0, 180.0), -(direction.y - view_pitch))
	return view_size / 2.0 + offset * pixels_per_degree(view_size)


func bin_direction() -> Vector2:
	return Vector2(bin_yaw, BIN_PITCH)


## Yaw difference (degrees) from the window to the bin, for the arrow that shows where to turn.
func bin_turn() -> float:
	return wrapf(bin_yaw - view_yaw, -180.0, 180.0)
