class_name MoodCanvas
extends RefCounted
## The square pixel canvas of "Mood of the day": transparent until painted. Its size matches what the
## server accepts (mood.go: moodSide), so the PNG goes up as it is.

const SIDE: int = 64

var image: Image = Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)


func clear() -> void:
	image.fill(Color(0, 0, 0, 0))


## A line of square brush dabs from `from` to `to` (cells), so a fast finger leaves no gaps.
func stroke(from: Vector2i, to: Vector2i, brush: int, color: Color) -> void:
	var steps: int = maxi(1, maxi(absi(to.x - from.x), absi(to.y - from.y)))
	for i: int in steps + 1:
		var point: Vector2i = Vector2i(Vector2(from).lerp(Vector2(to), float(i) / steps).round())
		@warning_ignore("integer_division")
		var half: int = brush / 2
		var dab: Rect2i = Rect2i(point - Vector2i(half, half), Vector2i(brush, brush))
		image.fill_rect(dab.intersection(Rect2i(0, 0, SIDE, SIDE)), color)


func is_empty() -> bool:
	return image.is_invisible()
