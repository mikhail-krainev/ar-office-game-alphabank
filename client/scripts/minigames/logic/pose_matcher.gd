class_name PoseMatcher
extends RefCounted
## Poses of "Copy the pose" and whether body landmarks show them. Every check is measured in shoulder
## widths from the shoulders, so it does not depend on how far the player stands from the camera.
## The same poses give the ghost figure the player copies (target_points). Pure math, tested without
## a camera.

const HANDS_UP: StringName = &"hands_up"
const T_POSE: StringName = &"t_pose"
const LEFT_UP: StringName = &"left_up"
const RIGHT_UP: StringName = &"right_up"
const HANDS_ON_HEAD: StringName = &"hands_on_head"
const POSES: Array[StringName] = [HANDS_UP, T_POSE, LEFT_UP, RIGHT_UP, HANDS_ON_HEAD]

## A landmark counts when the detector is at least this sure of it.
const MIN_LIKELIHOOD: float = 0.5
## Narrower shoulders (normalized) mean the body is not really in the frame.
const MIN_SHOULDER_WIDTH: float = 0.04
## The nose is about this many shoulder widths above the shoulder line.
const NOSE_HEIGHT: float = 0.7

## Elbow and wrist of each pose from its shoulder, in shoulder widths: x outwards from the body,
## y downwards. LEFT_UP and RIGHT_UP raise one arm and lower the other.
const ARM_UP: Array[Vector2] = [Vector2(0.15, -0.8), Vector2(0.2, -1.6)]
const ARM_SIDE: Array[Vector2] = [Vector2(0.8, 0.0), Vector2(1.6, 0.0)]
const ARM_DOWN: Array[Vector2] = [Vector2(0.15, 0.8), Vector2(0.2, 1.6)]
const ARM_ON_HEAD: Array[Vector2] = [Vector2(0.7, -0.7), Vector2(-0.2, -1.0)]


## Elbow and wrist offsets [left arm, right arm] of `pose`.
static func arms_of(pose: StringName) -> Array:
	match pose:
		HANDS_UP:
			return [ARM_UP, ARM_UP]
		T_POSE:
			return [ARM_SIDE, ARM_SIDE]
		LEFT_UP:
			return [ARM_UP, ARM_DOWN]
		RIGHT_UP:
			return [ARM_DOWN, ARM_UP]
		HANDS_ON_HEAD:
			return [ARM_ON_HEAD, ARM_ON_HEAD]
	return [ARM_DOWN, ARM_DOWN]


## Ghost figure of `pose` on the player's shoulders (normalized points): {left_elbow, left_wrist,
## right_elbow, right_wrist}. Each side goes outwards from the middle of the shoulders.
static func target_points(pose: StringName, left_shoulder: Vector2, right_shoulder: Vector2) -> Dictionary:
	var width: float = maxf(left_shoulder.distance_to(right_shoulder), MIN_SHOULDER_WIDTH)
	var outwards_left: float = signf(left_shoulder.x - right_shoulder.x) if not is_equal_approx(left_shoulder.x, right_shoulder.x) else -1.0
	var arms: Array = arms_of(pose)
	var result: Dictionary = {}
	for side: int in 2:
		var shoulder: Vector2 = left_shoulder if side == 0 else right_shoulder
		var outwards: float = outwards_left if side == 0 else -outwards_left
		var prefix: String = "left_" if side == 0 else "right_"
		var offsets: Array = arms[side]
		for joint: int in 2:
			var offset: Vector2 = offsets[joint]
			result[StringName(prefix + ("elbow" if joint == 0 else "wrist"))] = shoulder + Vector2(offset.x * outwards, offset.y) * width
	return result


## The landmarks show `pose`.
static func matches(pose: StringName, landmarks: Dictionary) -> bool:
	for name: StringName in [&"left_shoulder", &"right_shoulder", &"left_wrist", &"right_wrist"]:
		if not _seen(landmarks, name):
			return false
	var left_shoulder: Vector2 = _point(landmarks, &"left_shoulder")
	var right_shoulder: Vector2 = _point(landmarks, &"right_shoulder")
	var width: float = left_shoulder.distance_to(right_shoulder)
	if width < MIN_SHOULDER_WIDTH:
		return false
	var shoulder_y: float = (left_shoulder.y + right_shoulder.y) / 2.0
	var head_y: float = _point(landmarks, &"nose").y if _seen(landmarks, &"nose") else shoulder_y - NOSE_HEIGHT * width
	var head_x: float = _point(landmarks, &"nose").x if _seen(landmarks, &"nose") else (left_shoulder.x + right_shoulder.x) / 2.0
	var left: Vector2 = _point(landmarks, &"left_wrist")
	var right: Vector2 = _point(landmarks, &"right_wrist")
	# Raised hands are well above the head; hands on the head stay below that line.
	var raised_y: float = head_y - 0.5 * width
	var is_up: Callable = func(wrist: Vector2) -> bool: return wrist.y < raised_y
	var is_down: Callable = func(wrist: Vector2) -> bool: return wrist.y > shoulder_y + 0.5 * width
	var is_side: Callable = func(wrist: Vector2, shoulder: Vector2) -> bool:
		return absf(wrist.y - shoulder.y) < 0.6 * width and absf(wrist.x - shoulder.x) > 0.9 * width
	var is_on_head: Callable = func(wrist: Vector2) -> bool:
		return absf(wrist.x - head_x) < 0.8 * width and wrist.y < shoulder_y - 0.2 * width and wrist.y >= raised_y
	match pose:
		HANDS_UP:
			return is_up.call(left) and is_up.call(right)
		T_POSE:
			return is_side.call(left, left_shoulder) and is_side.call(right, right_shoulder)
		LEFT_UP:
			return is_up.call(left) and is_down.call(right)
		RIGHT_UP:
			return is_up.call(right) and is_down.call(left)
		HANDS_ON_HEAD:
			return is_on_head.call(left) and is_on_head.call(right)
	return false


## `count` different poses in random order (all of them when count is larger).
static func pick(count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var poses: Array[StringName] = POSES.duplicate()
	for i: int in range(poses.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: StringName = poses[i]
		poses[i] = poses[j]
		poses[j] = swap
	return poses.slice(0, mini(count, poses.size()))


static func _seen(landmarks: Dictionary, name: StringName) -> bool:
	return landmarks.has(name) and (landmarks[name] as Vector3).z >= MIN_LIKELIHOOD


static func _point(landmarks: Dictionary, name: StringName) -> Vector2:
	var point: Vector3 = landmarks[name]
	return Vector2(point.x, point.y)
