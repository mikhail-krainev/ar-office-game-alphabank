class_name TwoTruthsMinigame
extends Minigame
## "Three truths, two lies". The player writes five facts about themselves (or keeps the ones written
## after the check-in), finds the colleague the server assigned (context["colleague"]) and sends them
## the facts. The colleague marks the true ones in their inbox. Then the player scans the colleague's
## "My QR". The server checks that the colleague has answered and scores how well they were fooled.
## Closing the game is safe: the next start goes straight to the step the player stopped at.

const DEFAULT_TIME_LIMIT: float = 3600.0

var _time_left: float = DEFAULT_TIME_LIMIT
var _busy: bool = false

var _column: VBoxContainer
var _message: Label
var _status: Label


func _ready() -> void:
	if task != null:
		_time_left = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_status = add_status()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	_column.position = Vector2(8, 4)
	_column.size = Vector2(AREA_SIZE.x - 16.0, 0)
	add_child(_column)
	_load_facts()


func _colleague() -> BackendModels.Colleague:
	return context.get("colleague")


func _load_facts() -> void:
	_clear()
	_column.add_child(_wrap(tr("MG_FACTS_LOADING"), 11, UiStyle.MUTED))
	var state: BackendModels.FactsState = await Backend.social.get_facts()
	if is_done():
		return
	if not state.ok:
		_message.text = tr("ERROR_" + state.error.to_upper())
		return
	if state.written_today:
		_show_send()
	else:
		_show_write(state.facts)


func _show_write(draft: Array[BackendModels.Fact]) -> void:
	_clear()
	_column.add_child(_wrap(tr("MG_FACTS_WRITE"), 10, UiStyle.MUTED))
	var form: FactsForm = FactsForm.new(AREA_SIZE.x - 16.0, draft)
	_column.add_child(form)
	_add_button(tr("FACTS_SAVE"), true).pressed.connect(_save.bind(form))
	_column.move_child(_message, -1)


func _save(form: FactsForm) -> void:
	var problem: String = form.problem()
	if not problem.is_empty():
		_message.text = tr(problem)
		return
	if _busy:
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.social.set_facts(form.facts())
	_busy = false
	# Locked facts were already sent to the colleague: carry on with them.
	if result.ok or result.error == "facts_locked":
		_show_send()
	elif not is_done():
		_message.text = tr("ERROR_" + result.error.to_upper())


func _show_send() -> void:
	_clear()
	_column.add_child(_wrap(tr("MG_FACTS_FIND"), 11, UiStyle.MUTED))
	if _colleague() != null:
		_column.add_child(ColleagueCard.new(_colleague(), AREA_SIZE.x - 16.0))
	_add_button(tr("MG_FACTS_SEND"), true).pressed.connect(_send)
	_add_button(tr("MG_FACTS_EDIT"), false).pressed.connect(_edit)
	_column.move_child(_message, -1)


func _edit() -> void:
	if _busy:
		return
	_busy = true
	var state: BackendModels.FactsState = await Backend.social.get_facts()
	_busy = false
	if not is_done():
		_show_write(state.facts)


func _send() -> void:
	if _busy:
		return
	_busy = true
	var sent: BackendModels.FactsSent = await Backend.social.send_facts(task.id if task != null else "")
	_busy = false
	if is_done():
		return
	if not sent.ok:
		_message.text = tr("ERROR_" + sent.error.to_upper())
		return
	_show_scan(sent.answered)


func _show_scan(answered: bool) -> void:
	_clear()
	var colleague_name: String = _colleague().name if _colleague() != null else ""
	_column.add_child(_wrap(tr("MG_FACTS_WAIT") % colleague_name, 11, UiStyle.INK))
	_add_button(tr("MG_MEET_SCAN_BUTTON"), true).pressed.connect(_check_and_scan)
	_column.move_child(_message, -1)
	_message.text = tr("MG_FACTS_ANSWERED") % colleague_name if answered else ""


## The QR only counts after the colleague's guess, so the server is asked first.
func _check_and_scan() -> void:
	if _busy:
		return
	_busy = true
	var sent: BackendModels.FactsSent = await Backend.social.send_facts(task.id if task != null else "")
	_busy = false
	if is_done():
		return
	if not sent.ok:
		_message.text = tr("ERROR_" + sent.error.to_upper())
		return
	if not sent.answered:
		_message.text = tr("ERROR_FACTS_NOT_ANSWERED")
		return
	await _scan()


func _scan() -> void:
	var colleague: BackendModels.Colleague = _colleague()
	while not is_done():
		var scanned: BackendModels.ColleagueResult = await scan_colleague(tr("MG_MEET_SCAN"))
		if not scanned.ok:
			_message.text = colleague_error_text(scanned)
			continue
		if colleague != null and scanned.colleague.user_id != colleague.user_id:
			_message.text = tr("MG_MEET_WRONG_PERSON") % colleague.name
			continue
		proof["colleague_id"] = scanned.colleague.user_id
		finish(true)


func _clear() -> void:
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_message = _wrap("", 10, UiStyle.RED)
	_column.add_child(_message)


func _add_button(text: String, primary: bool) -> Button:
	var button: Button = UiStyle.make_button(text, primary, 12 if primary else 10)
	button.custom_minimum_size = Vector2(0, 34 if primary else 26)
	_column.add_child(button)
	return button


func _wrap(text: String, font_size: int, color: Color) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(AREA_SIZE.x - 16.0, 0)
	return label


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
	_status.text = tr("MG_TIME_LEFT") % ["%d:%02d" % [total / 60, total % 60]]
