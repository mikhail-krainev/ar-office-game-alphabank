class_name MoodPhoto
extends RefCounted
## The "Mood of the day" photo: the drawing put on every forehead of a camera still, where the try-on
## preview shows it (the same placement), with the same faint neon frame. Pure image work, so it is
## tested without a camera.

## The drawing on the forehead is this many eye spans wide.
const FOREHEAD_SCALE: float = 1.3
## Between the eye line and the top of the forehead, a little above the middle.
const FOREHEAD_LIFT: float = 0.35
## A smaller drawing is not put on (the face is too far or the detector is unsure).
const MIN_WIDTH: float = 4.0
const FRAME_WIDTH: float = 2.0
const FRAME_COLOR: Color = Color(1.0, 0.18, 0.53, 0.35)
## The still goes to the server as a JPEG of this quality (mood.go limits its size).
const JPEG_QUALITY: float = 0.8


## Centre of the drawing on the face.
static func center(anchor: ArAnchor) -> Vector2:
	return anchor.top.lerp(anchor.eye_center(), FOREHEAD_LIFT)


## Side of the drawing on the face.
static func width(anchor: ArAnchor) -> float:
	return anchor.eye_span() * FOREHEAD_SCALE


## A copy of `photo` with `drawing` on the forehead of each face (normalized to the photo).
static func compose(photo: Image, drawing: Image, faces: Array[SensorModels.Face]) -> Image:
	var result: Image = photo.duplicate() as Image
	result.convert(Image.FORMAT_RGB8)
	var frame: Rect2 = Rect2(Vector2.ZERO, Vector2(result.get_size()))
	for face: SensorModels.Face in faces:
		var anchor: ArAnchor = ArAnchor.of_face(face, frame)
		if width(anchor) >= MIN_WIDTH:
			_stamp(result, drawing, center(anchor), width(anchor), anchor.roll())
	return result


static func to_jpeg_base64(photo: Image) -> String:
	return Marshalls.raw_to_base64(photo.save_jpg_to_buffer(JPEG_QUALITY))


## Draws `drawing` as a square of `side` centred at `at` and turned by `roll`, nearest-neighbour like
## the pixel art, with the frame around it.
static func _stamp(target: Image, drawing: Image, at: Vector2, side: float, roll: float) -> void:
	var half: float = side / 2.0
	var reach: int = ceili((half + FRAME_WIDTH) * sqrt(2.0))
	var bounds: Rect2i = Rect2i(Vector2i(at) - Vector2i(reach, reach), Vector2i(reach, reach) * 2)
	bounds = bounds.intersection(Rect2i(Vector2i.ZERO, target.get_size()))
	var drawing_side: int = drawing.get_width()
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var local: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - at).rotated(-roll)
			var distance: float = maxf(absf(local.x), absf(local.y))
			var color: Color = Color(0, 0, 0, 0)
			if distance < half:
				var cell: Vector2i = Vector2i((local + Vector2(half, half)) / side * drawing_side)
				color = drawing.get_pixelv(cell.clampi(0, drawing_side - 1))
			elif distance < half + FRAME_WIDTH:
				color = FRAME_COLOR
			if color.a > 0.0:
				target.set_pixel(x, y, target.get_pixel(x, y).blend(color))
