class_name ArTracker
extends RefCounted
## The phone in the room for the AR minigames. Where the platform tracks the world (SLAM: 8th Wall in
## the phone browser) the camera has six degrees of freedom and taps hit real surfaces: the floor, a
## table, a wall. Otherwise, or when the tracking fails, the back camera opens as usual and only the
## phone's turns and tilts are tracked (DevicePose), with the floor at y = 0 and no surface hits.
## Room points are metres: x to the right, y up from the floor, z forward from the start.

## The tracking engine is given this long (seconds) to load and start before the fallback opens.
const START_TIMEOUT: float = 45.0
const FALLBACK_STATUSES: Array[String] = ["unsupported", "failed"]
## The notice the engine's license asks for wherever it is used.
const ENGINE_LICENSE_URL: String = "https://github.com/8thwall/engine/blob/main/LICENSE"
const CREDIT_FONT_SIZE: int = 8

var _pose: DevicePose
var _eye_height: float
## The desktop sensor emulator reports a phone lying flat, not one held up: there only its gyroscope
## (the arrow keys) turns the view.
var _use_gravity: bool = OS.has_feature("web")
var _is_slam: bool = false
var _started_for: float = 0.0
var _world: SensorModels.WorldPose


## Without world tracking the phone is held `eye_height` metres high, tilted `degrees_down`.
func _init(eye_height: float, degrees_down: float) -> void:
	_eye_height = eye_height
	_pose = DevicePose.new(degrees_down)


## Opens the camera for a game view `view_size` big.
func start(view_size: Vector2) -> void:
	_is_slam = PlatformServices.has_feature(PlatformBackend.Feature.WORLD_TRACKING)
	if _is_slam:
		PlatformServices.start_world_tracking(view_size)
	else:
		PlatformServices.start_camera(PlatformBackend.CameraMode.PREVIEW, false)


func update(delta: float) -> void:
	_pose.update(delta, PlatformServices.get_rotation_rate(), PlatformServices.get_acceleration(), _use_gravity)
	if not _is_slam:
		return
	_started_for += delta
	var status: String = PlatformServices.get_world_tracking_status()
	var is_stuck: bool = _started_for > START_TIMEOUT and status in ["loading", "off"]
	if status in FALLBACK_STATUSES or is_stuck:
		_fall_back()
		return
	_world = PlatformServices.get_world_pose() if status in ["limited", "normal"] else null


## Whether the camera moves with six degrees of freedom and taps can hit real surfaces.
func is_tracking_world() -> bool:
	return _is_slam and _world != null


## Still loading or starting the world tracking: surfaces are not known yet.
func is_starting() -> bool:
	return _is_slam and _world == null


## The camera as the phone is held now, over the camera picture `frame`.
func camera(frame: Rect2) -> ArCamera:
	if not is_tracking_world():
		return ArCamera.new(frame, _pose.basis, Vector3(0.0, _eye_height, 0.0))
	var position: Vector3 = _world.position
	var degrees: float = _world.field_of_view if _world.field_of_view > 1.0 else ArCamera.FIELD_OF_VIEW
	return ArCamera.new(frame, Basis(_world.rotation), Vector3(position.x, position.y, -position.z), degrees)


## The real surface point (room metres) under a point of the game view `view` big, or null when the
## world is not tracked or nothing was found there.
func hit(point: Vector2, view: Vector2) -> Variant:
	if not is_tracking_world():
		return null
	var found: Variant = PlatformServices.world_hit_test(point / view)
	if found == null:
		return null
	var surface: Vector3 = found as Vector3
	return Vector3(surface.x, surface.y, -surface.z)


## Whether the world tracking engine runs (or is starting): its notice must show then.
func uses_engine() -> bool:
	return _is_slam


## A small link at the bottom of `rect` (the camera view in `parent`) that names the tracking engine
## and opens its license; shown only while the engine is used.
func add_credit(parent: Control, rect: Rect2) -> LinkButton:
	var credit: LinkButton = LinkButton.new()
	credit.text = parent.tr("AR_ENGINE_CREDIT")
	credit.uri = ENGINE_LICENSE_URL
	credit.add_theme_font_size_override("font_size", CREDIT_FONT_SIZE)
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	credit.position = rect.position + Vector2(6, rect.size.y - CREDIT_FONT_SIZE - 8)
	credit.visible = _is_slam
	parent.add_child(credit)
	return credit


func _fall_back() -> void:
	_is_slam = false
	_world = null
	PlatformServices.stop_world_tracking()
	PlatformServices.start_camera(PlatformBackend.CameraMode.PREVIEW, false)
