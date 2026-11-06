class_name GroceryStopScene
extends ErrandScene
## A stop at the grocery store: water and bananas in the morning, something for dinner at night.


func get_caption_key() -> String:
	return "INTRO_STOP_GROCERY_EVENING" if intro.evening else "INTRO_STOP_GROCERY"


func _background() -> String:
	return "grocery"


func _door() -> Vector2:
	return Vector2(100, DOOR_Y)


func _car_x() -> float:
	return 176.0


func _inside_time() -> float:
	return 1.3


func _item() -> Item:
	return Item.BAG


func _inside_loop() -> String:
	return "cafe_chatter_loop"


func _door_sound() -> String:
	return "door_slide"


func _inside_text() -> String:
	return tr("INTRO_STOP_GROCERY_WAIT")


func _on_exit() -> void:
	intro.audio.play_one("cash_register", -10.0)


func _glow_rects() -> Array[Rect2]:
	return [Rect2(8, 86, 72, 42), Rect2(120, 86, 76, 42), Rect2(88, 90, 24, 42)]


func _draw_details(canvas: CanvasItem) -> void:
	# The sliding doors open while the player passes through.
	var near: float = 1.0 - clampf(absf(_player.position.x - _door().x) / 24.0, 0.0, 1.0) if _player.visible else 0.0
	if near > 0.0:
		var gap: float = roundf(near * 10.0)
		canvas.draw_rect(Rect2(100 - gap, 90, gap * 2.0, 42), Color(1.0, 0.92, 0.75, 0.85))
