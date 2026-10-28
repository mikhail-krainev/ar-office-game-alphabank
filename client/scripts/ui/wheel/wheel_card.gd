class_name WheelCard
extends PanelContainer
## Fortune wheel in the shop: today's wheel, the spin button and the chance of every prize. The
## server picks the sector and grants the prize; the card only spins the wheel to it. A win that
## cannot be given (out of stock, or customization the player has) offers the spin back or coins.

## Text for the shop toast.
signal message(text: String)
## The state changed on the server: the shop reloads the card.
signal changed

const WHEEL_SIZE: float = 230.0

var _state: BackendModels.WheelState
var _width: float = 300.0
var _wheel: WheelView
var _spin_button: Button
var _busy: bool = false


func build(state: BackendModels.WheelState, width: float) -> void:
	_state = state
	_width = width
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.SHADE, 5, 8)
	style.border_width_top = 3
	style.border_color = UiStyle.RED
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var hint: Label = UiStyle.make_label(tr("WHEEL_HINT"), 9, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(_width - 20.0, 0)
	column.add_child(hint)

	var holder: CenterContainer = CenterContainer.new()
	column.add_child(holder)
	_wheel = WheelView.new()
	_wheel.custom_minimum_size = Vector2(WHEEL_SIZE, WHEEL_SIZE)
	_wheel.sectors = state.sectors
	if state.pending != null:
		_wheel.wheel_rotation = WheelView.target_rotation(0.0, state.pending.sector, state.sectors.size(), 0)
	holder.add_child(_wheel)

	if state.pending != null:
		column.add_child(_make_choice(state.pending))
	else:
		_spin_button = UiStyle.make_button(_spin_text(), state.spins_left > 0, 12)
		_spin_button.disabled = state.spins_left <= 0 or state.sectors.is_empty()
		_spin_button.custom_minimum_size = Vector2(0, 34)
		_spin_button.pressed.connect(_on_spin)
		column.add_child(_spin_button)
	column.add_child(UiStyle.make_label(tr("WHEEL_CHANCES"), 11))
	for sector: BackendModels.WheelSector in state.sectors:
		column.add_child(_make_chance_row(sector))


func _spin_text() -> String:
	if _state.spins_left <= 0:
		return tr("WHEEL_COME_TOMORROW")
	# A spin given back for an exchanged win is free.
	if _state.free_spin:
		return tr("WHEEL_SPIN_FREE")
	return tr("WHEEL_SPIN") % _state.spin_price


func _make_chance_row(sector: BackendModels.WheelSector) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var color: Color = WheelView.COIN_GOLD if sector.is_coins() else UiStyle.RARITY_COLORS.get(sector.rarity, UiStyle.MUTED)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(8, 8)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var title: String = tr("WHEEL_COINS") % sector.coins if sector.is_coins() else sector.name
	if sector.out_of_stock:
		title += " · " + tr("SHOP_OUT_OF_STOCK")
	elif sector.owned:
		title += " · " + tr("SHOP_OWNED")
	var name_label: Label = UiStyle.make_label(title, 9, UiStyle.MUTED if sector.out_of_stock or sector.owned else UiStyle.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(UiStyle.make_label("%s%%" % String.num(sector.chance, 1), 9, UiStyle.MUTED))
	return row


func _make_choice(pending: BackendModels.WheelPending) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var reason: String = tr("WHEEL_OWNED") if pending.reason == "owned" else tr("WHEEL_OUT_OF_STOCK")
	var text: Label = UiStyle.make_label(reason, 10, UiStyle.RED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(_width - 20.0, 0)
	box.add_child(text)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	var respin: Button = UiStyle.make_button(tr("WHEEL_TAKE_SPIN"), false, 11)
	respin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	respin.custom_minimum_size = Vector2(0, 32)
	respin.pressed.connect(_on_choice.bind(BackendWheel.CHOICE_RESPIN))
	buttons.add_child(respin)
	var coins: Button = UiStyle.make_button(tr("WHEEL_TAKE_COINS") % pending.coins, true, 11)
	coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coins.custom_minimum_size = Vector2(0, 32)
	coins.pressed.connect(_on_choice.bind(BackendWheel.CHOICE_COINS))
	buttons.add_child(coins)
	return box


func _on_spin() -> void:
	if _busy or _wheel.is_spinning():
		return
	_busy = true
	_spin_button.disabled = true
	var result: BackendModels.SpinResult = await Backend.wheel.spin()
	if result.is_failed():
		_busy = false
		message.emit(tr("ERROR_" + result.error.to_upper()))
		changed.emit()
		return
	await _wheel.spin_to(result.sector)
	_busy = false
	message.emit(_prize_text(result))
	changed.emit()


func _prize_text(result: BackendModels.SpinResult) -> String:
	var sector: BackendModels.WheelSector = _state.sectors[result.sector] if result.sector < _state.sectors.size() else null
	var prize: String = sector.name if sector != null else ""
	match result.status:
		"coins":
			return tr("WHEEL_WON_COINS") % result.coins
		"granted":
			return tr("WHEEL_WON_VOUCHER") % [prize, result.voucher] if not result.voucher.is_empty() else tr("WHEEL_WON") % prize
		"pending_approval":
			return tr("WHEEL_WON_PENDING") % prize
		"choice":
			return tr("WHEEL_WON_CHOICE") % prize
	return ""


func _on_choice(choice: String) -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.SpinResult = await Backend.wheel.resolve(choice)
	_busy = false
	if result.is_failed():
		message.emit(tr("ERROR_" + result.error.to_upper()))
	elif choice == BackendWheel.CHOICE_COINS:
		message.emit(tr("WHEEL_GOT_COINS") % result.coins)
	else:
		message.emit(tr("WHEEL_GOT_SPIN"))
	changed.emit()
