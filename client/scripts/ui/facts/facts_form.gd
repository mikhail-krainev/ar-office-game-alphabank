class_name FactsForm
extends VBoxContainer
## Five facts for "Three truths, two lies": a text field and a TRUE / LIE toggle per fact. The counter
## shows how many are marked true; the form is complete with five texts and exactly three truths.
## The server checks the same rules again (server/modules/facts.go).

const FACTS_COUNT: int = 5
const TRUE_COUNT: int = 3
const MAX_LENGTH: int = 100
const ROW_HEIGHT: float = 30.0
const TOGGLE_WIDTH: float = 66.0

var _fields: Array[LineEdit] = []
var _toggles: Array[Button] = []
var _counter: Label


## `draft`: earlier facts to edit; empty starts with three truths and two lies.
func _init(width: float, draft: Array[BackendModels.Fact] = []) -> void:
	custom_minimum_size = Vector2(width, 0)
	add_theme_constant_override("separation", 4)
	for i: int in FACTS_COUNT:
		var fact: BackendModels.Fact = draft[i] if i < draft.size() else BackendModels.Fact.new("", i < TRUE_COUNT)
		add_child(_make_row(i, fact))
	_counter = UiStyle.make_label("", 9, UiStyle.MUTED)
	add_child(_counter)
	_update_counter()


func _make_row(index: int, fact: BackendModels.Fact) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var field: LineEdit = LineEdit.new()
	field.max_length = MAX_LENGTH
	field.text = fact.text
	field.placeholder_text = tr("FACTS_PLACEHOLDER") % (index + 1)
	field.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", 10)
	row.add_child(field)
	_fields.append(field)
	var toggle: Button = make_truth_toggle(fact.is_true)
	toggle.toggled.connect(func(_on: bool) -> void: _update_counter())
	row.add_child(toggle)
	_toggles.append(toggle)
	return row


## TRUE / LIE switch: pressed means "true". Shared with the colleague's guess in the inbox.
static func make_truth_toggle(is_true: bool) -> Button:
	var toggle: Button = UiStyle.make_button("", false, 9)
	toggle.toggle_mode = true
	toggle.custom_minimum_size = Vector2(TOGGLE_WIDTH, ROW_HEIGHT - 4.0)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(_style_toggle.bind(toggle))
	toggle.set_pressed_no_signal(is_true)
	_style_toggle(is_true, toggle)
	return toggle


static func _style_toggle(is_true: bool, toggle: Button) -> void:
	toggle.text = TranslationServer.translate("FACTS_TRUE" if is_true else "FACTS_LIE")
	var color: Color = Color("#3f9e4a") if is_true else UiStyle.RED
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(state, color)


func facts() -> Array[BackendModels.Fact]:
	var result: Array[BackendModels.Fact] = []
	for i: int in FACTS_COUNT:
		result.append(BackendModels.Fact.new(_fields[i].text.strip_edges(), _toggles[i].button_pressed))
	return result


## Translation key of what is still missing, or "" when the facts can be saved.
func problem() -> String:
	for field: LineEdit in _fields:
		if field.text.strip_edges().is_empty():
			return "FACTS_EMPTY"
	return "" if _truths() == TRUE_COUNT else "FACTS_WRONG_COUNT"


func _truths() -> int:
	return _toggles.filter(func(toggle: Button) -> bool: return toggle.button_pressed).size()


func _update_counter() -> void:
	_counter.text = tr("FACTS_COUNTER") % [_truths(), TRUE_COUNT, FACTS_COUNT - _truths(), FACTS_COUNT - TRUE_COUNT]
	_counter.label_settings.font_color = UiStyle.MUTED if _truths() == TRUE_COUNT else UiStyle.RED
