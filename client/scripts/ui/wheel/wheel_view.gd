class_name WheelView
extends Control
## The fortune wheel drawn in code: equal sectors coloured by prize (gold coins, items by rarity),
## each with its icon and a short caption, and the pointer at the top. `spin_to` turns it a few full
## times and stops on the sector the server picked.

signal stopped

const SPIN_TURNS: int = 5
const SPIN_SECONDS: float = 4.2
## The wheel stops anywhere inside the sector, not only at its middle (share of the sector).
const STOP_JITTER: float = 0.35
const RIM: float = 6.0
const ICON_SIZE: int = 24
const CAPTION_LENGTH: int = 10
const COIN_GOLD: Color = Color("#f2b632")

var sectors: Array[BackendModels.WheelSector] = []
## Clockwise rotation of the wheel in radians.
var wheel_rotation: float = 0.0:
	set(value):
		wheel_rotation = value
		queue_redraw()

var _spinning: bool = false


## Angle of one sector.
static func sector_step(count: int) -> float:
	return TAU / maxi(count, 1)


## Rotation that stops sector `index` under the pointer after `turns` full clockwise turns from
## `current`; `offset` in [-1, 1] moves the stop inside the sector.
static func target_rotation(current: float, index: int, count: int, turns: int, offset: float = 0.0) -> float:
	var step: float = sector_step(count)
	# Sector i is centred at i * step clockwise from the top, so a rotation of -i * step brings it up.
	var aim: float = fposmod(-index * step + offset * step * STOP_JITTER, TAU)
	var base: float = current - fposmod(current, TAU)
	var target: float = base + aim
	if target <= current:
		target += TAU
	return target + turns * TAU


## Index of the sector under the pointer at the wheel rotation `angle`.
static func sector_at(angle: float, count: int) -> int:
	var step: float = sector_step(count)
	return posmod(roundi(-angle / step), maxi(count, 1))


func is_spinning() -> bool:
	return _spinning


func spin_to(index: int) -> void:
	_spinning = true
	var target: float = target_rotation(wheel_rotation, index, sectors.size(), SPIN_TURNS, randf_range(-1.0, 1.0))
	var tween: Tween = create_tween()
	tween.tween_property(self, "wheel_rotation", target, SPIN_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await tween.finished
	_spinning = false
	stopped.emit()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0 - RIM
	draw_circle(center, radius + RIM, UiStyle.INK)
	if sectors.is_empty():
		return
	var step: float = sector_step(sectors.size())
	for index: int in sectors.size():
		var middle: float = index * step + wheel_rotation
		_draw_sector(center, radius, middle - step / 2.0, middle + step / 2.0, sectors[index], index)
	for index: int in sectors.size():
		var middle: float = index * step + wheel_rotation
		_draw_contents(center, radius, middle, sectors[index])
	draw_circle(center, radius * 0.16, UiStyle.RED)
	draw_circle(center, radius * 0.08, Color.WHITE)
	_draw_pointer(center, radius)


func _sector_color(sector: BackendModels.WheelSector, index: int) -> Color:
	var color: Color = COIN_GOLD if sector.is_coins() else UiStyle.RARITY_COLORS.get(sector.rarity, UiStyle.MUTED)
	if index % 2 == 1:
		color = color.lightened(0.12)
	if sector.out_of_stock or sector.owned:
		color = color.lerp(UiStyle.SHADE, 0.6)
	return color


func _draw_sector(center: Vector2, radius: float, from: float, to: float, sector: BackendModels.WheelSector, index: int) -> void:
	var points: PackedVector2Array = PackedVector2Array([center])
	const SEGMENTS: int = 16
	for i: int in SEGMENTS + 1:
		points.append(center + _direction(lerpf(from, to, float(i) / SEGMENTS)) * radius)
	draw_colored_polygon(points, _sector_color(sector, index))
	draw_line(center, center + _direction(from) * radius, Color.WHITE, 1.0)


func _draw_contents(center: Vector2, radius: float, angle: float, sector: BackendModels.WheelSector) -> void:
	var at: Vector2 = center + _direction(angle) * radius * 0.66
	# Sectors on the lower half are turned over, so their captions are never upside down.
	draw_set_transform(at, angle + PI if cos(angle) < 0.0 else angle)
	if sector.is_coins():
		draw_texture_rect_region(ShopPanel.COIN_SHEET, Rect2(-8, -18, 16, 16), Rect2(0, 0, 16, 16))
	elif sector.icon >= 0:
		draw_texture_rect_region(ShopPanel.ICONS, Rect2(-ICON_SIZE / 2.0, -ICON_SIZE - 4, ICON_SIZE, ICON_SIZE), Rect2(sector.icon * ICON_SIZE, 0, ICON_SIZE, ICON_SIZE))
	var font: Font = get_theme_default_font()
	var caption: String = caption_of(sector)
	var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(-width / 2.0, 8), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE if not sector.out_of_stock else UiStyle.MUTED)
	draw_set_transform(Vector2.ZERO)


## Short caption of a sector: the coins, else the item name cut to fit.
static func caption_of(sector: BackendModels.WheelSector) -> String:
	if sector.is_coins():
		return "+%d" % sector.coins
	var words: PackedStringArray = sector.name.split(" ")
	var caption: String = words[0] if not words.is_empty() else ""
	return caption if caption.length() <= CAPTION_LENGTH else caption.left(CAPTION_LENGTH - 1) + "…"


func _draw_pointer(center: Vector2, radius: float) -> void:
	var tip: Vector2 = center + Vector2(0, -radius + 10)
	var points: PackedVector2Array = PackedVector2Array([tip, tip + Vector2(-9, -18), tip + Vector2(9, -18)])
	draw_colored_polygon(points, UiStyle.RED)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color.WHITE, 2.0)


## Unit vector at `angle` clockwise from the top.
static func _direction(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))
