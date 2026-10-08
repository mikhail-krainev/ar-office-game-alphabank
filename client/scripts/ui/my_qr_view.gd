class_name MyQrView
extends VBoxContainer
## The player's "My QR" for the meet-a-colleague tasks. The server signs the code and it rotates every
## 10 seconds, so a colleague has to scan it from this phone: a screenshot stops working within
## seconds. The view asks for the next code when the current one rotates and shows the time left.

const RETRY_SECONDS: float = 3.0
## Never ask the server more often than this, even if it reports a code about to rotate.
const MIN_REFRESH_SECONDS: float = 1.0
const QR_MARGIN_MODULES: int = 2

var _qr_scale: int
var _code: TextureRect
var _countdown: Label
var _left: float = 0.0
var _loading: bool = false


func _init(qr_scale: int, width: float) -> void:
	_qr_scale = qr_scale
	add_theme_constant_override("separation", 2)
	_code = TextureRect.new()
	_code.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_code.custom_minimum_size = Vector2(width, 0)
	add_child(_code)
	_countdown = UiStyle.make_label(tr("MY_QR_LOADING"), 9, UiStyle.MUTED)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.custom_minimum_size = Vector2(width, 0)
	add_child(_countdown)


func _process(delta: float) -> void:
	if _loading:
		return
	_left -= delta
	if _left <= 0.0:
		_load_code()
	elif _code.texture != null:
		_countdown.text = tr("MY_QR_REFRESH") % ceili(_left)


func _load_code() -> void:
	_loading = true
	var response: ServerSession.RpcResult = await Backend.social.my_colleague_code()
	_loading = false
	if not is_inside_tree():
		return
	var code: String = str(response.data.get("code", ""))
	if not response.ok or code.is_empty():
		_countdown.text = tr("ERROR_" + (response.error if not response.error.is_empty() else "server").to_upper())
		_left = RETRY_SECONDS
		return
	var matrix: QrEncoder.QrMatrix = QrEncoder.encode(QrPayload.user(code))
	_code.texture = ImageTexture.create_from_image(matrix.to_image(_qr_scale, QR_MARGIN_MODULES))
	_left = maxf(MIN_REFRESH_SECONDS, float(response.data.get("expires_in", 0)))
