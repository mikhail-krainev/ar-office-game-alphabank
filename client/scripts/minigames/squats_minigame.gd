class_name SquatsMinigame
extends Minigame
## "Morning exercise": put the phone on a desk facing you and do squats. Pose detection measures
## the knee angle; SquatCounter turns it into repetitions. AR: a neon skeleton over the body, energy
## rings on the knees at the bottom of a squat and a floating "+1" for each repetition (scripts/ar).

const DEFAULT_REPS: int = 10
const DEFAULT_TIME_LIMIT: float = 120.0
const LOST_POSE_SECONDS: float = 1.0
const REP_POP_SECONDS: float = 0.8
const KNEE_RING_RADIUS: float = 9.0
const BONES: Array = [
	[&"left_shoulder", &"left_hip"], [&"left_hip", &"left_knee"], [&"left_knee", &"left_ankle"],
	[&"right_shoulder", &"right_hip"], [&"right_hip", &"right_knee"], [&"right_knee", &"right_ankle"],
	[&"left_shoulder", &"right_shoulder"], [&"left_hip", &"right_hip"],
]

var _needed: int = DEFAULT_REPS
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _counter: SquatCounter = SquatCounter.new()
var _landmarks: Dictionary = {}
var _since_pose: float = LOST_POSE_SECONDS
## Seconds since the last repetition (for the "+1"), and since the start (for the AR motion).
var _since_rep: float = REP_POP_SECONDS
var _ar_time: float = 0.0

var _view: CameraView
var _count_label: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_needed = int(task.params.get("reps", DEFAULT_REPS))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	add_hint(tr("MG_SQUATS_HINT") % _needed)
	_view = add_camera_view()
	_view.overlay = _draw_skeleton
	_count_label = add_big_label(232, 26, UiStyle.RED)
	_status = add_status()
	PlatformServices.pose_detected.connect(_on_pose)
	PlatformServices.start_camera(PlatformBackend.CameraMode.POSE, true)


func _exit_tree() -> void:
	super()
	PlatformServices.pose_detected.disconnect(_on_pose)


func _on_pose(landmarks: Dictionary) -> void:
	if is_done():
		return
	_landmarks = landmarks
	_since_pose = 0.0
	var before: int = _counter.reps
	_counter.update(landmarks)
	if _counter.reps != before:
		_since_rep = 0.0
	if _counter.reps != before and _counter.reps >= _needed:
		set_score(_time_left / _time_limit)
		proof["reps"] = _counter.reps
		finish(true)


func _process(delta: float) -> void:
	super(delta)
	_since_pose += delta
	_since_rep += delta
	_ar_time += delta
	if not is_done():
		_time_left -= delta
		if _time_left <= 0.0:
			finish(false)
	_count_label.text = "%d / %d" % [mini(_counter.reps, _needed), _needed]
	var state: String = tr("MG_SQUATS_NO_BODY")
	if _since_pose < LOST_POSE_SECONDS and _counter.knee_angle >= 0.0:
		state = tr("MG_SQUATS_DOWN") if _counter.is_down else tr("MG_SQUATS_UP")
	_status.text = "%s   %s" % [state, tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	_view.queue_redraw()


func _draw_skeleton(view: CameraView, image_rect: Rect2) -> void:
	if _since_pose >= LOST_POSE_SECONDS:
		return
	var color: Color = ArPainter.NEON_PINK if _counter.is_down else ArPainter.NEON_CYAN
	for bone: Array in BONES:
		if _landmarks.has(bone[0]) and _landmarks.has(bone[1]):
			ArPainter.neon_line(view, _to_view(_landmarks[bone[0]], image_rect), _to_view(_landmarks[bone[1]], image_rect), color)
	for landmark: StringName in _landmarks:
		view.draw_circle(_to_view(_landmarks[landmark], image_rect), 3.0, Color.WHITE)
	if _counter.is_down:
		for knee: StringName in [&"left_knee", &"right_knee"]:
			if _landmarks.has(knee):
				var pulse: float = 0.5 + 0.5 * sin(_ar_time * 12.0)
				view.draw_arc(_to_view(_landmarks[knee], image_rect), KNEE_RING_RADIUS + pulse * 4.0, 0.0, TAU, 20, UiStyle.GOLD, 2.0)
	var nose: Vector3 = _landmarks.get(&"nose", Vector3(0.5, 0.2, 0.0))
	ArPainter.pop_text(view, _to_view(nose, image_rect) + Vector2(0, -14), "+1", _since_rep / REP_POP_SECONDS)


static func _to_view(point: Vector3, image_rect: Rect2) -> Vector2:
	return image_rect.position + Vector2(point.x, point.y) * image_rect.size
