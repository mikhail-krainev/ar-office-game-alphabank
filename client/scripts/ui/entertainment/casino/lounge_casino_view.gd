class_name LoungeCasinoView
extends VBoxContainer
## Base of the 21 and roulette screens. The view stays on screen between server polls and only
## receives new room states, so card and wheel animations run on instead of being rebuilt.
## Every action goes to the server through `action_requested`; nothing here changes money.

signal action_requested(action_name: String, extra: Dictionary)
signal leave_requested
signal minimize_requested

const BUTTON_HEIGHT: float = 38.0

var room: Dictionary = {}
var status_label: Label
var _sound: AudioStreamPlayer
var _leave_button: Button


func _init(data: Dictionary = {}) -> void:
	room = data
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_sound)


func _process(_delta: float) -> void:
	if status_label != null:
		status_label.visible = not status_label.text.is_empty()


func room_id() -> String:
	return str(room.get("id", ""))


func update_room(data: Dictionary) -> void:
	room = data
	_refresh()


## Subclasses redraw their state from `room`.
func _refresh() -> void:
	pass


func players() -> Array:
	return room.get("players", [])


func my_index() -> int:
	var list: Array = players()
	for i: int in list.size():
		if (list[i] as Dictionary).get("id", "") == Backend.get_user_id():
			return i
	return -1


func my_player() -> Dictionary:
	var index: int = my_index()
	return players()[index] if index >= 0 else {}


func is_host() -> bool:
	return room.get("host", "") == Backend.get_user_id()


func play_sound(sound_name: String) -> void:
	if _sound == null:
		return
	_sound.stream = load("res://assets/audio/%s.wav" % sound_name)
	_sound.play()


## The server answered an action this view requested; subclasses drop their "sending" state.
func action_finished(_action_name: String, _ok: bool) -> void:
	pass


func request(action_name: String, extra: Dictionary = {}) -> void:
	action_requested.emit(action_name, extra)


static func make_button(caption: String, primary: bool, callback: Callable, font_size: int = 12) -> Button:
	var button: Button = UiStyle.make_button(caption, primary, font_size)
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


static func make_row(separation: int = 6) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


## Error line plus a compact row: room code, leave, minimize.
func build_footer(extra: Array[Button] = []) -> void:
	status_label = UiStyle.make_label("", 10, UiStyle.RED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(status_label)
	var row: HBoxContainer = make_row(4)
	add_child(row)
	var code: Button = make_button("Код %s" % room_id(), false, func() -> void: PlatformServices.copy_text(room_id()), 10)
	code.tooltip_text = "Скопировать код комнаты"
	row.add_child(code)
	for button: Button in extra:
		button.add_theme_font_size_override("font_size", 10)
		row.add_child(button)
	_leave_button = make_button("Выйти", false, func() -> void: leave_requested.emit(), 10)
	row.add_child(_leave_button)
	row.add_child(make_button("Свернуть", false, func() -> void: minimize_requested.emit(), 10))
