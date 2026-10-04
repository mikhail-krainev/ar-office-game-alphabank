class_name PlatformBackend
extends Node
## Platform implementation behind PlatformServices. This base class is the "nothing available"
## platform: accelerometer and microphone come from the Godot core, everything else reports
## unsupported. Subclasses override what their platform provides.

@warning_ignore_start("unused_signal")
signal steps_changed(steps: int)
signal camera_frame(frame: Image)
signal pose_detected(landmarks: Dictionary)
signal faces_detected(faces: Array[SensorModels.Face])
signal markers_detected(marker_ids: PackedInt32Array)
signal labels_detected(labels: Array[SensorModels.ObjectLabel])
signal qr_detected(text: String)
signal speech_recognized(text: String, is_final: bool)
signal speech_failed(error: String)
## Emulated platforms only: a scheduled notification "arrived" while the game is open.
signal notification_shown(title: String, body: String)
@warning_ignore_restore("unused_signal")

signal _image_picked(image: Image)

enum Feature {
	ACCELEROMETER,
	PEDOMETER,
	CAMERA,
	QR_SCAN,
	POSE_DETECTION,
	FACE_DETECTION,
	MARKER_DETECTION,
	OBJECT_RECOGNITION,
	MICROPHONE,
	SPEECH_RECOGNITION,
	## Local notifications scheduled by the game (reminders, announcements).
	NOTIFICATIONS,
	## Picking a picture from the gallery or the file system.
	PHOTO_LIBRARY,
}

enum CameraMode { PREVIEW, QR, POSE, FACES, MARKERS, LABELS }


func has_feature(feature: Feature) -> bool:
	match feature:
		Feature.ACCELEROMETER:
			return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		Feature.MICROPHONE:
			return bool(ProjectSettings.get_setting("audio/driver/enable_input", false))
		Feature.PHOTO_LIBRARY:
			return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	return false


## Asks the OS for the permissions the features need. Resolves to true when all are granted.
func request_access(_features: Array[Feature]) -> bool:
	return true


## Why the last request_access() was refused, for the message to the player: "" (unknown),
## "microphone_site" (blocked for this site in the browser) or "microphone_system" (the browser app
## has no microphone access in the phone settings). Web only adds ":<error name>" for diagnostics.
func access_problem() -> String:
	return ""


func get_acceleration() -> Vector3:
	return Input.get_accelerometer()


## Raw microphone samples. The base class uses the Godot core (MicrophoneCapture); the web replaces it.
func start_microphone() -> void:
	_core_microphone().start()


func stop_microphone() -> void:
	_core_microphone().stop()


func get_microphone_sample_rate() -> float:
	return _core_microphone().get_sample_rate()


## Mono samples captured since the previous call, at most `max_frames`.
func read_microphone(max_frames: int) -> PackedFloat32Array:
	return _core_microphone().read(max_frames)


func start_step_counter() -> void:
	pass


func stop_step_counter() -> void:
	pass


func start_camera(_mode: CameraMode, _front: bool) -> void:
	pass


func stop_camera() -> void:
	pass


## Shows the camera at full quality over `rect` (window pixels) outside the game viewport. Returns
## false when the platform cannot, then the game draws camera_frame itself. An empty rect hides it.
func show_camera_view(_rect: Rect2) -> bool:
	return false


func start_speech(_locale: String) -> void:
	speech_failed.emit("unsupported")


## Lets the next tap start recognition where the browser allows it only inside a tap.
func prepare_speech(_locale: String) -> void:
	pass


func stop_speech() -> void:
	pass


## Shows `body` under `title` after `delay_seconds`, even when the game is closed. A new call with
## the same id replaces the earlier notification.
func schedule_notification(_id: int, _title: String, _body: String, _delay_seconds: int) -> void:
	pass


func cancel_all_notifications() -> void:
	pass


## Web only: scheme and host of the page, see PlatformServices.get_page_origin().
func page_origin() -> String:
	return ""


## Lets the player choose a picture. Resolves to null when cancelled or unreadable.
func pick_image() -> Image:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		return null
	var on_selected: Callable = func(status: bool, paths: PackedStringArray, _filter: int) -> void:
		_image_picked.emit(load_image_file(paths[0]) if status and not paths.is_empty() else null)
	DisplayServer.file_dialog_show(
		"", OS.get_system_dir(OS.SYSTEM_DIR_PICTURES), "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"]), on_selected
	)
	return await _image_picked


func _core_microphone() -> MicrophoneCapture:
	var capture: MicrophoneCapture = get_node_or_null(^"Microphone") as MicrophoneCapture
	if capture == null:
		capture = MicrophoneCapture.new()
		capture.name = "Microphone"
		add_child(capture)
	return capture


static func load_image_file(path: String) -> Image:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	return decode_image(bytes)


## PNG, JPEG or WebP bytes to an image; null when the format is not supported.
static func decode_image(bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image: Image = Image.new()
	for loader: Callable in [image.load_png_from_buffer, image.load_jpg_from_buffer, image.load_webp_from_buffer]:
		if loader.call(bytes) == OK:
			return image
	return null
