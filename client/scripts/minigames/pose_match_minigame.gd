class_name PoseMatchMinigame
extends Minigame
## "Copy the pose" (AR): put the phone on a desk facing you and step back. A gold ghost figure stands
## on your shoulders in the camera view and shows a pose (hands up, T, one hand up, hands on the
## head); copy it and hold it until the ring fills. Pose detection (PoseMatcher) checks the arms; a
## neon skeleton shows how the phone sees you. The frames stay on the phone.

const DEFAULT_POSES: int = 4
const DEFAULT_TIME_LIMIT: float = 90.0
const HOLD_SECONDS: float = 1.2
## A pose lost for a moment (a missed frame) does not reset the hold.
const HOLD_GRACE: float = 0.3
const LOST_POSE_SECONDS: float = 1.0
const MATCH_EFFECT_SECONDS: float = 0.7
const VIEW_RECT: Rect2 = Rect2(30, 34, 260, 200)
const HOLD_RING_RADIUS: float = 16.0
## Ghost shoulders when the body is not seen yet (normalized frame points).
const IDLE_SHOULDERS: Array[Vector2] = [Vector2(0.4, 0.42), Vector2(0.6, 0.42)]
const BONES: Array = [
	[&"left_shoulder", &"right_shoulder"], [&"left_shoulder", &"left_elbow"], [&"left_elbow", &"left_wrist"],
	[&"right_shoulder", &"right_elbow"], [&"right_elbow", &"right_wrist"],
	[&"left_shoulder", &"left_hip"], [&"right_shoulder", &"right_hip"], [&"left_hip", &"right_hip"],
]

var _poses: Array[StringName] = []
var _index: int = 0
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _held: float = 0.0
var _since_match: float = HOLD_GRACE
var _since_pose: float = LOST_POSE_SECONDS
var _since_done: float = MATCH_EFFECT_SECONDS
var _landmarks: Dictionary = {}
var _ar_time: float = 0.0

var _view: CameraView
var _pose_label: Label
var _status: Label


func _ready() -> void:
	var count: int = DEFAULT_POSES
	if task != null:
		count = int(task.params.get("poses", DEFAULT_POSES))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_poses = PoseMatcher.pick(count, rng)
	add_hint(tr("MG_POSE_HINT"))
	_view = add_camera_view(VIEW_RECT)
	_view.overlay = _draw_overlay
	_pose_label = add_big_label(VIEW_RECT.end.y + 6, 15, UiStyle.RED)
	_status = add_status()
	PlatformServices.pose_detected.connect(_on_pose)
	PlatformServices.start_camera(PlatformBackend.CameraMode.POSE, true)


func _exit_tree() -> void:
	super()
	PlatformServices.pose_detected.disconnect(_on_pose)


func _on_pose(landmarks: Dictionary) -> void:
	_landmarks = landmarks
	_since_pose = 0.0
	if not is_done() and PoseMatcher.matches(_poses[_index], landmarks):
		_since_match = 0.0


func _process(delta: float) -> void:
	super(delta)
	_ar_time += delta
	_since_pose += delta
	_since_match += delta
	_since_done += delta
	if not is_done():
		_update_hold(delta)
		_time_left -= delta
		if _time_left <= 0.0:
			finish(false)
	var shown: int = mini(_index, _poses.size() - 1)
	_pose_label.text = "%d / %d  %s" % [mini(_index + 1, _poses.size()), _poses.size(), tr("MG_POSE_" + String(_poses[shown]).to_upper())]
	var state: String = tr("MG_POSE_NO_BODY") if _since_pose >= LOST_POSE_SECONDS else (tr("MG_POSE_HOLD") if _held > 0.0 else tr("MG_POSE_COPY"))
	_status.text = "%s   %s" % [state, tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	_view.queue_redraw()


func _update_hold(delta: float) -> void:
	if _since_match > HOLD_GRACE:
		_held = 0.0
		return
	_held += delta
	if _held < HOLD_SECONDS:
		return
	_held = 0.0
	_since_match = HOLD_GRACE
	_since_done = 0.0
	_index += 1
	if _index >= _poses.size():
		set_score(_time_left / _time_limit)
		proof["poses"] = _poses.size()
		finish(true)


func _draw_overlay(view: CameraView, image_rect: Rect2) -> void:
	var shoulders: Array[Vector2] = _shoulders()
	var left: Vector2 = _to_view(shoulders[0], image_rect)
	var right: Vector2 = _to_view(shoulders[1], image_rect)
	if _index < _poses.size():
		_draw_ghost(view, image_rect, shoulders)
	if _since_pose < LOST_POSE_SECONDS:
		_draw_skeleton(view, image_rect)
	var head: Vector2 = (left + right) / 2.0 + Vector2(0, -left.distance_to(right) * 0.9)
	if _held > 0.0:
		view.draw_arc(head, HOLD_RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * _held / HOLD_SECONDS, 24, ArPainter.NEON_CYAN, 3.0)
	var age: float = _since_done / MATCH_EFFECT_SECONDS
	ArPainter.burst(view, head, 34.0, age, UiStyle.GOLD)
	ArPainter.pop_text(view, head + Vector2(0, -20), tr("MG_POSE_NICE"), age)


## The player's shoulders when seen, else a standing spot in the middle of the frame.
func _shoulders() -> Array[Vector2]:
	if _since_pose < LOST_POSE_SECONDS and _landmarks.has(&"left_shoulder") and _landmarks.has(&"right_shoulder"):
		var left: Vector3 = _landmarks[&"left_shoulder"]
		var right: Vector3 = _landmarks[&"right_shoulder"]
		if Vector2(left.x, left.y).distance_to(Vector2(right.x, right.y)) >= PoseMatcher.MIN_SHOULDER_WIDTH:
			return [Vector2(left.x, left.y), Vector2(right.x, right.y)]
	return IDLE_SHOULDERS


## The gold ghost of the pose to copy, pulsing softly.
func _draw_ghost(view: CameraView, image_rect: Rect2, shoulders: Array[Vector2]) -> void:
	var targets: Dictionary = PoseMatcher.target_points(_poses[_index], shoulders[0], shoulders[1])
	var color: Color = Color(UiStyle.GOLD, 0.55 + 0.25 * sin(_ar_time * 4.0))
	var left: Vector2 = _to_view(shoulders[0], image_rect)
	var right: Vector2 = _to_view(shoulders[1], image_rect)
	var width: float = left.distance_to(right)
	ArPainter.neon_line(view, left, right, color, 3.0)
	for side: String in ["left_", "right_"]:
		var shoulder: Vector2 = left if side == "left_" else right
		var elbow: Vector2 = _to_view(targets[StringName(side + "elbow")], image_rect)
		var wrist: Vector2 = _to_view(targets[StringName(side + "wrist")], image_rect)
		ArPainter.neon_polyline(view, PackedVector2Array([shoulder, elbow, wrist]), color, 3.0)
		view.draw_circle(wrist, 4.0, color)
	var middle: Vector2 = (left + right) / 2.0
	view.draw_arc(middle + Vector2(0, -width * 0.55), width * 0.28, 0.0, TAU, 20, color, 2.0)
	ArPainter.neon_line(view, middle, middle + Vector2(0, width * 1.3), color, 3.0)


func _draw_skeleton(view: CameraView, image_rect: Rect2) -> void:
	var color: Color = ArPainter.NEON_PINK if _held > 0.0 else ArPainter.NEON_CYAN
	for bone: Array in BONES:
		if _landmarks.has(bone[0]) and _landmarks.has(bone[1]):
			ArPainter.neon_line(view, _landmark_view(bone[0], image_rect), _landmark_view(bone[1], image_rect), color)
	for wrist: StringName in [&"left_wrist", &"right_wrist"]:
		if _landmarks.has(wrist):
			view.draw_circle(_landmark_view(wrist, image_rect), 5.0, Color.WHITE)


func _landmark_view(landmark: StringName, image_rect: Rect2) -> Vector2:
	var point: Vector3 = _landmarks[landmark]
	return _to_view(Vector2(point.x, point.y), image_rect)


static func _to_view(point: Vector2, image_rect: Rect2) -> Vector2:
	return image_rect.position + point * image_rect.size
