class_name MeetColleagueMinigame
extends Minigame
## Meeting someone from another department: blind coffee, "explain your job". With an assigned colleague (context["colleague"]) the card shows whom to find; otherwise
## anyone from another department who is in the office will do. Icebreaker questions help to start
## the talk. After the talk timer the colleague opens "My QR" in their game and the player scans it.
## The server checks the code, the department, the colleague's presence and the task's hours.

enum Stage { INTRO, TALK, SCAN }

const DEFAULT_TIME_LIMIT: float = 1800.0

var _stage: Stage = Stage.INTRO
var _time_left: float = DEFAULT_TIME_LIMIT
var _talk_left: float = 0.0
var _topics: Array = []
var _topic_index: int = 0

var _column: VBoxContainer
var _topic: Label
var _action: Button
var _message: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_time_left = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
		_talk_left = float(task.params.get("talk_seconds", 0))
		_topics = task.params.get("topics", [])
	_topic_index = randi() % maxi(1, _topics.size())
	_status = add_status()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 7)
	_column.position = Vector2(8, 4)
	_column.size = Vector2(AREA_SIZE.x - 16.0, 0)
	add_child(_column)
	var colleague: BackendModels.Colleague = context.get("colleague")
	_column.add_child(_wrap(tr("MG_MEET_FIND") if colleague != null else tr("MG_MEET_ANYONE"), 11, UiStyle.MUTED))
	if colleague != null:
		_column.add_child(ColleagueCard.new(colleague, AREA_SIZE.x - 16.0))
	if not _topics.is_empty():
		var card: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = UiStyle.panel(Color("#fff3ea"), 5, 7)
		style.border_width_left = 3
		style.border_color = UiStyle.RED
		card.add_theme_stylebox_override("panel", style)
		_column.add_child(card)
		var inner: VBoxContainer = VBoxContainer.new()
		card.add_child(inner)
		inner.add_child(UiStyle.make_label(tr("MG_MEET_TOPIC"), 8, UiStyle.RED))
		_topic = _wrap(str(_topics[_topic_index]), 11, UiStyle.INK, AREA_SIZE.x - 50.0)
		inner.add_child(_topic)
		var next: Button = UiStyle.make_button(tr("MG_MEET_NEXT_TOPIC"), false, 10)
		next.custom_minimum_size = Vector2(0, 24)
		next.size_flags_horizontal = Control.SIZE_SHRINK_END
		next.pressed.connect(_next_topic)
		inner.add_child(next)
	_action = UiStyle.make_button(tr("MG_MEET_START"), true, 12)
	_action.custom_minimum_size = Vector2(0, 34)
	_action.pressed.connect(_on_action)
	_column.add_child(_action)
	_message = _wrap("", 10, UiStyle.RED)
	_column.add_child(_message)


func _wrap(text: String, font_size: int, color: Color, width: float = AREA_SIZE.x - 16.0) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _next_topic() -> void:
	_topic_index = (_topic_index + 1) % _topics.size()
	_topic.text = str(_topics[_topic_index])


func _on_action() -> void:
	match _stage:
		Stage.INTRO:
			_stage = Stage.TALK
			_action.disabled = _talk_left > 0.0
		Stage.TALK:
			if _talk_left <= 0.0:
				_scan()


func _scan() -> void:
	_stage = Stage.SCAN
	var colleague: BackendModels.Colleague = context.get("colleague")
	while not is_done():
		var scanned: BackendModels.ColleagueResult = await scan_colleague(tr("MG_MEET_SCAN"))
		if not scanned.ok:
			_message.text = colleague_error_text(scanned)
			continue
		if colleague != null and scanned.colleague.user_id != colleague.user_id:
			_message.text = tr("MG_MEET_WRONG_PERSON") % colleague.name
			continue
		proof["colleague_id"] = scanned.colleague.user_id
		set_score(1.0)
		finish(true)


func _process(delta: float) -> void:
	super(delta)
	if is_done():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		finish(false)
		return
	if _stage == Stage.TALK and _talk_left > 0.0:
		_talk_left = maxf(0.0, _talk_left - delta)
		@warning_ignore("integer_division")
		var left: int = ceili(_talk_left)
		_action.text = tr("MG_MEET_TALKING") % ["%d:%02d" % [left / 60, left % 60]]
		if _talk_left <= 0.0:
			_action.disabled = false
			_action.text = tr("MG_MEET_SCAN_BUTTON")
	elif _stage == Stage.TALK:
		_action.text = tr("MG_MEET_SCAN_BUTTON")
	@warning_ignore("integer_division")
	var total: int = ceili(_time_left)
	_status.text = tr("MG_TIME_LEFT") % ["%d:%02d" % [total / 60, total % 60]]
