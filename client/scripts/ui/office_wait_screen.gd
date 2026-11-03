class_name OfficeWaitScreen
extends CanvasLayer
## Shown at home when the player sets off to the office outside the office network: the office with
## the tasks opens only after the player comes to the office and joins its Wi-Fi. Checks again by
## itself every POLL_SECONDS and on "Check again"; "Stay home" goes back to the apartment.
## await wait() resolves to true when the office opened, false when the player stays home.

signal _finished(opened: bool)

const BACKGROUND: Color = Color("#141218")
const NEON: Color = Color("#5ce1e6")
const POLL_SECONDS: float = 10.0
const SIDE_MARGIN: float = 16.0

var _screen: ColorRect
var _room: RestRoom
var _stage: Control
var _text: Label
var _status: Label
var _retry: Button
var _waiting: bool = false
var _checking: bool = false
var _poll_left: float = 0.0


func _ready() -> void:
	layer = 45
	_build()
	_screen.visible = false


func wait() -> bool:
	_waiting = true
	_poll_left = POLL_SECONDS
	_status.text = ""
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var scale_factor: int = maxi(1, floori((safe.size.x - SIDE_MARGIN * 2.0) / RestRoom.SIZE.x))
	_room.scale = Vector2(scale_factor, scale_factor)
	_stage.custom_minimum_size = Vector2(RestRoom.SIZE * scale_factor)
	_text.custom_minimum_size = Vector2(safe.size.x - SIDE_MARGIN * 2.0, 0)
	_screen.visible = true
	var opened: bool = await _finished
	_screen.visible = false
	_waiting = false
	return opened


func _process(delta: float) -> void:
	if not _waiting or _checking:
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_check()


func _check() -> void:
	if _checking:
		return
	_checking = true
	_retry.disabled = true
	_status.text = tr("OFFICE_WAIT_CHECKING")
	var opened: bool = await Backend.home.office_open()
	_checking = false
	_retry.disabled = false
	_poll_left = POLL_SECONDS
	if not _waiting:
		return
	if opened:
		_finished.emit(true)
	else:
		_status.text = tr("OFFICE_WAIT_STILL_CLOSED")


func _build() -> void:
	_screen = ColorRect.new()
	_screen.color = BACKGROUND
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	column.add_child(_centered(tr("OFFICE_WAIT_TITLE"), 18, Color.WHITE))
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_stage)
	_room = RestRoom.new()
	_room.no_wifi = true
	_stage.add_child(_room)
	_text = _centered(tr("OFFICE_WAIT_TEXT"), 11, UiStyle.PAPER_EDGE)
	column.add_child(_text)
	_status = _centered("", 10, NEON)
	column.add_child(_status)
	_retry = UiStyle.make_button(tr("NETWORK_RETRY"), true, 13)
	_retry.custom_minimum_size = Vector2(200, 36)
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_retry.pressed.connect(_check)
	column.add_child(_retry)
	var stay: Button = UiStyle.make_button(tr("OFFICE_WAIT_STAY"), false, 12)
	stay.custom_minimum_size = Vector2(200, 32)
	stay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stay.pressed.connect(func() -> void: _finished.emit(false))
	column.add_child(stay)


func _centered(text: String, size: int, color: Color) -> Label:
	var label: Label = UiStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
