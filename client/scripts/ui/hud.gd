class_name Hud
extends CanvasLayer
## Portrait HUD inside the safe area: brand and room at the top, coin balance top-right,
## large action buttons at the bottom within thumb reach, short messages, and a hint under the brand
## that the player closes with a cross (it stays closed for the session).

const RED: Color = Color("#ef3124")
const INK: Color = Color("#1d1d1f")
const COIN_SHEET: Texture2D = preload("res://assets/ui/alfa_coin.png")
const MARK: Texture2D = preload("res://assets/brand/alfa_mark_small.png")
const GLITCH_DURATION: float = 0.35
const MESSAGE_DURATION: float = 1.6
const MESSAGE_FADE: float = 0.3
const MESSAGE_FONT_SIZE: int = 13
const LAYOUT_SETTLE_FRAMES: int = 2
const MARGIN: float = 8.0
const ACTION_HEIGHT: float = 38.0
const MAX_FLYING_COINS: int = 12
## Corner buttons sit this far below the top margin, under the coin counter.
const CORNER_TOP: float = 32.0
## The hint sits under the brand bar and leaves the right side to the corner panel (TaskList).
const HINT_TOP: float = 46.0
const HINT_RIGHT_GAP: float = 158.0

## Hints the player closed this session; they do not come back on the next scene.
static var _closed_hints: Dictionary[String, bool] = {}

var _glitch_left: float = 0.0
var _message_left: float = 0.0
var _message_hidden_frames: int = 0

var _root: Control
var _brand: Label
var _room_label: Label
var _coins: CoinCounter
var _corner: HBoxContainer
var _actions: HBoxContainer
var _hint_panel: PanelContainer
var _hint: Label
var _message_panel: PanelContainer
var _message: Label


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top_bar()
	_build_bottom()
	_message_panel = PanelContainer.new()
	_message_panel.add_theme_stylebox_override("panel", UiStyle.panel(RED, 8, 6))
	_message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_panel.set_anchors_preset(Control.PRESET_CENTER)
	_message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message_panel.modulate.a = 0.0
	_root.add_child(_message_panel)
	_message = UiStyle.make_label("", MESSAGE_FONT_SIZE, Color.WHITE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_panel.add_child(_message)
	PlatformServices.safe_rect_changed.connect(_apply_safe_rect)
	_apply_safe_rect(PlatformServices.get_safe_rect())


func set_title(text: String) -> void:
	_brand.text = text


func set_hint(text: String) -> void:
	_hint.text = text
	_hint_panel.visible = not text.is_empty() and not _closed_hints.has(text)


## Small buttons in the top-right corner under the balance (inbox, profile).
## Panel in the top-right corner under the corner buttons, e.g. today's tasks.
func add_corner_panel(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	control.offset_left = -MARGIN
	control.offset_right = -MARGIN
	control.offset_top = MARGIN + CORNER_TOP + PlayerCorner.BUTTON_SIDE + 6.0
	_root.add_child(control)


func add_corner(control: Control) -> void:
	_corner.add_child(control)


func add_action(text: String, primary: bool) -> Button:
	var button: Button = UiStyle.make_button(text, primary, 14)
	button.custom_minimum_size = Vector2(0, ACTION_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(button)
	_actions.visible = true
	return button


## Full-width button above the action row, e.g. "Go home"; `pulse` makes it breathe to draw the eye.
func add_wide_action(text: String, pulse: bool = true) -> Button:
	var button: Button = UiStyle.make_button(text, true, 14)
	button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bottom: float = -MARGIN * 2.0 - ACTION_HEIGHT if _actions.visible else -MARGIN
	button.offset_left = MARGIN
	button.offset_right = -MARGIN
	button.offset_bottom = bottom
	button.offset_top = bottom - ACTION_HEIGHT
	_root.add_child(button)
	if pulse:
		var breathing: Tween = button.create_tween().set_loops()
		breathing.tween_property(button, "modulate", Color(1.2, 1.2, 1.2), 0.6)
		breathing.tween_property(button, "modulate", Color.WHITE, 0.6)
	return button


func show_room(room_name: String) -> void:
	_room_label.text = room_name.to_upper()
	_glitch_left = GLITCH_DURATION


func hide_hint() -> void:
	_hint_panel.visible = false


func _close_hint() -> void:
	_closed_hints[_hint.text] = true
	hide_hint()


func flash_message(text: String) -> void:
	_message.text = text
	# Long messages wrap inside the safe area.
	var text_width: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MESSAGE_FONT_SIZE).x
	var width: float = minf(ceilf(text_width) + 2.0, _root.size.x - MARGIN * 4.0)
	_message.custom_minimum_size = Vector2(width, 0)
	_message.size = Vector2(width, 0)
	_fit_message()
	_message_hidden_frames = LAYOUT_SETTLE_FRAMES
	_message_left = MESSAGE_DURATION


## Coins fly from a screen position into the balance counter.
func play_reward(from_screen: Vector2, amount: int) -> void:
	var count: int = clampi(amount / 5, 3, MAX_FLYING_COINS)
	for i: int in count:
		var coin: TextureRect = TextureRect.new()
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = COIN_SHEET
		atlas.region = Rect2(0, 0, 16, 16)
		coin.texture = atlas
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.position = from_screen - Vector2(8, 8)
		add_child(coin)
		var scatter: Vector2 = from_screen + Vector2(randf_range(-40, 40), randf_range(-40, 10)) - Vector2(8, 8)
		var tween: Tween = create_tween()
		tween.tween_interval(i * 0.04)
		tween.tween_property(coin, "position", scatter, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "position", _coins.get_coin_center() - Vector2(8, 8), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(coin.queue_free)


func _build_top_bar() -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.PAPER, 0.96), 4, 5))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(MARGIN, MARGIN)
	_root.add_child(bar)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	var logo: TextureRect = TextureRect.new()
	logo.texture = MARK
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(logo)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_brand = UiStyle.make_label("", 10, RED)
	text.add_child(_brand)
	_room_label = UiStyle.make_label("", 14, INK)
	_room_label.label_settings.shadow_color = Color(RED, 0.7)
	text.add_child(_room_label)

	_coins = CoinCounter.new()
	_coins.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_coins.offset_left = -MARGIN
	_coins.offset_right = -MARGIN
	_coins.offset_top = MARGIN
	_root.add_child(_coins)

	_corner = HBoxContainer.new()
	_corner.add_theme_constant_override("separation", 6)
	_corner.alignment = BoxContainer.ALIGNMENT_END
	_corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner.offset_left = -MARGIN
	_corner.offset_right = -MARGIN
	_corner.offset_top = MARGIN + CORNER_TOP
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_corner)


func _build_bottom() -> void:
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_actions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_actions.offset_left = MARGIN
	_actions.offset_right = -MARGIN
	_actions.offset_top = -MARGIN - ACTION_HEIGHT
	_actions.offset_bottom = -MARGIN
	_actions.visible = false
	_root.add_child(_actions)

	_hint_panel = PanelContainer.new()
	_hint_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.PAPER, 0.92), 6, 5))
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.position = Vector2(MARGIN, MARGIN + HINT_TOP)
	_hint_panel.visible = false
	_root.add_child(_hint_panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(row)
	_hint = UiStyle.make_label("", 10, INK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hint)
	var close: Button = UiStyle.make_button("✕", false, 10)
	close.custom_minimum_size = Vector2(22, 22)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_close_hint)
	row.add_child(close)


func _process(delta: float) -> void:
	if _glitch_left > 0.0:
		_glitch_left -= delta
		var settings: LabelSettings = _room_label.label_settings
		settings.font_color = RED if randi() % 2 == 0 else INK
		settings.shadow_offset = Vector2(randi_range(-2, 2), 0)
		if _glitch_left <= 0.0:
			settings.font_color = INK
			settings.shadow_offset = Vector2.ZERO
	if _message_left > 0.0:
		_message_left -= delta
		_fit_message()
		# An autowrapped label reports its real height only after a layout pass, so the panel stays
		# hidden for the first frames instead of flashing at the wrong size.
		_message_hidden_frames = maxi(0, _message_hidden_frames - 1)
		var alpha: float = clampf(_message_left / MESSAGE_FADE, 0.0, 1.0)
		_message_panel.modulate.a = 0.0 if _message_hidden_frames > 0 else alpha


func _fit_message() -> void:
	_message_panel.reset_size()
	_message_panel.position = ((_root.size - _message_panel.size) / 2.0).round()


func _apply_safe_rect(rect: Rect2) -> void:
	_root.position = rect.position
	_root.size = rect.size
	var width: float = maxf(120.0, rect.size.x - MARGIN - HINT_RIGHT_GAP)
	# An autowrapped label needs a width; the rest of the row is the cross and the panel padding.
	_hint.custom_minimum_size = Vector2(width - 36.0, 0)
	_hint_panel.custom_minimum_size = Vector2(width, 0)
	_hint_panel.reset_size()
