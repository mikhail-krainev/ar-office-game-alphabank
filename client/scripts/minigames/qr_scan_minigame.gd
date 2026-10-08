class_name QrScanMinigame
extends Minigame
## Not a task: the "QR" action from the HUD. Reads any game code and hands it to the caller.
## "My QR" shows the player's own rotating code (MyQrView) for a colleague's meet-a-colleague task.

const PROOF_KEY: String = "qr"
const PROFILE_QR_SCALE: int = 5

var _profile_card: Control


func _ready() -> void:
	shows_result = false
	# Deferred calls run in order: the scan overlay first, then the button above it.
	_run_scan.call_deferred()
	_add_profile_button.call_deferred()


func _add_profile_button() -> void:
	var toggle: Button = UiStyle.make_button(tr("MY_QR_TITLE"), false, 12)
	toggle.custom_minimum_size = Vector2(120, 30)
	toggle.position = Vector2((AREA_SIZE.x - 120.0) / 2.0, STATUS_Y - 14)
	toggle.pressed.connect(_toggle_profile)
	add_child(toggle)


func _run_scan() -> void:
	var payload: QrPayload = await scan_qr(tr("QR_SCAN_HINT"), QrPayload.Kind.UNKNOWN)
	proof[PROOF_KEY] = QrPayload.make(payload.kind, payload.value)
	finish(true)


func _toggle_profile() -> void:
	if _profile_card != null:
		_profile_card.queue_free()
		_profile_card = null
		return
	_profile_card = ColorRect.new()
	(_profile_card as ColorRect).color = UiStyle.PAPER
	_profile_card.size = Vector2(AREA_SIZE.x, STATUS_Y - 20)
	add_child(_profile_card)
	var hint: Label = UiStyle.make_label(tr("MY_QR_HINT"), 11, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(AREA_SIZE.x - 16.0, 30)
	hint.position = Vector2(8, 4)
	_profile_card.add_child(hint)
	var code: MyQrView = MyQrView.new(PROFILE_QR_SCALE, AREA_SIZE.x)
	code.position = Vector2(0, 40)
	_profile_card.add_child(code)
