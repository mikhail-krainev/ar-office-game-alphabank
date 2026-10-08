class_name ColleagueBingoMinigame
extends Minigame
## "Networking bingo": meet `count` colleagues from `count` different departments (not your own) and
## scan the rotating code each of them shows in "My QR" on their phone. The card fills as people are met; the
## server rechecks the departments and that everyone is in the office today.

const DEFAULT_COUNT: int = 3
const DEFAULT_TIME_LIMIT: float = 3600.0

var _count: int = DEFAULT_COUNT
var _time_left: float = DEFAULT_TIME_LIMIT
var _met: Array[BackendModels.Colleague] = []
var _scanning: bool = false

var _slots: VBoxContainer
var _scan_button: Button
var _message: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_count = int(task.params.get("count", DEFAULT_COUNT))
		_time_left = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_status = add_status()
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.position = Vector2(8, 4)
	column.size = Vector2(AREA_SIZE.x - 16.0, 0)
	add_child(column)
	var hint: Label = UiStyle.make_label(tr("MG_BINGO_HINT") % _count, 11, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 0)
	column.add_child(hint)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 4)
	column.add_child(_slots)
	_scan_button = UiStyle.make_button(tr("MG_BINGO_SCAN_BUTTON"), true, 12)
	_scan_button.custom_minimum_size = Vector2(0, 32)
	_scan_button.pressed.connect(_scan)
	column.add_child(_scan_button)
	_message = UiStyle.make_label("", 10, UiStyle.RED)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 0)
	column.add_child(_message)
	_render_slots()


func _render_slots() -> void:
	for child: Node in _slots.get_children():
		child.queue_free()
	for index: int in _count:
		if index < _met.size():
			_slots.add_child(ColleagueCard.new(_met[index], AREA_SIZE.x - 16.0))
			continue
		var empty: PanelContainer = PanelContainer.new()
		empty.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.SHADE, 5, 6))
		empty.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 56)
		var label: Label = UiStyle.make_label(tr("MG_BINGO_SLOT") % (index + 1), 11, UiStyle.MUTED)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_child(label)
		_slots.add_child(empty)


func _scan() -> void:
	if _scanning or is_done():
		return
	_scanning = true
	var scanned: BackendModels.ColleagueResult = await scan_colleague(tr("MG_BINGO_SCAN") % (_met.size() + 1))
	_scanning = false
	_message.text = colleague_error_text(scanned) if not scanned.ok else _problem(scanned.colleague)
	if not _message.text.is_empty():
		return
	_met.append(scanned.colleague)
	_render_slots()
	if _met.size() >= _count:
		var ids: Array[String] = []
		for met: BackendModels.Colleague in _met:
			ids.append(met.user_id)
		proof["colleague_ids"] = ids
		set_score(1.0)
		finish(true)


## Early feedback for the player; the server makes the real decision.
func _problem(colleague: BackendModels.Colleague) -> String:
	var key: String = ""
	if Backend.profile != null and colleague.department == Backend.profile.department:
		key = "ERROR_SAME_DEPARTMENT"
	elif _met.any(func(met: BackendModels.Colleague) -> bool: return met.user_id == colleague.user_id):
		key = "MG_BINGO_ALREADY"
	elif _met.any(func(met: BackendModels.Colleague) -> bool: return met.department == colleague.department):
		key = "ERROR_SAME_DEPARTMENT_TWICE"
	elif not colleague.present:
		key = "ERROR_COLLEAGUE_NOT_PRESENT"
	return tr(key) if not key.is_empty() else ""


func _process(delta: float) -> void:
	super(delta)
	if is_done():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		finish(false)
		return
	@warning_ignore("integer_division")
	var total: int = ceili(_time_left)
	_status.text = "%s   %d/%d" % [tr("MG_TIME_LEFT") % ["%d:%02d" % [total / 60, total % 60]], _met.size(), _count]
