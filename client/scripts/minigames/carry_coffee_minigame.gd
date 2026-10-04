class_name CarryCoffeeMinigame
extends Minigame
## "Carry the coffee": scan the kitchen code, get the phone flat during a short countdown, walk to the
## meeting room holding it like a tray, press "I'm there" and scan the meeting room code. Tilting or
## jerking the phone spills coffee only while carrying: the countdown and the final scan do not count.

enum Phase { START_SCAN, COUNTDOWN, CARRY, FINISH_SCAN, DONE }

const DEFAULT_START_ROOM: String = "kitchen"
const DEFAULT_FINISH_ROOM: String = "meeting"
const DEFAULT_TIME_LIMIT: float = 180.0
const CUP_CENTER: Vector2 = Vector2(160, 150)
const CUP_RADIUS: float = 62.0
const COFFEE: Color = Color("#6b3d26")
const CREMA: Color = Color("#c08a55")
const SURFACE_SHIFT: float = 22.0
const MAX_DROPS: int = 24
## Seconds after the kitchen scan to get the phone flat before the coffee starts to count.
const COUNTDOWN_SECONDS: float = 5.0

var _phase: Phase = Phase.START_SCAN
var _meter: SpillMeter = SpillMeter.new()
var _time_left: float = DEFAULT_TIME_LIMIT
var _start_room: String = DEFAULT_START_ROOM
var _finish_room: String = DEFAULT_FINISH_ROOM
var _drops: Array[Vector3] = []
var _countdown_left: float = 0.0

var _status: Label
var _hint: Label
var _arrived: Button
var _countdown: Label


func _ready() -> void:
	if task != null:
		_start_room = str(task.params.get("start_room", DEFAULT_START_ROOM))
		_finish_room = str(task.params.get("finish_room", DEFAULT_FINISH_ROOM))
		_time_left = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_hint = add_hint(tr("MG_CARRY_HINT") % tr(_room_key(_finish_room)))
	_status = add_status()
	_arrived = UiStyle.make_button(tr("MG_CARRY_ARRIVED"), true, 12)
	_arrived.position = Vector2(AREA_SIZE.x - 150, STATUS_Y - 44)
	_arrived.custom_minimum_size = Vector2(142, 32)
	_arrived.pressed.connect(_scan_finish)
	_arrived.visible = false
	add_child(_arrived)
	_countdown = add_big_label(CUP_CENTER.y - 22.0, 36, UiStyle.RED)
	_countdown.visible = false
	await _scan_room(_start_room, tr("MG_CARRY_START") % tr(_room_key(_start_room)))
	_phase = Phase.COUNTDOWN
	_countdown_left = COUNTDOWN_SECONDS
	_countdown.visible = true


func _scan_room(room_id: String, prompt: String) -> void:
	while true:
		var payload: QrPayload = await scan_qr(prompt, QrPayload.Kind.ROOM)
		Presence.set_zone_from_qr(StringName(payload.value))
		if payload.value == room_id:
			return
		prompt = tr("MG_CARRY_WRONG_ROOM") % tr(_room_key(room_id))


func _scan_finish() -> void:
	if _phase != Phase.CARRY:
		return
	# The carry is over: the level is final, the phone can be turned to scan the door code.
	_phase = Phase.FINISH_SCAN
	_arrived.visible = false
	await _scan_room(_finish_room, tr("MG_CARRY_FINISH") % tr(_room_key(_finish_room)))
	if _phase != Phase.FINISH_SCAN:
		return
	_phase = Phase.DONE
	set_score(_meter.level)
	proof["coffee_level"] = snappedf(_meter.level, 0.01)
	finish(true)


func _process(delta: float) -> void:
	super(delta)
	if _phase == Phase.COUNTDOWN:
		_countdown_left -= delta
		_countdown.text = str(ceili(_countdown_left))
		if _countdown_left <= 0.0:
			_countdown.visible = false
			_phase = Phase.CARRY
			_arrived.visible = true
	if _phase == Phase.CARRY:
		_meter.update(PlatformServices.get_acceleration(), delta)
		_time_left -= delta
		if _meter.spilled_this_update and _drops.size() < MAX_DROPS:
			var angle: float = randf() * TAU
			_drops.append(Vector3(cos(angle), sin(angle), 1.0))
		if _meter.is_failed() or _time_left <= 0.0:
			_phase = Phase.DONE
			finish(false)
	for i: int in range(_drops.size() - 1, -1, -1):
		_drops[i].z -= delta
		if _drops[i].z <= 0.0:
			_drops.remove_at(i)
	if _phase == Phase.COUNTDOWN:
		_status.text = tr("MG_CARRY_GET_READY")
	else:
		_status.text = "%s   %s" % [tr("MG_CARRY_LEVEL") % roundi(_meter.level * 100.0), tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	queue_redraw()


func _draw() -> void:
	# Saucer, cup rim and the coffee surface that slides towards the low side.
	draw_circle(CUP_CENTER + Vector2(0, 4), CUP_RADIUS + 26.0, UiStyle.PAPER_EDGE)
	draw_circle(CUP_CENTER, CUP_RADIUS + 26.0, UiStyle.SHADE)
	draw_circle(CUP_CENTER, CUP_RADIUS + 6.0, UiStyle.INK)
	draw_circle(CUP_CENTER, CUP_RADIUS + 3.0, Color.WHITE)
	var fill: float = CUP_RADIUS * clampf(_meter.level, 0.2, 1.0)
	var shift: Vector2 = _meter.tilt_direction * SURFACE_SHIFT
	draw_circle(CUP_CENTER + shift * 0.4, fill, COFFEE)
	draw_circle(CUP_CENTER + shift * 0.6, fill * 0.55, CREMA)
	var danger: float = clampf(_meter.tilt_degrees / SpillMeter.SAFE_TILT_DEGREES, 0.0, 1.5)
	var ring: Color = UiStyle.RED if danger >= 1.0 else Color("#3f9e4a").lerp(UiStyle.HARD, danger)
	draw_arc(CUP_CENTER, CUP_RADIUS + 18.0, 0.0, TAU, 48, ring, 3.0)
	for drop: Vector3 in _drops:
		var travel: float = CUP_RADIUS + 12.0 + (1.0 - drop.z) * 30.0
		draw_circle(CUP_CENTER + Vector2(drop.x, drop.y) * travel, 3.0, Color(COFFEE, drop.z))
	# Level bar.
	var bar: Rect2 = Rect2(16, 60, 10, 180)
	draw_rect(bar.grow(2), UiStyle.INK)
	draw_rect(bar, UiStyle.PAPER)
	var failed_y: float = bar.end.y - bar.size.y * SpillMeter.FAIL_LEVEL
	var level_height: float = bar.size.y * _meter.level
	draw_rect(Rect2(bar.position.x, bar.end.y - level_height, bar.size.x, level_height), COFFEE)
	draw_rect(Rect2(bar.position.x - 4, failed_y, bar.size.x + 8, 1), UiStyle.RED)


static func _room_key(room_id: String) -> String:
	return "ROOM_" + room_id.to_upper()
