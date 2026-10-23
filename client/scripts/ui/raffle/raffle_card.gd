class_name RaffleCard
extends PanelContainer
## Parking draw in the shop: the prize, a days:hours:minutes countdown, the ticket and its
## requirements, who is taking part, and the fairness data (seed commitment, revealed seed).
## On the draw day the replay of the roulette and the winner are available.

signal buy_pressed
signal watch_pressed

const MAX_ENTRANT_AVATARS: int = 8

var countdown: Label

var _width: float = 300.0


## "03 : 14 : 27" (days, hours, minutes); minutes round up, so zero means the draw is starting.
static func countdown_text(seconds: int) -> String:
	var total_minutes: int = ceili(seconds / 60.0)
	@warning_ignore("integer_division")
	var days: int = total_minutes / 1440
	@warning_ignore("integer_division")
	var hours: int = total_minutes / 60 % 24
	return "%02d : %02d : %02d" % [days, hours, total_minutes % 60]


func build(state: BackendModels.RaffleState, width: float, watched: bool) -> void:
	_width = width
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.SHADE, 5, 8)
	style.border_width_top = 3
	style.border_color = UiStyle.RARITY_COLORS["legendary"]
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(_make_prize(state))
	if state.phase == BackendModels.RaffleState.Phase.OPEN:
		column.add_child(_make_countdown(state))
		column.add_child(_make_ticket(state))
	else:
		column.add_child(_make_result(state, watched))
	column.add_child(_make_entrants(state))
	column.add_child(_make_fairness(state))


func _make_prize(state: BackendModels.RaffleState) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sign_box: PanelContainer = PanelContainer.new()
	sign_box.add_theme_stylebox_override("panel", UiStyle.panel(ShopPanel.PARKING_BLUE, 4, 2))
	sign_box.custom_minimum_size = Vector2(40, 40)
	var letter: Label = UiStyle.make_label("P", 24, Color.WHITE)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign_box.add_child(letter)
	row.add_child(sign_box)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UiStyle.make_label(tr("RARITY_LEGENDARY"), 8, UiStyle.RARITY_COLORS["legendary"]))
	text.add_child(_wrap(state.prize_name, 13, UiStyle.INK, _width - 60.0))
	text.add_child(_wrap(state.prize_description, 9, UiStyle.MUTED, _width - 60.0))
	return row


func _make_countdown(state: BackendModels.RaffleState) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(state.draw_at + WorkCalendar.local_offset())
	var when: String = tr("RAFFLE_DRAW_AT") % ["%02d.%02d" % [int(local["day"]), int(local["month"])], "%02d:%02d" % [int(local["hour"]), int(local["minute"])]]
	column.add_child(_centered(when, 10, UiStyle.MUTED))
	countdown = _centered(countdown_text(state.seconds_to_draw), 24, UiStyle.RED)
	countdown.label_settings.shadow_color = Color(UiStyle.INK, 0.2)
	countdown.label_settings.shadow_offset = Vector2(2, 2)
	column.add_child(countdown)
	column.add_child(_centered(tr("RAFFLE_COUNTDOWN_UNITS"), 8, UiStyle.MUTED))
	return column


func _make_ticket(state: BackendModels.RaffleState) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	var requirement: String = tr("RAFFLE_REQUIREMENT") % [state.min_office_days, state.window_days, state.office_days]
	column.add_child(_wrap(requirement, 9, UiStyle.INK if state.office_days >= state.min_office_days else UiStyle.RED, _width - 10.0))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	var coin: TextureRect = TextureRect.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = ShopPanel.COIN_SHEET
	atlas.region = Rect2(0, 0, 16, 16)
	coin.texture = atlas
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	var price: Label = UiStyle.make_label(str(state.ticket_price), 14)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(price)
	var button: Button
	if state.has_ticket:
		button = UiStyle.make_button(tr("RAFFLE_HAS_TICKET"), false, 11)
		button.disabled = true
	else:
		button = UiStyle.make_button(tr("RAFFLE_BUY"), true, 11)
		button.disabled = not state.buy_error.is_empty()
		button.pressed.connect(buy_pressed.emit)
	button.custom_minimum_size = Vector2(120, 30)
	row.add_child(button)
	if not state.has_ticket and not state.buy_error.is_empty():
		column.add_child(_wrap(tr("ERROR_" + state.buy_error.to_upper()), 9, UiStyle.RED, _width - 10.0))
	return column


func _make_result(state: BackendModels.RaffleState, watched: bool) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(_centered(tr("RAFFLE_RESULTS_TODAY"), 11, UiStyle.INK))
	if watched or state.entrants.is_empty():
		var text: String = tr("RAFFLE_NO_ENTRANTS") if state.entrants.is_empty() else (tr("RAFFLE_YOU_WON") if state.is_winner else tr("RAFFLE_WINNER") % state.winner_name)
		column.add_child(_centered(text, 13, UiStyle.RED if state.is_winner else UiStyle.INK))
	var watch: Button = UiStyle.make_button(tr("RAFFLE_WATCH") if not watched else tr("RAFFLE_WATCH_AGAIN"), not watched, 12)
	watch.custom_minimum_size = Vector2(0, 32)
	watch.pressed.connect(watch_pressed.emit)
	column.add_child(watch)
	return column


func _make_entrants(state: BackendModels.RaffleState) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.add_child(UiStyle.make_label(tr("RAFFLE_ENTRANTS") % state.entrants.size(), 9, UiStyle.MUTED))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	column.add_child(row)
	for index: int in mini(state.entrants.size(), MAX_ENTRANT_AVATARS):
		var entrant: BackendModels.RaffleEntrant = state.entrants[index]
		var avatar: AvatarView = AvatarView.new(26.0)
		avatar.selected = entrant.user_id == Backend.get_user_id()
		row.add_child(avatar)
		avatar.show_avatar(entrant.avatar, entrant.user_id)
		ColleagueProfiles.make_tappable(avatar, entrant.user_id)
	if state.entrants.size() > MAX_ENTRANT_AVATARS:
		row.add_child(UiStyle.make_label("+%d" % (state.entrants.size() - MAX_ENTRANT_AVATARS), 10, UiStyle.MUTED))
	return column


func _make_fairness(state: BackendModels.RaffleState) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.add_child(_wrap(tr("RAFFLE_FAIRNESS"), 8, UiStyle.MUTED, _width - 10.0))
	column.add_child(_wrap(tr("RAFFLE_COMMITMENT") % _short(state.commitment), 8, UiStyle.MUTED, _width - 10.0))
	if not state.revealed_seed.is_empty():
		column.add_child(_wrap(tr("RAFFLE_SEED") % _short(state.revealed_seed), 8, UiStyle.MUTED, _width - 10.0))
	return column


static func _short(hex: String) -> String:
	return hex if hex.length() <= 20 else "%s…%s" % [hex.substr(0, 10), hex.substr(hex.length() - 8)]


func _wrap(text: String, font_size: int, color: Color, width: float) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _centered(text: String, font_size: int, color: Color) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
