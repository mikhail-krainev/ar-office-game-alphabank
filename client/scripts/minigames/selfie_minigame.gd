class_name SelfieMinigame
extends Minigame
## "Photo with a colleague": the server picks a colleague who checked in at the office today. The two
## find each other and look into the front camera together; face detection only counts the faces
## (at least two) and identifies nobody. No photo is stored or sent. The server then asks the
## colleague in their own game to confirm the photo, and the reward waits for that answer. AR: every
## face gets neon shades, a smiling one also a crown with sparks (scripts/ar), drawn on the phone only.
## Needs context["colleague"] (BackendModels.Colleague) from Backend.social.assign_colleague().

const MIN_FACES: int = 2
const SMILE_THRESHOLD: float = 0.7
const HOLD_SECONDS: float = 1.0
const DEFAULT_TIME_LIMIT: float = 180.0

var _faces: Array[SensorModels.Face] = []
var _hold: float = 0.0
var _time_left: float = DEFAULT_TIME_LIMIT
var _camera_on: bool = false
var _captured: bool = false
var _flash: float = 0.0
## Seconds since the camera started, for the AR stickers' motion.
var _ar_time: float = 0.0

var _intro: Control
var _view: CameraView
var _status: Label


func _ready() -> void:
	if task != null:
		_time_left = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_status = add_status()
	_show_partner()


func _exit_tree() -> void:
	super()
	if PlatformServices.faces_detected.is_connected(_on_faces):
		PlatformServices.faces_detected.disconnect(_on_faces)


## First screen: whom to find, and a button for when they are together.
func _show_partner() -> void:
	var colleague: BackendModels.Colleague = context.get("colleague")
	_intro = VBoxContainer.new()
	_intro.position = Vector2(8, 4)
	_intro.size = Vector2(AREA_SIZE.x - 16.0, 0)
	(_intro as VBoxContainer).add_theme_constant_override("separation", 8)
	add_child(_intro)
	var hint: Label = UiStyle.make_label(tr("MG_PHOTO_FIND"), 11, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 0)
	_intro.add_child(hint)
	if colleague != null:
		_intro.add_child(ColleagueCard.new(colleague, AREA_SIZE.x - 16.0))
	var note: Label = UiStyle.make_label(tr("MG_PHOTO_CONFIRM_NOTE"), 9, UiStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 0)
	_intro.add_child(note)
	var start: Button = UiStyle.make_button(tr("MG_PHOTO_START"), true, 12)
	start.custom_minimum_size = Vector2(0, 34)
	start.pressed.connect(_start_camera)
	_intro.add_child(start)


func _start_camera() -> void:
	_intro.queue_free()
	_camera_on = true
	add_hint(tr("MG_SELFIE_HINT"))
	_view = add_camera_view()
	_view.overlay = _draw_faces
	PlatformServices.faces_detected.connect(_on_faces)
	PlatformServices.start_camera(PlatformBackend.CameraMode.FACES, true)


func _on_faces(faces: Array[SensorModels.Face]) -> void:
	_faces = faces


func _smiling_count() -> int:
	return _faces.filter(func(face: SensorModels.Face) -> bool: return face.smiling >= SMILE_THRESHOLD).size()


func _process(delta: float) -> void:
	super(delta)
	_flash = maxf(0.0, _flash - delta * 1.5)
	_ar_time += delta
	if is_done():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		finish(false)
		return
	if not _camera_on:
		_status.text = tr("MG_TIME_LEFT") % _clock(_time_left)
		return
	if _captured:
		return
	_hold = _hold + delta if _faces.size() >= MIN_FACES else 0.0
	_status.text = "%s   %s" % [tr("MG_PHOTO_FACES") % [_faces.size(), MIN_FACES], tr("MG_TIME_LEFT") % _clock(_time_left)]
	if _hold >= HOLD_SECONDS:
		_capture()
	_view.queue_redraw()


static func _clock(seconds: float) -> String:
	var total: int = ceili(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


func _capture() -> void:
	_captured = true
	_flash = 1.0
	var colleague: BackendModels.Colleague = context.get("colleague")
	proof["faces"] = _faces.size()
	proof["partner_id"] = colleague.user_id if colleague != null else ""
	# Smiles only raise the reward bonus; two faces are enough to count.
	set_score(float(_smiling_count()) / maxf(1.0, _faces.size()))
	PlatformServices.stop_camera()
	await get_tree().create_timer(0.6).timeout
	finish(true)


func _draw_faces(view: CameraView, image_rect: Rect2) -> void:
	for face: SensorModels.Face in _faces:
		var anchor: ArAnchor = ArAnchor.of_face(face, image_rect)
		var smiling: bool = face.smiling >= SMILE_THRESHOLD
		ArPainter.shades(view, anchor, UiStyle.RED if smiling else ArPainter.NEON_CYAN)
		if smiling:
			ArPainter.crown(view, anchor, _ar_time)
			ArPainter.sparks(view, anchor.top, anchor.eye_span() * 1.1, _ar_time, UiStyle.GOLD)
	if _flash > 0.0:
		view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(1, 1, 1, _flash))
