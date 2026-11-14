class_name LoungePanel
extends ModalPanel
## Daily-independent entertainment rooms. Polling resumes server timers and never derives money locally.

const TITLES: Dictionary = {"blackjack": "21", "roulette": "Рулетка", "checkers": "Шашки", "memory": "Альфа-пары", "defuse": "Обезвредить баг", "bug_hunt": "Охота на баги"}
static var last_room: Dictionary = {}
var _room: Dictionary = {}
var _busy: bool = false
var _poll_left: float = 0.0
var _status: Label
var _timer: Label
var _stake: SpinBox
var _capacity: OptionButton
var _teams: CheckBox
var _level: OptionButton
var _training: CheckBox
var _memory_size: OptionButton
var _game: String = ""
var _table: LoungeTable
var _board: LoungeBoard
var _sound: AudioStreamPlayer
var _sound_on: bool = true
var _previous_board: Array = []
var _exercising: bool = false
var _exercise: SquatsMinigame
var _workout_session: String = ""
var _rep_sequence: int = 0
var _rep_queue: int = 0
var _sending_rep: bool = false
var _bugs: LoungeBugs
var _memory_grid: GridContainer
var _ui_epoch: int = 0
var _focused: bool = true
var _temperature: ProgressBar
var _score_labels: Dictionary[String, Label] = {}


func _init() -> void:
	super("Развлечения")


func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_sound)
	closed.connect(_on_closed)


func open() -> void:
	show_panel()
	_room = {}
	_exercising = false
	_home()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		if is_instance_valid(_memory_grid):
			_memory_grid.visible = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		if is_instance_valid(_memory_grid):
			_memory_grid.visible = true
		_poll_left = 0


func _process(delta: float) -> void:
	if not visible or _busy or _room.is_empty() or _exercising:
		return
	_poll_left -= delta
	if _poll_left <= 0:
		_poll_left = 0.8
		await _send("get")


func _home() -> void:
	_ui_epoch += 1
	clear()
	set_title("Развлечения")
	set_subtitle("Ежедневно · без заданий из дневного пула")
	_room = {}
	_text("Собери коллег за одним столом или начни один.")
	if not last_room.is_empty():
		_button("Вернуться в комнату", func() -> void: _room = last_room; await _send("get"))
	for key: String in TITLES:
		var game_key: String = key
		_button(str(TITLES[key]), func() -> void: _configure(game_key))
	_button("Помочь отделу: приседания", _department)
	_button("Долги и переводы", func() -> void: var panel: LoungeLoans = LoungeLoans.new(); get_parent().add_child(panel); panel.open())
	var code: LineEdit = LineEdit.new()
	code.placeholder_text = "Код комнаты"
	code.max_length = 12
	content.add_child(code)
	_button("Войти по коду", func() -> void: await _join(code.text.strip_edges()))
	_button("Открытые комнаты", _rooms)
	_status = _text("")


func _configure(game_key: String) -> void:
	_ui_epoch += 1
	clear()
	_game = game_key
	set_title(str(TITLES[game_key]))
	set_subtitle("Правила и ставка видны до входа")
	var rules: Dictionary = {
		"blackjack": "Один: против дилера. 2–6: ближе к 21. «Хватит» сохраняет результат, «Пас» теряет стартовую ставку. 60 секунд на решение. Команд нет.",
		"roulette": "Общий стол. Каждый ставит собственные койны. Красное/чёрное: выплата ×2, ноль или номер: ×36, включая возврат ставки. Команд и турниров нет.",
		"checkers": "Двое: русские шашки 8×8. Четверо: Альфа-хаос, порталы и баррикады. Взятие обязательно. Ход: 60 секунд.",
		"memory": "Открой пару одинаковых карточек. Правильная пара продолжает твой ход. 15 секунд на ход. В браузере блокировка системных скриншотов недоступна.",
		"defuse": "Строго трое, рядом в помещении. Оператор нажимает кнопки. Инструктор молчит и показывает инструкцию жестами связному. Связной объясняет оператору словами. Три ошибки — поражение.",
		"bug_hunt": "90 секунд, три одинаковые волны багов. Поворачивай телефон, лови багов касанием. Побеждает большее число пойманных багов.",
	}
	_text(str(rules[game_key]))
	_capacity = OptionButton.new()
	var counts: Array[int] = [1, 2, 3, 4, 5, 6]
	if game_key == "checkers":
		counts = [2, 4]
	elif game_key == "defuse":
		counts = [3]
	elif game_key == "bug_hunt":
		counts = [2, 3, 4, 5, 6]
	elif game_key == "roulette":
		counts = [30]
	for count: int in counts:
		_capacity.add_item("Один" if count == 1 else ("Общий стол" if count == 30 else "%d игроков" % count), count)
	content.add_child(_capacity)
	_teams = CheckBox.new()
	_style_check(_teams)
	_teams.text = "Команды 2 на 2 / 3 на 3"
	_teams.visible = game_key in ["memory", "bug_hunt"]
	content.add_child(_teams)
	_stake = SpinBox.new()
	_stake.min_value = 0
	_stake.max_value = 1000000
	_stake.step = 2 if game_key == "blackjack" else 1
	_stake.value = 20
	_stake.visible = game_key not in ["roulette", "defuse"]
	if _stake.visible:
		_text("Стартовая ставка, койны. Один: выплаты дилера. С коллегами: победителю весь фонд." if game_key == "blackjack" else "Стартовая ставка, койны. Победителю — фонд, победившей команде — поровну.")
	content.add_child(_stake)
	_level = OptionButton.new()
	for caption: String in ["1. Первый сбой", "2. Перепутанные каналы", "3. Потерянный пакет", "4. Перегрев", "5. Каскадный сбой"]:
		_level.add_item(caption)
	_level.visible = game_key == "defuse"
	content.add_child(_level)
	_training = CheckBox.new()
	_style_check(_training)
	_training.text = "Обучение без таймера и награды"
	_training.visible = game_key == "defuse"
	content.add_child(_training)
	_memory_size = OptionButton.new()
	for count: int in [12, 24, 36]:
		_memory_size.add_item("%d карточек" % count, count)
	_memory_size.select(1)
	_memory_size.visible = game_key == "memory"
	content.add_child(_memory_size)
	_button("Создать комнату", _create, true)
	_button("Назад", _home)
	_status = _text("")


func _create() -> void:
	if _busy:
		return
	var extra: Dictionary = {"game": _game, "capacity": _capacity.get_selected_id(), "teams": _teams.visible and _teams.button_pressed, "stake": int(_stake.value) if _stake.visible else 0, "level": _level.selected + 1, "training": _training.button_pressed, "memory_size": _memory_size.get_selected_id()}
	await _send("create", extra)


func _join(code: String) -> void:
	_room = {"id": code}
	await _send("join")


func _rooms() -> void:
	if _busy:
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("lounge_list")
	_busy = false
	if not visible:
		return
	clear()
	set_title("Открытые комнаты")
	for item: Variant in result.get("rooms", []):
		var entry: Dictionary = item
		var id: String = str(entry.get("id", ""))
		_button("%s · %d/%d · %d койнов" % [str(TITLES.get(entry.get("game", ""), "Игра")), int(entry.get("count", 0)), int(entry.get("capacity", 0)), int(entry.get("stake", 0))], func() -> void: await _join(id))
	_button("Обновить", _rooms)
	_button("Назад", _home)
	_status = _text(_error(str(result.get("error", ""))))


func _send(action_name: String, extra: Dictionary = {}) -> bool:
	if _busy and action_name == "get":
		return false
	while _busy:
		await get_tree().process_frame
		if not visible:
			return false
	_busy = true
	var epoch: int = _ui_epoch
	var old_revision: int = int(_room.get("revision", -1))
	var old_phase: String = str(_room.get("phase", ""))
	var old_progress: int = int(_room.get("progress", -1))
	var old_errors: int = int(_room.get("errors", -1))
	var result: Dictionary = await Backend.lounge.action(action_name, _room, extra)
	_busy = false
	if not visible:
		return false
	if epoch != _ui_epoch:
		return false
	var incoming: Dictionary = result.get("room", {})
	if not incoming.is_empty():
		_previous_board = _room.get("board", [])
		_room = incoming
		last_room = incoming
		var heat_only: bool = action_name == "get" and incoming.get("game", "") == "defuse" and old_phase == "playing" and incoming.get("phase", "") == old_phase and int(incoming.get("progress", 0)) == old_progress and int(incoming.get("errors", 0)) == old_errors
		if heat_only:
			if is_instance_valid(_temperature):
				_temperature.value = int(incoming.get("heat", 0))
			if is_instance_valid(_timer):
				_timer.text = "Без таймера" if incoming.get("training", false) else "Осталось: %d сек." % int(incoming.get("left", 0))
		elif int(incoming.get("revision", 0)) != old_revision or old_phase.is_empty() or action_name in ["create", "join"]:
			_render_room()
		elif is_instance_valid(_timer):
			_timer.text = "Осталось: %d сек." % int(_room.get("left", 0))
	if action_name == "catch" and is_instance_valid(_bugs) and not incoming.is_empty():
		_bugs.update_room(incoming)
	if is_instance_valid(_status):
		_status.text = _error(str(result.get("error", "")))
	if old_phase != "result" and _room.get("phase", "") == "result" and _room.get("game", "") == "roulette":
		_show_result(_room.duplicate(true))
	if old_phase != "finished" and _room.get("phase", "") == "finished":
		_play_sound("neighbor_voice" if _room.get("game", "") == "blackjack" else "cash_register")

	return bool(result.get("ok", false))


func _render_room() -> void:
	# Retain the live AR view and its gyro orientation during score updates.
	if is_instance_valid(_bugs) and _room.get("phase", "") == "playing" and _room.get("game", "") == "bug_hunt":
		_bugs.update_room(_room)
		for p: Dictionary in _room.get("players", []):
			var id: String = str(p.get("id", ""))
			if _score_labels.has(id) and is_instance_valid(_score_labels[id]):
				_score_labels[id].text = "%s · %d" % [p.get("name", ""), int(p.get("score", 0))]
		if is_instance_valid(_timer):
			_timer.text = "Осталось: %d сек." % int(_room.get("left", 0))
		return
	if is_instance_valid(_table) and _table.get_parent() == content:
		if _table.room.get("id", "") == _room.get("id", "") and _room.get("phase", "") != "waiting" and _room.get("game", "") in ["blackjack", "roulette"]:
			content.remove_child(_table)
		else:
			_table = null
	clear()
	set_title(str(TITLES.get(_room.get("game", ""), "Развлечения")))
	set_subtitle("Код: %s · взнос: %d · фонд: %d" % [_room.get("id", ""), int(_room.get("stake", 0)), int(_room.get("pot", 0))])
	var phase: String = str(_room.get("phase", "waiting"))
	var game_key: String = str(_room.get("game", ""))
	_timer = _text("Ожидание готовности" if phase == "waiting" else ("Без таймера" if _room.get("training", false) else "Осталось: %d сек." % int(_room.get("left", 0))))
	var players: Array = _room.get("players", [])
	_score_labels.clear()
	for i: int in players.size():
		if phase not in ["waiting", "finished"] and game_key in ["blackjack", "roulette"]:
			continue
		var p: Dictionary = players[i]
		_score_labels[str(p.get("id", ""))] = _text("%s%s · %d%s" % ["ГОТОВ · " if p.get("ready", false) else "", p.get("name", ""), int(p.get("score", 0)), " · команда %d" % (int(p.get("team", 0)) + 1) if _room.get("teams", false) else ""], 10)
	if phase in ["waiting", "finished"]:
		if phase == "finished":
			var winners: Array = _room.get("winners", [])
			var names: PackedStringArray = PackedStringArray()
			for p: Dictionary in players:
				if winners.has(p.get("id", "")):
					names.append(str(p.get("name", "")))
			_text("Победители: " + ", ".join(names) if not names.is_empty() else "Партия завершена")
			if game_key != "blackjack" or players.size() != 1:
				_text(str(_room.get("message", "")))
			var awards: Dictionary = _room.get("awards", {})
			for p: Dictionary in players:
				var id: String = str(p.get("id", ""))
				if awards.has(id):
					_text("%s получил %d койнов" % [p.get("name", ""), int(awards[id])], 11)
			if game_key == "blackjack":
				_show_table()
		_button("Скопировать код комнаты", func() -> void: PlatformServices.copy_text(str(_room.get("id", ""))))
		_button("Готов / не готов", func() -> void: await _send("ready", {"ready": not bool(_my_player().get("ready", false))}))
		if _room.get("host", "") == Backend.get_user_id():
			_button("Начать · ставка %d" % int(_room.get("stake", 0)), func() -> void: await _send("start"), true)
	else:
		match game_key:
			"blackjack":
				_show_table()
				var me: Dictionary = _my_player()
				_text("Твои карты: %s · сумма %d" % [_card_names(me.get("cards", [])), int(me.get("total", 0))])
				var actions: Array[String] = ["hit", "stand"] if players.size() == 1 else ["hit", "stand", "pass"]
				for action_name: String in actions:
					var action_copy: String = action_name
					var button: Button = _button({"hit": "Ещё карту", "stand": "Хватит", "pass": "Пас: потерять ставку"}[action_name], func() -> void: await _send(action_copy))
					button.disabled = bool(me.get("done", false)) or bool(me.get("eliminated", false))
			"roulette":
				_show_table()
				_roulette()
			"memory":
				_memory()
			"checkers":
				_text("Ходит: " + str((players[int(_room.get("turn", 0))] as Dictionary).get("name", "")))
				_board = LoungeBoard.new(_room)
				_board.animate_from(_previous_board)
				content.add_child(_board)
				_board.action_requested.connect(func(action_name: String, extra: Dictionary) -> void: await _send(action_name, extra); _play_sound("clink"))
				if int(_room.get("capacity", 2)) == 4:
					var power: CheckBox = CheckBox.new()
					_style_check(power)
					var powers: Dictionary = _room.get("powers", {})
					var ability: String = str(powers.get(str(_my_index()), ""))
					power.text = "Применить: " + {"portal": "портал", "barrier": "баррикада"}.get(ability, "нет способности")
					power.disabled = ability.is_empty()
					power.toggled.connect(func(enabled: bool) -> void: _board.use_power = enabled)
					content.add_child(power)
					_text("Фиолетовые клетки: П — портал, Б — баррикада. Взятие приоритетно.", 10)
			"defuse":
				_defuse()
			"bug_hunt":
				_bugs = LoungeBugs.new(_room)
				content.add_child(_bugs)
				_bugs.caught.connect(func(index: int) -> void: await _send("catch", {"index": index}))
	var sound: CheckBox = CheckBox.new()
	_style_check(sound)
	sound.text = "Звуки"
	sound.button_pressed = _sound_on
	sound.toggled.connect(func(enabled: bool) -> void: _sound_on = enabled)
	content.add_child(sound)
	if phase in ["waiting", "finished"] or game_key == "roulette":
		_button("Выйти из комнаты", _leave)
	_button("Свернуть комнату", _home)
	_status = _text("")


func _roulette() -> void:
	var phase: String = str(_room.get("phase", ""))
	if phase == "betting" and Backend.get_balance() > 0:
		var amount: SpinBox = SpinBox.new()
		amount.min_value = 1
		amount.max_value = maxi(1, Backend.get_balance())
		amount.value = mini(20, int(amount.max_value))
		content.add_child(amount)
		for field: String in ["red", "black", "green"]:
			var field_copy: String = field
			_button({"red": "Красное · ×2", "black": "Чёрное · ×2", "green": "Зелёный 0 · ×36"}[field], func() -> void: await _send("bet", {"field": field_copy, "amount": int(amount.value)}))
		var number: SpinBox = SpinBox.new()
		number.min_value = 0
		number.max_value = 36
		content.add_child(number)
		_button("Поставить на номер · ×36", func() -> void: await _send("bet", {"field": "n%d" % int(number.value), "amount": int(amount.value)}))
	if Backend.get_balance() == 0:
		_text("Баланс 0: ты зритель. После пополнения можно снова ставить.")
	var bets: Array = _room.get("bets", [])
	for item: Dictionary in bets:
		var players: Array = _room.get("players", [])
		_text("%s: %d на %s" % [(players[int(item.get("player", 0))] as Dictionary).get("name", ""), int(item.get("amount", 0)), item.get("field", "")], 10)
	var history: Array = _room.get("history", [])
	_text("История: " + ", ".join(history.map(func(n: Variant) -> String: return str(n))), 10)
	var gains: Dictionary = _room.get("gains", {})
	if phase == "result":
		for positive: bool in [true, false]:
			_text("Выиграли" if positive else "Проиграли / без изменения")
			for p: Dictionary in _room.get("players", []):
				var id: String = str(p.get("id", ""))
				if gains.has(id) and (int(gains[id]) > 0) == positive:
					_text("%s: %+d" % [p.get("name", ""), int(gains[id])], 11)
	if (_room.get("players", []) as Array).size() > 6:
		content.add_child(LoungeRoster.new(_room.get("players", [])))
	_button("Попросить койны в долг", func() -> void: var panel: LoungeLoans = LoungeLoans.new(); get_parent().add_child(panel); panel.open())


func _memory() -> void:
	var players: Array = _room.get("players", [])
	_text("Ходит: " + str((players[int(_room.get("turn", 0))] as Dictionary).get("name", "")))
	_memory_grid = GridContainer.new()
	_memory_grid.columns = 4 if (_room.get("cards", []) as Array).size() == 12 else 6
	_memory_grid.add_theme_constant_override("h_separation", 3)
	_memory_grid.add_theme_constant_override("v_separation", 3)
	_memory_grid.visible = _focused
	content.add_child(_memory_grid)
	var cards: Array = _room.get("cards", [])
	var matched: Dictionary = _room.get("matched", {})
	for i: int in cards.size():
		var index: int = i
		var button: LoungeCard = LoungeCard.new(int(cards[i]), bool(matched.get(str(i), false)))
		button.pressed.connect(func() -> void: await _send("flip", {"index": index}); _play_sound("page_flip"))
		_memory_grid.add_child(button)


func _defuse() -> void:
	var me: int = _my_index()
	var operator: int = int(_room.get("operator", 0))
	var instructor: int = int(_room.get("instructor", 1))
	_text("Твоя роль: " + ("ОПЕРАТОР" if me == operator else ("ИНСТРУКТОР · БЕЗ РЕЧИ" if me == instructor else "СВЯЗНОЙ")))
	_text("Модуль %d/%d · ошибки %d/3" % [int(_room.get("progress", 0)) + 1, int(_room.get("modules", 0)), int(_room.get("errors", 0))])
	var symbols: Array[String] = ["АЛЬФА", "КОТ", "КАРТА", "КЛЮЧ", "СЕТЬ", "ПАКЕТ", "СЕРВЕР", "КОИН"]
	var level: int = int(_room.get("level", 1))
	var scenes: Array[String] = ["Первый сбой: восстанови порядок запуска", "Перепутанные каналы: соедини канал с символом", "Потерянный пакет: собери двоичную последовательность", "Перегрев: восстанавливай модули и охлаждай сервер", "Каскадный сбой: восстанавливай связанные узлы"]
	_text(scenes[level - 1])
	if level >= 4:
		_temperature = ProgressBar.new()
		_temperature.value = int(_room.get("heat", 0))
		_temperature.custom_minimum_size.y = 20
		content.add_child(_temperature)
		_text("Температура: %d / 100" % int(_room.get("heat", 0)), 10)
	if me == instructor:
		var instruction: Array = _room.get("instruction", [])
		_text("Молча покажи связному порядок. Не показывай экран оператору.")
		for i: int in instruction.size():
			var value: int = int(instruction[i])
			var caption: String = symbols[value % 8]
			if level == 2:
				caption = "Канал %d: %s" % [i + 1, caption]
			elif level == 3:
				caption = "Пакет %d: %s" % [i + 1, _binary(value)]
			elif level == 5:
				caption = "Узел %d: %s" % [value / 8 + 1, caption]
			_text("%d. %s" % [i + 1, caption])
	elif me == operator:
		_text("Слушай связного. Инструкция есть только у молчащего коллеги.")
		var nodes: OptionButton = OptionButton.new()
		if level == 5:
			for node: int in 3:
				nodes.add_item("Узел %d" % (node + 1), node)
			content.add_child(nodes)
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		content.add_child(grid)
		for i: int in symbols.size():
			var index: int = i
			var caption: String = _binary(i) if level == 3 else symbols[i]
			var button: Button = UiStyle.make_button(caption, false, 12)
			button.custom_minimum_size = Vector2(140, 42)
			button.pressed.connect(func() -> void: await _send("defuse", {"index": index, "to": nodes.selected if level == 5 else int(_room.get("progress", 0))}))
			grid.add_child(button)
		if level >= 4:
			_button("Охлаждение · −5 секунд", func() -> void: await _send("cool"))
		_button("Подсказка · −20 секунд", func() -> void: await _send("hint"))
	else:
		_text("Смотри на жесты инструктора. Объясняй оператору словами; инструкцию видит только инструктор.")
	_text(str(_room.get("message", "")))


static func _binary(value: int) -> String:
	return "%d%d%d" % [(value >> 2) & 1, (value >> 1) & 1, value & 1]


func _show_table() -> void:
	if not is_instance_valid(_table) or _table.is_queued_for_deletion():
		_table = LoungeTable.new(_room)
	else:
		_table.update_room(_room)
	content.add_child(_table)


func _department() -> void:
	if _busy:
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("department_squats", {"action": "get"})
	_busy = false
	if not visible:
		return
	clear()
	set_title("План отдела")
	set_subtitle("По числу сотрудников с приседаниями сегодня")
	_text("%d / %d повторений · назначено %d сотрудникам" % [int(result.get("total", 0)), int(result.get("goal", 0)), int(result.get("assigned", 0))])
	_text("Твой вклад: %d. Дополнительное приседание: 15 койнов до выполнения плана. Личного лимита нет." % int(result.get("mine", 0)))
	if result.get("can_help", false):
		_button("Начать приседания", _start_exercise, true)
	else:
		_text("Сначала выполни личное задание «Утренняя зарядка».")
	_button("Назад", _home)
	_status = _text(_error(str(result.get("error", ""))))


func _start_exercise() -> void:
	var features: Array[PlatformBackend.Feature] = [PlatformBackend.Feature.POSE_DETECTION]
	if not PlatformServices.has_features(features) or not await PlatformServices.request_access(features):
		_status.text = "Распознавание позы недоступно."
		return
	var result: Dictionary = await Backend.lounge.request("department_squats", {"action": "start"}, true)
	if not result.get("ok", false):
		_status.text = _error(str(result.get("error", "")))
		return
	_workout_session = str(result.get("session", ""))
	_rep_sequence = 0
	_rep_queue = 0
	_exercising = true
	PlayTime.exercise_mode = true
	clear()
	_exercise = SquatsMinigame.new()
	_exercise.context = {"continuous": true}
	_exercise.repetition.connect(_on_rep)
	var exercise_host: Control = Control.new()
	exercise_host.custom_minimum_size = Vector2(288, 306)
	content.add_child(exercise_host)
	_exercise.scale = Vector2(0.9, 0.9)
	exercise_host.add_child(_exercise)
	_status = _text("15 койнов за повторение до выполнения плана.")
	_button("Закончить тренировку", func() -> void: _exercising = false; PlayTime.exercise_mode = false; _exercise.queue_free(); await _department())


func _on_rep() -> void:
	_rep_queue += 1
	if _sending_rep:
		return
	_sending_rep = true
	while _rep_queue > 0 and _exercising:
		_rep_queue -= 1
		var result: Dictionary = await Backend.lounge.request("department_squats", {"action": "rep", "session": _workout_session, "sequence": _rep_sequence + 1}, true)
		if result.get("ok", false):
			_rep_sequence += 1
		if is_instance_valid(_status):
			_status.text = "%d / %d · за повторение +%d" % [int(result.get("total", 0)), int(result.get("goal", 0)), int(result.get("reward", 0))] if result.get("ok", false) else _error(str(result.get("error", "")))
	_sending_rep = false


func _on_closed() -> void:
	_ui_epoch += 1
	_exercising = false
	PlayTime.exercise_mode = false
	if is_instance_valid(_exercise):
		_exercise.queue_free()
	if is_instance_valid(_bugs):
		_bugs.queue_free()


func _my_index() -> int:
	var players: Array = _room.get("players", [])
	for i: int in players.size():
		if (players[i] as Dictionary).get("id", "") == Backend.get_user_id():
			return i
	return -1


func _my_player() -> Dictionary:
	var index: int = _my_index()
	return (_room.get("players", []) as Array)[index] if index >= 0 else {}


func _text(value: String, font_size: int = 12) -> Label:
	var label: Label = make_text(value, font_size)
	content.add_child(label)
	return label


func _button(caption: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = UiStyle.make_button(caption, primary, 12)
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	content.add_child(button)
	return button


func _play_sound(sound_name: String) -> void:
	if not _sound_on:
		return
	_sound.stream = load("res://assets/audio/%s.wav" % sound_name)
	_sound.play()


static func _card_names(cards: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for card: int in cards:
		names.append(LoungeTable.card_name(card))
	return " ".join(names)


static func _error(key: String) -> String:
	return {
		"": "", "stale_room": "Комната обновилась. Повтори действие.", "not_ready": "Все участники должны подтвердить готовность.",
		"not_enough_coins": "Недостаточно койнов у участника.", "room_full": "Комната заполнена.", "round_started": "Дождись завершения партии.",
		"not_your_turn": "Сейчас ход другого игрока.", "capture_required": "Взятие обязательно.", "invalid_move": "Этот ход недоступен.",
		"personal_squats_required": "Сначала выполни личное задание с приседаниями.", "too_fast": "Повторение пока не подтверждено сервером.",
		"invalid_teams": "Для команд нужно 4 или 6 игроков.", "not_enough_players": "Собери нужное число участников.",
		"office_network_required": "Для помощи отделу подключись к Wi-Fi офиса.", "presence_required": "Сначала отметь вход в офис по QR-коду.",
		"invalid_workout": "Тренировка устарела. Начни её заново.", "invalid_loan": "Запрос уже обработан или сумма недоступна.",
		"turn_finished": "Твоё решение принято. Ждём остальных.", "already_caught": "Этот баг уже пойман.", "wrong_wave": "Началась следующая волна.",
		"not_in_room": "Ты вышел из комнаты. Присоединись заново.", "invalid_mode": "Этот режим недоступен.",
		"even_stake_required": "Для 21 выбери чётную ставку: выплата за блэкджек составляет 3:2.", "host_only": "Начать игру может создатель комнаты.",
		"no_power": "У тебя пока нет способности.", "wrong_role": "Нажимать кнопки может только оператор.", "wrong_channel": "Сначала подключи текущий канал.",
		"invalid_bet": "Ставка недоступна. Проверь сумму и дождись приёма ставок.", "invalid_card": "Эта карточка сейчас недоступна.",
		"player_unavailable": "Коллега сейчас недоступен.", "loan_not_found": "Запрос не найден.", "duplicate_operation": "Действие уже обработано. Обнови экран.",
		"room_not_found": "Комната не найдена.", "network": "Нет связи с сервером.", "server": "Ошибка сервера.",
	}.get(key, "Действие недоступно. Обнови экран.")


func _show_result(data: Dictionary) -> void:
	await get_tree().create_timer(1.8).timeout
	if visible and _room.get("id", "") == data.get("id", "") and _room.get("phase", "") == "result":
		get_parent().add_child(LoungeResult.new(data))
		_play_sound("cash_register")


static func _style_check(check: CheckBox) -> void:
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(state, UiStyle.INK)
	check.add_theme_font_size_override("font_size", 12)


func _exit_tree() -> void:
	PlayTime.exercise_mode = false
	if is_instance_valid(_table) and _table.get_parent() == null:
		_table.queue_free()


func _leave() -> void:
	if await _send("leave"):
		last_room = {}
		_home()
