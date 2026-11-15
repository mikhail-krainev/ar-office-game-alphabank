class_name RouletteRoster
extends ScrollContainer
## Everyone at the roulette table: avatar, name and this round's stake, or the net result once the
## wheel has stopped. The bar under an avatar has the colour of that player's chips on the layout.
## The row scrolls sideways when the table is fuller than the screen is wide.

const SEAT_WIDTH: float = 52.0
const AVATAR_SIDE: float = 24.0
const BAR_HEIGHT: float = 4.0
const ROSTER_HEIGHT: float = 60.0

var _row: HBoxContainer
var _seat_key: String = ""
## Player id -> the label under the name.
var _amounts: Dictionary[String, Label] = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, ROSTER_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 2)
	add_child(_row)


## `totals`: seat index -> coins staked this round; `gains`: player id -> net result of the round.
func set_state(players: Array, totals: Dictionary, gains: Dictionary, stopped: bool, lobby: bool) -> void:
	_rebuild(players)
	for i: int in players.size():
		var p: Dictionary = players[i]
		var label: Label = _amounts.get(str(p.get("id", "")))
		if label == null:
			continue
		var color: Color = UiStyle.MUTED
		var text: String = "—"
		if stopped and gains.has(p.get("id", "")):
			var gain: int = int(gains[p.get("id", "")])
			text = "±0" if gain == 0 else "%s%d" % ["+" if gain > 0 else "−", absi(gain)]
			color = UiStyle.MUTED if gain == 0 else (CasinoArt.WIN if gain > 0 else CasinoArt.LOSE)
		elif lobby:
			text = "готов" if p.get("ready", false) else "ждём"
		elif int(totals.get(i, 0)) > 0:
			text = CasinoArt.short_amount(int(totals[i]))
			color = UiStyle.INK
		label.text = text
		label.add_theme_color_override("font_color", color)


## Seats are rebuilt only when somebody sits down, leaves or changes their picture.
func _rebuild(players: Array) -> void:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in players.size():
		var p: Dictionary = players[i]
		if not p.get("departed", false):
			parts.append("%d|%s|%s|%s|%s" % [i, p.get("id", ""), p.get("name", ""), p.get("avatar", ""), p.get("outfit", {})])
	var key: String = ";".join(parts)
	if key == _seat_key:
		return
	_seat_key = key
	_amounts.clear()
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for i: int in players.size():
		var p: Dictionary = players[i]
		if not p.get("departed", false):
			_row.add_child(_make_seat(p, i))


func _make_seat(player: Dictionary, index: int) -> Control:
	var id: String = str(player.get("id", ""))
	var mine: bool = id == Backend.get_user_id()
	var seat: VBoxContainer = VBoxContainer.new()
	seat.custom_minimum_size.x = SEAT_WIDTH
	seat.add_theme_constant_override("separation", 0)
	var avatar: AvatarView = AvatarView.new(AVATAR_SIDE)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seat.add_child(avatar)
	if player.get("character_avatar", false):
		avatar.show_outfit(player.get("outfit", {}), id)
	else:
		avatar.show_avatar(str(player.get("avatar", "me")), id)
	var bar: ColorRect = ColorRect.new()
	bar.color = CasinoArt.GOLD_TEXT if mine else CasinoArt.seat_color(index)
	bar.custom_minimum_size = Vector2(AVATAR_SIDE, BAR_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seat.add_child(bar)
	seat.add_child(_make_line("Ты" if mine else str(player.get("name", "")), UiStyle.INK))
	var amount: Label = _make_line("—", UiStyle.MUTED)
	seat.add_child(amount)
	_amounts[id] = amount
	return seat


func _make_line(text: String, color: Color) -> Label:
	var label: Label = UiStyle.make_label(text, 8, color)
	label.custom_minimum_size.x = SEAT_WIDTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label
