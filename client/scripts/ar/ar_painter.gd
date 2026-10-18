class_name ArPainter
extends RefCounted
## AR stickers drawn over the camera view in the game's neon style: shades and a crown that stay on
## a face and turn with the head, a glowing skeleton, a target lock around a found object, sparks.
## Everything is drawn on the phone over the live camera; nothing is recorded or sent. Each function
## draws on the given canvas item (a CameraView overlay) and takes the time in seconds for its motion.

const NEON_PINK: Color = Color("#ff2e88")
const NEON_CYAN: Color = Color("#2ef2ff")
const GLOW_ALPHA: float = 0.28
const GLOW_WIDTH: float = 3.0
const LENS_SIZE: Vector2 = Vector2(0.46, 0.3)
const LENS_OFFSET: float = 0.27
const CROWN_WIDTH: float = 1.5
const CROWN_HEIGHT: float = 0.55
const CROWN_LIFT: float = 0.12
const CROWN_BOB: float = 0.04
const SPARK_COUNT: int = 4
const BRACKET_SHARE: float = 0.22
const TAG_FONT_SIZE: int = 10
const TAG_PADDING: Vector2 = Vector2(4, 2)
const SCAN_PERIOD: float = 1.4


## A line with a soft neon glow under it.
static func neon_line(
	canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float = 2.0
) -> void:
	canvas.draw_line(from, to, Color(color, GLOW_ALPHA), width + GLOW_WIDTH * 2.0)
	canvas.draw_line(from, to, color, width)


static func neon_polyline(
	canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float = 2.0
) -> void:
	canvas.draw_polyline(points, Color(color, GLOW_ALPHA), width + GLOW_WIDTH * 2.0)
	canvas.draw_polyline(points, color, width)


## Pixel shades on the eyes, tilted with the head.
static func shades(canvas: CanvasItem, anchor: ArAnchor, color: Color = NEON_PINK) -> void:
	var span: float = anchor.eye_span()
	if span < 2.0:
		return
	canvas.draw_set_transform(anchor.eye_center(), anchor.roll())
	var lens: Vector2 = LENS_SIZE * span
	for side: float in [-1.0, 1.0]:
		var rect: Rect2 = Rect2(
			Vector2(side * LENS_OFFSET * span - lens.x / 2.0, -lens.y / 2.0), lens
		)
		canvas.draw_rect(rect, Color(0.04, 0.02, 0.06, 0.88))
		canvas.draw_rect(rect, color, false, 2.0)
		# Glare stripe.
		var glare: Vector2 = rect.position + Vector2(lens.x * 0.18, lens.y * 0.22)
		canvas.draw_line(glare, glare + Vector2(lens.x * 0.3, 0), Color(1, 1, 1, 0.75), 2.0)
	var bridge: float = LENS_OFFSET * span - lens.x / 2.0
	neon_line(canvas, Vector2(-bridge, -lens.y * 0.2), Vector2(bridge, -lens.y * 0.2), color)
	canvas.draw_set_transform(Vector2.ZERO)


## A gold crown on the forehead that bobs gently; `t` in seconds.
static func crown(canvas: CanvasItem, anchor: ArAnchor, t: float) -> void:
	var span: float = anchor.eye_span()
	if span < 2.0:
		return
	var up: Vector2 = (anchor.top - anchor.chin).normalized()
	if up == Vector2.ZERO:
		up = Vector2.UP
	var base: Vector2 = anchor.top + up * span * (CROWN_LIFT + CROWN_BOB * sin(t * TAU))
	canvas.draw_set_transform(base, anchor.roll())
	var width: float = span * CROWN_WIDTH
	var height: float = span * CROWN_HEIGHT
	var half: float = width / 2.0
	var outline: PackedVector2Array = PackedVector2Array(
		[
			Vector2(-half, 0),
			Vector2(-half, -height * 0.55),
			Vector2(-half * 0.5, -height * 0.25),
			Vector2(0, -height),
			Vector2(half * 0.5, -height * 0.25),
			Vector2(half, -height * 0.55),
			Vector2(half, 0),
		]
	)
	canvas.draw_colored_polygon(outline, UiStyle.GOLD)
	outline.append(outline[0])
	neon_polyline(canvas, outline, Color("#fff1a8"))
	for x: float in [-half * 0.5, 0.0, half * 0.5]:
		canvas.draw_circle(Vector2(x, -height * 0.12), maxf(1.5, span * 0.05), UiStyle.RED)
	canvas.draw_set_transform(Vector2.ZERO)


## Four-pointed sparks circling `center`; `t` in seconds.
static func sparks(
	canvas: CanvasItem, center: Vector2, radius: float, t: float, color: Color = Color.WHITE
) -> void:
	for i: int in SPARK_COUNT:
		var angle: float = t * 1.7 + TAU * i / SPARK_COUNT
		var point: Vector2 = center + Vector2.from_angle(angle) * radius
		var size: float = maxf(2.0, radius * 0.12) * (0.6 + 0.4 * absf(sin(t * 5.0 + i)))
		star(canvas, point, size, color)


static func star(canvas: CanvasItem, point: Vector2, size: float, color: Color) -> void:
	canvas.draw_line(point - Vector2(size, 0), point + Vector2(size, 0), color, 2.0)
	canvas.draw_line(point - Vector2(0, size), point + Vector2(0, size), color, 2.0)
	canvas.draw_rect(Rect2(point - Vector2.ONE, Vector2(2, 2)), Color.WHITE)


## Target lock: corner brackets around `rect`, a scan line while searching, a filled tag when locked.
static func target_lock(
	canvas: CanvasItem, rect: Rect2, label: String, locked: bool, t: float
) -> void:
	var color: Color = UiStyle.RED if locked else NEON_CYAN
	var grow: float = 0.0 if locked else 3.0 * absf(sin(t * 4.0))
	var box: Rect2 = rect.grow(grow)
	var arm: Vector2 = box.size * BRACKET_SHARE
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var point: Vector2 = box.position + box.size * corner
		var dir: Vector2 = Vector2(1.0 - corner.x * 2.0, 1.0 - corner.y * 2.0)
		neon_polyline(
			canvas,
			PackedVector2Array(
				[point + Vector2(arm.x * dir.x, 0), point, point + Vector2(0, arm.y * dir.y)]
			),
			color
		)
	if not locked:
		var y: float = box.position.y + box.size.y * fposmod(t / SCAN_PERIOD, 1.0)
		canvas.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), Color(color, 0.55), 1.0)
	if label.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE
	)
	var tag: Rect2 = Rect2(
		box.position - Vector2(0, text_size.y + TAG_PADDING.y * 2.0 + 2.0),
		text_size + TAG_PADDING * 2.0
	)
	tag.position.y = maxf(tag.position.y, 2.0)
	canvas.draw_rect(tag, Color(color, 0.9) if locked else Color(0, 0, 0, 0.7))
	canvas.draw_rect(tag, color, false, 1.0)
	var baseline: Vector2 = (
		tag.position + Vector2(TAG_PADDING.x, TAG_PADDING.y + font.get_ascent(TAG_FONT_SIZE))
	)
	canvas.draw_string(
		font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE, Color.WHITE
	)


## A number or word that floats up and fades: `age` from 0 (just shown) to 1 (gone).
static func pop_text(
	canvas: CanvasItem, point: Vector2, text: String, age: float, color: Color = UiStyle.GOLD
) -> void:
	if age < 0.0 or age >= 1.0:
		return
	var font: Font = ThemeDB.fallback_font
	var size: int = 16
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at: Vector2 = point + Vector2(-width / 2.0, -age * 24.0)
	var alpha: float = 1.0 - age
	canvas.draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, alpha)
	)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, alpha))


## Rings that spread out from `center`, for a hit; `age` from 0 to 1.
static func burst(
	canvas: CanvasItem, center: Vector2, radius: float, age: float, color: Color = UiStyle.GOLD
) -> void:
	if age < 0.0 or age >= 1.0:
		return
	for ring: int in 2:
		var share: float = clampf(age * 1.4 - ring * 0.25, 0.0, 1.0)
		if share > 0.0:
			canvas.draw_arc(center, radius * share, 0.0, TAU, 24, Color(color, 1.0 - share), 2.0)
	sparks(canvas, center, radius * (0.4 + age * 0.6), age * 3.0, Color(color, 1.0 - age))
