class_name ModalPanel
extends CanvasLayer
## Centred paper panel over a dimmer with a title, a close button and a scrolling content column.
## Tapping the dimmer closes it. Subclasses fill `content` in open().

signal closed

const SIDE_MARGIN: float = 10.0
const MAX_SCROLL_HEIGHT: float = 470.0

var content: VBoxContainer
## Inner width available to the content.
var content_width: float = 300.0

var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _scroll: TouchScroll
var _header: HBoxContainer


func _init(title_key: String = "") -> void:
	layer = 25
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dimmer: ColorRect = UiStyle.make_dimmer()
	dimmer.gui_input.connect(func(event: InputEvent) -> void:
		if Minigame.press_position(event) != null:
			close_panel()
	)
	root.add_child(dimmer)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 10))
	center.add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 6)
	column.add_child(_header)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	_header.add_child(titles)
	_title = UiStyle.make_label(TranslationServer.translate(title_key) if not title_key.is_empty() else "", 16)
	titles.add_child(_title)
	_subtitle = UiStyle.make_label("", 9, UiStyle.MUTED)
	_subtitle.visible = false
	titles.add_child(_subtitle)
	var close: Button = UiStyle.make_button("✕", false, 14)
	close.custom_minimum_size = Vector2(34, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_panel)
	_header.add_child(close)
	_scroll = TouchScroll.new()
	column.add_child(_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	_scroll.add_child(content)


func is_open() -> bool:
	return visible


## Sizes the panel to the safe area, clears the content and shows the panel.
func show_panel() -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var width: float = safe.size.x - SIDE_MARGIN * 2.0
	_panel.custom_minimum_size = Vector2(width, 0)
	content_width = width - 24.0
	_scroll.custom_minimum_size = Vector2(0, minf(MAX_SCROLL_HEIGHT, safe.size.y - 130.0))
	clear()
	visible = true


func clear() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()


func close_panel() -> void:
	if visible:
		visible = false
		closed.emit()


func set_title(text: String) -> void:
	_title.text = text


func set_subtitle(text: String) -> void:
	_subtitle.text = text
	_subtitle.visible = not text.is_empty()


## Extra control in the header, left of the close button.
func add_header_control(control: Control) -> void:
	_header.add_child(control)
	_header.move_child(control, _header.get_child_count() - 2)


func make_card(color: Color = UiStyle.SHADE, accent: Color = Color.TRANSPARENT) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(color, 5, 7)
	if accent.a > 0.0:
		style.border_width_left = 3
		style.border_color = accent
	card.add_theme_stylebox_override("panel", style)
	return card


func make_text(text: String, font_size: int, color: Color = UiStyle.INK, width: float = -1.0) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(content_width - 16.0 if width < 0.0 else width, 0)
	return label
