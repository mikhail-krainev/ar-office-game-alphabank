class_name LoungeRouletteView
extends LoungeCasinoView
## Shared roulette table: wheel, betting layout and chip rack. Each tap on the layout is one bet of
## the chosen chip; repeated bets on a field add up and the chip shows the field's total. Results
## and colleagues' wins appear only once the wheel and the ball have stopped.

signal loan_requested

var _wheel: RouletteWheel
var _board: RouletteBoard
var _chips: RouletteChips
var _players_label: Label
var _rules_label: Label
var _lobby: HBoxContainer
var _ready_button: Button
var _start_button: Button
var _phase: String = ""
var _round: int = -1
var _left: float = 0.0
## Bets sent but not yet confirmed, oldest first: shown at once so a tap never feels lost.
var _pending: Array[Dictionary] = []


func _ready() -> void:
	super()
	_wheel = RouletteWheel.new()
	add_child(_wheel)
	_wheel.ball_dropped.connect(func() -> void: play_sound("clink"))
	_wheel.settled.connect(_on_settled)
	_board = RouletteBoard.new()
	add_child(_board)
	_board.bet_requested.connect(_on_bet)
	_chips = RouletteChips.new()
	add_child(_chips)
	_players_label = _make_label(10, UiStyle.INK)
	_rules_label = _make_label(9, UiStyle.MUTED)
	_lobby = make_row()
	add_child(_lobby)
	_ready_button = make_button("Я готов", false, func() -> void: request("ready", {"ready": not bool(my_player().get("ready", false))}))
	_lobby.add_child(_ready_button)
	_start_button = make_button("Открыть стол", true, func() -> void: request("open_table"), 14)
	_lobby.add_child(_start_button)
	var loan: Button = make_button("В долг", false, func() -> void: loan_requested.emit())
	loan.tooltip_text = "Попросить койны в долг у коллеги"
	build_footer([loan])
	_refresh()


func _make_label(font_size: int, color: Color) -> Label:
	var label: Label = UiStyle.make_label("", font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label


func _process(delta: float) -> void:
	super(delta)
	_left = maxf(0.0, _left - delta)
	if _wheel != null:
		_wheel.seconds_left = _left if _phase in ["betting", "spinning"] else -1.0


func _refresh() -> void:
	if _wheel == null:
		return
	var phase: String = str(room.get("phase", "waiting"))
	var round_number: int = int(room.get("round", 0))
	var history: Array = room.get("history", [])
	var changed: bool = phase != _phase or round_number != _round
	_left = float(room.get("left", 0))
	if changed:
		match phase:
			"spinning":
				_wheel.spin()
				play_sound("whoosh")
			"result":
				_wheel.land(int(room.get("result", 0)), true, float(room.get("left", 0)) - RouletteWheel.MIN_RESULT_TIME)
			_:
				# During "result" history[0] is this round; afterwards it is the ball's resting pocket.
				_wheel.idle(int(history[0]) if not history.is_empty() else -1)
	_phase = phase
	_round = round_number
	_wheel.phase_caption = {"waiting": "ОЖИДАНИЕ", "betting": "СТАВКИ", "spinning": "ВРАЩЕНИЕ", "result": "ШАРИК", "finished": "СТОЛ ЗАКРЫТ"}.get(phase, "")
	_wheel.history = history
	_update_bets()
	var lobby: bool = phase in ["waiting", "finished"]
	_lobby.visible = lobby
	_ready_button.visible = not is_host()
	_ready_button.text = "Не готов" if my_player().get("ready", false) else "Я готов"
	_start_button.visible = is_host()
	_rules_label.text = _rules_text(phase)


func _rules_text(phase: String) -> String:
	if Backend.get_balance() <= 0 and phase == "betting":
		return "Баланс 0: ты зритель. Можно попросить койны в долг у коллеги."
	if phase in ["waiting", "finished"]:
		return "Стол открывает создатель комнаты. Дальше раунды идут сами: 20 секунд на ставки, затем вращение."
	return "Тап по полю — фишка, ставки на поле суммируются. Число и зеро ×36, цвет ×2."


func _update_bets() -> void:
	var me: int = my_index()
	var mine: Dictionary = {}
	var others: Dictionary = {}
	var totals: Dictionary = {}
	for item: Variant in room.get("bets", []):
		var bet: Dictionary = item
		var field: String = str(bet.get("field", ""))
		var player: int = int(bet.get("player", -1))
		var amount: int = int(bet.get("amount", 0))
		var target: Dictionary = mine if player == me else others
		target[field] = int(target.get(field, 0)) + amount
		totals[player] = int(totals.get(player, 0)) + amount
	for bet: Dictionary in _pending:
		mine[bet["field"]] = int(mine.get(bet["field"], 0)) + int(bet["amount"])
		totals[me] = int(totals.get(me, 0)) + int(bet["amount"])
	var stopped: bool = _wheel.is_stopped() and _wheel.result() >= 0
	_board.set_state(mine, others, _phase == "betting" and Backend.get_balance() > 0, _wheel.result() if stopped else -1)
	_chips.set_state(Backend.get_balance(), int(totals.get(me, 0)))
	_players_label.text = _players_text(totals, stopped)


func _players_text(totals: Dictionary, stopped: bool) -> String:
	var gains: Dictionary = room.get("gains", {})
	var parts: PackedStringArray = PackedStringArray()
	var list: Array = players()
	for i: int in list.size():
		var p: Dictionary = list[i]
		if p.get("departed", false):
			continue
		var id: String = str(p.get("id", ""))
		var player_name: String = "Ты" if id == Backend.get_user_id() else str(p.get("name", ""))
		if stopped and gains.has(id):
			var gain: int = int(gains[id])
			parts.append("%s %s%d" % [player_name, "+" if gain > 0 else "−", absi(gain)] if gain != 0 else "%s ±0" % player_name)
		elif _phase in ["waiting", "finished"]:
			parts.append(player_name + (" (готов)" if p.get("ready", false) else ""))
		elif int(totals.get(i, 0)) > 0:
			parts.append("%s %d" % [player_name, int(totals[i])])
		else:
			parts.append(player_name)
	if parts.is_empty():
		return ""
	return ("Итоги: " if stopped else "За столом: ") + " · ".join(parts)


func _on_bet(field: String) -> void:
	if _chips.selected > Backend.get_balance() - _pending_total():
		status_label.text = "Недостаточно койнов для этой фишки."
		return
	_pending.append({"field": field, "amount": _chips.selected})
	play_sound("clink")
	_update_bets()
	request("bet", {"field": field, "amount": _chips.selected})


func _pending_total() -> int:
	var total: int = 0
	for bet: Dictionary in _pending:
		total += int(bet["amount"])
	return total


func action_finished(action_name: String, _ok: bool) -> void:
	if action_name == "bet" and not _pending.is_empty():
		_pending.pop_front()
		_update_bets()


func _on_settled() -> void:
	var gains: Dictionary = room.get("gains", {})
	var id: String = Backend.get_user_id()
	_wheel.my_gain = int(gains[id]) if gains.has(id) else null
	if gains.has(id) and int(gains[id]) > 0:
		play_sound("cash_register")
	_update_bets()
