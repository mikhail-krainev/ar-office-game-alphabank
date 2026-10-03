class_name TaskPanel
extends CanvasLayer
## Daily task list: the check-in and the player's pack for today. Every open task has a marker on
## the map; "Go" walks there and starts it on arrival. Hard tasks show a difficulty tag with the
## reward multiplier; skippable ones have a "Skip" button. During the break between tasks and
## outside the task hours (Backend.task_schedule) the tasks are locked, with the reason on top.

signal go_requested(task: BackendModels.TaskInfo)
signal skip_requested(task: BackendModels.TaskInfo)

const COIN_SHEET: Texture2D = preload("res://assets/ui/alfa_coin.png")
const SIDE_MARGIN: float = 12.0

var _panel: PanelContainer
var _subtitle: Label
var _notice: Label
var _tasks: Array[BackendModels.TaskInfo] = []
var _player_cell: Vector2i
var _profile: BackendModels.Profile
## Lock text the list was built with; the list is rebuilt when it changes (the countdown ticks).
var _lock_text: String = ""
var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	layer = 20
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dimmer: ColorRect = UiStyle.make_dimmer()
	dimmer.gui_input.connect(_on_dimmer_input)
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
	column.add_child(header)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	header.add_child(titles)
	titles.add_child(UiStyle.make_label(tr("TASKS_TITLE"), 16))
	_subtitle = UiStyle.make_label("", 10, UiStyle.RED)
	titles.add_child(_subtitle)
	_notice = UiStyle.make_label("", 9, UiStyle.MUTED)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_notice)
	var close: Button = UiStyle.make_button("✕", false, 14)
	close.custom_minimum_size = Vector2(34, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_panel)
	header.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	_scroll.add_child(_list)


func is_open() -> bool:
	return visible


func open(tasks: Array[BackendModels.TaskInfo], player_cell: Vector2i, profile: BackendModels.Profile) -> void:
	_tasks = tasks
	_player_cell = player_cell
	_profile = profile
	_rebuild()
	visible = true


func _process(_delta: float) -> void:
	if visible and lock_text() != _lock_text:
		_rebuild()


## Why tasks cannot start now, for the player: "" when they can.
static func lock_text() -> String:
	var schedule: BackendModels.TaskSchedule = Backend.task_schedule
	match schedule.lock_reason():
		"outside_task_window":
			return TranslationServer.translate("TASKS_LOCK_WINDOW") % [schedule.window_start, schedule.window_end]
		"task_cooldown":
			return TranslationServer.translate("TASKS_LOCK_COOLDOWN") % TimeText.short_minutes(schedule.cooldown_left())
	return ""


func _rebuild() -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var width: float = safe.size.x - SIDE_MARGIN * 2.0
	_panel.custom_minimum_size = Vector2(width, 0)
	_scroll.custom_minimum_size = Vector2(0, minf(430.0, safe.size.y - 160.0))
	_subtitle.text = tr("TASKS_STREAK") % [_profile.streak_days, "%.1f" % _profile.multiplier]
	_lock_text = lock_text()
	_notice.custom_minimum_size = Vector2(width - 70.0, 0)
	_notice.text = _pack_text()
	if not _lock_text.is_empty():
		_notice.text += "\n" + _lock_text
	for child: Node in _list.get_children():
		child.queue_free()
	for task: BackendModels.TaskInfo in _tasks:
		_list.add_child(_make_row(task, task.spot == _player_cell, width - 24.0))


func _pack_text() -> String:
	var count: int = _tasks.filter(func(task: BackendModels.TaskInfo) -> bool: return not task.is_check_in()).size()
	if count == 0:
		return tr("TASKS_NONE_TODAY")
	var cooldown: int = Backend.task_schedule.cooldown_minutes
	if cooldown <= 0:
		return tr("TASKS_PACK_INFO_NO_PAUSE") % count
	return tr("TASKS_PACK_INFO") % [count, TimeText.short_minutes(cooldown * 60)]


func close_panel() -> void:
	visible = false


func _make_row(task: BackendModels.TaskInfo, at_spot: bool, width: float) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.SHADE, 5, 7))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var closed: bool = task.is_closed()
	var can_skip: bool = task.skippable and not closed
	if task.difficulty != "normal" or can_skip:
		var tags: HBoxContainer = HBoxContainer.new()
		tags.add_theme_constant_override("separation", 6)
		column.add_child(tags)
		if task.difficulty != "normal":
			var badge: PanelContainer = UiStyle.make_difficulty_badge(task.difficulty, task.difficulty_multiplier)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tags.add_child(badge)
		var spacer: Control = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tags.add_child(spacer)
		if can_skip:
			var skip: Button = UiStyle.make_button(tr("TASK_SKIP"), false, 10)
			skip.custom_minimum_size = Vector2(0, 24)
			skip.pressed.connect(func() -> void: skip_requested.emit(task))
			tags.add_child(skip)

	var title: Label = UiStyle.make_label(task.title, 12, UiStyle.MUTED if closed else UiStyle.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(width - 16.0, 0)
	column.add_child(title)
	var description: Label = UiStyle.make_label(task.description, 9, UiStyle.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(width - 16.0, 0)
	column.add_child(description)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)
	var place: String = tr(_room_key(task.room))
	if task.floor_id != OfficeFloors.current:
		place += " · " + tr("FLOOR_SHORT") % OfficeFloors.NUMBERS.get(task.floor_id, 0)
	var room: Label = UiStyle.make_label("▸ " + place, 9, UiStyle.RED)
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(room)
	var coin: TextureRect = TextureRect.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = COIN_SHEET
	atlas.region = Rect2(0, 0, 16, 16)
	coin.texture = atlas
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(coin)
	var reward: Label = UiStyle.make_label("+%d" % task.reward, 12)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(reward)

	var button: Button
	var schedule: BackendModels.TaskSchedule = Backend.task_schedule
	var lock: String = "" if task.is_check_in() else schedule.lock_reason()
	if closed:
		var state_key: String = "TASK_DONE" if task.completed else ("TASK_PENDING" if task.pending else "TASK_SKIPPED")
		button = UiStyle.make_button(tr(state_key), false, 12)
		button.disabled = true
	elif lock == "task_cooldown":
		button = UiStyle.make_button(tr("TASK_LOCKED_COOLDOWN") % TimeText.short_minutes(schedule.cooldown_left()), false, 10)
		button.disabled = true
	elif lock == "outside_task_window":
		button = UiStyle.make_button(tr("TASK_LOCKED_WINDOW") % schedule.window_start, false, 10)
		button.disabled = true
	else:
		button = UiStyle.make_button(tr("TASK_START") if at_spot else tr("TASK_GO"), true, 12)
		button.pressed.connect(func() -> void: go_requested.emit(task))
	button.custom_minimum_size = Vector2(78, 30)
	footer.add_child(button)
	return card


func _room_key(room_id: StringName) -> String:
	var room: MapLayout.Room = OfficeFloors.find_room(room_id)
	return room.name_key if room != null else String(room_id)


func _on_dimmer_input(event: InputEvent) -> void:
	if Minigame.press_position(event) != null:
		close_panel()
