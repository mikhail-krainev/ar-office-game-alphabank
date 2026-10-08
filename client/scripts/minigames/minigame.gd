class_name Minigame
extends Control
## Base class for task minigames. Subclasses call finish() exactly once.
## Physical minigames use phone sensors through PlatformServices; the screen-only games from the
## first prototype remain as fallbacks for devices without the needed sensors.
## Sensors started by a game are stopped automatically when the game closes.

signal finished(success: bool)
signal _qr_scanned(payload: QrPayload)

## Portrait play area.
const AREA_SIZE: Vector2 = Vector2(320, 340)
const STATUS_Y: float = AREA_SIZE.y - 22.0
const CAMERA_RECT: Rect2 = Rect2(40, 40, 240, 180)
const QR_WRONG_COOLDOWN: float = 1.5

## Sensors each physical minigame needs. Games not listed work everywhere.
const REQUIRED_FEATURES: Dictionary[String, Array] = {
	"presence_qr": [PlatformBackend.Feature.QR_SCAN],
	"stairs": [PlatformBackend.Feature.PEDOMETER],
	"find_object": [PlatformBackend.Feature.OBJECT_RECOGNITION],
	"squats": [PlatformBackend.Feature.POSE_DETECTION],
	"tongue_twister": [PlatformBackend.Feature.SPEECH_RECOGNITION],
	"selfie": [PlatformBackend.Feature.FACE_DETECTION],
	"meet_colleague": [PlatformBackend.Feature.QR_SCAN],
	"colleague_bingo": [PlatformBackend.Feature.QR_SCAN],
	"two_truths": [PlatformBackend.Feature.QR_SCAN],
}

var task: BackendModels.TaskInfo
## The host shows "DONE" / "FAILED" before closing.
var shows_result: bool = true
## Evidence and score sent to the server with the result. The server decides what it is worth.
var proof: Dictionary = {}
## Data the server prepared for this run, e.g. {"colleague": BackendModels.Colleague}.
var context: Dictionary = {}

var _is_done: bool = false
var _qr_kind: QrPayload.Kind = QrPayload.Kind.UNKNOWN
var _qr_cooldown: float = 0.0
var _qr_overlay: Control
var _qr_message: Label


func _init() -> void:
	custom_minimum_size = AREA_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _exit_tree() -> void:
	PlatformServices.stop_all()


func finish(success: bool) -> void:
	if _is_done:
		return
	_is_done = true
	PlatformServices.stop_all()
	finished.emit(success)


func is_done() -> bool:
	return _is_done


## 0..1 performance; the server turns it into a capped reward bonus.
func set_score(value: float) -> void:
	proof["score"] = clampf(value, 0.0, 1.0)


## Hint at the top of the play area, wrapped to its width.
func add_hint(text: String) -> Label:
	var hint: Label = UiStyle.make_label(text, 11, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(8, 2)
	hint.size = Vector2(AREA_SIZE.x - 16.0, 30)
	add_child(hint)
	return hint


func add_status() -> Label:
	var status: Label = UiStyle.make_label("", 12)
	status.position = Vector2(8, STATUS_Y)
	add_child(status)
	return status


func add_camera_view(rect: Rect2 = CAMERA_RECT) -> CameraView:
	var view: CameraView = CameraView.new()
	view.position = rect.position
	view.size = rect.size
	add_child(view)
	return view


## Big centred label for counters and prompts.
func add_big_label(y: float, font_size: int = 22, color: Color = UiStyle.INK) -> Label:
	var label: Label = UiStyle.make_label("", font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector2(8, y)
	label.size = Vector2(AREA_SIZE.x - 16.0, font_size + 8)
	add_child(label)
	return label


## Opens the camera over the play area until a QR code of `kind` is seen (UNKNOWN = any game code).
## Other codes show a hint.
func scan_qr(prompt: String, kind: QrPayload.Kind) -> QrPayload:
	_qr_kind = kind
	_qr_overlay = Control.new()
	_qr_overlay.size = AREA_SIZE
	_qr_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_qr_overlay)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = UiStyle.PAPER
	backdrop.size = AREA_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qr_overlay.add_child(backdrop)
	var title: Label = UiStyle.make_label(prompt, 12)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(8, 4)
	title.size = Vector2(AREA_SIZE.x - 16.0, 32)
	_qr_overlay.add_child(title)
	var view: CameraView = CameraView.new()
	view.position = CAMERA_RECT.position + Vector2(0, 10)
	view.size = CAMERA_RECT.size
	view.overlay = _draw_qr_frame
	_qr_overlay.add_child(view)
	_qr_message = UiStyle.make_label("", 11, UiStyle.RED)
	_qr_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qr_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qr_message.position = Vector2(8, CAMERA_RECT.end.y + 18)
	_qr_message.size = Vector2(AREA_SIZE.x - 16.0, 40)
	_qr_overlay.add_child(_qr_message)
	PlatformServices.qr_detected.connect(_on_qr_detected)
	PlatformServices.start_camera(PlatformBackend.CameraMode.QR, false)
	var payload: QrPayload = await _qr_scanned
	PlatformServices.qr_detected.disconnect(_on_qr_detected)
	PlatformServices.stop_camera()
	_qr_overlay.queue_free()
	_qr_overlay = null
	return payload


## Scans a colleague's "My QR" and asks the server who it is. The result carries the error key when
## the code is the player's own ("own_code"), expired or unknown; colleague_error_text() words it.
func scan_colleague(prompt: String) -> BackendModels.ColleagueResult:
	var payload: QrPayload = await scan_qr(prompt, QrPayload.Kind.USER)
	if QrPayload.user_id_of(payload.value) == Backend.get_user_id():
		var own: BackendModels.ColleagueResult = BackendModels.ColleagueResult.new()
		own.error = "own_code"
		return own
	return await Backend.social.lookup_colleague(payload.value)


static func colleague_error_text(result: BackendModels.ColleagueResult) -> String:
	if result.error == "own_code":
		return TranslationServer.translate("MG_MEET_OWN_CODE")
	return TranslationServer.translate("ERROR_" + result.error.to_upper())


func _on_qr_detected(text: String) -> void:
	if _qr_overlay == null or _qr_cooldown > 0.0:
		return
	var payload: QrPayload = QrPayload.parse(text)
	if payload.kind == _qr_kind or (_qr_kind == QrPayload.Kind.UNKNOWN and payload.is_valid()):
		_qr_scanned.emit(payload)
		return
	_qr_cooldown = QR_WRONG_COOLDOWN
	_qr_message.text = tr("QR_WRONG_CODE")


func _process(delta: float) -> void:
	_qr_cooldown = maxf(0.0, _qr_cooldown - delta)


static func _draw_qr_frame(view: CameraView, _image_rect: Rect2) -> void:
	var side: float = minf(view.size.x, view.size.y) * 0.7
	var square: Rect2 = Rect2((view.size - Vector2(side, side)) / 2.0, Vector2(side, side))
	var corner: float = side * 0.2
	for x: float in [square.position.x, square.end.x]:
		for y: float in [square.position.y, square.end.y]:
			var dx: float = corner if x == square.position.x else -corner
			var dy: float = corner if y == square.position.y else -corner
			view.draw_line(Vector2(x, y), Vector2(x + dx, y), UiStyle.RED, 3.0)
			view.draw_line(Vector2(x, y), Vector2(x, y + dy), UiStyle.RED, 3.0)


static func required_features(kind: String) -> Array[PlatformBackend.Feature]:
	var result: Array[PlatformBackend.Feature] = []
	for feature: Variant in REQUIRED_FEATURES.get(kind, []):
		result.append(feature as PlatformBackend.Feature)
	return result


## Position of a primary press inside this control, or null when event is not a press.
static func press_position(event: InputEvent) -> Variant:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		return mouse.position
	return null


static func is_release(event: InputEvent) -> bool:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	return mouse != null and not mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT


static func create(kind: String) -> Minigame:
	match kind:
		"presence_qr":
			return PresenceQrMinigame.new()
		"stairs":
			return StairsMinigame.new()
		"find_object":
			return FindObjectMinigame.new()
		"squats":
			return SquatsMinigame.new()
		"tongue_twister":
			return TongueTwisterMinigame.new()
		"selfie":
			return SelfieMinigame.new()
		"meet_colleague":
			return MeetColleagueMinigame.new()
		"colleague_bingo":
			return ColleagueBingoMinigame.new()
		"two_truths":
			return TwoTruthsMinigame.new()
		# Screen-only fallbacks from the first prototype.
		"coffee":
			return CoffeeMinigame.new()
		"bubble_wrap":
			return BubbleWrapMinigame.new()
		"paper_sort":
			return PaperSortMinigame.new()
		"alfa_red":
			return AlfaRedMinigame.new()
		_:
			return CheckInMinigame.new()
