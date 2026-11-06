class_name PaperToss
extends RefCounted
## "Paper basketball": an AR bin stands on the floor of the room where the player put it, seen
## through the camera of a phone that turns and tilts (ArCamera, DevicePose). A swipe up throws a
## paper ball where the phone looks: the swipe length is the strength (a farther bin needs a harder
## throw), its sideways part the aim, and the wind of this throw carries the ball sideways. The room
## is in metres: x to the right, y up from the floor, z forward from the player's feet. Pure math,
## tested without sensors.

## The phone is held this high (metres) and, without motion sensors, tilted this far down (degrees).
const EYE_HEIGHT: float = 1.25
const CAMERA_TILT: float = 34.0
## A usual office bin: a plastic cone, a little wider at the top.
const BIN_DISTANCE: float = 1.6
const BIN_HEIGHT: float = 0.32
const BIN_TOP_RADIUS: float = 0.15
const BIN_BOTTOM_RADIUS: float = 0.115
const BALL_RADIUS: float = 0.035
## The bin can be put on the floor this near and this far (metres, from the player's feet).
const PLACE_MIN: float = 0.8
const PLACE_MAX: float = 3.0
## Where the ball waits in the hand with the phone held without sensors, below the bin in the picture.
const HAND: Vector3 = Vector3(0.0, EYE_HEIGHT - 0.42, 0.34)
## Half the bin opening, in degrees, the strength that reaches a bin at BIN_DISTANCE (a share of the
## view height) and how far it may be off.
const BIN_HALF_WIDTH: float = 4.5
const IDEAL_POWER: float = 0.5
const POWER_TOLERANCE: float = 0.17
## Floor distance a throw flies per unit of strength: too strong flies over the bin.
const METRES_PER_POWER: float = BIN_DISTANCE / IDEAL_POWER
## A swipe across the whole view aims this many degrees sideways.
const AIM_RANGE: float = 30.0
const WIND_MAX: float = 6.0
## Height (metres) the throw arcs above the straight line from the hand, per unit of strength.
const ARC_PER_POWER: float = 0.6
const ARC_MIN: float = 0.15
## Even the weakest throw lands this far (metres) from the player's feet.
const MIN_LANDING: float = 0.5
## A ball that bounces off the rim lands this far (metres) outside the bin wall.
const RIM_BOUNCE: float = 0.16
const RIM_HOP: float = 0.14
## A ball that lands on the floor hops and rolls on this far (metres) away from the player.
const FLOOR_ROLL: float = 0.12
const FLOOR_HOP: float = 0.05


class Throw:
	extends RefCounted

	var power: float = 0.0
	## Degrees to the right of straight ahead where the ball comes down.
	var yaw: float = 0.0
	var hit: bool = false
	## The flight arcs from `start` (the hand) to `target` with `arc` metres of lift; then the ball
	## drops into the bin or hops `hop` metres high on the way to `rest`.
	var start: Vector3 = HAND
	var target: Vector3 = Vector3.ZERO
	var rest: Vector3 = Vector3.ZERO
	var arc: float = 0.0
	var hop: float = 0.0


## The floor point under the middle of the bin.
var bin: Vector3 = Vector3(0.0, 0.0, BIN_DISTANCE)
## Degrees the wind carries the next ball; positive to the right.
var wind: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## `rng_seed` 0 picks a random one.
func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	new_wind()


func new_wind() -> void:
	wind = _rng.randf_range(-WIND_MAX, WIND_MAX)


## Whether the bin may stand on this floor point for a player standing at `from` (floor x, z).
static func can_place(point: Vector3, from: Vector2 = Vector2.ZERO) -> bool:
	var distance: float = Vector2(point.x, point.z).distance_to(from)
	return distance >= PLACE_MIN and distance <= PLACE_MAX


func bin_distance(from: Vector2 = Vector2.ZERO) -> float:
	return Vector2(bin.x, bin.z).distance_to(from)


## Degrees to the right of straight ahead where the bin stands, seen from `from`.
func bin_yaw(from: Vector2 = Vector2.ZERO) -> float:
	return rad_to_deg(atan2(bin.x - from.x, bin.z - from.y))


## The strength that reaches the bin from `from`.
func needed_power(from: Vector2 = Vector2.ZERO) -> float:
	return bin_distance(from) / METRES_PER_POWER


## The throw of a swipe (view pixels, up is negative y) in a view `view_size` big, with the phone
## looking `heading` degrees to the right, the ball leaving the hand at `hand` and the player standing
## at `from` (floor x, z).
func throw(
	swipe: Vector2, view_size: Vector2, heading: float = 0.0, hand: Vector3 = HAND, from: Vector2 = Vector2.ZERO
) -> Throw:
	var result: Throw = Throw.new()
	result.power = maxf(0.0, -swipe.y / maxf(view_size.y, 1.0))
	result.yaw = heading + swipe.x / maxf(view_size.x, 1.0) * AIM_RANGE + wind
	var off_yaw: float = wrapf(result.yaw - bin_yaw(from), -180.0, 180.0)
	result.hit = absf(off_yaw) <= BIN_HALF_WIDTH and absf(result.power - needed_power(from)) <= POWER_TOLERANCE
	result.start = hand
	result.arc = ARC_PER_POWER * clampf(result.power, ARC_MIN, 1.2)
	if result.hit:
		_drop_into_bin(result, off_yaw, from)
	else:
		_land_outside(result, from)
	return result


## A hit comes down through the opening, nearer the far wall when thrown harder, and falls to the bottom.
func _drop_into_bin(result: Throw, off_yaw: float, from: Vector2) -> void:
	var inside: float = BIN_TOP_RADIUS - BALL_RADIUS
	var away: float = deg_to_rad(bin_yaw(from))
	var outward: Vector3 = Vector3(sin(away), 0.0, cos(away))
	var sideways: Vector3 = Vector3(cos(away), 0.0, -sin(away))
	var side: float = clampf(bin_distance(from) * tan(deg_to_rad(off_yaw)), -inside, inside)
	var depth: float = (result.power - needed_power(from)) / POWER_TOLERANCE * inside * 0.6
	var offset: Vector3 = sideways * side + outward * depth
	result.target = bin + offset + Vector3.UP * BIN_HEIGHT
	result.rest = bin + offset * 0.4 + Vector3.UP * (BALL_RADIUS + 0.01)


## A miss lands on the floor and rolls on, or strikes the rim when it comes down on the bin.
func _land_outside(result: Throw, from: Vector2) -> void:
	var distance: float = maxf(result.power * METRES_PER_POWER, MIN_LANDING)
	var direction: float = deg_to_rad(result.yaw)
	var landing: Vector3 = Vector3(from.x + sin(direction) * distance, BALL_RADIUS, from.y + cos(direction) * distance)
	var off_centre: Vector2 = Vector2(landing.x - bin.x, landing.z - bin.z)
	if off_centre.length() < BIN_TOP_RADIUS + BALL_RADIUS:
		var outward: Vector2 = Vector2(0.0, 1.0) if off_centre.is_zero_approx() else off_centre.normalized()
		var rim: Vector2 = outward * BIN_TOP_RADIUS
		var bounce: Vector2 = outward * (BIN_TOP_RADIUS + BALL_RADIUS + RIM_BOUNCE)
		result.target = Vector3(bin.x + rim.x, BIN_HEIGHT + BALL_RADIUS, bin.z + rim.y)
		result.rest = Vector3(bin.x + bounce.x, BALL_RADIUS, bin.z + bounce.y)
		result.hop = RIM_HOP
		return
	var away: Vector3 = Vector3(sin(direction), 0.0, cos(direction))
	result.target = landing
	result.rest = landing + away * FLOOR_ROLL
	result.hop = FLOOR_HOP


## Where a ball in flight is, `t` from 0 (thrown) to 1 (landed): a parabola from the hand.
static func flight_point(flight: Throw, t: float) -> Vector3:
	return flight.start.lerp(flight.target, t) + Vector3.UP * flight.arc * 4.0 * t * (1.0 - t)


## Where a landed ball is, `s` from 0 (landed) to 1 (at rest): a hit falls down inside the bin, a miss
## hops to its resting place.
static func settle_point(flight: Throw, s: float) -> Vector3:
	if flight.hit:
		return flight.target.lerp(flight.rest, s * s)
	return flight.target.lerp(flight.rest, s) + Vector3.UP * flight.hop * 4.0 * s * (1.0 - s)


## The ball in the hand, held the same way below the lens whatever way the phone looks.
static func hand_point(camera: ArCamera) -> Vector3:
	return camera.from_device(ArCamera.to_device(HAND, eye(), DevicePose.tilted(CAMERA_TILT)))


## The camera of a phone held without motion sensors over a picture `frame`.
static func default_camera(frame: Rect2) -> ArCamera:
	return ArCamera.new(frame, DevicePose.tilted(CAMERA_TILT), eye())


static func eye() -> Vector3:
	return Vector3(0.0, EYE_HEIGHT, 0.0)
