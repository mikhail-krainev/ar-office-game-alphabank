class_name ChoicePrompt
extends CanvasLayer
## Bottom card with a question and two answers. ask() resolves with true for the first answer;
## choose() also tells a tap outside the card (DISMISSED) from the second answer.

signal _answered(choice: int)

enum Choice { DISMISSED, FIRST, SECOND }

const MARGIN: float = 10.0

var _card: PanelContainer
var _question: Label
var _yes: Button
var _no: Button


func _ready() -> void:
	layer = 45
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dimmer: ColorRect = UiStyle.make_dimmer()
	dimmer.gui_input.connect(func(event: InputEvent) -> void:
		if Minigame.press_position(event) != null:
			_answered.emit(Choice.DISMISSED)
	)
	root.add_child(dimmer)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 12))
	_card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_card.add_child(column)
	_question = UiStyle.make_label("", 14)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_question)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	_no = UiStyle.make_button("", false, 13)
	_yes = UiStyle.make_button("", true, 13)
	for button: Button in [_no, _yes]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 38)
		buttons.add_child(button)
	_yes.pressed.connect(func() -> void: _answered.emit(Choice.FIRST))
	_no.pressed.connect(func() -> void: _answered.emit(Choice.SECOND))


func is_open() -> bool:
	return visible


func ask(question: String, yes_text: String, no_text: String) -> bool:
	return await choose(question, yes_text, no_text) == Choice.FIRST


## The first answer is the primary button.
func choose(question: String, yes_text: String, no_text: String) -> Choice:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	_question.text = question
	_question.custom_minimum_size = Vector2(safe.size.x - MARGIN * 2.0 - 24.0, 0)
	_yes.text = yes_text
	_no.text = no_text
	var viewport: Vector2 = _card.get_parent_area_size()
	_card.offset_left = safe.position.x + MARGIN
	_card.offset_right = safe.end.x - viewport.x - MARGIN
	_card.offset_bottom = safe.end.y - viewport.y - MARGIN
	_card.offset_top = _card.offset_bottom
	visible = true
	var answer: Choice = await _answered
	visible = false
	return answer
