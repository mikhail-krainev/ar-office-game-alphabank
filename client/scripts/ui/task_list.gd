class_name TaskList
extends PanelContainer
## Today's tasks, always on screen in the top-right corner of the office HUD. A tap on an open task
## starts it right away; the header folds the list. The colour square shows the state: red open,
## green done, gold waiting for a colleague, grey skipped.

signal task_pressed(task: BackendModels.TaskInfo)

const WIDTH: float = 150.0
const ROW_HEIGHT: float = 20.0
const MARK_SIDE: float = 6.0
const DONE_COLOR: Color = Color("#3f9e4a")

## Folded or not, kept for the whole session (the office scene reloads on every lift ride).
static var _folded: bool = false

var _header: Button
var _rows: VBoxContainer
var _tasks: Array[BackendModels.TaskInfo] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.PAPER, 0.94), 5, 4))
	custom_minimum_size = Vector2(WIDTH, 0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_header = _make_row_button(UiStyle.RED, true)
	_header.pressed.connect(_toggle)
	column.add_child(_header)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 1)
	column.add_child(_rows)
	_update_header()


func set_tasks(tasks: Array[BackendModels.TaskInfo]) -> void:
	_tasks = tasks
	for child: Node in _rows.get_children():
		child.queue_free()
	for task: BackendModels.TaskInfo in tasks:
		var row: Button = _make_row_button(UiStyle.MUTED if task.is_closed() else UiStyle.INK, false)
		row.text = task.title
		row.tooltip_text = task.description
		row.pressed.connect(func() -> void: task_pressed.emit(task))
		var mark: ColorRect = ColorRect.new()
		mark.color = _state_color(task)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.size = Vector2(MARK_SIDE, MARK_SIDE)
		mark.position = Vector2(4, (ROW_HEIGHT - MARK_SIDE) / 2.0)
		row.add_child(mark)
		_rows.add_child(row)
	_update_header()


func _toggle() -> void:
	_folded = not _folded
	_update_header()


func _update_header() -> void:
	var done: int = _tasks.filter(func(task: BackendModels.TaskInfo) -> bool: return task.is_closed()).size()
	_header.text = "%s %d/%d %s" % [tr("HUD_TASKS").to_upper(), done, _tasks.size(), "▸" if _folded else "▾"]
	_rows.visible = not _folded


func _make_row_button(color: Color, header: bool) -> Button:
	var button: Button = Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(WIDTH - 8.0, ROW_HEIGHT)
	button.add_theme_font_size_override("font_size", 10 if header else 9)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)
	var padding: StyleBoxEmpty = StyleBoxEmpty.new()
	padding.content_margin_left = 2.0 if header else 14.0
	padding.content_margin_right = 2.0
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, padding)
	return button


static func _state_color(task: BackendModels.TaskInfo) -> Color:
	if task.completed:
		return DONE_COLOR
	if task.pending:
		return UiStyle.GOLD
	if task.skipped:
		return UiStyle.PAPER_EDGE
	return UiStyle.RED
