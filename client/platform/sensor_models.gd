class_name SensorModels
extends RefCounted
## Data passed from the platform layer to game code. The web bridge sends JSON; these helpers
## convert it so game code never parses bridge payloads itself.


## One detected face. Coordinates are normalized to the camera frame (0..1).
class Face:
	extends RefCounted

	var bounds: Rect2 = Rect2()
	## Probability of a smile, 0..1, or -1 when the detector does not report it.
	var smiling: float = -1.0

	func _init(p_bounds: Rect2 = Rect2(), p_smiling: float = -1.0) -> void:
		bounds = p_bounds
		smiling = p_smiling


## One recognized object: the model label text and how sure the model is.
class ObjectLabel:
	extends RefCounted

	var id: String = ""
	var confidence: float = 0.0

	func _init(p_id: String = "", p_confidence: float = 0.0) -> void:
		id = p_id
		confidence = p_confidence


## Pose landmark names used by game code (MediaPipe landmark indices map to these).
const POSE_LANDMARKS: Array[StringName] = [
	&"nose", &"left_shoulder", &"right_shoulder", &"left_hip", &"right_hip",
	&"left_knee", &"right_knee", &"left_ankle", &"right_ankle",
]


## Pose JSON: {"landmarks": {"left_knee": [x, y, likelihood], ...}} with x, y normalized.
static func parse_pose(json: String) -> Dictionary:
	var result: Dictionary = {}
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return result
	var landmarks: Variant = (parsed as Dictionary).get("landmarks")
	if not landmarks is Dictionary:
		return result
	for name: StringName in POSE_LANDMARKS:
		var point: Variant = (landmarks as Dictionary).get(String(name))
		if point is Array and (point as Array).size() >= 3:
			var values: Array = point
			result[name] = Vector3(float(values[0]), float(values[1]), float(values[2]))
	return result


## Faces JSON: {"faces": [{"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.3, "smiling": 0.9}, ...]}.
static func parse_faces(json: String) -> Array[Face]:
	var result: Array[Face] = []
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return result
	var faces: Variant = (parsed as Dictionary).get("faces")
	if not faces is Array:
		return result
	for entry: Variant in faces:
		if not entry is Dictionary:
			continue
		var face: Dictionary = entry
		var bounds: Rect2 = Rect2(float(face.get("x", 0)), float(face.get("y", 0)), float(face.get("w", 0)), float(face.get("h", 0)))
		result.append(Face.new(bounds, float(face.get("smiling", -1.0))))
	return result


## Markers JSON: {"markers": [10, 12]}.
static func parse_markers(json: String) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return result
	var markers: Variant = (parsed as Dictionary).get("markers")
	if markers is Array:
		for marker: Variant in markers:
			result.append(int(marker))
	return result


## Labels JSON: {"labels": [{"id": "coffee mug", "confidence": 0.82}, ...]}, most confident first.
static func parse_labels(json: String) -> Array[ObjectLabel]:
	var result: Array[ObjectLabel] = []
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return result
	var labels: Variant = (parsed as Dictionary).get("labels")
	if not labels is Array:
		return result
	for entry: Variant in labels:
		if entry is Dictionary:
			var label: Dictionary = entry
			result.append(ObjectLabel.new(str(label.get("id", "")), float(label.get("confidence", 0.0))))
	return result


## Camera frame as tightly packed RGB bytes.
static func frame_from_rgb(width: int, height: int, rgb: PackedByteArray) -> Image:
	if width <= 0 or height <= 0 or rgb.size() != width * height * 3:
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, rgb)
