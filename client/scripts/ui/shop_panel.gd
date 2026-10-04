class_name ShopPanel
extends CanvasLayer
## Reward shop with three tabs: the daily rotating rewards, the parking draw and the garage with car
## models. Prices, discounts, ownership, tickets and the draw itself are decided by Backend.

enum Tab { REWARDS, RAFFLE, GARAGE }

const TAB_KEYS: Dictionary[Tab, String] = {Tab.REWARDS: "SHOP_TAB_REWARDS", Tab.RAFFLE: "SHOP_TAB_RAFFLE", Tab.GARAGE: "SHOP_TAB_GARAGE"}
const TITLE_KEYS: Dictionary[Tab, String] = {Tab.REWARDS: "SHOP_TITLE", Tab.RAFFLE: "RAFFLE_TITLE", Tab.GARAGE: "GARAGE_TITLE"}
const PARKING_BLUE: Color = Color("#2f6fd0")

const ICONS: Texture2D = preload("res://assets/ui/shop_icons.png")
const COIN_SHEET: Texture2D = preload("res://assets/ui/alfa_coin.png")
const ICON_SIZE: int = 24
const COLUMNS: int = 2
const SIDE_MARGIN: float = 10.0

var _shop: BackendModels.ShopState
var _tab: Tab = Tab.REWARDS
var _panel: PanelContainer
var _title: Label
var _refresh_label: Label
var _tab_buttons: Array[Button] = []
var _scroll: TouchScroll
var _content: VBoxContainer
var _toast: Label
var _toast_left: float = 0.0
var _busy: bool = false
var _width: float = 320.0
var _raffle: BackendModels.RaffleState
var _raffle_loaded_msec: int = 0
var _countdown: Label
## Draws whose replay the player has watched this session.
static var _watched_draws: Array[String] = []


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
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	header.add_child(titles)
	_title = UiStyle.make_label(tr("SHOP_TITLE"), 16)
	titles.add_child(_title)
	_refresh_label = UiStyle.make_label("", 9, UiStyle.MUTED)
	titles.add_child(_refresh_label)
	var coins: CoinCounter = CoinCounter.new()
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(coins)
	var close: Button = UiStyle.make_button("✕", false, 14)
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(func() -> void: visible = false)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	for tab: Tab in TAB_KEYS:
		var button: Button = UiStyle.make_button(tr(TAB_KEYS[tab]), false, 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 30)
		button.pressed.connect(_select_tab.bind(tab))
		tabs.add_child(button)
		_tab_buttons.append(button)

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


func open(tab: Tab = Tab.REWARDS) -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	_width = safe.size.x - SIDE_MARGIN * 2.0
	_panel.custom_minimum_size = Vector2(_width, 0)
	_scroll.custom_minimum_size = Vector2(0, minf(440.0, safe.size.y - 170.0))
	_toast.custom_minimum_size = Vector2(_width - 24.0, 0)
	visible = true
	_toast.text = ""
	await _select_tab(tab)


func _select_tab(tab: int) -> void:
	_tab = tab as Tab
	for index: int in _tab_buttons.size():
		var active: bool = index == tab
		var style: StyleBoxFlat = UiStyle.panel(UiStyle.RED if active else UiStyle.SHADE, 5, 4)
		_tab_buttons[index].add_theme_stylebox_override("normal", style)
		_tab_buttons[index].add_theme_stylebox_override("hover", style)
		_tab_buttons[index].add_theme_color_override("font_color", Color.WHITE if active else UiStyle.INK)
		_tab_buttons[index].add_theme_color_override("font_hover_color", Color.WHITE if active else UiStyle.INK)
	_title.text = tr(TITLE_KEYS[_tab])
	await _reload()


func _reload() -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	if _tab == Tab.REWARDS:
		_shop = await Backend.get_shop()
		if _tab != Tab.REWARDS:
			return
		var grid: GridContainer = GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_content.add_child(grid)
		for offer: BackendModels.ShopOffer in _shop.offers:
			grid.add_child(_make_offer_card(offer))
	elif _tab == Tab.RAFFLE:
		_refresh_label.text = ""
		_raffle = await Backend.raffle.get_raffle()
		_raffle_loaded_msec = Time.get_ticks_msec()
		if _tab != Tab.RAFFLE:
			return
		_content.add_child(_make_raffle_card(_raffle))
	else:
		_refresh_label.text = ""
		var garage: BackendModels.GarageState = await Backend.get_garage()
		if _tab != Tab.GARAGE:
			return
		for car: BackendModels.CarInfo in garage.cars:
			_content.add_child(_make_car_card(car))


func _process(delta: float) -> void:
	if not visible:
		return
	if _tab == Tab.REWARDS and _shop != null:
		var left: int = maxi(0, _shop.refresh_at - int(Time.get_unix_time_from_system()))
		_refresh_label.text = tr("SHOP_REFRESH") % "%02d:%02d:%02d" % [left / 3600, left / 60 % 60, left % 60]
		if left == 0:
			_shop = null
			_reload()
	if _tab == Tab.RAFFLE and _raffle != null and _raffle.phase == BackendModels.RaffleState.Phase.OPEN and _countdown != null:
		@warning_ignore("integer_division")
		var until_draw: int = maxi(0, _raffle.seconds_to_draw - (Time.get_ticks_msec() - _raffle_loaded_msec) / 1000)
		_countdown.text = RaffleCard.countdown_text(until_draw)
		if until_draw == 0:
			_raffle = null
			_reload()
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)


func _make_offer_card(offer: BackendModels.ShopOffer) -> Control:
	var rarity_color: Color = UiStyle.RARITY_COLORS.get(offer.rarity, UiStyle.MUTED)
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.SHADE, 5, 6)
	style.border_width_top = 3
	style.border_color = rarity_color
	card.add_theme_stylebox_override("panel", style)
	var card_width: float = floorf((_width - 30.0) / COLUMNS)
	card.custom_minimum_size = Vector2(card_width, 0)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	column.add_child(top)
	var icon: TextureRect = TextureRect.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = Rect2(offer.icon * ICON_SIZE, 0, ICON_SIZE, ICON_SIZE)
	icon.texture = atlas
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(48, 48)
	top.add_child(icon)
	var rarity: Label = UiStyle.make_label(tr("RARITY_" + offer.rarity.to_upper()), 8, rarity_color)
	rarity.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(rarity)

	var name_label: Label = UiStyle.make_label(offer.name, 10)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(card_width - 14.0, 26)
	column.add_child(name_label)

	var price_row: HBoxContainer = HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 3)
	column.add_child(price_row)
	price_row.add_child(_coin_icon())
	price_row.add_child(UiStyle.make_label(str(offer.price), 11, UiStyle.RED if offer.discount_percent > 0 else UiStyle.INK))
	if offer.discount_percent > 0:
		var old_price: RichTextLabel = RichTextLabel.new()
		old_price.bbcode_enabled = true
		old_price.fit_content = true
		old_price.autowrap_mode = TextServer.AUTOWRAP_OFF
		old_price.scroll_active = false
		old_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		old_price.add_theme_font_size_override("normal_font_size", 9)
		old_price.add_theme_color_override("default_color", UiStyle.MUTED)
		old_price.text = "[s]%d[/s] [color=#ef3124]−%d%%[/color]" % [offer.base_price, offer.discount_percent]
		price_row.add_child(old_price)

	var button: Button = UiStyle.make_button(tr("SHOP_BOUGHT") if offer.purchased else tr("SHOP_BUY"), not offer.purchased, 11)
	button.disabled = offer.purchased
	button.custom_minimum_size = Vector2(0, 28)
	button.pressed.connect(_on_buy.bind(offer))
	column.add_child(button)
	return card


# --- Parking draw ----------------------------------------------------------------


func _make_raffle_card(state: BackendModels.RaffleState) -> Control:
	var card: RaffleCard = RaffleCard.new()
	card.build(state, _width - 30.0, _watched_draws.has(state.draw_id))
	_countdown = card.countdown
	card.buy_pressed.connect(_on_buy_ticket)
	card.watch_pressed.connect(_watch_draw.bind(state))
	return card


func _on_buy_ticket() -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.PurchaseResult = await Backend.raffle.buy_ticket()
	_busy = false
	_show_toast(tr("RAFFLE_TICKET_BOUGHT") if result.status == BackendModels.PurchaseResult.Status.GRANTED else tr("ERROR_" + result.error.to_upper()))
	await _reload()


func _watch_draw(state: BackendModels.RaffleState) -> void:
	var roulette: RaffleRoulette = RaffleRoulette.new()
	add_child(roulette)
	roulette.play(state)
	await roulette.finished
	if not _watched_draws.has(state.draw_id):
		_watched_draws.append(state.draw_id)
	await _reload()



func _make_car_card(car: BackendModels.CarInfo) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.SHADE, 5, 7)
	if car.selected:
		style.border_width_left = 3
		style.border_color = UiStyle.RED
	card.add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)

	var preview: Control = Control.new()
	var body_size: Vector2i = VehicleCatalog.body_size(car.id)
	preview.custom_minimum_size = Vector2(_width - 30.0, body_size.y + 10)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("#d9d2c6")
	backdrop.position = Vector2(0, body_size.y - 2)
	backdrop.size = Vector2(_width - 30.0, 12)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(backdrop)
	var sprite: VehicleSprite = VehicleSprite.new()
	sprite.position = Vector2(roundf((_width - 30.0 - body_size.x) / 2.0), body_size.y + 4)
	preview.add_child(sprite)
	sprite.setup(car.id)
	column.add_child(preview)

	var name_row: HBoxContainer = HBoxContainer.new()
	column.add_child(name_row)
	var name_label: Label = UiStyle.make_label(car.name, 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(UiStyle.make_label(tr("GARAGE_SPEED") % car.speed_kmh, 9, UiStyle.MUTED))
	var description: Label = UiStyle.make_label(car.description, 9, UiStyle.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(_width - 34.0, 0)
	column.add_child(description)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	column.add_child(footer)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var button: Button
	if car.selected:
		button = UiStyle.make_button(tr("GARAGE_SELECTED"), false, 11)
		button.disabled = true
	elif car.owned:
		button = UiStyle.make_button(tr("GARAGE_SELECT"), true, 11)
		button.pressed.connect(_on_select_car.bind(car))
	else:
		footer.add_child(_coin_icon())
		footer.add_child(UiStyle.make_label(str(car.price), 12))
		button = UiStyle.make_button(tr("GARAGE_BUY"), true, 11)
		button.pressed.connect(_on_buy_car.bind(car))
	button.custom_minimum_size = Vector2(96, 28)
	footer.add_child(button)
	return card


func _coin_icon() -> TextureRect:
	var coin: TextureRect = TextureRect.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = COIN_SHEET
	atlas.region = Rect2(0, 0, 16, 16)
	coin.texture = atlas
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return coin


func _on_buy(offer: BackendModels.ShopOffer) -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.PurchaseResult = await Backend.buy(offer.offer_id)
	_busy = false
	match result.status:
		BackendModels.PurchaseResult.Status.GRANTED:
			_show_toast(tr("SHOP_VOUCHER") % result.voucher if not result.voucher.is_empty() else tr("SHOP_GRANTED"))
		BackendModels.PurchaseResult.Status.PENDING_APPROVAL:
			_show_toast(tr("SHOP_PENDING"))
		_:
			_show_toast(tr("ERROR_" + result.error.to_upper()))
	await _reload()


func _on_buy_car(car: BackendModels.CarInfo) -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.PurchaseResult = await Backend.buy_car(car.id)
	if result.status == BackendModels.PurchaseResult.Status.GRANTED:
		await Backend.select_car(car.id)
		_show_toast(tr("GARAGE_BOUGHT"))
	else:
		_show_toast(tr("ERROR_" + result.error.to_upper()))
	_busy = false
	await _reload()


func _on_select_car(car: BackendModels.CarInfo) -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.select_car(car.id)
	_busy = false
	_show_toast(tr("GARAGE_CHOSEN") % car.name if result.ok else tr("ERROR_" + result.error.to_upper()))
	await _reload()


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 4.0
