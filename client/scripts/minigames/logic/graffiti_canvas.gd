class_name GraffitiCanvas
extends RefCounted
## The player's spray layer of "Graffiti wall": transparent until painted, the size of the shared
## office wall the server accepts (graffiti.go: graffitiWidth x graffitiHeight), so the PNG goes up
## as it is. A spray can leaves a solid core with a speckled overspray around it, and where paint
## piles up it runs down in drips, like on a real wall. Pure image math, tested without a screen.

const WIDTH: int = 144
const HEIGHT: int = 96
## Nozzle radii in wall pixels.
const THIN: float = 2.5
const FAT: float = 5.0
## The solid share of the nozzle radius; the rest is overspray.
const CORE: float = 0.55
const OVERSPRAY_DOTS: int = 14
const OVERSPRAY_ALPHA: float = 0.55
## Stamps along a stroke, in nozzle radii between them.
const STAMP_STEP: float = 0.5
## Paint a pixel takes before it runs, and how far (pixels) and fast (pixels a second) a drip runs.
const DRIP_PAINT: float = 6.0
const DRIP_CHANCE: float = 0.08
const DRIP_LENGTH_MIN: float = 3.0
const DRIP_LENGTH_MAX: float = 10.0
const DRIP_SPEED: float = 7.0
const MAX_DRIPS: int = 24
## The server needs at least this many painted pixels (graffiti.go: graffitiMinPixels).
const MIN_PIXELS: int = 20


class Drip:
	extends RefCounted

	var x: int = 0
	var y: float = 0.0
	var left: float = 0.0
	var color: Color = Color.WHITE


var image: Image = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)

var _paint: PackedFloat32Array = PackedFloat32Array()
var _drips: Array[Drip] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## `rng_seed` 0 picks a random one.
func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_paint.resize(WIDTH * HEIGHT)


## Sprays a line from `from` to `to` (wall pixels), so a fast finger leaves no gaps.
func spray(from: Vector2, to: Vector2, radius: float, color: Color) -> void:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * STAMP_STEP)))
	for step: int in steps + 1:
		_stamp(from.lerp(to, float(step) / steps), radius, color)


## Runs the drips down by `delta` seconds; true while some still run.
func update(delta: float) -> bool:
	for drip: Drip in _drips:
		var run: float = minf(DRIP_SPEED * delta, drip.left)
		var from: int = int(drip.y)
		drip.y += run
		drip.left -= run
		for y: int in range(from, mini(int(drip.y), HEIGHT - 1) + 1):
			_put(drip.x, y, drip.color, 1.0, false)
	_drips = _drips.filter(func(drip: Drip) -> bool: return drip.left > 0.0 and drip.y < HEIGHT - 1)
	return not _drips.is_empty()


func painted_pixels() -> int:
	var count: int = 0
	for y: int in HEIGHT:
		for x: int in WIDTH:
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func has_enough_paint() -> bool:
	return painted_pixels() >= MIN_PIXELS


func to_png_base64() -> String:
	return Marshalls.raw_to_base64(image.save_png_to_buffer())


## One puff of the can: a solid disc in the middle and speckles around it.
func _stamp(centre: Vector2, radius: float, color: Color) -> void:
	var core: float = radius * CORE
	var reach: int = ceili(core)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			if Vector2(dx, dy).length() <= core:
				_put(roundi(centre.x) + dx, roundi(centre.y) + dy, color, 1.0)
	for dot: int in OVERSPRAY_DOTS:
		var offset: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * lerpf(core, radius, sqrt(_rng.randf()))
		_put(roundi(centre.x + offset.x), roundi(centre.y + offset.y), color, OVERSPRAY_ALPHA)


## Paints one pixel over what is there; paint sprayed on a pile runs down (a drip itself does not).
func _put(x: int, y: int, color: Color, alpha: float, can_drip: bool = true) -> void:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return
	var painted: Color = Color(color, alpha)
	image.set_pixel(x, y, image.get_pixel(x, y).blend(painted))
	if not can_drip:
		return
	var index: int = y * WIDTH + x
	_paint[index] += alpha
	if _paint[index] < DRIP_PAINT or _drips.size() >= MAX_DRIPS or _rng.randf() > DRIP_CHANCE:
		return
	_paint[index] = 0.0
	var drip: Drip = Drip.new()
	drip.x = x
	drip.y = y
	drip.left = _rng.randf_range(DRIP_LENGTH_MIN, DRIP_LENGTH_MAX)
	drip.color = color
	_drips.append(drip)
