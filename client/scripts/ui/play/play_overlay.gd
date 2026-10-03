class_name PlayOverlay
extends CanvasLayer
## Screens of game access, above every scene: the warning with a countdown to leave the game (it
## can shrink to a pill at the top), the quiet notice that the rest starts after the minigame, the
## rest screen with the countdown, the screen of a game locked until tomorrow and the screen asking
## to connect to the office Wi-Fi. PlayTime decides what is shown; this class only draws it.

signal rest_now_pressed
signal resume_pressed
signal retry_pressed

## Above every panel (ChoicePrompt is 45), below the CRT effect (50) so the screens get it too.
const LAYER: int = 48
const BACKGROUND: Color = Color("#120a1c")
const NEON: Color = RestRoom.NEON
const SIDE_MARGIN: float = 16.0

var _warning: Control
var _warning_text: Label
var _warning_timer: Label
var _pill: Button
var _screen: Control
var _room: RestRoom
var _stage: Control
var _screen_title: Label
var _screen_text: Label
var _screen_timer: Label
var _resume: Button
var _retry: Button
var _notice: PanelContainer


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_screen()
	_build_warning()
	_build_pill()
	_build_notice()


func is_screen_open() -> bool:
	return _screen.visible


## Fills the warning text without showing it.
func prepare_warning(status: BackendModels.PlayStatus) -> void:
	_warning_text.text = (
		tr("PLAY_WARNING_TEXT")
		% [TimeText.minutes(status.limit_minutes, true), TimeText.minutes(status.rest_minutes)]
	)


func show_warning_again() -> void:
	_warning.visible = true
	_pill.visible = false


## A quiet line at the top while a minigame goes on: the rest starts once it ends.
func show_deferred_notice() -> void:
	_notice.visible = true


func hide_deferred_notice() -> void:
	_notice.visible = false


## The player read the warning and keeps playing for now: only the countdown stays on screen.
func collapse_warning() -> void:
	_warning.visible = false
	_pill.visible = true


func hide_warning() -> void:
	_warning.visible = false
	_pill.visible = false


func set_grace_left(seconds: int) -> void:
	_warning_timer.text = TimeText.countdown(seconds)
	_pill.text = tr("PLAY_PILL") % TimeText.countdown(seconds)


func show_rest(seconds: int) -> void:
	hide_warning()
	_room.asleep = false
	_room.no_wifi = false
	_screen_title.text = tr("PLAY_REST_TITLE")
	_screen_text.text = tr("PLAY_REST_TEXT")
	_screen_timer.visible = true
	_resume.visible = false
	_retry.visible = false
	set_rest_left(seconds)
	_open_screen()


func set_rest_left(seconds: int) -> void:
	_screen_timer.text = TimeText.countdown(seconds)
	_room.clock_text = TimeText.countdown(seconds)


## The rest is over: the clock shows zero and the player may go back.
func show_rest_done() -> void:
	set_rest_left(0)
	_screen_text.text = tr("PLAY_REST_DONE")
	_screen_timer.visible = false
	_resume.visible = true


func show_blocked() -> void:
	hide_warning()
	_room.asleep = true
	_room.no_wifi = false
	_screen_title.text = tr("PLAY_BLOCKED_TITLE")
	_screen_text.text = tr("PLAY_BLOCKED_TEXT")
	_screen_timer.visible = false
	_resume.visible = false
	_retry.visible = false
	_open_screen()


## Outside the office network: the game waits for the office Wi-Fi.
func show_network() -> void:
	hide_warning()
	_room.asleep = false
	_room.no_wifi = true
	_screen_title.text = tr("NETWORK_TITLE")
	_screen_text.text = tr("NETWORK_TEXT")
	_screen_timer.visible = false
	_resume.visible = false
	_retry.visible = true
	_open_screen()


func hide_screen() -> void:
	_screen.visible = false
	_room.no_wifi = false


func _open_screen() -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var scale_factor: int = maxi(1, floori((safe.size.x - SIDE_MARGIN * 2.0) / RestRoom.SIZE.x))
	_room.scale = Vector2(scale_factor, scale_factor)
	_stage.custom_minimum_size = Vector2(RestRoom.SIZE * scale_factor)
	_screen_text.custom_minimum_size = Vector2(safe.size.x - SIDE_MARGIN * 2.0, 0)
	_screen.visible = true


func _build_screen() -> void:
	_screen = ColorRect.new()
	(_screen as ColorRect).color = BACKGROUND
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.visible = false
	add_child(_screen)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	_screen_title = _centered_label("", 18, Color.WHITE)
	column.add_child(_screen_title)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_stage)
	_room = RestRoom.new()
	_stage.add_child(_room)
	_screen_text = _centered_label("", 11, UiStyle.PAPER_EDGE)
	column.add_child(_screen_text)
	_screen_timer = _centered_label("", 28, NEON)
	column.add_child(_screen_timer)
	_resume = UiStyle.make_button(tr("PLAY_RESUME"), true, 13)
	_resume.custom_minimum_size = Vector2(200, 36)
	_resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume.visible = false
	_resume.pressed.connect(func() -> void: resume_pressed.emit())
	column.add_child(_resume)
	_retry = UiStyle.make_button(tr("NETWORK_RETRY"), true, 13)
	_retry.custom_minimum_size = Vector2(200, 36)
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_retry.visible = false
	_retry.pressed.connect(func() -> void: retry_pressed.emit())
	column.add_child(_retry)


func _build_warning() -> void:
	_warning = Control.new()
	_warning.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.visible = false
	add_child(_warning)
	_warning.add_child(UiStyle.make_dimmer())
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 12))
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(UiStyle.make_label(tr("PLAY_WARNING_TITLE"), 16, UiStyle.RED))
	_warning_text = UiStyle.make_label("", 11)
	_warning_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_text.custom_minimum_size = Vector2(276, 0)
	column.add_child(_warning_text)
	_warning_timer = _centered_label("", 26, UiStyle.RED)
	column.add_child(_warning_timer)
	var hint: Label = _centered_label(tr("PLAY_WARNING_HINT"), 9, UiStyle.MUTED)
	hint.custom_minimum_size = Vector2(276, 0)
	column.add_child(hint)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	var rest: Button = UiStyle.make_button(tr("PLAY_REST_NOW"), true, 12)
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.custom_minimum_size = Vector2(0, 32)
	rest.pressed.connect(func() -> void: rest_now_pressed.emit())
	buttons.add_child(rest)
	var later: Button = UiStyle.make_button(tr("PLAY_WARNING_OK"), false, 12)
	later.custom_minimum_size = Vector2(96, 32)
	later.pressed.connect(collapse_warning)
	buttons.add_child(later)


func _build_pill() -> void:
	_pill = UiStyle.make_button("", true, 10)
	_pill.visible = false
	_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pill.position.y = 44
	_pill.pressed.connect(
		func() -> void:
			_warning.visible = true
			_pill.visible = false
	)
	add_child(_pill)


func _build_notice() -> void:
	_notice = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.INK, 6, 6)
	style.border_color = UiStyle.GOLD
	style.border_width_bottom = 2
	_notice.add_theme_stylebox_override("panel", style)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.position.y = 40
	var label: Label = _centered_label(tr("PLAY_DEFERRED_NOTICE"), 9, Color.WHITE)
	label.custom_minimum_size = Vector2(300, 0)
	_notice.add_child(label)
	add_child(_notice)


func _centered_label(text: String, size: int, color: Color) -> Label:
	var label: Label = UiStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
