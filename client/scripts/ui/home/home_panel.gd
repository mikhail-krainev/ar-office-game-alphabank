class_name HomePanel
extends CanvasLayer
## The interior catalog at home, like a home editor in life sims: apartments (buy, move in),
## furniture and posters (buy, place, rearrange) and colour palettes. Purchases go to the server
## here; placing and the palette are applied by HomeDecorator, which listens to the signals.

signal place_requested(item_id: String)
signal arrange_requested
signal move_requested(apartment_id: String)
signal palette_requested(palette_id: String)
## A purchase changed what the player owns.
signal state_changed(state: BackendHome.State)

enum Tab { APARTMENTS, FURNITURE, POSTERS, PALETTES }

const TAB_KEYS: Dictionary[Tab, String] = {
	Tab.APARTMENTS: "HOME_TAB_APARTMENTS", Tab.FURNITURE: "HOME_TAB_FURNITURE", Tab.POSTERS: "HOME_TAB_POSTERS",
	Tab.PALETTES: "HOME_TAB_PALETTES",
}
const SIDE_MARGIN: float = 10.0
const PREVIEW_HEIGHT: float = 56.0
const COLUMNS: int = 2
const SWATCH_SIZE: Vector2 = Vector2(18, 18)

static var _prop_texture: Texture2D
static var _prop_regions: Dictionary = {}

var _state: BackendHome.State
var _tab: Tab = Tab.APARTMENTS
var _panel: PanelContainer
var _tab_buttons: Array[Button] = []
var _scroll: TouchScroll
var _content: VBoxContainer
var _arrange: Button
var _toast: Label
var _toast_left: float = 0.0
var _busy: bool = false
var _width: float = 320.0


func _ready() -> void:
	layer = 20
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dimmer: ColorRect = UiStyle.make_dimmer()
	dimmer.gui_input.connect(func(event: InputEvent) -> void:
		if Minigame.press_position(event) != null:
			visible = false
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
	column.add_child(_build_header())
	var tabs: GridContainer = GridContainer.new()
	tabs.columns = 2
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	column.add_child(tabs)
	for tab: Tab in TAB_KEYS:
		var button: Button = UiStyle.make_button(tr(TAB_KEYS[tab]), false, 11)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 28)
		button.pressed.connect(_select_tab.bind(tab))
		tabs.add_child(button)
		_tab_buttons.append(button)
	_arrange = UiStyle.make_button(tr("HOME_ARRANGE"), false, 11)
	_arrange.custom_minimum_size = Vector2(0, 28)
	_arrange.pressed.connect(func() -> void:
		visible = false
		arrange_requested.emit()
	)
	column.add_child(_arrange)
	_scroll = TouchScroll.new()
	column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)
	_toast = UiStyle.make_label("", 11, UiStyle.RED)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_toast)


func is_open() -> bool:
	return visible


func open(state: BackendHome.State, tab: Tab = _tab) -> void:
	_state = state
	var safe: Rect2 = PlatformServices.get_safe_rect()
	_width = safe.size.x - SIDE_MARGIN * 2.0
	_panel.custom_minimum_size = Vector2(_width, 0)
	_scroll.custom_minimum_size = Vector2(0, minf(420.0, safe.size.y - 200.0))
	_toast.custom_minimum_size = Vector2(_width - 24.0, 0)
	_toast.text = ""
	visible = true
	_select_tab(tab)


## The decorator saved a new look; redraws the open tab with it.
func set_state(state: BackendHome.State) -> void:
	_state = state
	if visible:
		_reload()


func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)


func _build_header() -> HBoxContainer:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var title: Label = UiStyle.make_label(tr("HOME_TITLE"), 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var coins: CoinCounter = CoinCounter.new()
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(coins)
	var close: Button = UiStyle.make_button("✕", false, 14)
	close.custom_minimum_size = Vector2(34, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)
	return header


func _select_tab(tab: int) -> void:
	_tab = tab as Tab
	for index: int in _tab_buttons.size():
		var active: bool = index == tab
		var style: StyleBoxFlat = UiStyle.panel(UiStyle.RED if active else UiStyle.SHADE, 5, 4)
		_tab_buttons[index].add_theme_stylebox_override("normal", style)
		_tab_buttons[index].add_theme_stylebox_override("hover", style)
		_tab_buttons[index].add_theme_color_override("font_color", Color.WHITE if active else UiStyle.INK)
		_tab_buttons[index].add_theme_color_override("font_hover_color", Color.WHITE if active else UiStyle.INK)
	_arrange.visible = _tab == Tab.FURNITURE or _tab == Tab.POSTERS
	_reload()


func _reload() -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	if _state == null:
		return
	match _tab:
		Tab.APARTMENTS:
			for apartment: BackendHome.Apartment in _state.apartments:
				_content.add_child(_apartment_card(apartment))
		Tab.FURNITURE, Tab.POSTERS:
			_fill_items(BackendHome.ITEM_FURNITURE if _tab == Tab.FURNITURE else BackendHome.ITEM_POSTER)
		Tab.PALETTES:
			for palette: BackendHome.PaletteInfo in _state.palettes:
				_content.add_child(_palette_card(palette))
	_scroll.scroll_vertical = 0


func _fill_items(kind: String) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_content.add_child(grid)
	for item: BackendHome.Item in _state.items:
		if item.kind == kind:
			grid.add_child(_item_card(item))


func _card(selected: bool) -> Array:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.SHADE, 5, 7)
	if selected:
		style.border_width_left = 3
		style.border_color = UiStyle.RED
	card.add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)
	return [card, column]


func _apartment_card(apartment: BackendHome.Apartment) -> Control:
	var parts: Array = _card(apartment.current)
	var column: VBoxContainer = parts[1]
	var name_row: HBoxContainer = HBoxContainer.new()
	column.add_child(name_row)
	var name_label: Label = UiStyle.make_label(apartment.name, 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(_swatches(apartment.palette))
	var description: Label = UiStyle.make_label(apartment.description, 9, UiStyle.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(_width - 34.0, 0)
	column.add_child(description)
	var button: Button
	if apartment.current:
		button = UiStyle.make_button(tr("HOME_LIVING_HERE"), false, 11)
		button.disabled = true
	elif apartment.owned:
		button = UiStyle.make_button(tr("HOME_MOVE_IN"), true, 11)
		button.pressed.connect(func() -> void:
			visible = false
			move_requested.emit(apartment.id)
		)
	else:
		button = UiStyle.make_button(tr("HOME_BUY_FOR") % apartment.price, true, 11)
		button.disabled = Backend.get_balance() < apartment.price
		button.pressed.connect(_buy.bind(BackendHome.KIND_APARTMENT, apartment.id, tr("HOME_BOUGHT_APARTMENT")))
	button.custom_minimum_size = Vector2(0, 28)
	column.add_child(button)
	return parts[0]


func _item_card(item: BackendHome.Item) -> Control:
	var parts: Array = _card(false)
	var card: PanelContainer = parts[0]
	var column: VBoxContainer = parts[1]
	card.custom_minimum_size = Vector2(floorf((_width - 30.0) / COLUMNS), 0)
	var preview: TextureRect = TextureRect.new()
	preview.texture = prop_texture(item.id)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	column.add_child(preview)
	var name_label: Label = UiStyle.make_label(item.name, 10)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name_label)
	var free: int = _state.free_copies(item.id)
	if item.owned > 0:
		column.add_child(UiStyle.make_label(tr("HOME_OWNED") % [item.owned, free], 9, UiStyle.MUTED))
	var buy: Button = UiStyle.make_button(tr("HOME_BUY_FOR") % item.price, item.owned == 0, 10)
	buy.disabled = Backend.get_balance() < item.price or item.owned >= _state.max_owned
	buy.pressed.connect(_buy.bind(BackendHome.KIND_ITEM, item.id, tr("HOME_BOUGHT_ITEM")))
	column.add_child(buy)
	if free > 0:
		var place: Button = UiStyle.make_button(tr("HOME_PLACE"), true, 10)
		place.pressed.connect(func() -> void:
			visible = false
			place_requested.emit(item.id)
		)
		column.add_child(place)
	return card


func _palette_card(palette: BackendHome.PaletteInfo) -> Control:
	var current: bool = _state.palette == palette.id
	var parts: Array = _card(current)
	var column: VBoxContainer = parts[1]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	row.add_child(_swatches(palette.id))
	var name_label: Label = UiStyle.make_label(palette.name, 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var button: Button
	if current:
		button = UiStyle.make_button(tr("HOME_PALETTE_ON"), false, 10)
		button.disabled = true
	elif palette.owned:
		button = UiStyle.make_button(tr("HOME_PALETTE_APPLY"), true, 10)
		button.pressed.connect(func() -> void: palette_requested.emit(palette.id))
	else:
		button = UiStyle.make_button(tr("HOME_BUY_FOR") % palette.price, true, 10)
		button.disabled = Backend.get_balance() < palette.price
		button.pressed.connect(_buy.bind(BackendHome.KIND_PALETTE, palette.id, tr("HOME_BOUGHT_PALETTE")))
	row.add_child(button)
	return parts[0]


func _swatches(palette_id: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for color: Color in HomePalettes.swatch(palette_id):
		var swatch: ColorRect = ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
	return row


func _buy(kind: String, id: String, done_text: String) -> void:
	if _busy:
		return
	_busy = true
	var result: BackendHome.Purchase = await Backend.home.buy(kind, id)
	_busy = false
	if not result.ok:
		_show_toast(tr("ERROR_" + (result.error if not result.error.is_empty() else "server").to_upper()))
		return
	if result.state != null:
		_state = result.state
		state_changed.emit(_state)
	_reload()
	_show_toast(done_text)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 4.0


## The atlas picture of a prop for catalog cards; null when the prop has no art.
static func prop_texture(prop_id: String) -> Texture2D:
	if _prop_texture == null:
		_prop_texture = load(PropCatalog.TEXTURE_PATH)
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(PropCatalog.MANIFEST_PATH))
		_prop_regions = manifest if manifest is Dictionary else {}
	if not _prop_regions.has(prop_id):
		return null
	var region: Array = _prop_regions[prop_id]
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = _prop_texture
	atlas.region = Rect2(region[0], region[1], region[2], region[3])
	return atlas
