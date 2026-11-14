class_name LoungeLoans
extends ModalPanel
## Explicitly confirmed loans and partial repayments from the existing wallet.

var _busy: bool = false
var _amount: SpinBox
var _message: Label


func _init() -> void:
	super("Долги и переводы")


func open() -> void:
	show_panel()
	await _refresh()


func _refresh() -> void:
	if _busy:
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("lounge_loans", {"action": "list"})
	_busy = false
	if not visible:
		return
	clear()
	set_subtitle("Баланс: %d койнов · без процентов" % Backend.get_balance())
	var search: LineEdit = LineEdit.new()
	search.placeholder_text = "Имя или логин коллеги"
	search.max_length = 100
	content.add_child(search)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 1000000
	_amount.value = 100
	content.add_child(_amount)
	_button("Найти, у кого попросить", func() -> void: await _search(search.text))
	for category: String in ["pending", "borrowed", "lent", "closed"]:
		var title: String = {"pending": "Запросы", "borrowed": "Я должен", "lent": "Мне должны", "closed": "Завершённые"}[category]
		content.add_child(make_text(title, 14))
		for entry: Dictionary in result.get("loans", []):
			var is_borrower: bool = entry.get("borrower", "") == Backend.get_user_id()
			var state: String = str(entry.get("status", ""))
			var matches_category: bool = state == "pending" if category == "pending" else ((state == "accepted" and is_borrower) if category == "borrowed" else ((state == "accepted" and not is_borrower) if category == "lent" else state in ["repaid", "declined"]))
			if not matches_category:
				continue
			var id: String = str(entry.get("id", ""))
			var remaining: int = int(entry.get("amount", 0)) - int(entry.get("repaid", 0))
			content.add_child(make_text("%s · %d койнов · %s" % [entry.get("lender_name", "") if is_borrower else entry.get("borrower_name", ""), remaining, {"pending": "ожидает подтверждения", "accepted": "долг", "repaid": "погашен", "declined": "отклонён"}.get(state, state)], 11))
			if state == "pending" and not is_borrower:
				_button("Подтвердить: передать %d" % remaining, func() -> void: await _act({"action": "accept", "id": id}))
				_button("Отклонить", func() -> void: await _act({"action": "decline", "id": id}))
			elif state == "accepted" and is_borrower:
				var repayment: SpinBox = SpinBox.new()
				repayment.min_value = 1
				repayment.max_value = remaining
				repayment.value = remaining
				content.add_child(repayment)
				_button("Передать в счёт долга", func() -> void: await _act({"action": "repay", "id": id, "amount": int(repayment.value)}))
	_button("Обновить", _refresh)
	_message = make_text(LoungePanel._error(str(result.get("error", ""))), 11)
	content.add_child(_message)


func _search(term: String) -> void:
	if _busy:
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("lounge_people", {"search": term})
	_busy = false
	if not visible:
		return
	var amount: int = int(_amount.value)
	for person: Dictionary in result.get("people", []):
		var id: String = str(person.get("id", ""))
		_button("Попросить %d у %s" % [amount, person.get("name", "")], func() -> void: await _act({"action": "request", "user_id": id, "amount": amount}))


func _act(payload: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("lounge_loans", payload, true)
	_busy = false
	if result.get("ok", false):
		await _refresh()
	elif is_instance_valid(_message):
		_message.text = LoungePanel._error(str(result.get("error", "")))


func _button(caption: String, callback: Callable) -> void:
	var button: Button = UiStyle.make_button(caption, false, 11)
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	content.add_child(button)
