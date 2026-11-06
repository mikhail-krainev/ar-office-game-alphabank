class_name DevicePose
extends RefCounted
## Where the phone looks in the room: its orientation from the gyroscope, kept level by gravity (a
## complementary filter with three degrees of freedom: the phone turns and tilts, but is assumed to
## stay where the player stands). `basis` turns device axes (x right, y up along the screen, z out of
## the screen; the back camera looks along -z) into room axes, right-handed: x right, y up, z back
## towards the player at the start, so the player first looks along -z. Pure math, tested without
## sensors.

const GRAVITY: float = 9.81
## Share of the tilt error towards gravity removed per second: corrects the gyroscope drift without
## following the shake of the hand.
const GRAVITY_GAIN: float = 2.0
## Readings further than this from GRAVITY (m/s^2) are the hand moving, not the phone's tilt.
const STEADY_TOLERANCE: float = 1.5
## Gravity is too weak to tell the tilt below this (no sensor, no permission).
const MIN_GRAVITY: float = GRAVITY * 0.5

var basis: Basis
## Whether the tilt was already taken from gravity once.
var is_levelled: bool = false


## Starts with the phone upright and tilted `degrees_down` at the floor.
func _init(degrees_down: float = 0.0) -> void:
	basis = tilted(degrees_down)


## Turns the phone by the gyroscope (degrees per second about the device axes) over `delta` seconds
## and, with `use_gravity`, levels it by the accelerometer (m/s^2 with gravity, pointing up at rest).
func update(delta: float, rotation_rate: Vector3, acceleration: Vector3, use_gravity: bool) -> void:
	var has_gravity: bool = use_gravity and acceleration.length() >= MIN_GRAVITY
	if has_gravity and not is_levelled:
		basis = from_gravity(acceleration)
		is_levelled = true
		return
	var turn: Vector3 = rotation_rate * (PI / 180.0) * delta
	if not turn.is_zero_approx():
		basis = (basis * Basis(turn.normalized(), turn.length())).orthonormalized()
	if has_gravity and absf(acceleration.length() - GRAVITY) <= STEADY_TOLERANCE:
		_level(acceleration, minf(GRAVITY_GAIN * delta, 1.0))


## The camera direction in the room.
func forward() -> Vector3:
	return basis * Vector3.FORWARD


## The phone held upright and tilted `degrees_down` at the floor, looking along -z.
static func tilted(degrees_down: float) -> Basis:
	return Basis(Vector3.RIGHT, -deg_to_rad(degrees_down))


## The orientation that gravity alone tells: the tilt is exact, the camera looks along -z.
static func from_gravity(acceleration: Vector3) -> Basis:
	var up: Vector3 = acceleration.normalized()
	var ahead: Vector3 = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if ahead.length() < 0.01:
		# Lying flat: the top of the phone points ahead.
		ahead = Vector3.UP - up * Vector3.UP.dot(up)
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(up)
	# Columns are the room axes in device axes: this is room -> device, so turn it around.
	return Basis(right, up, -ahead).transposed()


## Turns the room tilt a `share` of the way so that the measured up is the room up.
func _level(acceleration: Vector3, share: float) -> void:
	var measured_up: Vector3 = basis * acceleration.normalized()
	var axis: Vector3 = measured_up.cross(Vector3.UP)
	if axis.length() < 0.00001:
		return
	basis = (Basis(axis.normalized(), measured_up.angle_to(Vector3.UP) * share) * basis).orthonormalized()
