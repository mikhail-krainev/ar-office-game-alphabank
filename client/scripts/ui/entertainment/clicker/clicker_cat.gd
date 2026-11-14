class_name ClickerCat
extends Control
## Stage of the lucky cat: a spotlight, the waving cat of the player's gold level, a squash on every
## tap, flying numbers and coins. A tap anywhere on the stage counts (`tapped`).

signal tapped(at: Vector2)

const SHEET: Texture2D = preload("res://assets/ui/clicker_cat.png")
const FRAME: int = 128
const FRAMES: int = 4
## Frames of one wave: up, down and back.
const WAVE: Array[int] = [0, 0, 0, 1, 2, 3, 3, 2, 1]
const LEVELS: int = 13
const WAVE_PERIOD: float = 0.11
const SQUASH_TIME: float = 0.14
const FLOAT_TIME: float = 0.8
const COIN_TIME: float = 0.7
const MAX_EFFECTS: int = 40

## Gold level 0..12 of the drawn cat.
var gold: int = 0
## Pixel scale of the cat; whole numbers keep the pixel art sharp.
var pixel_scale: int = 1
## Combo 1..2 speeds up the paw and warms the spotlight.
var combo: float = 1.0
## Taps are counted only while true (the screen of a colleague's cat is a picture).
var interactive: bool = true
## Only the cat, without the stage (leaderboard icons).
var plain: bool = false
## The points under the cat and the income line at the top of the stage.
var title_text: String = ""
var detail_text: String = ""
## Short notice over the bottom of the stage (achievements, errors); "" hides it.
var toast_text: String = ""

var _clock: float = 0.0
var _squash: float = 0.0
var _floats: Array[Dictionary] = []
var _coins: Array[Dictionary] = []


func _init(height: float = 150.0) -> void:
	custom_minimum_size = Vector2(0, height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	if plain:
		return
	_clock += delta * (1.0 + (combo - 1.0) * 1.5)
	_squash = maxf(0.0, _squash - delta)
	for item: Dictionary in _floats:
		item["age"] = float(item["age"]) + delta
	for coin: Dictionary in _coins:
		coin["age"] = float(coin["age"]) + delta
		coin["vel"] = (coin["vel"] as Vector2) + Vector2(0, 420) * delta
		coin["pos"] = (coin["pos"] as Vector2) + (coin["vel"] as Vector2) * delta
	_floats = _floats.filter(func(item: Dictionary) -> bool: return float(item["age"]) < FLOAT_TIME)
	_coins = _coins.filter(func(coin: Dictionary) -> bool: return float(coin["age"]) < COIN_TIME)
	queue_redraw()


## Effects of one counted tap: `text` flies up from `at` (local position).
func burst(text: String, at: Vector2) -> void:
	_squash = SQUASH_TIME
	if _floats.size() < MAX_EFFECTS:
		_floats.append({"text": text, "pos": at + Vector2(randf_range(-10, 10), -6), "age": 0.0})
	for i: int in 2:
		if _coins.size() < MAX_EFFECTS:
			_coins.append({"pos": _cat_center() + Vector2(randf_range(-20, 20), 10), "vel": Vector2(randf_range(-140, 140), randf_range(-260, -160)), "age": 0.0})


func _cat_center() -> Vector2:
	var top: float = 10.0 if detail_text.is_empty() else 20.0
	var bottom: float = 14.0 if title_text.is_empty() else 44.0
	return Vector2(size.x / 2.0, (top + size.y - bottom) / 2.0)


func _draw() -> void:
	var center: Vector2 = _cat_center()
	if plain:
		var side: float = minf(size.x, size.y)
		var icon: Rect2 = Rect2(((size - Vector2(side, side)) / 2.0).round(), Vector2(side, side))
		draw_texture_rect_region(SHEET, icon, Rect2(0, clampi(gold, 0, LEVELS - 1) * FRAME, FRAME, FRAME))
		return
	_draw_stage(center)
	var frame: int = WAVE[int(_clock / WAVE_PERIOD) % WAVE.size()]
	var t: float = _squash / SQUASH_TIME
	var stretch: Vector2 = Vector2(1.0 + 0.08 * t, 1.0 - 0.1 * t)
	var cat_size: Vector2 = Vector2(FRAME, FRAME) * pixel_scale * stretch
	var feet: Vector2 = center + Vector2(0, FRAME * pixel_scale / 2.0)
	var rect: Rect2 = Rect2((feet - Vector2(cat_size.x / 2.0, cat_size.y)).round(), cat_size.round())
	var source: Rect2 = Rect2(frame * FRAME, clampi(gold, 0, LEVELS - 1) * FRAME, FRAME, FRAME)
	draw_texture_rect_region(SHEET, rect, source)
	for coin: Dictionary in _coins:
		var alpha: float = 1.0 - float(coin["age"]) / COIN_TIME
		var p: Vector2 = (coin["pos"] as Vector2).round()
		draw_circle(p, 4.0, Color(0.69, 0.45, 0.09, alpha))
		draw_circle(p - Vector2(0.5, 0.5), 3.0, Color(0.97, 0.79, 0.28, alpha))
		draw_rect(Rect2(p - Vector2(1, 2), Vector2(1, 3)), Color(1, 0.95, 0.7, alpha))
	if not detail_text.is_empty():
		CasinoArt.draw_text_centered(self, Vector2(size.x / 2.0, 13), detail_text, 9, Color("#e9c9d6"))
	if not title_text.is_empty():
		var points_at: Vector2 = Vector2(size.x / 2.0, size.y - 30.0)
		CasinoArt.draw_text_centered(self, points_at + Vector2(1, 1), title_text, 18, Color(0.1, 0.03, 0.05))
		CasinoArt.draw_text_centered(self, points_at, title_text, 18, CasinoArt.GOLD_TEXT)
	if interactive:
		_draw_combo()
	if not toast_text.is_empty():
		_draw_toast()
	for item: Dictionary in _floats:
		var age: float = float(item["age"]) / FLOAT_TIME
		var pos: Vector2 = (item["pos"] as Vector2) + Vector2(0, -46.0 * age)
		var color: Color = Color(1.0, 0.85, 0.35, 1.0 - age * age)
		CasinoArt.draw_text_centered(self, pos + Vector2(1, 1), str(item["text"]), 12, Color(0.12, 0.05, 0.05, color.a))
		CasinoArt.draw_text_centered(self, pos, str(item["text"]), 12, color)


## Dark stage with a neon rim, a warm spotlight and a round rug under the cat.
func _draw_stage(center: Vector2) -> void:
	var area: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(CasinoArt.box(Color("#1b1420"), Color("#3a2440"), 2, 10), area)
	var warm: float = clampf(combo - 1.0, 0.0, 1.0)
	for i: int in 6:
		var radius: float = 78.0 - i * 11.0
		var light: Color = Color(1.0, 0.45 + 0.25 * warm, 0.3, 0.035 + 0.02 * i + 0.03 * warm)
		draw_circle(center + Vector2(0, -6), radius, light)
	var rug: Vector2 = center + Vector2(0, FRAME * pixel_scale / 2.0 - 4.0)
	_draw_ellipse(rug, Vector2(70, 12), Color("#5c1820"))
	_draw_ellipse(rug, Vector2(62, 9), Color("#8e2228"))
	_draw_ellipse(rug + Vector2(0, -1), Vector2(54, 6), Color("#b52f30"))
	# Neon line along the bottom edge.
	draw_rect(Rect2(Vector2(10, size.y - 6), Vector2(size.x - 20, 2)), Color(1.0, 0.25, 0.35, 0.55 + 0.35 * warm))


## Combo meter along the bottom: fills while the taps come fast.
func _draw_combo() -> void:
	var bar: Rect2 = Rect2(Vector2(14, size.y - 16), Vector2(size.x - 28, 5))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var share: float = clampf(combo - 1.0, 0.0, 1.0)
	if share > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(1.0, 0.78 - 0.4 * share, 0.25))
		CasinoArt.draw_text_centered(self, Vector2(size.x - 40, 28), "КОМБО ×%s" % String.num(combo, 1).replace(".", ","), 8, CasinoArt.GOLD_TEXT)


func _draw_toast() -> void:
	var font: Font = CasinoArt.font()
	var lines: PackedStringArray = PackedStringArray()
	var line: String = ""
	for word: String in toast_text.split(" "):
		var candidate: String = word if line.is_empty() else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x > size.x - 36.0 and not line.is_empty():
			lines.append(line)
			line = word
		else:
			line = candidate
	lines.append(line)
	var height: float = 14.0 * lines.size() + 8.0
	var box: Rect2 = Rect2(Vector2(10, 22.0), Vector2(size.x - 20, height))
	draw_style_box(CasinoArt.box(Color(0.06, 0.03, 0.05, 0.88), CasinoArt.GOLD_TEXT, 1, 6), box)
	for i: int in lines.size():
		CasinoArt.draw_text_centered(self, Vector2(size.x / 2.0, box.position.y + 11.0 + 14.0 * i), lines[i], 9, CasinoArt.GOLD_TEXT)


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 24:
		var angle: float = TAU * i / 24.0
		points.append((center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)).round())
	draw_colored_polygon(points, color)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if not interactive or button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	tapped.emit(button.position)
