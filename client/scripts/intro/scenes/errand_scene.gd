class_name ErrandScene
extends IntroScene
## A stop on the way (CommutePlan picks one): the car pulls up in front of a place, the player goes
## in, comes back out with something in hand after a while, gets in and drives on. Subclasses give
## the background, the door, the carried item and their own details. Light follows the clock and
## the evening; the day's rain (DayConditions) falls here too.

const GROUND: float = 157.0
const CURB_Y: float = 148.0
const DOOR_Y: float = 134.0
const CAR_FROM: float = -150.0
const NIGHT: Color = Color(0.36, 0.38, 0.6)
const PEOPLE_NIGHT: Color = Color(0.68, 0.7, 0.88)
const WINDOW_GLOW: Color = Color(1.0, 0.84, 0.52)
const EVENING_DARKNESS: float = 0.75
const PASSER_LOOKS: Array[String] = ["anna", "sergey", "olga", "igor", "reception"]
const PASSER_SPEED: float = 22.0
## Timeline, seconds from the start of the shot.
const PARK_TIME: float = 1.4
const OUT_TIME: float = 1.7
const DRIVE_DELAY: float = 0.5
const ACCELERATION: float = 380.0
const WALK_SPEED: float = 90.0

enum Item { NONE, CUP, BAG, BOX }

var _car: VehicleSprite
var _car_id: String
var _player: CharacterSprite
var _passer: CharacterSprite
var _passer_dir: float = 1.0
var _darkness: float = 0.0
var _raining: bool = false
var _carrying: Item = Item.NONE
var _inside: bool = false
var _back_in_car: bool = false
var _driving: bool = false
var _sounds_played: Dictionary[String, bool] = {}


## Background id in IntroArt.IMAGES.
func _background() -> String:
	return ""


## Where the player enters, on the sidewalk.
func _door() -> Vector2:
	return Vector2(90, DOOR_Y)


func _car_x() -> float:
	return 164.0


## Seconds the player spends inside.
func _inside_time() -> float:
	return 1.4


func _item() -> Item:
	return Item.NONE


## Shop windows that glow when it is dark, in stage coordinates.
func _glow_rects() -> Array[Rect2]:
	return []


## Ambience loop heard through the open door; empty for none.
func _inside_loop() -> String:
	return ""


func _door_sound() -> String:
	return "shop_bell"


## Called when the player steps inside and when they come back out.
func _on_enter() -> void:
	pass


func _on_exit() -> void:
	pass


## Bubble over the door while the player is inside, e.g. "20 minutes later".
func _inside_text() -> String:
	return ""


## Scene details drawn over the background and under the characters.
func _draw_details(_canvas: CanvasItem) -> void:
	pass


## Seconds between getting out of the car and walking to the door (refuelling at the pump).
func _pre_door_time() -> float:
	return 0.0


## Where the walk to the door starts: the car door, or the pump.
func _walk_from() -> Vector2:
	return _car_door()


## Animates the player between getting out and walking to the door.
func _update_before_door() -> void:
	pass


func _walk_start() -> float:
	return OUT_TIME + 0.2 + _pre_door_time()


func _walk_out_time() -> float:
	return _walk_start() + _walk_seconds()


func _back_time() -> float:
	return _walk_out_time() + _inside_time()


func _in_car_time() -> float:
	return _back_time() + 0.2 + _walk_seconds()


func get_duration() -> float:
	return _in_car_time() + DRIVE_DELAY + 1.0


func _walk_seconds() -> float:
	return clampf(_walk_from().distance_to(_door()) / WALK_SPEED, 0.8, 1.4)


func _car_door() -> Vector2:
	return Vector2(_car_x() + VehicleCatalog.door_x(_car_id), CURB_Y)


func _curb() -> Vector2:
	return Vector2(_door().x + 22.0, CURB_Y)


func begin() -> void:
	_car_id = VehicleCatalog.player_car(intro.car_id)
	_darkness = maxf(DayConditions.darkness(), EVENING_DARKNESS if intro.evening else 0.0)
	_raining = DayConditions.is_raining()
	var background: Sprite2D = sprite(_background())
	background.modulate = Color.WHITE.lerp(NIGHT, _darkness)
	layer(_draw_glow)
	layer(_draw_details)
	_passer_dir = 1.0 if randf() < 0.5 else -1.0
	var passer_x: float = -20.0 if _passer_dir > 0.0 else IntroArt.STAGE.x + 20.0
	_passer = character(PASSER_LOOKS.pick_random(), Vector2(passer_x, DOOR_Y + 2), Vector2(_passer_dir, 0))
	_passer.modulate = Color.WHITE.lerp(PEOPLE_NIGHT, _darkness)
	_player = character(CharacterSprite.PLAYER_ID, _car_door(), Vector2.LEFT)
	_player.modulate = _passer.modulate
	_player.visible = false
	layer(_draw_item)
	_car = vehicle(VehicleCatalog.with_driver(_car_id), Vector2(CAR_FROM, GROUND))
	_car.modulate = Color.WHITE.lerp(PEOPLE_NIGHT, _darkness)
	_car.lights_on = _darkness > 0.3 or _raining
	_car.beam = _darkness > 0.5
	layer(_draw_rain)
	intro.audio.play_loop("engine_loop", -10.0, VehicleCatalog.engine_pitch(_car_id))
	intro.audio.play_loop("city_loop", -8.0)
	if _raining:
		intro.audio.play_loop("rain_loop", -8.0)


func update(delta: float) -> void:
	_update_passer(delta)
	var pitch: float = VehicleCatalog.engine_pitch(_car_id)
	if time < PARK_TIME:
		var k: float = time / PARK_TIME
		_car.position.x = roundf(lerpf(CAR_FROM, _car_x(), ease(k, 0.4)))
		_car.brake = k > 0.6
		intro.audio.play_loop("engine_loop", -10.0, lerpf(1.0, 0.6, k) * pitch)
	elif not _back_in_car and _once("park"):
		_car.position.x = _car_x()
		_car.brake = false
		intro.audio.stop_loop("engine_loop", 0.3)
	if time >= OUT_TIME and _once("out"):
		_car.setup(_car_id)
		_player.visible = true
		intro.audio.play_one("car_door", -2.0)
	if time >= OUT_TIME and not _back_in_car:
		_update_walk()
	if time >= _in_car_time() and not _back_in_car:
		_back_in_car = true
		_player.visible = false
		_car.setup(VehicleCatalog.with_driver(_car_id))
		intro.audio.play_one("car_door", -2.0)
	if _back_in_car and time >= _in_car_time() + DRIVE_DELAY:
		if _once("start"):
			intro.audio.play_one("engine_start", -4.0, pitch)
			intro.audio.play_loop("engine_loop", -8.0, 0.8 * pitch)
			_car.lights_on = true
		var t: float = time - _in_car_time() - DRIVE_DELAY
		_car.position.x = roundf(_car_x() + 0.5 * ACCELERATION * t * t)


## The walk to the door, the time inside and the walk back, with the item in hand.
func _update_walk() -> void:
	var out_end: float = _walk_out_time()
	var back_start: float = _back_time()
	var half: float = _walk_start() + _walk_seconds() * 0.6
	if time < _walk_start():
		_update_before_door()
	elif time < half:
		walk(_player, _walk_from(), _curb(), _walk_start(), half)
	elif time < out_end:
		walk(_player, _curb(), _door(), half, out_end)
		_player.modulate.a = clampf((out_end - time) / 0.25, 0.0, 1.0)
	elif time < back_start:
		if _once("enter"):
			_inside = true
			_play_door()
			if not _inside_loop().is_empty():
				intro.audio.play_loop(_inside_loop(), -16.0)
			_on_enter()
	else:
		if _once("exit"):
			_inside = false
			_carrying = _item()
			_play_door()
			if not _inside_loop().is_empty():
				intro.audio.stop_loop(_inside_loop(), 0.6)
			_on_exit()
		_player.modulate.a = clampf((time - back_start) / 0.25, 0.0, 1.0)
		var turn: float = back_start + _walk_seconds() * 0.4
		if time < turn:
			walk(_player, _door(), _curb(), back_start, turn)
		else:
			walk(_player, _curb(), _car_door(), turn, _in_car_time())


func _play_door() -> void:
	var sound: String = _door_sound()
	if not sound.is_empty():
		intro.audio.play_one(sound, -6.0)


func _update_passer(delta: float) -> void:
	_passer.position.x += _passer_dir * PASSER_SPEED * delta
	_passer.set_walking(true, Vector2(_passer_dir, 0))


## True the first time it is asked for `key`.
func _once(key: String) -> bool:
	if _sounds_played.has(key):
		return false
	_sounds_played[key] = true
	return true


func _draw_glow(canvas: CanvasItem) -> void:
	if _darkness < 0.2:
		return
	var flicker: float = 0.9 + 0.1 * sin(time * 9.0)
	for rect: Rect2 in _glow_rects():
		canvas.draw_rect(rect, Color(WINDOW_GLOW, 0.55 * _darkness * flicker))
		canvas.draw_rect(Rect2(rect.position.x - 3, rect.end.y + 2, rect.size.x + 6, 10), Color(WINDOW_GLOW, 0.12 * _darkness))


func _draw_item(canvas: CanvasItem) -> void:
	if _inside and not _inside_text().is_empty():
		draw_bubble(canvas, _door() + Vector2(0, -52), _inside_text())
	if _carrying == Item.NONE or not _player.visible or _inside:
		return
	var facing_right: bool = _player.position.x < _car_door().x - 1.0
	var hand: Vector2 = _player.position + Vector2(6.0 if facing_right else -9.0, -19.0)
	hand = hand.round()
	var shade: Color = Color.WHITE.lerp(PEOPLE_NIGHT, _darkness)
	match _carrying:
		Item.CUP:
			canvas.draw_rect(Rect2(hand + Vector2(0, -5), Vector2(3, 5)), WHITE * shade)
			canvas.draw_rect(Rect2(hand + Vector2(0, -3), Vector2(3, 2)), Color("#8a5a3a") * shade)
			canvas.draw_rect(Rect2(hand + Vector2(0, -6), Vector2(3, 1)), INK)
			if fmod(time * 2.0, 1.0) < 0.6:
				canvas.draw_rect(Rect2(hand + Vector2(1, -9 - fmod(time * 4.0, 2.0)), Vector2(1, 2)), Color(1, 1, 1, 0.5))
		Item.BAG:
			canvas.draw_rect(Rect2(hand + Vector2(-1, -2), Vector2(7, 8)), Color("#d9b77a") * shade)
			canvas.draw_rect(Rect2(hand + Vector2(0, -4), Vector2(2, 2)), Color("#4f9a4a") * shade)
			canvas.draw_rect(Rect2(hand + Vector2(3, -3), Vector2(2, 1)), Color("#ffcc33") * shade)
		Item.BOX:
			canvas.draw_rect(Rect2(hand + Vector2(-1, -1), Vector2(8, 5)), WHITE * shade)
			canvas.draw_rect(Rect2(hand + Vector2(-1, -1), Vector2(8, 1)), RED * shade)


func _draw_rain(canvas: CanvasItem) -> void:
	if not _raining:
		return
	canvas.draw_rect(Rect2(0, 0, IntroArt.STAGE.x, IntroArt.STAGE.y), Color(0.2, 0.25, 0.35, 0.18))
	for i: int in 70:
		var x: float = fposmod(i * 47.3 + time * 60.0, IntroArt.STAGE.x + 20.0) - 10.0
		var y: float = fposmod(i * 29.1 + time * 260.0, IntroArt.STAGE.y)
		canvas.draw_line(Vector2(roundf(x), roundf(y)), Vector2(roundf(x) - 2, roundf(y) + 7), Color(0.75, 0.82, 0.95, 0.4))
	for i: int in 6:
		var k: float = fmod(time * 1.5 + i * 0.37, 1.0)
		var splash: Vector2 = Vector2(fposmod(i * 61.0, IntroArt.STAGE.x), 150.0 + (i % 3) * 9.0)
		canvas.draw_rect(Rect2(splash + Vector2(-k * 3.0, 0), Vector2(1 + k * 6.0, 1)), Color(0.85, 0.9, 1.0, 0.5 * (1.0 - k)))
