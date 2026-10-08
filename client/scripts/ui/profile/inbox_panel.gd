class_name InboxPanel
extends ModalPanel
## In-game notifications from the server: fines, a lost streak, photo confirmations and draw results.
## A colleague's joint photo is confirmed or declined right here, and a colleague's facts from "Three
## truths, two lies" are guessed here; after the guess the player's own QR is shown for the colleague.

const KIND_COLORS: Dictionary[String, Color] = {
	"penalty": UiStyle.RED,
	"streak_reset": UiStyle.HARD,
	"photo_request": Color("#3a7bd5"),
	"photo_confirmed": Color("#3f9e4a"),
	"photo_declined": UiStyle.MUTED,
	"facts_quiz": Color("#3a7bd5"),
	"facts_answered": Color("#3f9e4a"),
	"raffle_win": UiStyle.GOLD,
	"raffle_lost": UiStyle.MUTED,
}

const QUIZ_QR_SCALE: int = 4
const GUESS_RIGHT: Color = Color("#3f9e4a")

var _busy: bool = false
## Facts quiz answered in this session: its card shows the player's QR for the colleague to scan.
var _just_answered: int = -1


func _init() -> void:
	super("INBOX_TITLE")


func open() -> void:
	show_panel()
	await _reload()
	await Backend.social.mark_inbox_read()
	Notifications.poll()


func _reload() -> void:
	var items: Array[BackendModels.InboxItem] = await Backend.social.get_inbox()
	clear()
	if items.is_empty():
		content.add_child(make_text(tr("INBOX_EMPTY"), 11, UiStyle.MUTED))
	for item: BackendModels.InboxItem in items:
		content.add_child(_make_item(item))


func _make_item(item: BackendModels.InboxItem) -> Control:
	var card: PanelContainer = make_card(UiStyle.SHADE if item.read else Color("#fff3ea"), KIND_COLORS.get(item.kind, UiStyle.MUTED))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var avatar_id: String = str(item.params.get("avatar", ""))
	var text_width: float = content_width - 20.0
	if not avatar_id.is_empty():
		var avatar: AvatarView = AvatarView.new(28.0)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(avatar)
		avatar.show_avatar(avatar_id)
		text_width -= 34.0
	row.add_child(make_text(NotificationTexts.inbox_text(item), 11, UiStyle.INK, text_width))
	if item.is_facts_quiz():
		column.add_child(_make_quiz(item))
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)
	var stamp: Label = UiStyle.make_label(WorkCalendar.stamp(item.created_at), 8, UiStyle.MUTED)
	stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(stamp)
	if item.needs_answer() and not item.is_facts_quiz():
		var decline: Button = UiStyle.make_button(tr("INBOX_PHOTO_DECLINE"), false, 10)
		decline.custom_minimum_size = Vector2(0, 26)
		decline.pressed.connect(_answer.bind(item, false))
		footer.add_child(decline)
		var confirm: Button = UiStyle.make_button(tr("INBOX_PHOTO_CONFIRM"), true, 10)
		confirm.custom_minimum_size = Vector2(0, 26)
		confirm.pressed.connect(_answer.bind(item, true))
		footer.add_child(confirm)
	elif item.kind == "photo_request" or (item.is_facts_quiz() and item.state != "pending"):
		footer.add_child(UiStyle.make_label(tr("INBOX_STATE_" + item.state.to_upper()), 9, UiStyle.MUTED))
	return card


## The colleague's facts: TRUE / LIE toggles and "Answer" while pending, the result after the guess.
func _make_quiz(item: BackendModels.InboxItem) -> VBoxContainer:
	var quiz: VBoxContainer = VBoxContainer.new()
	quiz.add_theme_constant_override("separation", 3)
	var facts: Array = item.params.get("facts", []) if item.params.get("facts") is Array else []
	if item.state == "pending":
		_add_guess_form(quiz, item, facts)
	elif item.state == "answered":
		_add_guess_result(quiz, item, facts)
	return quiz


func _add_guess_form(quiz: VBoxContainer, item: BackendModels.InboxItem, facts: Array) -> void:
	quiz.add_child(make_text(tr("INBOX_FACTS_GUESS"), 9, UiStyle.MUTED))
	var toggles: Array[Button] = []
	for fact: Variant in facts:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(make_text(str(fact), 10, UiStyle.INK, content_width - FactsForm.TOGGLE_WIDTH - 24.0))
		var toggle: Button = FactsForm.make_truth_toggle(false)
		row.add_child(toggle)
		toggles.append(toggle)
		quiz.add_child(row)
	var message: Label = make_text("", 9, UiStyle.RED)
	quiz.add_child(message)
	var answer: Button = UiStyle.make_button(tr("INBOX_FACTS_ANSWER"), true, 10)
	answer.custom_minimum_size = Vector2(0, 28)
	answer.pressed.connect(_answer_quiz.bind(item, toggles, message))
	quiz.add_child(answer)


func _add_guess_result(quiz: VBoxContainer, item: BackendModels.InboxItem, facts: Array) -> void:
	var truths: Array[bool] = BackendParser.bools(item.params.get("truths"))
	var guesses: Array[bool] = BackendParser.bools(item.params.get("guesses"))
	for i: int in mini(facts.size(), mini(truths.size(), guesses.size())):
		var verdict: String = tr("FACTS_TRUE") if truths[i] else tr("FACTS_LIE")
		var color: Color = GUESS_RIGHT if guesses[i] == truths[i] else UiStyle.RED
		quiz.add_child(make_text("%s — %s" % [str(facts[i]), verdict], 10, color))
	quiz.add_child(make_text(tr("INBOX_FACTS_SCORE") % [int(item.params.get("correct", 0)), facts.size()], 10, UiStyle.INK))
	if item.id != _just_answered:
		return
	quiz.add_child(make_text(tr("INBOX_FACTS_SHOW_QR"), 10, UiStyle.MUTED))
	quiz.add_child(MyQrView.new(QUIZ_QR_SCALE, content_width - 16.0))


func _answer_quiz(item: BackendModels.InboxItem, toggles: Array[Button], message: Label) -> void:
	var guesses: Array[bool] = []
	for toggle: Button in toggles:
		guesses.append(toggle.button_pressed)
	if guesses.count(true) != FactsForm.TRUE_COUNT:
		message.text = tr("FACTS_WRONG_COUNT")
		return
	if _busy:
		return
	_busy = true
	var result: BackendModels.FactsAnswer = await Backend.social.answer_facts(item.id, guesses)
	_busy = false
	if not result.ok:
		message.text = tr("ERROR_" + result.error.to_upper())
		return
	_just_answered = item.id
	await _reload()
	Notifications.poll()


func _answer(item: BackendModels.InboxItem, confirm: bool) -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.social.respond_photo_request(item.id, confirm)
	_busy = false
	if not result.ok:
		content.add_child(make_text(tr("ERROR_" + result.error.to_upper()), 10, UiStyle.RED))
		return
	await _reload()
	Notifications.poll()
