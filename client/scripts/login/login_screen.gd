extends Control
## First screen of the game. With a saved session (it lives a week) the player goes straight in;
## otherwise they sign in with the username and password the admin issued. There is no sign-up:
## wrong credentials send the player to the admin. A player who must rest or is locked for the day
## by the play-time limit (PlayTime) waits on that screen first.

const NEXT_SCENE: String = "res://scenes/intro/morning_intro.tscn"
const BACKGROUND: Color = Color("#1d1d1f")
const FIELD_BG: Color = Color("#2b2a2e")
const MARK: Texture2D = preload("res://assets/brand/alfa_mark_large.png")
const MARGIN: int = 24
const FIELD_HEIGHT: float = 34.0
const ERROR_KEYS: Dictionary[String, String] = {
	ServerSession.ERROR_INVALID_CREDENTIALS: "LOGIN_ERROR_CREDENTIALS",
	ServerSession.ERROR_BLOCKED: "LOGIN_ERROR_BLOCKED",
	ServerSession.ERROR_NETWORK: "LOGIN_ERROR_NETWORK",
	"not_player": "LOGIN_ERROR_NOT_PLAYER",
}

var _form: VBoxContainer
var _username: LineEdit
var _password: LineEdit
var _submit: Button
var _message: Label
var _busy: bool = false


func _ready() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	_form = _build_form()
	margin.add_child(_form)
	await _enter()


## Saved session first; the form appears only when the player has to sign in.
func _enter() -> void:
	_set_busy(true, tr("LOGIN_CONNECTING"))
	if Backend.server.restore():
		var error: String = await Backend.load_account()
		if error.is_empty():
			_go_next()
			return
		if error == ServerSession.ERROR_NETWORK:
			_show_error(error)
			_set_busy(false)
			return
		await Backend.server.sign_out()
	_set_busy(false, tr("LOGIN_HINT"))
	_username.grab_focus()


func _build_form() -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	var logo: TextureRect = TextureRect.new()
	logo.texture = MARK
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size = Vector2(0, 48)
	column.add_child(logo)
	var title: Label = UiStyle.make_label(tr("LOGIN_TITLE"), 16, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_username = _make_field(tr("LOGIN_USERNAME"), false)
	_username.text_submitted.connect(func(_text: String) -> void: _password.grab_focus())
	column.add_child(_username)
	_password = _make_field(tr("LOGIN_PASSWORD"), true)
	_password.text_submitted.connect(func(_text: String) -> void: _on_submit())
	column.add_child(_password)
	_submit = UiStyle.make_button(tr("LOGIN_SUBMIT"), true, 12)
	_submit.custom_minimum_size = Vector2(0, FIELD_HEIGHT)
	_submit.pressed.connect(_on_submit)
	column.add_child(_submit)
	_message = UiStyle.make_label("", 10, UiStyle.PAPER_EDGE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	return column


func _make_field(placeholder: String, secret: bool) -> LineEdit:
	var field: LineEdit = LineEdit.new()
	field.placeholder_text = placeholder
	field.secret = secret
	field.custom_minimum_size = Vector2(0, FIELD_HEIGHT)
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
	field.add_theme_font_size_override("font_size", 12)
	field.add_theme_color_override("font_color", Color.WHITE)
	field.add_theme_color_override("font_placeholder_color", UiStyle.MUTED)
	var box: StyleBoxFlat = UiStyle.panel(FIELD_BG, 5, 8)
	box.border_color = UiStyle.MUTED
	field.add_theme_stylebox_override("normal", box)
	var focus: StyleBoxFlat = box.duplicate() as StyleBoxFlat
	focus.border_color = UiStyle.RED
	focus.set_border_width_all(1)
	field.add_theme_stylebox_override("focus", focus)
	return field


func _on_submit() -> void:
	if _busy:
		return
	if _username.text.strip_edges().is_empty() or _password.text.is_empty():
		_show_error(ServerSession.ERROR_INVALID_CREDENTIALS)
		return
	_set_busy(true, tr("LOGIN_CONNECTING"))
	var error: String = await Backend.server.sign_in(_username.text, _password.text)
	if error.is_empty():
		error = await Backend.load_account()
		if error.is_empty():
			_go_next()
			return
		await Backend.server.sign_out()
	_password.clear()
	_set_busy(false)
	_show_error(error)


func _show_error(error: String) -> void:
	_message.text = tr(ERROR_KEYS.get(error, "LOGIN_ERROR_SERVER"))
	_message.label_settings = UiStyle.label(10, UiStyle.RED)


func _set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	_username.editable = not busy
	_password.editable = not busy
	_submit.disabled = busy
	if not message.is_empty():
		_message.text = message
		_message.label_settings = UiStyle.label(10, UiStyle.PAPER_EDGE)


func _go_next() -> void:
	await PlayTime.wait_until_allowed()
	get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
