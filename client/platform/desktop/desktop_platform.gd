extends PlatformBackend
@warning_ignore_start("integer_division")
## Debug-only desktop implementation: emulates phone sensors from the keyboard so every minigame
## can be played on a PC. The microphone is real. See SensorEmulator for the controls.

const GRAVITY: float = 9.81
const FRAME_INTERVAL: float = 1.0 / 12.0
const FRAME_SIZE: Vector2i = Vector2i(96, 72)
const STEPS_PER_SECOND: float = 2.5
const TILT_SPEED: float = 60.0
const TILT_RETURN_SPEED: float = 90.0
const MAX_TILT: float = 80.0
const JERK_STRENGTH: float = 9.0
const SQUAT_SPEED: float = 2.5
const STAND_KNEE_ANGLE: float = 175.0
const SQUAT_KNEE_ANGLE: float = 75.0
const SPEECH_DELAY: float = 0.6

var tilt: Vector2 = Vector2.ZERO
var face_count: int = 0
var smiling: bool = false
var marker_id: int = 0
## Object label the emulated camera "sees" in CameraMode.LABELS.
var label_id: String = ""
## 0 = standing, 1 = full squat.
var squat_depth: float = 0.0

var _steps_running: bool = false
var _steps: float = 0.0
var _camera_running: bool = false
var _camera_mode: PlatformBackend.CameraMode = CameraMode.PREVIEW
var _camera_front: bool = false
var _frame_left: float = 0.0
var _speech_running: bool = false
var _jerk: Vector3 = Vector3.ZERO
var _emulator: SensorEmulator
## Notification id -> ticket of its latest schedule call; a stale ticket means it was replaced or cancelled.
var _notifications: Dictionary[int, int] = {}
var _notification_ticket: int = 0


func _ready() -> void:
	_emulator = SensorEmulator.new()
	_emulator.platform = self
	add_child(_emulator)


func has_feature(_feature: PlatformBackend.Feature) -> bool:
	return true


func get_acceleration() -> Vector3:
	var x: float = GRAVITY * sin(deg_to_rad(tilt.x))
	var y: float = GRAVITY * sin(deg_to_rad(tilt.y))
	var z: float = -sqrt(maxf(0.0, pow(GRAVITY, 2) - x * x - y * y))
	return Vector3(x, y, z) + _jerk


func jerk() -> void:
	_jerk = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0).normalized() * JERK_STRENGTH


func start_step_counter() -> void:
	_steps_running = true
	_steps = 0.0
	_emulator.refresh()


func stop_step_counter() -> void:
	_steps_running = false
	_emulator.refresh()


func add_steps(count: int) -> void:
	if not _steps_running:
		return
	_steps += count
	steps_changed.emit(floori(_steps))


func start_camera(mode: PlatformBackend.CameraMode, front: bool) -> void:
	_camera_running = true
	_camera_mode = mode
	_camera_front = front
	_frame_left = 0.0
	_emulator.refresh()


func stop_camera() -> void:
	_camera_running = false
	_emulator.refresh()


func start_speech(_locale: String) -> void:
	_speech_running = true
	_emulator.refresh()


func stop_speech() -> void:
	_speech_running = false
	_emulator.refresh()


## Notifications "arrive" as an in-game banner while the game runs; nothing reaches the desktop.
func schedule_notification(id: int, title: String, body: String, delay_seconds: int) -> void:
	_notification_ticket += 1
	var ticket: int = _notification_ticket
	_notifications[id] = ticket
	await get_tree().create_timer(delay_seconds).timeout
	if _notifications.get(id, -1) == ticket:
		_notifications.erase(id)
		notification_shown.emit(title, body)


func cancel_all_notifications() -> void:
	_notifications.clear()


func is_steps_running() -> bool:
	return _steps_running


func is_camera_running() -> bool:
	return _camera_running


func get_camera_mode() -> PlatformBackend.CameraMode:
	return _camera_mode


func is_speech_running() -> bool:
	return _speech_running


## Called by the emulator panel: the QR "seen" by the camera.
func emit_qr(text: String) -> void:
	if _camera_running and _camera_mode == CameraMode.QR:
		qr_detected.emit(text)


## Called by the emulator panel: the phrase "heard" by the recognizer.
func emit_speech(text: String) -> void:
	if not _speech_running:
		return
	speech_recognized.emit(text.substr(0, text.length() / 2), false)
	await get_tree().create_timer(SPEECH_DELAY).timeout
	if _speech_running:
		_speech_running = false
		_emulator.refresh()
		speech_recognized.emit(text, true)


func _process(delta: float) -> void:
	_update_tilt(delta)
	_jerk = _jerk.move_toward(Vector3.ZERO, JERK_STRENGTH * delta * 8.0)
	if _steps_running and Input.is_physical_key_pressed(KEY_W):
		var before: int = floori(_steps)
		_steps += STEPS_PER_SECOND * delta
		if floori(_steps) != before:
			steps_changed.emit(floori(_steps))
	var squatting: bool = Input.is_physical_key_pressed(KEY_S)
	squat_depth = move_toward(squat_depth, 1.0 if squatting else 0.0, SQUAT_SPEED * delta)
	if not _camera_running:
		return
	_frame_left -= delta
	if _frame_left > 0.0:
		return
	_frame_left = FRAME_INTERVAL
	camera_frame.emit(_render_frame())
	match _camera_mode:
		CameraMode.POSE:
			pose_detected.emit(_pose())
		CameraMode.FACES:
			faces_detected.emit(_faces())
		CameraMode.MARKERS:
			markers_detected.emit(PackedInt32Array([marker_id]) if marker_id > 0 else PackedInt32Array())
		CameraMode.LABELS:
			labels_detected.emit(_labels())


func _update_tilt(delta: float) -> void:
	var input: Vector2 = Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)),
	)
	if input.is_zero_approx():
		tilt = tilt.move_toward(Vector2.ZERO, TILT_RETURN_SPEED * delta)
	else:
		tilt = (tilt + input * TILT_SPEED * delta).limit_length(MAX_TILT)


func _knee_angle() -> float:
	return lerpf(STAND_KNEE_ANGLE, SQUAT_KNEE_ANGLE, squat_depth)


## Side view of the left leg: hip above the knee, shin vertical, thigh rotating with depth.
## Like the native plugin, front camera data is mirrored.
func _pose() -> Dictionary:
	var ankle: Vector2 = Vector2(0.5, 0.9)
	var knee: Vector2 = Vector2(0.5, 0.7)
	var thigh_angle: float = deg_to_rad(180.0 - _knee_angle())
	var hip: Vector2 = knee + Vector2(-sin(thigh_angle), -cos(thigh_angle)) * 0.2
	var pose: Dictionary = {
		&"left_hip": Vector3(hip.x, hip.y, 0.99),
		&"left_knee": Vector3(knee.x, knee.y, 0.99),
		&"left_ankle": Vector3(ankle.x, ankle.y, 0.99),
		&"left_shoulder": Vector3(hip.x, hip.y - 0.3, 0.99),
		&"nose": Vector3(hip.x, hip.y - 0.4, 0.99),
	}
	if _camera_front:
		for landmark: StringName in pose:
			var point: Vector3 = pose[landmark]
			pose[landmark] = Vector3(1.0 - point.x, point.y, point.z)
	return pose


## The chosen object plus a distractor, like a real labeler returns.
func _labels() -> Array[SensorModels.ObjectLabel]:
	var result: Array[SensorModels.ObjectLabel] = []
	if not label_id.is_empty():
		result.append(SensorModels.ObjectLabel.new(label_id, 0.86))
	result.append(SensorModels.ObjectLabel.new("person", 0.42))
	return result


func _faces() -> Array[SensorModels.Face]:
	var result: Array[SensorModels.Face] = []
	for i: int in face_count:
		var bounds: Rect2 = Rect2(0.1 + i * 0.3, 0.3, 0.22, 0.3)
		if _camera_front:
			bounds.position.x = 1.0 - bounds.end.x
		result.append(SensorModels.Face.new(bounds, 0.95 if smiling else 0.05))
	return result


func _render_frame() -> Image:
	var frame: Image = Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGB8)
	for y: int in FRAME_SIZE.y:
		var shade: float = 0.35 + 0.25 * float(y) / FRAME_SIZE.y
		frame.fill_rect(Rect2i(0, y, FRAME_SIZE.x, 1), Color(shade, shade * 0.97, shade * 0.92))
	var size: Vector2 = Vector2(FRAME_SIZE)
	match _camera_mode:
		CameraMode.FACES:
			for face: SensorModels.Face in _faces():
				var rect: Rect2i = Rect2i(face.bounds.position * size, face.bounds.size * size)
				frame.fill_rect(rect, Color("#e0b089"))
				frame.fill_rect(Rect2i(rect.position + Vector2i(4, 6), Vector2i(3, 3)), Color.BLACK)
				frame.fill_rect(Rect2i(rect.position + Vector2i(rect.size.x - 7, 6), Vector2i(3, 3)), Color.BLACK)
				var mouth_width: int = rect.size.x - 8 if smiling else 6
				frame.fill_rect(Rect2i(rect.get_center().x - mouth_width / 2, rect.end.y - 7, mouth_width, 2), Color("#8a2b20"))
		CameraMode.POSE:
			var pose: Dictionary = _pose()
			for landmark: StringName in pose:
				var point: Vector3 = pose[landmark]
				frame.fill_rect(Rect2i(Vector2i(Vector2(point.x, point.y) * size) - Vector2i(2, 2), Vector2i(4, 4)), Color("#ef3124"))
		CameraMode.MARKERS:
			if marker_id > 0:
				var origin: Vector2i = FRAME_SIZE / 2 - Vector2i(18, 18)
				frame.fill_rect(Rect2i(origin, Vector2i(36, 36)), Color.BLACK)
				for bit: int in 16:
					if (marker_id * 2654435761 >> bit) & 1:
						frame.fill_rect(Rect2i(origin + Vector2i(6 + bit % 4 * 6, 6 + bit / 4 * 6), Vector2i(6, 6)), Color.WHITE)
		CameraMode.QR:
			frame.fill_rect(Rect2i(FRAME_SIZE / 2 - Vector2i(20, 20), Vector2i(40, 40)), Color.WHITE)
		CameraMode.LABELS:
			var tint: Color = Color.from_hsv(float(hash(label_id) % 360) / 360.0, 0.5, 0.8)
			frame.fill_rect(Rect2i(FRAME_SIZE / 2 - Vector2i(22, 18), Vector2i(44, 36)), tint if not label_id.is_empty() else Color("#3a3a44"))
		_:
			frame.fill_rect(Rect2i(FRAME_SIZE / 2 - Vector2i(16, 16), Vector2i(32, 32)), Color("#4a6fa5"))
	for i: int in 40:
		frame.set_pixel(randi() % FRAME_SIZE.x, randi() % FRAME_SIZE.y, Color(randf(), randf(), randf()))
	return frame
