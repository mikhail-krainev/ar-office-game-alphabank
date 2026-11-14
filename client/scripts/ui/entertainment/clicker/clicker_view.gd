class_name ClickerView
extends VBoxContainer
## Lucky cat clicker inside the entertainment panel. Taps are shown at once and sent in batches;
## the server counts the points, the passive income and the combo, and its state always wins.

signal back_requested

const SYNC_TAPS_EVERY: float = 2.0
const SYNC_IDLE_EVERY: float = 6.0
const REFRESH_EVERY: float = 0.25
const COMBO_WINDOW: float = 2.0
const TOAST_TIME: float = 4.0
## Meows on taps: one of the variants, not more often than MEOW_GAP so fast tapping stays pleasant.
const MEOWS: Array[AudioStream] = [
	preload("res://assets/audio/meow_1.wav"),
	preload("res://assets/audio/meow_2.wav"),
	preload("res://assets/audio/meow_3.wav"),
	preload("res://assets/audio/meow_4.wav"),
]
const MEOW_GAP: float = 0.28
const TABS: Array[Array] = [["upgrades", "Улучшения"], ["gold", "Золото"], ["awards", "Достижения"], ["board", "Рейтинг"]]
const AMOUNTS: Array[Array] = [[1, "×1"], [10, "×10"], [0, "МАКС"]]
const ERRORS: Dictionary = {
	"not_enough_points": "Не хватает очков.",
	"upgrade_locked": "Это улучшение ещё не открыто.",
	"rebirth_locked": "Рубеж перерождения ещё не достигнут.",
	"presence_required": "Кот доступен только в офисе после кода входа.",
}

var _rules: ClickerRules = ClickerRules.new()
var _state: Dictionary = {}
var _cat: ClickerCat
var _tab_row: HBoxContainer
var _amount_row: HBoxContainer
var _tab_box: VBoxContainer
var _tab: String = "upgrades"
var _list: ClickerUpgradeList
var _sound: AudioStreamPlayer
var _meow: AudioStreamPlayer
var _last_meow: float = -1.0

var _seq: int = 0
var _busy: bool = false
var _queue: Array[Dictionary] = []
var _unsent_taps: int = 0
var _unsent_gain: float = 0.0
var _inflight_taps: int = 0
var _inflight_gain: float = 0.0
var _since_reply: float = 0.0
var _since_sync: float = 0.0
var _since_refresh: float = 0.0
var _toast_left: float = 0.0
var _tap_times: Array[float] = []
var _clock: float = 0.0
var _focused: bool = true
var _tab_signature: String = ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_sound.volume_db = -8.0
	add_child(_sound)
	_meow = AudioStreamPlayer.new()
	_meow.bus = _sound.bus
	_meow.volume_db = -4.0
	_meow.max_polyphony = 2
	add_child(_meow)
	_cat = ClickerCat.new(206)
	_cat.title_text = "…"
	_cat.tapped.connect(_on_tap)
	add_child(_cat)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 3)
	add_child(_tab_row)
	for tab: Array in TABS:
		var key: String = tab[0]
		var button: Button = UiStyle.make_button(str(tab[1]), false, 9)
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(func() -> void: _select_tab(key))
		_tab_row.add_child(button)
	_amount_row = HBoxContainer.new()
	_amount_row.add_theme_constant_override("separation", 3)
	add_child(_amount_row)
	for item: Array in AMOUNTS:
		var value: int = item[0]
		var button: Button = UiStyle.make_button(str(item[1]), false, 9)
		button.custom_minimum_size = Vector2(0, 26)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(func() -> void: _select_amount(value))
		_amount_row.add_child(button)
	_tab_box = VBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 4)
	add_child(_tab_box)
	var back: Button = UiStyle.make_button("К развлечениям", false, 10)
	back.custom_minimum_size.y = 34
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)
	_select_amount(1)
	_select_tab("upgrades")
	_send({"action": "get", "open": false})


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_since_sync = SYNC_IDLE_EVERY


func _process(delta: float) -> void:
	_clock += delta
	_since_reply += delta
	_since_sync += delta
	_since_refresh += delta
	while not _tap_times.is_empty() and _clock - _tap_times[0] > COMBO_WINDOW:
		_tap_times.pop_front()
	if _cat != null:
		_cat.combo = _combo()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_cat.toast_text = ""
	if _state.is_empty():
		return
	_cat.title_text = ClickerNumbers.format(_points())
	_cat.detail_text = "%s за тап · %s в сек." % [ClickerNumbers.format(float(_state.get("tap_value", 1))), ClickerNumbers.format(float(_state.get("idle_rate", 0)))]
	if _since_refresh >= REFRESH_EVERY:
		_since_refresh = 0.0
		if _list != null:
			_list.refresh(_points())
	var due: float = SYNC_TAPS_EVERY if _unsent_taps > 0 else SYNC_IDLE_EVERY
	if _focused and not _busy and (not _queue.is_empty() or _since_sync >= due):
		_flush()


## Points on screen: the server's, plus taps not yet confirmed and the passive income since then.
func _points() -> float:
	return float(_state.get("points", 0)) + _unsent_gain + _inflight_gain + float(_state.get("idle_rate", 0)) * _since_reply


func _combo() -> float:
	return _rules.combo(_tap_times.size() / COMBO_WINDOW) if not _rules.data.is_empty() else 1.0


func _on_tap(at: Vector2) -> void:
	if _state.is_empty():
		return
	_tap_times.append(_clock)
	var gain: float = float(_state.get("tap_value", 1)) * _combo()
	_unsent_taps += 1
	_unsent_gain += gain
	_cat.burst("+" + ClickerNumbers.format(gain), at)
	_play_meow()


func _play_meow() -> void:
	if _clock - _last_meow < MEOW_GAP:
		return
	_last_meow = _clock
	_meow.stream = MEOWS[randi() % MEOWS.size()]
	# A faster combo makes the cat a little more excited.
	_meow.pitch_scale = randf_range(0.92, 1.08) + (_combo() - 1.0) * 0.15
	_meow.play()


func _flush() -> void:
	var request: Dictionary = _queue.pop_front() if not _queue.is_empty() else {"action": "sync"}
	_send(request)


func _send(request: Dictionary) -> void:
	_busy = true
	_since_sync = 0.0
	var action_name: String = str(request.get("action", "sync"))
	var taps: int = 0
	if action_name != "get":
		taps = _unsent_taps
		_inflight_taps = _unsent_taps
		_inflight_gain = _unsent_gain
		_unsent_taps = 0
		_unsent_gain = 0.0
	var extra: Dictionary = request.duplicate()
	extra.erase("action")
	var result: Dictionary = await Backend.clicker.send(action_name, _seq + 1, taps, extra)
	_busy = false
	if not is_inside_tree():
		return
	if not result.has("state"):
		# Not applied (or the reply was lost): the taps go into the next request with the same seq.
		_unsent_taps += _inflight_taps
		_unsent_gain += _inflight_gain
		_inflight_taps = 0
		_inflight_gain = 0.0
		_show_toast(str(ERRORS.get(str(result.get("error", "")), "Нет связи с сервером, тапы сохранятся до ответа.")))
		return
	_inflight_taps = 0
	_inflight_gain = 0.0
	_apply(result, action_name)


func _apply(result: Dictionary, action_name: String) -> void:
	if result.has("rules"):
		_rules = ClickerRules.new(result["rules"])
	var old_gold: int = int(_state.get("gold", -1))
	_state = result["state"]
	_seq = int(_state.get("seq", _seq))
	_since_reply = 0.0
	_cat.gold = int(_state.get("gold", 0))
	var tick: Dictionary = result.get("tick", {})
	if action_name == "get" and tick.get("offline", false) and float(tick.get("passive", 0)) > 0.0:
		_show_toast("Пока тебя не было, кот намурлыкал +%s (%d мин. в офисе, половина скорости)." % [ClickerNumbers.format(float(tick["passive"])), int(float(tick.get("seconds", 0)) / 60.0)])
	for id: Variant in result.get("added", []):
		_show_toast("Достижение: %s! Доход +%d%%." % [_achievement_name(str(id)), int(float(_rules.data.get("achievement_bonus", 0.01)) * 100)])
		_play("chime")
	if not result.get("ok", true):
		_show_toast(str(ERRORS.get(str(result.get("error", "")), "Не получилось.")))
	elif action_name == "buy":
		_play("cash_register")
	elif action_name == "rebirth" and old_gold >= 0:
		_show_toast("Перерождение! Теперь у кота: %s." % _rules.gold_name(_cat.gold))
		_play("shop_bell")
	_render_tab()


func _achievement_name(id: String) -> String:
	for item: Variant in _rules.achievements():
		if (item as Dictionary).get("id", "") == id:
			return str((item as Dictionary).get("name", id))
	return id


func _show_toast(text: String) -> void:
	_cat.toast_text = text
	_toast_left = TOAST_TIME


func _play(sound_name: String) -> void:
	_sound.stream = load("res://assets/audio/%s.wav" % sound_name)
	_sound.pitch_scale = 1.0
	_sound.play()


func _select_tab(key: String) -> void:
	_tab = key
	for i: int in TABS.size():
		(_tab_row.get_child(i) as Button).set_pressed_no_signal(TABS[i][0] == key)
	_amount_row.visible = key == "upgrades"
	_tab_signature = ""
	_render_tab()


func _select_amount(value: int) -> void:
	for i: int in AMOUNTS.size():
		(_amount_row.get_child(i) as Button).set_pressed_no_signal(AMOUNTS[i][0] == value)
	if _list != null:
		_list.amount = value
		_list.show_state(_rules, _state, _points())
	set_meta("amount", value)


## Redraws the open tab; the upgrade lists keep their rows and only follow the state.
func _render_tab() -> void:
	if _tab_box == null or _state.is_empty():
		return
	var signature: String = _tab
	if _tab == "gold":
		signature += "|%d|%d|%d" % [int(_state.get("gold", 0)), int(_state.get("rebirth_gold", 0)), int(log(maxf(1.0, float(_state.get("run", 0)))) * 10.0)]
	elif _tab == "awards":
		signature += "|%d|%d" % [(_state.get("achievements", []) as Array).size(), int(float(_state.get("taps", 0)) / 100.0)]
	if signature == _tab_signature and _tab in ["gold", "awards", "board"]:
		return
	if _tab == "upgrades" and _list != null and _tab_signature == _tab:
		_list.show_state(_rules, _state, _points())
		return
	_tab_signature = signature
	for child: Node in _tab_box.get_children():
		_tab_box.remove_child(child)
		child.queue_free()
	_list = null
	match _tab:
		"upgrades":
			_list = ClickerUpgradeList.new()
			_list.amount = int(get_meta("amount", 1))
			_list.buy_requested.connect(func(kind: String, tier: int, count: int) -> void: _queue.append({"action": "buy", "kind": kind, "tier": tier, "count": count}))
			_tab_box.add_child(_list)
			_list.show_state(_rules, _state, _points())
		"gold":
			ClickerProgress.build_rebirth(_tab_box, _rules, _state, func() -> void: _queue.append({"action": "rebirth"}))
		"awards":
			ClickerProgress.build_achievements(_tab_box, _rules, _state)
		"board":
			_tab_box.add_child(ClickerBoard.new(_rules))
