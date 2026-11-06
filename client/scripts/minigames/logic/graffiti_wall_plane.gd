class_name GraffitiWallPlane
extends RefCounted
## Where the graffiti wall of "Graffiti wall" hangs in the room: a vertical rectangle facing the
## player, put where the phone looks when the player taps (ArCamera). With world tracking the tap hits
## the real wall and gives its distance; without it the rectangle stands DISTANCE metres away. It then
## stays on that spot as the phone moves. One wall pixel of GraffitiCanvas is one centimetre. Room
## points are metres: x to the right, y up from the floor, z forward from the player's feet. Pure
## math, tested without sensors.

const DISTANCE: float = 1.0
## A measured wall nearer or farther than this (metres) is taken at the nearest or farthest.
const MIN_DISTANCE: float = 0.4
const MAX_DISTANCE: float = 4.0
const PIXEL: float = 0.01
const WIDTH: float = GraffitiCanvas.WIDTH * PIXEL
const HEIGHT: float = GraffitiCanvas.HEIGHT * PIXEL
## The middle of the wall stays this high at least and at most (metres above the floor).
const MIN_CENTRE_HEIGHT: float = 0.6
const MAX_CENTRE_HEIGHT: float = 2.0
## Rays this close to parallel with the wall never reach it.
const MIN_FACING: float = 0.01

var centre: Vector3
## Unit vectors along the wall to the right and towards the player.
var right: Vector3
var normal: Vector3


## The wall `distance` metres in front of the camera (along the floor), square to where it looks and
## centred on the middle of `frame`.
static func facing(camera: ArCamera, frame: Rect2, distance: float = DISTANCE) -> GraffitiWallPlane:
	distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	var wall: GraffitiWallPlane = GraffitiWallPlane.new()
	var look: Vector3 = camera.ray(frame.get_center())
	var ahead: Vector3 = Vector3(look.x, 0.0, look.z)
	ahead = Vector3.BACK if ahead.length() < 0.001 else ahead.normalized()
	wall.normal = -ahead
	wall.right = Vector3(ahead.z, 0.0, -ahead.x)
	var reach: float = distance / maxf(look.normalized().dot(ahead), 0.2)
	var spot: Vector3 = camera.eye + look.normalized() * reach
	spot.y = clampf(spot.y, MIN_CENTRE_HEIGHT, MAX_CENTRE_HEIGHT)
	wall.centre = camera.eye + ahead * distance + Vector3.UP * (spot.y - camera.eye.y)
	return wall


## The room point of a wall pixel (0, 0 is the top left corner, may be outside the wall).
func point(pixel: Vector2) -> Vector3:
	var along: Vector2 = pixel * PIXEL - Vector2(WIDTH, HEIGHT) / 2.0
	return centre + right * along.x - Vector3.UP * along.y


## The wall pixel under a window point, or null when that ray does not reach the wall in front.
func pixel_at(camera: ArCamera, window_point: Vector2) -> Variant:
	var direction: Vector3 = camera.ray(window_point)
	var facing_wall: float = -direction.dot(normal)
	if facing_wall < MIN_FACING:
		return null
	var distance: float = (camera.eye - centre).dot(normal) / facing_wall
	if distance <= 0.0:
		return null
	var hit: Vector3 = camera.eye + direction * distance - centre
	return Vector2(hit.dot(right) + WIDTH / 2.0, HEIGHT / 2.0 - hit.y) / PIXEL
