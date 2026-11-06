class_name CoffeeStopScene
extends ErrandScene
## Morning stop at a coffee shop: the player comes out with a cup to go.


func get_caption_key() -> String:
	return "INTRO_STOP_COFFEE"


func _background() -> String:
	return "coffee_shop"


func _door() -> Vector2:
	return Vector2(90, DOOR_Y)


func _inside_time() -> float:
	return 1.2


func _item() -> Item:
	return Item.CUP


func _inside_loop() -> String:
	return "cafe_chatter_loop"


func _inside_text() -> String:
	return tr("INTRO_STOP_COFFEE_WAIT")


func _on_enter() -> void:
	intro.audio.play_one("coffee_machine", -12.0)


func _glow_rects() -> Array[Rect2]:
	return [Rect2(10, 88, 60, 36), Rect2(108, 88, 60, 36), Rect2(83, 95, 14, 22)]


func _draw_details(canvas: CanvasItem) -> void:
	# Steam over the cup on the sign.
	for i: int in 3:
		var k: float = fmod(time * 0.8 + i / 3.0, 1.0)
		canvas.draw_rect(Rect2(roundf(86 + i * 2 + sin(time * 3.0 + i) * 1.5), roundf(56 - k * 10.0), 1, 2), Color(1, 1, 1, 0.6 * (1.0 - k)))
