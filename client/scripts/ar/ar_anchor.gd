class_name ArAnchor
extends RefCounted
## Where an AR sticker stands on a face, in the coordinates of the control that draws it. Built from
## the face landmarks when the detector sends them, else estimated from the face box. Pure math, so
## it is tested without a camera.

## Eye line of a face box without landmarks, as a share of the box height from its top.
const EYE_LINE: float = 0.4
## Outer eye corners of a face box without landmarks, as a share of the box width.
const EYE_INSET: float = 0.2

## Outer eye corners, left to right on screen.
var left_eye: Vector2 = Vector2.ZERO
var right_eye: Vector2 = Vector2.ZERO
## Top of the forehead and the chin.
var top: Vector2 = Vector2.ZERO
var chin: Vector2 = Vector2.ZERO


## The face mapped through `image_rect`, the rectangle the whole camera frame occupies.
static func of_face(face: SensorModels.Face, image_rect: Rect2) -> ArAnchor:
	var anchor: ArAnchor = ArAnchor.new()
	if face.has_anchors():
		anchor.left_eye = to_view(face.left_eye, image_rect)
		anchor.right_eye = to_view(face.right_eye, image_rect)
		anchor.top = to_view(face.top, image_rect)
		anchor.chin = to_view(face.chin, image_rect)
		return anchor
	var box: Rect2 = Rect2(
		to_view(face.bounds.position, image_rect), face.bounds.size * image_rect.size
	)
	var eye_y: float = box.position.y + box.size.y * EYE_LINE
	anchor.left_eye = Vector2(box.position.x + box.size.x * EYE_INSET, eye_y)
	anchor.right_eye = Vector2(box.end.x - box.size.x * EYE_INSET, eye_y)
	anchor.top = Vector2(box.get_center().x, box.position.y)
	anchor.chin = Vector2(box.get_center().x, box.end.y)
	return anchor


## Normalized frame point -> control point.
static func to_view(point: Vector2, image_rect: Rect2) -> Vector2:
	return image_rect.position + point * image_rect.size


## Middle of the eye line: the stickers' origin.
func eye_center() -> Vector2:
	return (left_eye + right_eye) / 2.0


## Distance between the outer eye corners: the stickers' scale.
func eye_span() -> float:
	return left_eye.distance_to(right_eye)


## Head tilt in radians (0 when the eyes are level), so stickers turn with the head.
func roll() -> float:
	return (right_eye - left_eye).angle()
