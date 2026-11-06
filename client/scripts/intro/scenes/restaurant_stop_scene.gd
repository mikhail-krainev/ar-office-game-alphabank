class_name RestaurantStopScene
extends ErrandScene
## Evening dinner out on the way home: neon over the door, candles in the windows, and the player
## leaves an hour later with a box of leftovers.


func get_caption_key() -> String:
	return "INTRO_STOP_RESTAURANT"


func _background() -> String:
	return "restaurant"


func _door() -> Vector2:
	return Vector2(92, DOOR_Y)


func _inside_time() -> float:
	return 1.6


func _item() -> Item:
	return Item.BOX


func _inside_loop() -> String:
	return "cafe_chatter_loop"


func _inside_text() -> String:
	return tr("INTRO_STOP_RESTAURANT_WAIT")


func _on_enter() -> void:
	intro.audio.play_one("dishes", -14.0)


func _on_exit() -> void:
	intro.audio.play_one("laugh", -16.0)


func _glow_rects() -> Array[Rect2]:
	return [Rect2(12, 84, 50, 40), Rect2(122, 84, 50, 40), Rect2(85, 94, 14, 16)]


func _draw_details(canvas: CanvasItem) -> void:
	# The neon sign hums and flickers now and then.
	var on: bool = fmod(time, 2.3) > 0.12 and fmod(time, 3.7) > 0.08
	if on:
		canvas.draw_rect(Rect2(66, 57, 16, 13), Color(1.0, 0.31, 0.64, 0.25))
		canvas.draw_rect(Rect2(84, 58, 44, 11), Color(0.36, 0.88, 0.9, 0.18))
	else:
		canvas.draw_rect(Rect2(57, 57, 78, 12), Color(0.07, 0.07, 0.1, 0.6))
	for x: int in [26, 50, 136, 160]:
		var flame: float = 0.6 + 0.4 * sin(time * 11.0 + x)
		canvas.draw_rect(Rect2(x, 106, 1, 1), Color(1.0, 0.85, 0.3, flame))
