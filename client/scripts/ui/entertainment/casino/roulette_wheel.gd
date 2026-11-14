class_name RouletteWheel
extends Control
## European wheel with a ball. While the server spins, the ball orbits the track; once the result
## arrives the wheel slows to a full stop and the ball drops, hops and settles in the winning pocket.
## `settled` fires only when both are still, so the result is announced on a motionless wheel.
## The rolling ball is heard: a loop follows its speed, and frets click while it hops into a pocket.

signal settled
signal ball_dropped

const SECTORS: Array[int] = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const WHEEL_HEIGHT: float = 176.0
const IDLE_SPEED: float = 0.35
const SPIN_SPEED: float = 2.3
const BALL_LAUNCH: float = -10.0
const BALL_CRUISE: float = -4.4
const SETTLE_TIME: float = 3.6
## Share of the settle time after which the ball lies in its pocket and rides with the wheel.
const LANDING_SHARE: float = 0.7
const SHORT_SETTLE_TIME: float = 1.6
## The stopped wheel stays on screen at least this long before the next round may turn it again.
const MIN_RESULT_TIME: float = 2.5
const TRACK: float = 0.865
const POCKET: float = 0.63
const STEP: float = TAU / 37.0
const ROLL_SOUND: String = "res://assets/audio/roulette_roll_loop.wav"
const TICK_SOUND: String = "res://assets/audio/roulette_tick.wav"
## Ball speed (rad/s) heard as the loudest and highest roll: the launch speed.
const ROLL_FULL_SPEED: float = 10.0
const ROLL_QUIET_DB: float = -28.0
const ROLL_LOUD_DB: float = -10.0
const ROLL_FADE_DB_PER_SECOND: float = 90.0
const TICK_VOICES: int = 3
## Ticks closer than this merge into one, so a fast ball does not buzz.
const TICK_MIN_INTERVAL: float = 0.06

enum Mode { IDLE, SPIN, SETTLE, STOPPED }

## Caption and seconds of the current phase, drawn left of the wheel.
var phase_caption: String = ""
var seconds_left: float = -1.0
## Newest result first, drawn right of the wheel.
var history: Array = []
## Net result of this player in the round, shown after the stop (null before).
var my_gain: Variant = null

var _mode: Mode = Mode.IDLE
var _wheel: float = 0.0
var _wheel_speed: float = IDLE_SPEED
var _ball: float = -PI / 2.0
var _ball_speed: float = 0.0
var _ball_radius: float = TRACK
var _pocket: int = -1
var _result: int = -1
var _clock: float = 0.0
var _settle_clock: float = 0.0
var _settle_time: float = SETTLE_TIME
var _a0: float = 0.0
var _w0: float = 0.0
var _b0: float = 0.0
var _travel: float = 0.0
var _landed: bool = false
var _stopped_at: float = 0.0
## A new round that arrived while the ball was still rolling: applied once the result has been seen.
var _queued_idle: Variant = null
var _roll_player: AudioStreamPlayer
var _tick_players: Array[AudioStreamPlayer] = []
var _next_tick: int = 0
var _last_tick_at: float = -1.0
var _sound_ball: float = 0.0
var _sound_fret: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(0, WHEEL_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var bus: StringName = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	_roll_player = AudioStreamPlayer.new()
	_roll_player.bus = bus
	var roll: AudioStreamWAV = load(ROLL_SOUND) as AudioStreamWAV
	if roll != null:
		roll = roll.duplicate() as AudioStreamWAV
		roll.loop_mode = AudioStreamWAV.LOOP_FORWARD
		roll.loop_begin = 0
		roll.loop_end = int(roll.get_length() * roll.mix_rate)
	_roll_player.stream = roll
	add_child(_roll_player)
	var tick: AudioStream = load(TICK_SOUND)
	for i: int in TICK_VOICES:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = bus
		player.stream = tick
		add_child(player)
		_tick_players.append(player)


func is_stopped() -> bool:
	return _mode == Mode.STOPPED


func result() -> int:
	return _result


## Slow turn between rounds; the ball keeps lying in the last pocket, if any.
func idle(last_result: int) -> void:
	if _mode == Mode.SETTLE or (_mode == Mode.STOPPED and _clock - _stopped_at < MIN_RESULT_TIME):
		_queued_idle = last_result
		return
	_queued_idle = null
	_mode = Mode.IDLE
	_result = -1
	my_gain = null
	_pocket = SECTORS.find(last_result) if last_result >= 0 else -1
	_ball_radius = POCKET if _pocket >= 0 else TRACK


func spin() -> void:
	if _mode == Mode.SPIN:
		return
	_queued_idle = null
	_mode = Mode.SPIN
	_result = -1
	my_gain = null
	_pocket = -1
	_ball_speed = BALL_LAUNCH
	_ball_radius = TRACK


## Brings wheel and ball to rest on `number` within `time_budget` seconds (the rest of the server's
## result phase), so the stop is always seen; `animate` false places them at once.
func land(number: int, animate: bool = true, time_budget: float = SETTLE_TIME) -> void:
	if _result == number and _mode in [Mode.SETTLE, Mode.STOPPED]:
		return
	_result = number
	_pocket = SECTORS.find(number)
	if not animate:
		_finish_stop()
		return
	if _mode != Mode.SPIN:
		# The spin was not seen (screen opened late): a short roll so the stop is still visible.
		_ball_speed = BALL_CRUISE
		_wheel_speed = maxf(_wheel_speed, SPIN_SPEED * 0.6)
		_settle_time = SHORT_SETTLE_TIME
	else:
		_settle_time = clampf(time_budget, SHORT_SETTLE_TIME, SETTLE_TIME)
	_mode = Mode.SETTLE
	_landed = false
	_settle_clock = 0.0
	_a0 = _wheel
	_w0 = _wheel_speed
	_b0 = _ball
	var land_time: float = _settle_time * LANDING_SHARE
	var target: float = _wheel_at(land_time) + _pocket_offset()
	# With an ease-out the start speed is 2 * travel / time: pick the lap that matches the ball speed.
	var desired: float = _ball_speed * land_time / 2.0
	var travel: float = target - _b0
	travel += roundf((desired - travel) / TAU) * TAU
	if travel > -PI:
		travel -= TAU
	_travel = travel


func _pocket_offset() -> float:
	return (_pocket + 0.5) * STEP


func _wheel_at(t: float) -> float:
	var s: float = minf(t, _settle_time)
	return _a0 + _w0 * (s - s * s / (2.0 * _settle_time))


func _finish_stop() -> void:
	_mode = Mode.STOPPED
	_wheel_speed = 0.0
	_ball_radius = POCKET
	_ball = _wheel + _pocket_offset()
	_stopped_at = _clock
	settled.emit()


func _process(delta: float) -> void:
	_clock += delta
	if _queued_idle != null and _mode == Mode.STOPPED and _clock - _stopped_at >= MIN_RESULT_TIME:
		idle(int(_queued_idle))
	match _mode:
		Mode.IDLE:
			_wheel_speed = move_toward(_wheel_speed, IDLE_SPEED, delta * 0.8)
			_wheel += _wheel_speed * delta
			if _pocket >= 0:
				_ball = _wheel + _pocket_offset()
		Mode.SPIN:
			_wheel_speed = move_toward(_wheel_speed, SPIN_SPEED, delta * 2.0)
			_wheel += _wheel_speed * delta
			_ball_speed = move_toward(_ball_speed, BALL_CRUISE, delta * 0.9)
			_ball += _ball_speed * delta
			_ball_radius = TRACK + sin(_clock * 9.0) * 0.006
		Mode.SETTLE:
			_settle(delta)
	_update_sound(delta)
	queue_redraw()


## Rolling loop while the ball is on the track; fret ticks while it hops toward the pockets.
func _update_sound(delta: float) -> void:
	var speed: float = absf(wrapf(_ball - _sound_ball, -PI, PI)) / maxf(delta, 0.001)
	_sound_ball = _ball
	var rolling: bool = _mode == Mode.SPIN or (_mode == Mode.SETTLE and not _landed)
	var hopping: bool = _mode == Mode.SETTLE and not _landed and _ball_radius < TRACK - 0.005
	_update_roll(rolling, hopping, speed, delta)
	var fret: int = floori((_ball - _wheel) / STEP)
	if hopping and fret != _sound_fret and _clock - _last_tick_at >= TICK_MIN_INTERVAL:
		_play_tick(speed)
	_sound_fret = fret


func _update_roll(rolling: bool, hopping: bool, speed: float, delta: float) -> void:
	if _roll_player == null or _roll_player.stream == null:
		return
	if rolling:
		var k: float = clampf(speed / ROLL_FULL_SPEED, 0.0, 1.0)
		# A hopping ball leaves the track: the roll gives way to the ticks.
		var on_track: float = 0.4 if hopping else 1.0
		_roll_player.volume_db = linear_to_db(db_to_linear(lerpf(ROLL_QUIET_DB, ROLL_LOUD_DB, k)) * on_track)
		_roll_player.pitch_scale = lerpf(0.7, 1.25, k)
		if not _roll_player.playing:
			_roll_player.play()
	elif _roll_player.playing:
		_roll_player.volume_db -= ROLL_FADE_DB_PER_SECOND * delta
		if _roll_player.volume_db <= ROLL_QUIET_DB - 30.0:
			_roll_player.stop()


func _play_tick(speed: float) -> void:
	if _tick_players.is_empty() or _tick_players[0].stream == null:
		return
	var player: AudioStreamPlayer = _tick_players[_next_tick]
	_next_tick = (_next_tick + 1) % _tick_players.size()
	player.pitch_scale = randf_range(0.85, 1.15)
	player.volume_db = lerpf(-16.0, -6.0, clampf(speed / ROLL_FULL_SPEED, 0.0, 1.0))
	player.play()
	_last_tick_at = _clock


func _settle(delta: float) -> void:
	_settle_clock += delta
	_wheel = _wheel_at(_settle_clock)
	_wheel_speed = _w0 * maxf(0.0, 1.0 - _settle_clock / _settle_time)
	var land_time: float = _settle_time * LANDING_SHARE
	if _settle_clock < land_time:
		var u: float = _settle_clock / land_time
		_ball = _b0 + _travel * (1.0 - (1.0 - u) * (1.0 - u))
		if u < 0.5:
			_ball_radius = TRACK
		else:
			var v: float = (u - 0.5) / 0.5
			var hop: float = absf(sin(v * PI * 3.0)) * (1.0 - v) * 0.07
			_ball_radius = lerpf(TRACK, POCKET, v * v) + hop
	else:
		if not _landed:
			_landed = true
			ball_dropped.emit()
		_ball_radius = POCKET
		_ball = _wheel + _pocket_offset()
	if _settle_clock >= _settle_time:
		_finish_stop()


func _wheel_center_radius() -> Array:
	var radius: float = floorf(minf(size.y / 2.0 - 4.0, size.x / 2.0 - 70.0))
	return [Vector2(roundf(size.x / 2.0), roundf(size.y / 2.0)), maxf(40.0, radius)]


func _draw() -> void:
	CasinoArt.draw_felt(self, Rect2(Vector2.ZERO, size))
	var geometry: Array = _wheel_center_radius()
	var c: Vector2 = geometry[0]
	var r: float = geometry[1]
	_draw_wheel(c, r)
	_draw_ball(c, r)
	_draw_sides(c, r)


func _ring_quad(c: Vector2, a: float, b: float, inner: float, outer: float) -> PackedVector2Array:
	var mid: float = (a + b) / 2.0
	return PackedVector2Array([
		c + Vector2.from_angle(a) * inner, c + Vector2.from_angle(a) * outer, c + Vector2.from_angle(mid) * outer,
		c + Vector2.from_angle(b) * outer, c + Vector2.from_angle(b) * inner, c + Vector2.from_angle(mid) * inner,
	])


func _draw_wheel(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(0, 3), r + 1, Color(0, 0, 0, 0.35))
	draw_circle(c, r, CasinoArt.WOOD_DARK)
	draw_circle(c, r - 2, CasinoArt.WOOD)
	draw_circle(c, r * 0.94, Color("#24160d"))
	draw_arc(c, r * 0.94, 0, TAU, 96, CasinoArt.BRASS_DARK, 1)
	var outer: float = r * 0.80
	var numbers: float = r * 0.70
	var floor_r: float = r * 0.56
	var font: Font = CasinoArt.font()
	var glow: float = 0.5 + 0.5 * sin((_clock - _stopped_at) * 6.0)
	for i: int in 37:
		var a: float = _wheel + i * STEP
		var b: float = a + STEP
		var color: Color = CasinoArt.pocket_color(SECTORS[i])
		draw_colored_polygon(_ring_quad(c, a, b, numbers - 1.0, outer), color)
		draw_colored_polygon(_ring_quad(c, a, b, floor_r, numbers), color.darkened(0.35))
		if _mode == Mode.STOPPED and i == _pocket:
			draw_colored_polygon(_ring_quad(c, a, b, floor_r, outer), Color(1, 0.9, 0.5, 0.35 + 0.4 * glow))
		draw_line(c + Vector2.from_angle(a) * floor_r, c + Vector2.from_angle(a) * outer, CasinoArt.BRASS_DARK, 1)
		var mid: float = a + STEP / 2.0
		var label: String = str(SECTORS[i])
		var size_px: int = 7 if r >= 70.0 else 6
		draw_set_transform(c + Vector2.from_angle(mid) * (outer + numbers) / 2.0, mid + PI / 2.0, Vector2.ONE)
		draw_string(font, Vector2(-roundf(CasinoArt.text_width(label, size_px) / 2.0), 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_arc(c, outer, 0, TAU, 96, CasinoArt.BRASS, 1)
	draw_arc(c, floor_r, 0, TAU, 96, CasinoArt.BRASS, 1)
	draw_circle(c, floor_r - 1, Color("#5a3a22"))
	draw_circle(c, r * 0.40, Color("#6d4729"))
	draw_arc(c, r * 0.40, 0, TAU, 64, Color("#835936"), 2)
	if _mode == Mode.STOPPED and _result >= 0:
		_draw_result_disc(c, r)
		return
	for k: int in 4:
		var arm: Vector2 = Vector2.from_angle(_wheel + k * PI / 2.0)
		draw_line(c + arm * 4.0, c + arm * r * 0.30, CasinoArt.BRASS, 3)
		draw_circle(c + arm * r * 0.30, 3, CasinoArt.BRASS)
	draw_circle(c, 6, CasinoArt.BRASS)
	draw_circle(c, 3, CasinoArt.BRASS_DARK)


func _draw_result_disc(c: Vector2, r: float) -> void:
	var pop: float = clampf((_clock - _stopped_at) / 0.25, 0.0, 1.0)
	var disc: float = r * 0.36 * (0.6 + 0.4 * (1.0 - pow(1.0 - pop, 3.0)))
	draw_circle(c, disc + 2, CasinoArt.BRASS)
	draw_circle(c, disc, CasinoArt.pocket_color(_result))
	CasinoArt.draw_text_centered(self, c + Vector2(0, -3), str(_result), 20 if r >= 70.0 else 16, Color.WHITE)
	CasinoArt.draw_text_centered(self, c + Vector2(0, disc * 0.58), CasinoArt.color_name(_result), 6, Color(1, 1, 1, 0.85))


func _draw_ball(c: Vector2, r: float) -> void:
	var p: Vector2 = (c + Vector2.from_angle(_ball) * r * _ball_radius).round()
	var ball_r: float = maxf(3.0, roundf(r * 0.05))
	draw_circle(p + Vector2(1, 1.5), ball_r, Color(0, 0, 0, 0.45))
	draw_circle(p, ball_r, Color("#f4f1ea"))
	draw_circle(p + Vector2(-1, -1), maxf(1.0, ball_r * 0.35), Color.WHITE)


func _draw_sides(c: Vector2, r: float) -> void:
	var left_x: float = roundf((c.x - r) / 2.0)
	if my_gain != null and _mode == Mode.STOPPED:
		var gain: int = int(my_gain)
		CasinoArt.draw_text_centered(self, Vector2(left_x, c.y - 16), "ВЫИГРЫШ" if gain > 0 else ("ПРОИГРЫШ" if gain < 0 else "ТВОЙ ИТОГ"), 7, CasinoArt.FELT_TEXT)
		CasinoArt.draw_text_centered(self, Vector2(left_x, c.y + 4), ("+%d" % gain) if gain > 0 else ("−%d" % -gain if gain < 0 else "0"), 18, CasinoArt.GOLD_TEXT if gain > 0 else Color.WHITE)
	else:
		CasinoArt.draw_text_centered(self, Vector2(left_x, c.y - 16), phase_caption, 7, CasinoArt.FELT_TEXT)
		if seconds_left >= 0.0:
			CasinoArt.draw_text_centered(self, Vector2(left_x, c.y + 4), str(ceili(seconds_left)), 22, CasinoArt.LOSE if seconds_left < 5.0 else Color.WHITE)
			CasinoArt.draw_text_centered(self, Vector2(left_x, c.y + 22), "сек", 7, CasinoArt.FELT_TEXT)
	var right_x: float = roundf(c.x + r + (size.x - c.x - r) / 2.0)
	CasinoArt.draw_text_centered(self, Vector2(right_x, 16), "ИСТОРИЯ", 7, CasinoArt.FELT_TEXT)
	# The newest entry is the result itself: it stays hidden until the ball has stopped.
	var past: Array = history.slice(1) if _mode == Mode.SETTLE else history
	var shown: int = mini(past.size(), int((size.y - 34.0) / 20.0))
	for i: int in shown:
		var number: int = int(past[i])
		var p: Vector2 = Vector2(right_x, 34 + i * 20)
		if i == 0:
			draw_circle(p, 10, CasinoArt.BRASS)
		draw_circle(p, 8, CasinoArt.pocket_color(number))
		CasinoArt.draw_text_centered(self, p, str(number), 8, Color.WHITE)
