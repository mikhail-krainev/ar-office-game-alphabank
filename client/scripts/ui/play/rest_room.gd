class_name RestRoom
extends Node2D
## Pixel-art lounge for the play-limit screens: the player's character sits in an armchair with a
## cup of coffee while a neon wall clock counts down the rest. With `asleep` the lamp is off, the
## clock is dark and the character dozes. Drawn in SIZE units; the parent scales it by a whole number.

const SIZE: Vector2i = Vector2i(160, 120)
const WALL_TOP: Color = Color("#2b1d3f")
const WALL_BOTTOM: Color = Color("#4a2350")
const BASEBOARD: Color = Color("#1a1024")
const FLOOR: Color = Color("#5a3a2c")
const FLOOR_LINE: Color = Color("#4a2f24")
const RUG: Color = Color("#8e2a3a")
const RUG_EDGE: Color = Color("#b8364a")
const NEON: Color = Color("#ff3b5c")
const CLOCK_BODY: Color = Color("#140c1c")
const LAMP_GLOW: Color = Color(1.0, 0.8, 0.45, 0.16)
const MUG: Color = Color("#f4efe6")
const COFFEE: Color = Color("#5b3a22")
const STEAM: Color = Color(1, 1, 1, 0.55)
const NIGHT: Color = Color(0.03, 0.02, 0.08, 0.55)
const FLOOR_Y: int = 70
const WALL_GRADIENT_BANDS: int = 7
## Frame of the character sheet drawn above the seat: head, body and hips (CharacterPainter.FRAME).
const SEATED_REGION: Rect2 = Rect2(0, 0, 48, 46)
const SEATED_TOP: Vector2 = Vector2(56, 31)
const SIP_PERIOD: float = 4.0
const SIP_TIME: float = 1.2
## Cup in the hand: resting on the knee and at the mouth.
const CUP_LOW: Vector2 = Vector2(85, 72)
const CUP_HIGH: Vector2 = Vector2(83, 60)

## Text on the wall clock, e.g. "29:59".
var clock_text: String = ""
var asleep: bool = false
## Outside the office network: the clock shows a crossed-out Wi-Fi sign.
var no_wifi: bool = false

var _time: float = 0.0
var _props: Texture2D
var _regions: Dictionary = {}


func _ready() -> void:
	_props = load(PropCatalog.TEXTURE_PATH)
	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PropCatalog.MANIFEST_PATH)
	)
	_regions = manifest if manifest is Dictionary else {}
	Appearance.changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	_draw_room()
	_draw_clock()
	_prop("plant_big", Vector2(12, 100))
	_prop("floor_lamp", Vector2(126, 96))
	if not asleep:
		draw_circle(Vector2(136, 42), 26.0, LAMP_GLOW)
	_prop("armchair", Vector2(64, 92))
	_draw_character()
	_prop("coffee_table", Vector2(48, 116))
	if asleep:
		draw_rect(Rect2(Vector2.ZERO, SIZE), NIGHT)
		_draw_snore()
	else:
		_draw_cup()


func _draw_room() -> void:
	var band: float = float(FLOOR_Y) / WALL_GRADIENT_BANDS
	for i: int in WALL_GRADIENT_BANDS:
		var color: Color = WALL_TOP.lerp(WALL_BOTTOM, float(i) / (WALL_GRADIENT_BANDS - 1))
		draw_rect(Rect2(0, roundf(i * band), SIZE.x, ceilf(band) + 1.0), color)
	draw_rect(Rect2(0, FLOOR_Y, SIZE.x, SIZE.y - FLOOR_Y), FLOOR)
	for y: int in range(FLOOR_Y + 8, SIZE.y, 9):
		draw_rect(Rect2(0, y, SIZE.x, 1), FLOOR_LINE)
	draw_rect(Rect2(0, FLOOR_Y - 3, SIZE.x, 3), BASEBOARD)
	_ellipse(Vector2(80, 103), Vector2(58, 13), RUG_EDGE)
	_ellipse(Vector2(80, 103), Vector2(55, 11), RUG)


func _draw_clock() -> void:
	var body: Rect2 = Rect2(57, 10, 46, 18)
	draw_rect(body.grow(1.0), NEON if not asleep else BASEBOARD)
	draw_rect(body, CLOCK_BODY)
	if no_wifi:
		_draw_no_wifi(body.get_center() + Vector2(0, 5))
		return
	if asleep or clock_text.is_empty():
		return
	# Neon digits at twice the 3x5 glyph size, centred in the clock body.
	var width: float = 0.0
	for character: String in clock_text:
		width += 2.0 if character == ":" else 4.0
	var origin: Vector2 = Vector2(roundf(body.get_center().x - width), body.position.y + 4)
	draw_set_transform(origin, 0.0, Vector2(2, 2))
	IntroScene.draw_digits(self, clock_text, Vector2.ZERO, NEON)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Three Wi-Fi arcs and a dot, crossed out, centred on `base` (the dot).
func _draw_no_wifi(base: Vector2) -> void:
	for radius: float in [3.0, 6.0, 9.0]:
		draw_arc(base, radius, PI * 1.25, PI * 1.75, 8, NEON, 1.0)
	draw_rect(Rect2(base - Vector2(0.5, 0.5), Vector2(1, 1)), NEON)
	draw_line(base + Vector2(-8, -9), base + Vector2(8, 1), Color.WHITE, 1.0)


func _draw_character() -> void:
	var sheet: Texture2D = Appearance.get_sheet()
	if sheet != null:
		draw_texture_rect_region(sheet, Rect2(SEATED_TOP, SEATED_REGION.size), SEATED_REGION)


func _draw_cup() -> void:
	var phase: float = fmod(_time, SIP_PERIOD)
	var lift: float = sin(clampf(phase / SIP_TIME, 0.0, 1.0) * PI)
	var cup: Vector2 = CUP_LOW.lerp(CUP_HIGH, lift).round()
	draw_rect(Rect2(cup + Vector2(-2, 3), Vector2(3, 3)), Appearance.get_skin_color())
	draw_rect(Rect2(cup, Vector2(5, 5)), MUG)
	draw_rect(Rect2(cup + Vector2(5, 1), Vector2(1, 3)), MUG)
	draw_rect(Rect2(cup + Vector2(1, 0), Vector2(3, 1)), COFFEE)
	if lift < 0.1:
		for i: int in 3:
			var k: float = fmod(_time * 0.8 + i / 3.0, 1.0)
			var x: float = cup.x + 2.0 + sin(k * 6.0 + i) * 1.5
			draw_rect(
				Rect2(roundf(x), roundf(cup.y - 2.0 - k * 9.0), 1, 2),
				Color(STEAM, STEAM.a * (1.0 - k))
			)


func _draw_snore() -> void:
	var font: Font = ThemeDB.fallback_font
	for i: int in 3:
		var k: float = fmod(_time * 0.5 + i / 3.0, 1.0)
		var spot: Vector2 = Vector2(92 + k * 10.0, 44 - k * 18.0).round()
		draw_string(
			font, spot, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8 + i * 2, Color(1, 1, 1, 1.0 - k)
		)


## Draws a prop sprite with its bottom-left corner at `bottom_left` (props.png, PropCatalog).
func _prop(id: String, bottom_left: Vector2) -> void:
	var region: Array = _regions.get(id, [])
	if region.size() < 4 or _props == null:
		return
	var size: Vector2 = Vector2(region[2], region[3])
	draw_texture_rect_region(
		_props,
		Rect2(bottom_left - Vector2(0, size.y), size),
		Rect2(region[0], region[1], region[2], region[3])
	)


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, radius.y / radius.x))
	draw_circle(Vector2.ZERO, radius.x, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
