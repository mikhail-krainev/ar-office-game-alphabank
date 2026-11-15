class_name LoungePanel
extends ModalPanel
## Daily-independent entertainment rooms. Polling resumes server timers and never derives money locally.
## Joint task rooms (bug hunt) open here too, but only from the task list or an inbox invitation.

## A finished joint task room: the player asks the server to count their task by this room.
signal task_claimed(task_id: String, room_id: String)

const CASINO_GAMES: Array[String] = ["blackjack", "roulette"]
const TITLES: Dictionary = {"blackjack": "21", "roulette": "Рулетка", "checkers": "Шашки", "memory": "Альфа-пары", "defuse": "Обезвредить баг", "bug_hunt": "Охота на баги"}
## Played only as joint daily tasks, never created from the entertainment menu.
const TASK_GAMES: Array[String] = ["bug_hunt"]
## Open rooms listed on the menu itself; the rest are on the full list screen.
const HOME_ROOMS_SHOWN: int = 6
const GAME_ICON_DIR: String = "res://assets/ui/game_icons/%s.png"
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
var _casino: LoungeCasinoView
var _board: LoungeBoard
var _sound: AudioStreamPlayer
var _previous_board: Array = []
var _bugs: LoungeBugs
var _memory_grid: GridContainer
var _ui_epoch: int = 0
var _focused: bool = true
var _temperature: ProgressBar
var _score_labels: Dictionary[String, Label] = {}
var _clicker_view: ClickerView


func _init() -> void:
	super("Развлечения")


func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_sound)
	closed.connect(_on_closed)


func open() -> void:
	if Backend.profile == null or not Backend.profile.in_office:
		return
	show_panel()
	_room = {}
	_home()


## Opens a room directly: a joint task room from the task list or an inbox invitation.
func open_room(room: Dictionary) -> void:
	if Backend.profile == null or not Backend.profile.in_office:
		return
	_ui_epoch += 1
	show_panel()
	clear()
	_room = room
	await _send("join" if room.get("players") == null else "get")


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
	if not visible or _busy or _room.is_empty():
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
	_add_code_search()
	_text("Собери коллег за одним столом или начни один.")
	if not last_room.is_empty():
		_button("Вернуться в комнату", func() -> void: _room = last_room; await _send("get"))
	var clicker: Button = _game_button("Кот удачи · кликер", "clicker", _open_clicker, true)
	clicker.tooltip_text = "Гладь кота, покупай улучшения и золоти его перерождениями"
	for key: String in TITLES:
		if key in TASK_GAMES:
			continue
		var game_key: String = key
		_game_button(str(TITLES[key]), key, func() -> void: _configure(game_key))
	content.add_child(make_text("Сейчас играют", 11, UiStyle.MUTED))
	var room_list: VBoxContainer = VBoxContainer.new()
	room_list.add_theme_constant_override("separation", 4)
	content.add_child(room_list)
	_button("Открытые комнаты", _rooms)
	_status = _text("")
	_fill_room_list(room_list, _ui_epoch)


## Room code entry on top of the menu, like a search field.
func _add_code_search() -> void:
	var join_row: HBoxContainer = HBoxContainer.new()
	content.add_child(join_row)
	var code: LineEdit = LineEdit.new()
	code.placeholder_text = "Код комнаты"
	code.max_length = 12
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.custom_minimum_size.y = 36
	join_row.add_child(code)
	var apply: Button = UiStyle.make_symbol_button("arrow", "Войти в комнату")
	apply.custom_minimum_size = Vector2(36, 36)
	apply.visible = false
	join_row.add_child(apply)
	code.text_changed.connect(func(value: String) -> void: apply.visible = not value.strip_edges().is_empty())
	code.text_submitted.connect(func(value: String) -> void: if not value.strip_edges().is_empty(): await _join(value.strip_edges()))
	apply.pressed.connect(func() -> void: await _join(code.text.strip_edges()))


## Short list of open rooms on the menu: game and players; a tap joins. Loaded after the menu is shown.
func _fill_room_list(room_list: VBoxContainer, epoch: int) -> void:
	var loading: Label = make_text("Загрузка…", 10)
	room_list.add_child(loading)
	var result: Dictionary = await Backend.lounge.request("lounge_list")
	if not visible or epoch != _ui_epoch or not is_instance_valid(room_list):
		return
	loading.queue_free()
	if not result.get("ok", false):
		room_list.add_child(make_text(_error(str(result.get("error", ""))), 10))
		return
	var rooms: Array = result.get("rooms", [])
	if rooms.is_empty():
		room_list.add_child(make_text("Пока никого. Создай комнату — коллеги увидят её здесь.", 10))
		return
	for item: Variant in rooms.slice(0, HOME_ROOMS_SHOWN):
		var entry: Dictionary = item
		var id: String = str(entry.get("id", ""))
		var game_key: String = str(entry.get("game", ""))
		var count: int = int(entry.get("count", 0))
		var caption: String = "%s · %d %s" % [str(TITLES.get(game_key, "Игра")), count, TimeText.plural(count, "LOUNGE_PLAYERS")]
		var button: Button = _game_button(caption, game_key, func() -> void: await _join(id))
		content.remove_child(button)
		room_list.add_child(button)
	if rooms.size() > HOME_ROOMS_SHOWN:
		room_list.add_child(make_text("И ещё %d — в полном списке." % (rooms.size() - HOME_ROOMS_SHOWN), 10))


func _configure(game_key: String) -> void:
	_ui_epoch += 1
	clear()
	_game = game_key
	set_title(str(TITLES[game_key]))
	set_subtitle("Правила комнаты")
	var rules: Dictionary = {
		"blackjack": "Один: против дилера. 2–6: ближе к 21. «Хватит» сохраняет результат, «Пас» теряет стартовую ставку. 60 секунд на решение. Команд нет.",
		"roulette": "Общий стол. Каждый ставит собственные койны. Красное/чёрное: выплата ×2, ноль или номер: ×36, включая возврат ставки. Команд и турниров нет.",
		"checkers": "Двое: русские шашки 8×8. Четверо: Альфа-хаос, порталы и баррикады. Взятие обязательно. Ход: 60 секунд.",
		"memory": "Открой пару одинаковых карточек. Правильная пара продолжает твой ход. 15 секунд на ход. В браузере блокировка системных скриншотов недоступна.",
		"defuse": "Строго трое, рядом в помещении. Оператор нажимает кнопки. Инструктор молчит и показывает инструкцию жестами связному. Связной объясняет оператору словами. Три ошибки — поражение.",
	}
	_text(str(rules[game_key]))
	_capacity = OptionButton.new()
	var counts: Array[int] = [1, 2, 3, 4, 5, 6]
	if game_key == "checkers":
		counts = [2, 4]
	elif game_key == "defuse":
		counts = [3]
	elif game_key == "roulette":
		counts = [30]
	for count: int in counts:
		_capacity.add_item("Один" if count == 1 else ("Общий стол" if count == 30 else "%d игроков" % count), count)
	content.add_child(_capacity)
	_teams = CheckBox.new()
	_style_check(_teams)
	_teams.text = "Команды 2 на 2 / 3 на 3"
	_teams.visible = game_key == "memory"
	content.add_child(_teams)
	_stake = SpinBox.new()
	_stake.min_value = 0
	_stake.max_value = 1000000
	_stake.step = 2 if game_key == "blackjack" else 1
	_stake.value = 20
	_stake.visible = game_key not in ["blackjack", "roulette", "defuse"]
	if _stake.visible:
		_text("Стартовая ставка, койны. Победителю — фонд, победившей команде — поровну.")
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
		_game_button("%s · %d/%d · %d койнов" % [str(TITLES.get(entry.get("game", ""), "Игра")), int(entry.get("count", 0)), int(entry.get("capacity", 0)), int(entry.get("stake", 0))], str(entry.get("game", "")), func() -> void: await _join(id))
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
		if _casino_shows(incoming) and action_name not in ["create", "join"]:
			# Every poll reaches the table: its timers and animations follow the server clock.
			_casino.update_room(incoming)
			set_subtitle(_casino_subtitle())
		elif heat_only:
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
	# A quiet poll keeps the last error of a table action on screen.
	var quiet: bool = _casino_alive() and ((action_name == "get" and result.get("ok", false)) or result.get("error", "") == "turn_finished")
	if is_instance_valid(_status) and not quiet:
		_status.text = _error(str(result.get("error", "")))
	if old_phase != "finished" and _room.get("phase", "") == "finished" and _room.get("game", "") not in CASINO_GAMES:
		_play_sound("cash_register")

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
	if str(_room.get("game", "")) in CASINO_GAMES:
		_render_casino()
		return
	clear()
	set_title(str(TITLES.get(_room.get("game", ""), "Развлечения")))
	var phase: String = str(_room.get("phase", "waiting"))
	var game_key: String = str(_room.get("game", ""))
	var task_id: String = str(_room.get("task", ""))
	if task_id.is_empty():
		set_subtitle("Код: %s · взнос: %d · фонд: %d" % [_room.get("id", ""), int(_room.get("stake", 0)), int(_room.get("pot", 0))])
	else:
		set_subtitle("Совместное задание · 90 секунд, три волны багов")
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
			_text(str(_room.get("message", "")))
			var awards: Dictionary = _room.get("awards", {})
			for p: Dictionary in players:
				var id: String = str(p.get("id", ""))
				if awards.has(id):
					_text("%s получил %d койнов" % [p.get("name", ""), int(awards[id])], 11)
		if task_id.is_empty():
			_button("Скопировать код комнаты", func() -> void: PlatformServices.copy_text(str(_room.get("id", ""))))
		elif phase == "finished":
			var room_id: String = str(_room.get("id", ""))
			_button(tr("COOP_CLAIM"), func() -> void: task_claimed.emit(task_id, room_id), true)
		_button("Готов / не готов", func() -> void: await _send("ready", {"ready": not bool(_my_player().get("ready", false))}))
		if _room.get("host", "") == Backend.get_user_id():
			_button("Начать · ставка %d" % int(_room.get("stake", 0)), func() -> void: await _send("start"), true)
	else:
		match game_key:
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
	if phase in ["waiting", "finished"]:
		_button("Выйти из комнаты", _leave)
	_button("Свернуть комнату", _home)
	_status = _text("")


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


func _on_closed() -> void:
	_ui_epoch += 1
	if is_instance_valid(_bugs):
		_bugs.queue_free()
	# The clicker stops sending taps and counts the time away as closed.
	if is_instance_valid(_clicker_view):
		_clicker_view.queue_free()


func _open_clicker() -> void:
	_ui_epoch += 1
	clear()
	_room = {}
	set_title("Кот удачи")
	set_subtitle("Кликер · очки не превращаются в койны")
	_clicker_view = ClickerView.new()
	_clicker_view.back_requested.connect(_home)
	content.add_child(_clicker_view)


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


## Menu button with the game's icon on the left, text aligned next to it.
func _game_button(caption: String, game_key: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = _button(caption, callback, primary)
	var path: String = GAME_ICON_DIR % game_key
	if ResourceLoader.exists(path):
		button.icon = load(path)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("h_separation", 8)
		button.custom_minimum_size.y = 40
	return button


func _play_sound(sound_name: String) -> void:
	_sound.stream = load("res://assets/audio/%s.wav" % sound_name)
	_sound.play()


static func _error(key: String) -> String:
	return {
		"": "", "stale_room": "Комната обновилась. Повтори действие.", "not_ready": "Все участники должны подтвердить готовность.",
		"not_enough_coins": "Недостаточно койнов у участника.", "room_full": "Комната заполнена.", "round_started": "Дождись завершения партии.",
		"not_your_turn": "Сейчас ход другого игрока.", "capture_required": "Взятие обязательно.", "invalid_move": "Этот ход недоступен.",
		"personal_squats_required": "Сначала выполни личное задание с приседаниями.", "too_fast": "Повторение пока не подтверждено сервером.",
		"invalid_teams": "Для команд нужно 4 или 6 игроков.", "not_enough_players": "Собери нужное число участников.",
		"office_network_required": "Подключись к Wi-Fi офиса.", "presence_required": "Сначала отметь вход в офис по QR-коду.",
		"invalid_workout": "Тренировка устарела. Начни её заново.", "invalid_loan": "Запрос уже обработан или сумма недоступна.",
		"turn_finished": "Твоё решение принято. Ждём остальных.", "already_caught": "Этот баг уже пойман.", "wrong_wave": "Началась следующая волна.",
		"not_in_room": "Ты вышел из комнаты. Присоединись заново.", "invalid_mode": "Этот режим недоступен.",
		"even_stake_required": "Для 21 выбери чётную ставку: выплата за блэкджек составляет 3:2.", "host_only": "Начать игру и изменить общую ставку может создатель комнаты.",
		"no_power": "У тебя пока нет способности.", "wrong_role": "Нажимать кнопки может только оператор.", "wrong_channel": "Сначала подключи текущий канал.",
		"invalid_bet": "Ставка недоступна. Проверь сумму и дождись приёма ставок.", "invalid_card": "Эта карточка сейчас недоступна.",
		"player_unavailable": "Коллега сейчас недоступен.", "loan_not_found": "Запрос не найден.", "duplicate_operation": "Действие уже обработано. Обнови экран.",
		"room_not_found": "Комната не найдена.", "not_invited": "Тебя не приглашали в эту комнату.", "network": "Нет связи с сервером.", "server": "Ошибка сервера.",
	}.get(key, "Действие недоступно. Обнови экран.")


static func _style_check(check: CheckBox) -> void:
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(state, UiStyle.INK)
	check.add_theme_font_size_override("font_size", 12)


func _exit_tree() -> void:
	PlayTime.exercise_mode = false


func _leave() -> void:
	if await _send("leave"):
		last_room = {}
		_home()

func _casino_alive() -> bool:
	return is_instance_valid(_casino) and not _casino.is_queued_for_deletion() and _casino.get_parent() == content


func _casino_shows(data: Dictionary) -> bool:
	return _casino_alive() and _casino.room_id() == str(data.get("id", "")) and str(data.get("game", "")) in CASINO_GAMES


func _casino_subtitle() -> String:
	if _room.get("game", "") == "blackjack":
		return "Ставка %d · баланс %d" % [int(_room.get("stake", 0)), Backend.get_balance()]
	var seated: int = 0
	for p: Dictionary in _room.get("players", []):
		seated += 0 if p.get("departed", false) else 1
	return "Общий стол · за столом %d · баланс %d" % [seated, Backend.get_balance()]


## The 21 and roulette tables are built once per room and then only receive new states.
func _render_casino() -> void:
	set_title(str(TITLES.get(_room.get("game", ""), "Развлечения")))
	set_subtitle(_casino_subtitle())
	if _casino_shows(_room):
		_casino.update_room(_room)
		return
	clear()
	_casino = LoungeBlackjackView.new(_room) if _room.get("game", "") == "blackjack" else LoungeRouletteView.new(_room)
	content.add_child(_casino)
	_status = _casino.status_label
	_casino.action_requested.connect(_on_casino_action)
	_casino.leave_requested.connect(_leave)
	_casino.minimize_requested.connect(_home)
	var roulette: LoungeRouletteView = _casino as LoungeRouletteView
	if roulette != null:
		roulette.loan_requested.connect(func() -> void:
			var panel: LoungeLoans = LoungeLoans.new()
			get_parent().add_child(panel)
			panel.open()
		)


## Compound table actions: several server steps behind one button.
func _on_casino_action(action_name: String, extra: Dictionary) -> void:
	var view: LoungeCasinoView = _casino
	var ok: bool = false
	match action_name:
		"deal":
			var stake: int = int(extra.get("stake", 0))
			ok = stake == int(_room.get("stake", 0)) or await _send("stake", {"stake": stake})
			ok = ok and (bool(_my_player().get("ready", false)) or await _send("ready", {"ready": true}))
			ok = ok and await _send("start")
		"open_table":
			ok = bool(_my_player().get("ready", false)) or await _send("ready", {"ready": true})
			ok = ok and await _send("start")
		_:
			ok = await _send(action_name, extra)
	if is_instance_valid(view) and not view.is_queued_for_deletion():
		view.action_finished(action_name, ok)
