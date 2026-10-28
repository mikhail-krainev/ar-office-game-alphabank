class_name FaceCommands
extends RefCounted
## Face commands of "Cat mask": smile, wink, open the mouth, tilt the head. Reads the face detector's
## expression scores (blendshapes) and the eye line. A command the detector cannot see on this device
## (no score reported) is never asked. Pure logic, tested without a camera.

const SMILE: StringName = &"smile"
const WINK: StringName = &"wink"
const OPEN_MOUTH: StringName = &"open_mouth"
const TILT_HEAD: StringName = &"tilt_head"
const COMMANDS: Array[StringName] = [SMILE, WINK, OPEN_MOUTH, TILT_HEAD]

const SMILE_SCORE: float = 0.6
## A wink: one eye closed, the other open.
const CLOSED_EYE: float = 0.5
const OPEN_EYE: float = 0.35
const OPEN_JAW: float = 0.45
const TILT_DEGREES: float = 15.0


## Commands this face can show with the scores its detector reports.
static func available(face: SensorModels.Face) -> Array[StringName]:
	var result: Array[StringName] = []
	if face.smiling >= 0.0:
		result.append(SMILE)
	if face.blink_left >= 0.0 and face.blink_right >= 0.0:
		result.append(WINK)
	if face.jaw_open >= 0.0:
		result.append(OPEN_MOUTH)
	if face.has_anchors():
		result.append(TILT_HEAD)
	return result


## The face shows `command`. `roll` is the head tilt in radians (ArAnchor.roll()).
static func shows(command: StringName, face: SensorModels.Face, roll: float) -> bool:
	match command:
		SMILE:
			return face.smiling >= SMILE_SCORE
		WINK:
			var closed: float = maxf(face.blink_left, face.blink_right)
			var other: float = minf(face.blink_left, face.blink_right)
			return closed >= CLOSED_EYE and other >= 0.0 and other <= OPEN_EYE
		OPEN_MOUTH:
			return face.jaw_open >= OPEN_JAW
		TILT_HEAD:
			return face.has_anchors() and absf(rad_to_deg(roll)) >= TILT_DEGREES
	return false


## `count` commands from `pool`, never the same twice in a row.
static func sequence(pool: Array[StringName], count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var result: Array[StringName] = []
	if pool.is_empty():
		return result
	for i: int in count:
		var choices: Array[StringName] = pool.filter(func(command: StringName) -> bool: return result.is_empty() or command != result.back() or pool.size() == 1)
		result.append(choices[rng.randi_range(0, choices.size() - 1)])
	return result
