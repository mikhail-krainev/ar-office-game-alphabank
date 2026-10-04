class_name WardrobePanel
extends CanvasLayer
## Full-screen wardrobe: animated preview, slot tabs, item grid with painted thumbnails and colours.
## The outfit is validated and stored by Backend; "Done" saves, the close button discards changes.
## The preview faces the player and turns only with the arrow buttons.

signal closed

const MARGIN: float = 8.0
const COLUMNS: int = 4
const FRAME_TIME: float = 0.14
const PREVIEW_SCALE: int = 2
## Room kept for the item list's vertical scroll bar, so the grid never pushes the panel wider.
const SCROLL_BAR_ALLOWANCE: float = 14.0
## Directions the arrow buttons cycle through, starting from the front.
const PREVIEW_ROWS: Array[int] = [CharacterPainter.Dir.DOWN, CharacterPainter.Dir.SIDE, CharacterPainter.Dir.UP]
const PALETTES: Dictionary[String, Array] = {
	"hair": ["#1e1a18", "#4a2f22", "#7a3322", "#b5652a", "#e3b565", "#f2e6c8", "#9a9a9a", "#ef3124", "#3a7bd5", "#d6336c"],
	"top": ["#ef3124", "#fbfaf8", "#1d1d22", "#3a64a8", "#4c9e72", "#f2c230", "#7d8089", "#7a1f3a", "#e07a3f", "#5ac8d8"],
	"bottom": ["#2c3a55", "#1f1f24", "#3b3b44", "#c7b08c", "#5b8fd6", "#7a1f3a", "#e8e0d0", "#4f7a4a"],
	"shoes": ["#2a2020", "#fbfaf8", "#ef3124", "#3a7bd5", "#6b3a2a", "#f2c230", "#1d1d22"],
}

var _state: BackendModels.WardrobeState
var _outfit: Dictionary = {}
var _slot: String = "top"
var _busy: bool = false

var _panel: PanelContainer
## Panel size fixed at open() from the safe area; item cells are sized from it, never from the
## live panel size (which would grow with its content on every tab switch).
var _panel_size: Vector2 = Vector2.ZERO
var _preview: TextureRect
var _preview_atlas: AtlasTexture
var _preview_row_index: int = 0
var _preview_column: int = 2
var _frame_left: float = 0.0
var _slot_buttons: Dictionary[String, Button] = {}
var _grid: GridContainer
var _colors: HFlowContainer
var _toast: Label
var _toast_left: float = 0.0
var _thumbnails: Dictionary[String, ImageTexture] = {}


func _ready() -> void:
	layer = 25
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.add_child(UiStyle.make_dimmer())
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 8))
	root.add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = UiStyle.make_label(tr("WARDROBE_TITLE"), 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = UiStyle.make_button("✕", false, 14)
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(_close)
	header.add_child(close)

	column.add_child(_build_preview())

	var tabs: HFlowContainer = HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	column.add_child(tabs)
	for slot: String in Outfit.SLOTS:
		var tab: Button = UiStyle.make_button(tr("WARDROBE_SLOT_" + slot.to_upper()), false, 10)
		tab.custom_minimum_size = Vector2(0, 26)
		tab.pressed.connect(_select_slot.bind(slot))
		tabs.add_child(tab)
		_slot_buttons[slot] = tab

	_colors = HFlowContainer.new()
	_colors.add_theme_constant_override("h_separation", 4)
	_colors.add_theme_constant_override("v_separation", 4)
	column.add_child(_colors)

	var scroll: TouchScroll = TouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)

	_toast = UiStyle.make_label("", 11, UiStyle.RED)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_toast)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var random: Button = UiStyle.make_button(tr("WARDROBE_RANDOM"), false, 12)
	random.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random.custom_minimum_size = Vector2(0, 36)
	random.pressed.connect(_randomize)
	footer.add_child(random)
	var done: Button = UiStyle.make_button(tr("WARDROBE_DONE"), true, 13)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.custom_minimum_size = Vector2(0, 36)
	done.pressed.connect(_save_and_close)
	footer.add_child(done)


func is_open() -> bool:
	return visible


func open() -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	_panel_size = safe.size - Vector2(MARGIN, MARGIN) * 2.0
	_panel.position = safe.position + Vector2(MARGIN, MARGIN)
	_panel.custom_minimum_size = _panel_size
	_panel.size = _panel_size
	_toast.custom_minimum_size = Vector2(_panel_size.x - 24.0, 0)
	_preview_row_index = 0
	visible = true
	_busy = true
	_state = await Backend.get_wardrobe()
	_busy = false
	_outfit = Outfit.normalized(_state.outfit)
	_select_slot(_slot)


func _build_preview() -> Control:
	var stage: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(Color("#2a1f2e"), 6, 4)
	stage.add_theme_stylebox_override("panel", style)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	stage.add_child(row)
	var left: Button = UiStyle.make_button("◀", false, 14)
	left.custom_minimum_size = Vector2(36, 36)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.pressed.connect(_turn.bind(-1))
	row.add_child(left)
	_preview_atlas = AtlasTexture.new()
	_preview = TextureRect.new()
	_preview.texture = _preview_atlas
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(CharacterPainter.FRAME * PREVIEW_SCALE)
	row.add_child(_preview)
	var right: Button = UiStyle.make_button("▶", false, 14)
	right.custom_minimum_size = Vector2(36, 36)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.pressed.connect(_turn.bind(1))
	row.add_child(right)
	return stage


func _process(delta: float) -> void:
	if not visible or _preview_atlas.atlas == null:
		return
	_frame_left -= delta
	if _frame_left <= 0.0:
		_frame_left = FRAME_TIME
		_preview_column = 2 + (_preview_column - 1) % 4
		_update_preview_region()
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)


func _turn(step: int) -> void:
	_preview_row_index = posmod(_preview_row_index + step, PREVIEW_ROWS.size())
	_update_preview_region()


func _update_preview_region() -> void:
	var frame: Vector2i = CharacterPainter.FRAME
	_preview_atlas.region = Rect2(_preview_column * frame.x, PREVIEW_ROWS[_preview_row_index] * frame.y, frame.x, frame.y)


func _refresh_preview() -> void:
	_preview_atlas.atlas = ImageTexture.create_from_image(Appearance.paint_sheet(_outfit))
	_update_preview_region()


func _select_slot(slot: String) -> void:
	_slot = slot
	for key: String in _slot_buttons:
		var active: bool = key == slot
		var style: StyleBoxFlat = UiStyle.panel(UiStyle.RED if active else UiStyle.SHADE, 5, 4)
		style.content_margin_left = 7
		style.content_margin_right = 7
		_slot_buttons[key].add_theme_stylebox_override("normal", style)
		_slot_buttons[key].add_theme_stylebox_override("hover", style)
		_slot_buttons[key].add_theme_color_override("font_color", Color.WHITE if active else UiStyle.INK)
		_slot_buttons[key].add_theme_color_override("font_hover_color", Color.WHITE if active else UiStyle.INK)
	_refresh_all()


func _refresh_all() -> void:
	_refresh_preview()
	_refresh_items()
	_refresh_colors()


func _refresh_items() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	if _state == null:
		return
	var inner_width: float = _panel_size.x - 16.0 - SCROLL_BAR_ALLOWANCE
	var cell_width: float = floorf((inner_width - (COLUMNS - 1) * 4.0) / COLUMNS)
	for item: BackendModels.WardrobeItem in _state.items:
		if item.slot == _slot:
			_grid.add_child(_make_item_button(item, cell_width))


func _make_item_button(item: BackendModels.WardrobeItem, width: float) -> Button:
	var selected: bool = str(_outfit.get(item.slot, "")) == item.id
	var button: Button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 98)
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.SHADE, 5, 2)
	if selected:
		style.set_border_width_all(2)
		style.border_color = UiStyle.RED
	for state: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_on_item_pressed.bind(item))

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var thumb: TextureRect = TextureRect.new()
	thumb.texture = _thumbnail(item)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	thumb.custom_minimum_size = Vector2(width, 64)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not item.unlocked:
		thumb.modulate = Color(0.35, 0.33, 0.36, 0.8)
	box.add_child(thumb)
	var label: Label = UiStyle.make_label(item.name, 8, UiStyle.INK if item.unlocked else UiStyle.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	box.add_child(label)
	if not item.unlocked:
		var lock_text: String = tr("WARDROBE_LOCK_SHOP") if item.unlock_type == "shop" else tr("WARDROBE_LOCK_STREAK") % int(item.unlock_value)
		var lock: Label = UiStyle.make_label(lock_text, 8, UiStyle.RED)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.custom_minimum_size = Vector2(width, 0)
		box.add_child(lock)
	return button


func _thumbnail(item: BackendModels.WardrobeItem) -> ImageTexture:
	var preview_outfit: Dictionary = _outfit.duplicate()
	preview_outfit[item.slot] = item.id
	var direction: int = CharacterPainter.Dir.UP if item.slot == "back" else CharacterPainter.Dir.DOWN
	var key: String = "%d|%s" % [direction, Outfit.key(preview_outfit)]
	if not _thumbnails.has(key):
		_thumbnails[key] = ImageTexture.create_from_image(Appearance.paint_frame(preview_outfit, direction))
	return _thumbnails[key]


func _refresh_colors() -> void:
	for child: Node in _colors.get_children():
		child.queue_free()
	if not Outfit.COLOR_KEYS.has(_slot):
		return
	if _slot == "top" and Outfit.FIXED_TOP_COLORS.has(str(_outfit["top"])):
		return
	var key: String = Outfit.COLOR_KEYS[_slot]
	for hex: String in PALETTES[_slot]:
		var swatch: Button = Button.new()
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(26, 26)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(hex)
		style.set_corner_radius_all(4)
		style.set_border_width_all(2)
		style.border_color = UiStyle.RED if str(_outfit[key]) == hex else UiStyle.PAPER_EDGE
		style.anti_aliasing = false
		for state: String in ["normal", "hover", "pressed"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(_on_color_pressed.bind(key, hex))
		_colors.add_child(swatch)


func _on_item_pressed(item: BackendModels.WardrobeItem) -> void:
	if not item.unlocked:
		if item.unlock_type == "shop":
			_show_toast(tr("WARDROBE_LOCKED_SHOP"))
		else:
			_show_toast(tr("WARDROBE_LOCKED_STREAK") % int(item.unlock_value))
		return
	_outfit[item.slot] = item.id
	_refresh_all()


func _on_color_pressed(key: String, hex: String) -> void:
	_outfit[key] = hex
	_refresh_all()


func _randomize() -> void:
	if _state == null:
		return
	for slot: String in Outfit.SLOTS:
		var options: Array[BackendModels.WardrobeItem] = []
		for item: BackendModels.WardrobeItem in _state.items:
			if item.slot == slot and item.unlocked:
				options.append(item)
		if not options.is_empty():
			_outfit[slot] = options.pick_random().id
	for slot: String in PALETTES:
		_outfit[Outfit.COLOR_KEYS[slot]] = PALETTES[slot].pick_random()
	_refresh_all()


func _save_and_close() -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.save_outfit(_outfit)
	_busy = false
	if not result.ok:
		_show_toast(tr("ERROR_" + result.error.to_upper()))
		return
	_close()


func _close() -> void:
	if _busy:
		return
	visible = false
	_thumbnails.clear()
	closed.emit()


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 3.5
