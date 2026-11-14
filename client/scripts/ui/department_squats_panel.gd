class_name DepartmentSquatsPanel
extends ModalPanel
## Additional squats become available after the personal task is completed.

var _busy: bool = false
var _status: Label
var _exercising: bool = false
var _exercise: SquatsMinigame
var _workout_session: String = ""
var _rep_sequence: int = 0
var _rep_queue: int = 0
var _sending_rep: bool = false


func _init() -> void:
	super("План отдела")
	closed.connect(_on_closed)


func open() -> void:
	show_panel()
	await _department()


func _department() -> void:
	if _busy:
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("department_squats", {"action": "get"})
	_busy = false
	if not visible:
		return
	clear()
	set_title("План отдела")
	set_subtitle("По числу сотрудников с приседаниями сегодня")
	_text("%d / %d повторений · назначено %d сотрудникам" % [int(result.get("total", 0)), int(result.get("goal", 0)), int(result.get("assigned", 0))])
	_text("Твой вклад: %d. Дополнительное приседание: 15 койнов до выполнения плана. Личного лимита нет." % int(result.get("mine", 0)))
	if result.get("can_help", false):
		_button("Начать приседания", _start_exercise, true)
	else:
		_text("Сначала выполни личное задание «Утренняя зарядка».")
	_button("Закрыть", close_panel)
	_status = _text(LoungePanel._error(str(result.get("error", ""))))


func _start_exercise() -> void:
	if _busy or _exercising:
		return
	var features: Array[PlatformBackend.Feature] = [PlatformBackend.Feature.POSE_DETECTION]
	if not PlatformServices.has_features(features) or not await PlatformServices.request_access(features):
		_status.text = "Распознавание позы недоступно."
		return
	_busy = true
	var result: Dictionary = await Backend.lounge.request("department_squats", {"action": "start"}, true)
	_busy = false
	if not visible:
		return
	if not result.get("ok", false):
		_status.text = LoungePanel._error(str(result.get("error", "")))
		return
	_workout_session = str(result.get("session", ""))
	_rep_sequence = 0
	_rep_queue = 0
	_exercising = true
	PlayTime.exercise_mode = true
	clear()
	_exercise = SquatsMinigame.new()
	_exercise.context = {"continuous": true}
	_exercise.repetition.connect(_on_rep)
	var exercise_host: Control = Control.new()
	exercise_host.custom_minimum_size = Vector2(288, 306)
	content.add_child(exercise_host)
	_exercise.scale = Vector2(0.9, 0.9)
	exercise_host.add_child(_exercise)
	_status = _text("15 койнов за повторение до выполнения плана.")
	_button("Закончить тренировку", func() -> void: _exercising = false; PlayTime.exercise_mode = false; _exercise.queue_free(); await _department())


func _on_rep() -> void:
	_rep_queue += 1
	if _sending_rep:
		return
	_sending_rep = true
	while _rep_queue > 0 and _exercising:
		_rep_queue -= 1
		var result: Dictionary = await Backend.lounge.request("department_squats", {"action": "rep", "session": _workout_session, "sequence": _rep_sequence + 1}, true)
		if result.get("ok", false):
			_rep_sequence += 1
		if is_instance_valid(_status):
			_status.text = "%d / %d · за повторение +%d" % [int(result.get("total", 0)), int(result.get("goal", 0)), int(result.get("reward", 0))] if result.get("ok", false) else LoungePanel._error(str(result.get("error", "")))
	_sending_rep = false


func _on_closed() -> void:
	_exercising = false
	PlayTime.exercise_mode = false
	if is_instance_valid(_exercise):
		_exercise.queue_free()


func _text(value: String, font_size: int = 12) -> Label:
	var label: Label = make_text(value, font_size)
	content.add_child(label)
	return label


func _button(caption: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = UiStyle.make_button(caption, primary, 12)
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	content.add_child(button)
	return button
