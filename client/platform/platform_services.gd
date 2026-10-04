extends Node
## Single entry point for platform-specific functionality (autoload "PlatformServices").
## Game code must use this instead of native plugins or JavaScriptBridge.
## Implementations: WebPlatform (the game runs in a phone browser), DesktopPlatform (debug
## emulation of phone sensors on a PC) and PlatformBackend (no platform features).

signal safe_rect_changed(rect: Rect2)
signal steps_changed(steps: int)
## Low-resolution RGB camera frame for the in-game preview.
signal camera_frame(frame: Image)
## Landmark name -> Vector3(x, y, in-frame likelihood), x and y normalized to the frame.
signal pose_detected(landmarks: Dictionary)
signal faces_detected(faces: Array[SensorModels.Face])
signal markers_detected(marker_ids: PackedInt32Array)
## Objects recognized in the camera frame, most confident first.
signal labels_detected(labels: Array[SensorModels.ObjectLabel])
signal qr_detected(text: String)
signal speech_recognized(text: String, is_final: bool)
signal speech_failed(error: String)
## Desktop emulation only: a scheduled notification "arrived" while the game is open.
signal notification_shown(title: String, body: String)

const WEB_SCRIPT: String = "res://platform/web/web_platform.gd"
const DESKTOP_SCRIPT: String = "res://platform/desktop/desktop_platform.gd"

var _has_safe_rect_override: bool = false
var _safe_rect_override: Rect2 = Rect2()
var _backend: PlatformBackend


func _ready() -> void:
	get_viewport().size_changed.connect(_emit_safe_rect)
	_backend = _create_backend()
	_backend.name = "Backend"
	add_child(_backend)
	_backend.steps_changed.connect(steps_changed.emit)
	_backend.camera_frame.connect(camera_frame.emit)
	_backend.pose_detected.connect(pose_detected.emit)
	_backend.faces_detected.connect(faces_detected.emit)
	_backend.markers_detected.connect(markers_detected.emit)
	_backend.labels_detected.connect(labels_detected.emit)
	_backend.qr_detected.connect(qr_detected.emit)
	_backend.speech_recognized.connect(speech_recognized.emit)
	_backend.speech_failed.connect(speech_failed.emit)
	_backend.notification_shown.connect(notification_shown.emit)


func _create_backend() -> PlatformBackend:
	var script_path: String = ""
	if OS.has_feature("web"):
		script_path = WEB_SCRIPT
	elif OS.has_feature("pc") and OS.is_debug_build():
		script_path = DESKTOP_SCRIPT
	if script_path.is_empty():
		return PlatformBackend.new()
	var script: GDScript = load(script_path)
	return script.new() as PlatformBackend


# --- Features --------------------------------------------------------------------


func has_feature(feature: PlatformBackend.Feature) -> bool:
	return _backend.has_feature(feature)


func has_features(features: Array[PlatformBackend.Feature]) -> bool:
	return features.all(func(feature: PlatformBackend.Feature) -> bool: return has_feature(feature))


## Requests OS permissions for the features. Resolves to true when everything is granted.
func request_access(features: Array[PlatformBackend.Feature]) -> bool:
	# Platform overrides may wait for OS dialogs.
	@warning_ignore("redundant_await")
	return await _backend.request_access(features)


# --- Motion ----------------------------------------------------------------------


## Accelerometer in m/s^2 with gravity, Godot axes (x right, y up, z out of the screen).
## Why the last request_access() was refused, see PlatformBackend.access_problem().
func access_problem() -> String:
	return _backend.access_problem()


func get_acceleration() -> Vector3:
	return _backend.get_acceleration()


## Starts counting steps from zero; steps_changed reports the running total.
func start_step_counter() -> void:
	_backend.start_step_counter()


func stop_step_counter() -> void:
	_backend.stop_step_counter()


# --- Camera ----------------------------------------------------------------------


## Opens the camera. Frames arrive through camera_frame; detections through the signal of the mode.
func start_camera(mode: PlatformBackend.CameraMode, front: bool = false) -> void:
	_backend.start_camera(mode, front)


func stop_camera() -> void:
	_backend.stop_camera()


## Shows the camera at full quality over `rect` in window pixels, above everything under it and below
## the game drawn on top of it (the game must leave the rect transparent). False when not supported:
## then draw camera_frame. An empty rect hides the view.
func show_camera_view(rect: Rect2) -> bool:
	return _backend.show_camera_view(rect)


# --- Audio -----------------------------------------------------------------------


func start_microphone() -> void:
	_backend.start_microphone()


func stop_microphone() -> void:
	_backend.stop_microphone()


func get_microphone_sample_rate() -> float:
	return _backend.get_microphone_sample_rate()


## Mono samples captured since the previous call.
func read_microphone(max_frames: int) -> PackedFloat32Array:
	return _backend.read_microphone(max_frames)


func start_speech(locale: String = "ru-RU") -> void:
	_backend.start_speech(locale)


## Call while a "Speak" button is on screen: in the browser the tap on it starts recognition at once
## (Safari allows it only inside the tap), and start_speech() from its handler takes it over.
func prepare_speech(locale: String = "ru-RU") -> void:
	_backend.prepare_speech(locale)


func stop_speech() -> void:
	_backend.stop_speech()


## Stops every sensor a minigame may have left running.
func stop_all() -> void:
	stop_step_counter()
	stop_camera()
	stop_microphone()
	stop_speech()


# --- Notifications and gallery ---------------------------------------------------


## Replaces every scheduled local notification with `items`:
## [{"id": int, "title": String, "body": String, "delay": seconds from now}]. An empty list cancels
## them all. Ask for Feature.NOTIFICATIONS with request_access() first.
func replace_notifications(items: Array[Dictionary]) -> void:
	_backend.cancel_all_notifications()
	for item: Dictionary in items:
		_backend.schedule_notification(int(item["id"]), str(item["title"]), str(item["body"]), maxi(0, int(item["delay"])))


## Opens the gallery (or a file dialog). Resolves to null when cancelled or unsupported.
func pick_image() -> Image:
	@warning_ignore("redundant_await")
	return await _backend.pick_image()


## "https://host" of the page the web build was opened from (the server runs there too).
## Empty on native platforms.
func get_page_origin() -> String:
	return _backend.page_origin()


# --- Screen ----------------------------------------------------------------------


## Area of the viewport (in viewport coordinates) not covered by notches, rounded corners or system bars.
func get_safe_rect() -> Rect2:
	if _has_safe_rect_override:
		return _safe_rect_override
	var visible_rect: Rect2 = get_viewport().get_visible_rect()
	if not OS.has_feature("mobile"):
		return visible_rect
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return visible_rect
	var to_viewport: Vector2 = visible_rect.size / window_size
	var safe_px: Rect2 = Rect2(DisplayServer.get_display_safe_area())
	var window_position: Vector2 = Vector2(DisplayServer.window_get_position())
	var safe: Rect2 = Rect2((safe_px.position - window_position) * to_viewport, safe_px.size * to_viewport)
	return safe.intersection(visible_rect)


## Used by the desktop device emulator to simulate a phone's safe area.
func set_safe_rect_override(rect: Rect2) -> void:
	_has_safe_rect_override = true
	_safe_rect_override = rect
	_emit_safe_rect()


func clear_safe_rect_override() -> void:
	_has_safe_rect_override = false
	_emit_safe_rect()


func _emit_safe_rect() -> void:
	safe_rect_changed.emit(get_safe_rect())
