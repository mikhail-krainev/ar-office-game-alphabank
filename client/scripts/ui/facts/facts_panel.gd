class_name FactsPanel
extends ModalPanel
## Asks for today's facts right after the check-in when "Three truths, two lies" is in today's pack,
## so the player is ready before meeting the colleague. Closing it is fine: the task asks again.

var _form: FactsForm
var _message: Label
var _busy: bool = false


func _init() -> void:
	super("FACTS_TITLE")


func open(state: BackendModels.FactsState) -> void:
	show_panel()
	content.add_child(make_text(tr("FACTS_HINT"), 11, UiStyle.MUTED))
	_form = FactsForm.new(content_width, state.facts)
	content.add_child(_form)
	_message = make_text("", 10, UiStyle.RED)
	content.add_child(_message)
	var save: Button = UiStyle.make_button(tr("FACTS_SAVE"), true, 12)
	save.custom_minimum_size = Vector2(0, 34)
	save.pressed.connect(_save)
	content.add_child(save)


func _save() -> void:
	if _busy:
		return
	var problem: String = _form.problem()
	if not problem.is_empty():
		_message.text = tr(problem)
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.social.set_facts(_form.facts())
	_busy = false
	if not result.ok:
		_message.text = tr("ERROR_" + result.error.to_upper())
		return
	close_panel()
