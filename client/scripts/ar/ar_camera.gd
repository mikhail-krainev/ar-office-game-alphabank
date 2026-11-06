class_name ArCamera
extends RefCounted
## A pinhole camera matched to the phone camera picture: where a point of the room shows in the
## window and which floor point lies under a window point. Room points are metres: x to the right, y
## up from the floor, z forward from the player's feet. The pose is a DevicePose basis (right-handed,
## z back), so z is flipped on the way in and out.

## Horizontal field of view of a phone's main camera across the portrait picture, in degrees.
const FIELD_OF_VIEW: float = 50.0
## Points closer to the lens than this (metres) are not drawn.
const NEAR_PLANE: float = 0.05
## Floor rays flatter than this never reach the floor in the room.
const MIN_FLOOR_SLOPE: float = 0.01

## Where the camera picture lies in the window: the field of view spans its width.
var frame: Rect2
var pose: Basis
var eye: Vector3
## Degrees across the width of `frame`.
var field_of_view: float = FIELD_OF_VIEW


func _init(picture: Rect2, camera_pose: Basis, eye_point: Vector3, degrees: float = FIELD_OF_VIEW) -> void:
	frame = picture
	pose = camera_pose
	eye = eye_point
	field_of_view = degrees


## Window pixels of a room point in x and y; z is the pixels per metre there, 0 when the point is
## behind the lens.
func project(point: Vector3) -> Vector3:
	var local: Vector3 = pose.transposed() * _flip(point - eye)
	var centre: Vector2 = frame.get_center()
	var depth: float = -local.z
	if depth < NEAR_PLANE:
		return Vector3(centre.x, centre.y, 0.0)
	var scale: float = focal_length() / depth
	return Vector3(centre.x + local.x * scale, centre.y - local.y * scale, scale)


## The direction in the room (not normalized) of the ray from the lens through a window point.
func ray(window_point: Vector2) -> Vector3:
	var offset: Vector2 = (window_point - frame.get_center()) / focal_length()
	return _flip(pose * Vector3(offset.x, -offset.y, -1.0))


## The floor point under a window point, or null when that ray goes above the floor's horizon.
func floor_point(window_point: Vector2) -> Variant:
	var direction: Vector3 = ray(window_point)
	if direction.y > -MIN_FLOOR_SLOPE:
		return null
	return eye + direction * (-eye.y / direction.y)


## Degrees the camera looks to the right of straight ahead (the room +z), about the vertical.
func heading() -> float:
	var ahead: Vector3 = _flip(pose * Vector3.FORWARD)
	return rad_to_deg(atan2(ahead.x, ahead.z))


## The room point at `offset` metres from the lens in device axes (x right, y up, z out of the screen).
func from_device(offset: Vector3) -> Vector3:
	return eye + _flip(pose * offset)


## The opposite of from_device for a camera held with `camera_pose`.
static func to_device(point: Vector3, eye_point: Vector3, camera_pose: Basis) -> Vector3:
	return camera_pose.transposed() * _flip(point - eye_point)


func focal_length() -> float:
	return frame.size.x / 2.0 / tan(deg_to_rad(field_of_view / 2.0))


## Room axes (z forward) to pose axes (z back) and back.
static func _flip(vector: Vector3) -> Vector3:
	return Vector3(vector.x, vector.y, -vector.z)
