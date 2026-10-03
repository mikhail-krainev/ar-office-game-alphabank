extends Control
## Office screen at the reception: two rotating QR codes, entry and exit. The server signs them with
## a secret only it knows and hands them out for the server's HTTP key, so a player's phone cannot
## make them. Run it on a PC or TV: `run.sh --office-screen` (the key is taken from server/.env) or
## pass --kiosk-key=<NAKAMA_HTTP_KEY> / set OFFICE_GAME_KIOSK_KEY. Every office has its own screen:
## --kiosk-office=<office id> / OFFICE_GAME_KIOSK_OFFICE (the default office when empty).

const KEY_ARGUMENT: String = "--kiosk-key="
const KEY_ENV: String = "OFFICE_GAME_KIOSK_KEY"
const OFFICE_ARGUMENT: String = "--kiosk-office="
const OFFICE_ENV: String = "OFFICE_GAME_KIOSK_OFFICE"
const RETRY_SECONDS: float = 3.0
const BACKGROUND: Color = Color("#1d1d1f")
const MARGIN: int = 24
const LOGO_HEIGHT: float = 48.0
const MARK: Texture2D = preload("res://assets/brand/alfa_mark_large.png")

var _key: String = ""
var _office: String = ""
var _margin: MarginContainer
var _entry: TextureRect
var _exit: TextureRect
var _countdown: Label
var _bar: ColorRect
var _status: Label
## Seconds the current codes stay valid (server clock), and their full period.
var _left: float = 0.0
var _period: float = 30.0
var _fetching: bool = false


func _ready() -> void:
	_key = _read_setting(KEY_ARGUMENT, KEY_ENV)
	_office = _read_setting(OFFICE_ARGUMENT, OFFICE_ENV)
	var background: ColorRect = ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_margin = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(_margin)
	# On a phone the screen has a notch; on a TV the safe rect is the whole screen.
	PlatformServices.safe_rect_changed.connect(_fit_safe_rect)
	_fit_safe_rect(PlatformServices.get_safe_rect())
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	_margin.add_child(column)
	var logo: TextureRect = TextureRect.new()
	logo.texture = MARK
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, LOGO_HEIGHT)
	column.add_child(logo)
	_entry = _add_code(column, tr("OFFICE_SCREEN_ENTRY"))
	_exit = _add_code(column, tr("OFFICE_SCREEN_EXIT"))
	_bar = ColorRect.new()
	_bar.color = UiStyle.RED
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_bar)
	_countdown = _centered_label("", 12, UiStyle.PAPER_EDGE)
	column.add_child(_countdown)
	_status = _centered_label("" if not _key.is_empty() else tr("OFFICE_SCREEN_NO_KEY"), 12, UiStyle.RED)
	column.add_child(_status)


func _add_code(column: VBoxContainer, title: String) -> TextureRect:
	column.add_child(_centered_label(title, 18, Color.WHITE))
	var code: TextureRect = TextureRect.new()
	code.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	code.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(code)
	return code


func _centered_label(text: String, size: int, color: Color) -> Label:
	var label: Label = UiStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _fit_safe_rect(rect: Rect2) -> void:
	_margin.position = rect.position
	_margin.size = rect.size


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 and not _fetching and not _key.is_empty():
		_fetch()
	var shown: float = maxf(_left, 0.0)
	_countdown.text = tr("OFFICE_SCREEN_REFRESH") % ceili(shown)
	_bar.custom_minimum_size.x = _margin.size.x * 0.7 * shown / _period


func _fetch() -> void:
	_fetching = true
	var payload: Dictionary = {} if _office.is_empty() else {"office": _office}
	var result: ServerSession.RpcResult = await Backend.server.call_rpc_with_key("kiosk_codes", _key, payload)
	_fetching = false
	if not result.ok:
		_status.text = tr("OFFICE_SCREEN_OFFLINE")
		_left = RETRY_SECONDS
		return
	_status.text = ""
	_period = maxf(1.0, float(result.data.get("period", 30)))
	_left = float(result.data.get("seconds_left", _period))
	_entry.texture = _code_texture(QrPayload.presence(str(result.data.get("entry", ""))))
	_exit.texture = _code_texture(QrPayload.checkout(str(result.data.get("exit", ""))))


## Nearest-neighbour scaling keeps the modules sharp.
func _code_texture(text: String) -> Texture2D:
	return ImageTexture.create_from_image(QrEncoder.encode(text).to_image(8, 4))


func _read_setting(argument_prefix: String, env_name: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(argument_prefix):
			return argument.trim_prefix(argument_prefix)
	return OS.get_environment(env_name)
