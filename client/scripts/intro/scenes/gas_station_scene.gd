class_name GasStationScene
extends ErrandScene
## A stop to fill up: the player takes the nozzle, the pump counts litres and roubles, then the
## player pays in the kiosk (and grabs a coffee in the morning).

const PUMP_SPOT: Vector2 = Vector2(114, 146)
const NOZZLE: Vector2 = Vector2(103, 112)
const FUEL_CAP: Vector2 = Vector2(110, 134)
const DISPLAY: Vector2 = Vector2(86, 96)
const TO_PUMP: float = 0.8
const FILLING: float = 2.2
const LITRES: float = 34.0
const PRICE: int = 58


func get_caption_key() -> String:
	return "INTRO_STOP_GAS"


func _background() -> String:
	return "gas_station"


func _door() -> Vector2:
	return Vector2(31, DOOR_Y)


func _car_x() -> float:
	return 104.0


func _inside_time() -> float:
	return 0.9


func _item() -> Item:
	return Item.NONE if intro.evening else Item.CUP


func _pre_door_time() -> float:
	return TO_PUMP + FILLING


func _walk_from() -> Vector2:
	return PUMP_SPOT


func _update_before_door() -> void:
	var start: float = OUT_TIME + 0.2
	walk(_player, _car_door(), PUMP_SPOT, start, start + TO_PUMP)
	if time >= start + TO_PUMP:
		_player.face(Vector2.LEFT)
		if _once("pump"):
			intro.audio.play_loop("fuel_pump_loop", -12.0)
	if time >= _walk_start() - 0.05 and _once("pump_done"):
		intro.audio.stop_loop("fuel_pump_loop", 0.2)
		intro.audio.play_one("clank", -10.0)


func _glow_rects() -> Array[Rect2]:
	return [Rect2(6, 86, 14, 22), Rect2(42, 86, 12, 22), Rect2(24, 94, 14, 38), Rect2(60, 42, 220, 3)]


func _filled() -> float:
	var start: float = OUT_TIME + 0.2 + TO_PUMP
	return clampf((time - start) / FILLING, 0.0, 1.0)


func _draw_details(canvas: CanvasItem) -> void:
	var litres: int = int(_filled() * LITRES)
	draw_digits(canvas, "%02d" % litres, DISPLAY + Vector2(8, 0), Color("#4cd964"))
	draw_digits(canvas, "%04d" % (litres * PRICE), DISPLAY + Vector2(0, 5), Color("#ffcc33"))
	var filling: bool = time >= OUT_TIME + 0.2 + TO_PUMP and time < _walk_start()
	if filling:
		var sag: Vector2 = (NOZZLE + FUEL_CAP) / 2.0 + Vector2(0, 8)
		canvas.draw_polyline(PackedVector2Array([NOZZLE, sag, FUEL_CAP]), Color("#2a2f36"), 1.0)
		canvas.draw_rect(Rect2(FUEL_CAP + Vector2(-1, -2), Vector2(4, 3)), Color("#2a2f36"))
