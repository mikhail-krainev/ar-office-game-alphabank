class_name LoungeBlackjackView
extends LoungeCasinoView
## 21: the cloth on top, decisions or the next deal below. The solo "Раздать" button applies the
## chosen stake, marks the player ready and starts the hand in one tap (three server actions).

## Stake steps of the stepper; the server takes even stakes only (blackjack pays 3:2).
const STAKES: Array[int] = [0, 10, 20, 30, 50, 100, 200, 500, 1000, 2000, 5000, 10000]

var _table: BlackjackTable
var _play_row: HBoxContainer
var _hit: Button
var _stand: Button
var _pass: Button
var _lobby: VBoxContainer
var _stake_row: HBoxContainer
var _stake_label: Label
var _stake_minus: Button
var _stake_plus: Button
var _apply: Button
var _ready_button: Button
var _start_button: Button
var _hint: Label
var _stake: int = 20
var _stake_edited: bool = false
var _sending: bool = false


func _ready() -> void:
	super()
	_table = BlackjackTable.new()
	add_child(_table)
	_table.card_dealt.connect(func() -> void: play_sound("page_flip"))
	_table.result_shown.connect(func(outcome: String) -> void: play_sound("cash_register" if outcome == "win" else "clink"))
	_play_row = make_row()
	add_child(_play_row)
	_hit = make_button("Ещё", true, func() -> void: _decide("hit"), 14)
	_stand = make_button("Хватит", false, func() -> void: _decide("stand"), 14)
	_pass = make_button("Пас", false, func() -> void: _decide("pass"), 12)
	_pass.tooltip_text = "Пас: выйти из раздачи, ставка остаётся в фонде"
	_pass.size_flags_stretch_ratio = 0.6
	for button: Button in [_hit, _stand, _pass]:
		button.custom_minimum_size.y = 44
		_play_row.add_child(button)
	_build_lobby()
	build_footer()
	if int(room.get("stake", 0)) > 0:
		_stake = int(room.get("stake", 0))
	elif is_host():
		_stake_edited = true
	_refresh()


func _build_lobby() -> void:
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 6)
	add_child(_lobby)
	_stake_row = make_row(4)
	_lobby.add_child(_stake_row)
	var caption: Label = UiStyle.make_label("Ставка", 12, UiStyle.MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stake_row.add_child(caption)
	_stake_minus = _make_step("−", -1)
	_stake_row.add_child(_stake_minus)
	_stake_label = UiStyle.make_label("", 16)
	_stake_label.custom_minimum_size = Vector2(64, 0)
	_stake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stake_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stake_row.add_child(_stake_label)
	_stake_plus = _make_step("+", 1)
	_stake_row.add_child(_stake_plus)
	_apply = make_button("OK", false, func() -> void: request("stake", {"stake": _stake}), 11)
	_apply.size_flags_horizontal = Control.SIZE_SHRINK_END
	_apply.custom_minimum_size.x = 44
	_stake_row.add_child(_apply)
	_hint = UiStyle.make_label("", 10, UiStyle.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby.add_child(_hint)
	var buttons: HBoxContainer = make_row()
	_lobby.add_child(buttons)
	_ready_button = make_button("Я готов", false, func() -> void: request("ready", {"ready": not bool(my_player().get("ready", false))}))
	buttons.add_child(_ready_button)
	_start_button = make_button("", true, _on_start, 14)
	_start_button.custom_minimum_size.y = 44
	buttons.add_child(_start_button)


func _make_step(caption: String, direction: int) -> Button:
	var button: Button = make_button(caption, false, func() -> void: _step(direction), 16)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(40, 36)
	return button


func _step(direction: int) -> void:
	var index: int = 0
	for i: int in STAKES.size():
		if STAKES[i] <= _stake:
			index = i
	if direction < 0 and STAKES[index] == _stake:
		index -= 1
	elif direction > 0:
		index += 1
	_stake = STAKES[clampi(index, 0, STAKES.size() - 1)]
	_stake_edited = _stake != int(room.get("stake", 0))
	_refresh()


## One decision per tap: the buttons stay locked until the server has answered.
func _decide(action_name: String) -> void:
	if _sending:
		return
	_sending = true
	_refresh()
	request(action_name)


func action_finished(_action_name: String, _ok: bool) -> void:
	_sending = false
	_refresh()


func _on_start() -> void:
	if _sending:
		return
	_sending = true
	_refresh()
	if _is_solo():
		request("deal", {"stake": _stake})
	else:
		request("start")


func _is_solo() -> bool:
	return players().size() == 1


func _refresh() -> void:
	if _table == null:
		return
	_table.update_room(room)
	var phase: String = str(room.get("phase", "waiting"))
	var playing: bool = phase == "playing"
	var me: Dictionary = my_player()
	var solo: bool = _is_solo()
	var my_turn_over: bool = bool(me.get("done", false)) or bool(me.get("eliminated", false)) or _sending
	_play_row.visible = playing
	_hit.disabled = my_turn_over
	_stand.disabled = my_turn_over
	_pass.disabled = my_turn_over
	_pass.visible = not solo
	_lobby.visible = not playing
	_leave_button.disabled = playing
	if _stake_edited and _stake == int(room.get("stake", 0)):
		_stake_edited = false
	if not _stake_edited:
		_stake = int(room.get("stake", 0))
	var host: bool = is_host()
	_stake_label.text = str(_stake) if _stake > 0 else "без ставки"
	_stake_minus.visible = host
	_stake_plus.visible = host
	_stake_minus.disabled = _stake <= STAKES[0]
	_stake_plus.disabled = _stake >= STAKES[-1] or _stake >= Backend.get_balance()
	_apply.visible = host and not solo and _stake_edited
	_ready_button.visible = not solo
	_ready_button.text = "Не готов" if me.get("ready", false) else "Я готов"
	_start_button.visible = host
	_start_button.text = ("Раздать" if solo else "Начать") + (" · %d" % _stake if _stake > 0 else "")
	_start_button.disabled = _sending or (not solo and (_stake_edited or not _all_ready()))
	_hint.text = _hint_text(playing, solo, host)
	_hint.visible = not _hint.text.is_empty()


func _all_ready() -> bool:
	for p: Dictionary in players():
		if not p.get("ready", false):
			return false
	return true


func _hint_text(playing: bool, solo: bool, host: bool) -> String:
	if playing:
		return ""
	if solo:
		return "Баланс: %d. Блэкджек платит 3:2, ничья возвращает ставку." % Backend.get_balance()
	var ready: int = 0
	for p: Dictionary in players():
		ready += 1 if p.get("ready", false) else 0
	var text: String = "Готовы %d из %d. " % [ready, players().size()]
	if host and _stake_edited:
		return text + "Нажми OK, чтобы применить ставку: готовность сбросится."
	return text + ("Ставку задаёт создатель комнаты." if not host else "Ставка спишется у всех при старте.")

