class_name ErrandScenePainter
extends IntroScenePainter
## Side-view backgrounds of the commute stops (ErrandScene): a coffee shop, a grocery store, a
## restaurant and a gas station. Same street layout as the courtyard: sidewalk from y 132, road
## from y 142. Doors match the scenes' _door() points.

const SIDEWALK: Color = Color("#c9c4bc")
const ASPHALT: Color = Color("#5a5d64")
const WARM: Color = Color("#ffe2a8")
const WARM_DEEP: Color = Color("#e8b870")


func paint(id: String) -> Image:
	match id:
		"coffee_shop", "grocery", "restaurant", "gas_station":
			c = PixelCanvas.create(IntroArt.IMAGES[id])
			rng.seed = hash(id)
		_:
			return super.paint(id)
	match id:
		"coffee_shop":
			_coffee_shop()
		"grocery":
			_grocery()
		"restaurant":
			_restaurant()
		"gas_station":
			_gas_station()
	return c.image


# --- Shared street ---------------------------------------------------------------


func _sky_and_city(from_x: int) -> void:
	c.gradient(0, 0, W, 142, Color("#7fb6e6"), Color("#d6ebf6"), 8)
	_cloud(220, 28, 46, Color(1, 1, 1, 0.85))
	_cloud(120, 18, 30, Color(1, 1, 1, 0.7))
	var x: int = from_x
	while x < W:
		var bw: int = rng.randi_range(16, 32)
		var bh: int = rng.randi_range(36, 80)
		c.rect(x, 132 - bh, bw, bh, Color("#a9b8c8"))
		for wy: int in range(132 - bh + 4, 128, 6):
			for wx: int in range(x + 3, x + bw - 2, 5):
				c.rect(wx, wy, 2, 3, Color("#c3d0dc"))
		x += bw + rng.randi_range(0, 4)


func _street(lamp_x: int) -> void:
	c.rect(0, 132, W, 8, SIDEWALK)
	for jx: int in range(6, W, 20):
		c.vline(jx, 132, 8, Color("#b5b0a8"))
	c.rect(0, 140, W, 2, Color("#e3ded6"))
	c.rect(0, 142, W, 38, ASPHALT)
	for i: int in 160:
		c.px(rng.randi_range(0, W - 1), rng.randi_range(142, 179), Color("#676a72") if i % 2 else Color("#4f5258"))
	for dash: int in range(8, W, 40):
		c.rect(dash, 170, 20, 2, Color("#e9e5de"))
	c.rect(lamp_x, 44, 3, 96, Color("#3a3f46"))
	c.rect(lamp_x - 11, 44, 12, 2, Color("#3a3f46"))
	c.rect(lamp_x - 13, 46, 8, 3, Color("#fff4cf"))


## A shop window with a warm interior: `inside` paints people and furniture on top.
func _shop_window(x: int, y: int, w: int, h: int, frame: Color) -> void:
	_obj(x - 2, y - 2, w + 4, h + 4, frame)
	c.gradient(x, y, w, h, WARM, WARM_DEEP, 4)
	c.line(x + 3, y + h - 4, x + 14, y + 3, Color(1, 1, 1, 0.35))


func _silhouette(x: int, base_y: int, color: Color) -> void:
	c.ellipse(x + 3, base_y - 14, 3, 3, color)
	c.rect(x, base_y - 11, 7, 11, color)


func _potted_shrub(x: int, base_y: int) -> void:
	_obj(x, base_y - 9, 12, 9, Color("#6e737b"))
	for k: int in 6:
		c.ellipse(x + 2 + k * 1.7, base_y - 12 - (k % 2) * 2, 3.5, 3.5, Color("#4f9a4a") if k % 2 else Color("#66b35a"))


# --- Coffee shop (door at x 90) ----------------------------------------------------


func _coffee_shop() -> void:
	_sky_and_city(178)
	var facade: Color = Color("#e8dcc4")
	c.rect(0, 26, 176, 106, facade)
	c.vline(175, 26, 106, Palette.shade(facade, 0.2))
	for col: int in 5:
		var wx: int = 10 + col * 34
		_obj(wx, 36, 16, 14, Color("#f4f1ec"))
		c.gradient(wx + 1, 37, 14, 12, Color("#8fb6d6"), Color("#5a7a96"), 3)
		c.vline(wx + 8, 37, 12, Color("#f4f1ec"))
	# Brick base and the sign board with a coffee cup.
	c.rect(0, 74, 176, 58, Color("#a8604a"))
	for by: int in range(76, 132, 4):
		for bx: int in range(((by / 4) % 2) * 6, 176, 12):
			c.hline(bx, by, mini(11, 175 - bx), Color("#b86e56"))
	_obj(44, 58, 92, 12, Color("#2f3a3a"))
	c.rect(84, 60, 8, 7, WHITE)
	c.rect(92, 62, 2, 3, WHITE)
	c.rect(85, 61, 6, 2, Color("#8a5a3a"))
	for i: int in 3:
		c.vline(86 + i * 2, 56 - i % 2, 3, Color(1, 1, 1, 0.7))
	for i: int in 4:
		c.rect(52 + i * 6, 63, 4, 2, Color("#e8dcc4"))
		c.rect(100 + i * 7, 63, 5, 2, Color("#e8dcc4"))
	# Awning in teal and cream stripes with a scalloped edge.
	for ax: int in range(4, 172, 8):
		c.rect(ax, 72, 8, 10, Color("#2f8f8a") if (ax / 8) % 2 == 0 else Color("#f3eee4"))
		c.ellipse(ax + 4, 82, 4, 2, Color("#2f8f8a") if (ax / 8) % 2 == 0 else Color("#f3eee4"))
	c.hline(4, 72, 168, Palette.shade(Color("#2f8f8a"), 0.2))
	# Window with the counter, the espresso machine and the barista.
	_shop_window(10, 88, 60, 36, Color("#3a2a24"))
	c.rect(10, 112, 60, 12, Color("#6e4a36"))
	c.hline(10, 112, 60, Color("#8a6048"))
	_obj(16, 102, 14, 10, Color("#c9ced6"))
	c.rect(19, 106, 3, 3, INK)
	_silhouette(44, 112, Color("#5a3a2e"))
	c.rect(43, 101, 9, 2, WHITE)
	for i: int in 5:
		c.rect(56 + i * 2, 108, 1, 4, Color.from_hsv(rng.randf(), 0.5, 0.8))
	# Door.
	_obj(80, 92, 20, 40, Color("#3a2a24"))
	c.gradient(83, 95, 14, 22, WARM, WARM_DEEP, 3)
	c.rect(96, 112, 2, 4, Color("#d9a43c"))
	# Second window: guests at the tables.
	_shop_window(108, 88, 60, 36, Color("#3a2a24"))
	for gx: int in [116, 144]:
		c.rect(gx, 112, 16, 2, WHITE)
		c.vline(gx + 8, 114, 8, Color("#5a3a2e"))
		_silhouette(gx - 4, 118, Color("#4a3a4a"))
		_silhouette(gx + 14, 118, Color("#3a4a5a"))
		c.rect(gx + 6, 109, 2, 3, WHITE)
	# Chalkboard menu and a planter by the door.
	c.line(58, 132, 62, 112, Color("#6e4a36"))
	c.line(70, 132, 66, 112, Color("#6e4a36"))
	_obj(58, 112, 12, 14, Color("#2f3a3a"))
	for i: int in 4:
		c.hline(60, 115 + i * 3, rng.randi_range(4, 8), Color(1, 1, 1, 0.7))
	_potted_shrub(102, 132)
	_street(300)


# --- Grocery store (door at x 100) -------------------------------------------------


func _grocery() -> void:
	_sky_and_city(204)
	var wall: Color = Color("#f2efe9")
	c.rect(0, 58, 204, 74, wall)
	c.vline(203, 58, 74, Palette.shade(wall, 0.2))
	_obj(0, 60, 204, 18, Color("#3f9a4a"))
	# Sign: an apple, a carrot and blocky letters.
	c.ellipse(20, 69, 5, 5, RED)
	c.vline(20, 62, 3, Color("#6b4a36"))
	c.ellipse(23, 63, 2, 1, Color("#8bd07a"))
	_poly([Vector2(32, 64), Vector2(42, 66), Vector2(32, 72)], Color("#ff9a3c"))
	c.rect(30, 63, 3, 2, Color("#8bd07a"))
	for i: int in 9:
		_obj(52 + i * 14, 64, 10, 10, WHITE)
		c.rect(55 + i * 14, 67, 4, 4, Color("#3f9a4a"))
	for wx: int in [8, 120]:
		var ww: int = 72 if wx == 8 else 76
		_shop_window(wx, 86, ww, 42, Color("#9aa0a8"))
		for row: int in 3:
			var sy: int = 96 + row * 11
			c.rect(wx, sy, ww, 2, Color("#c9ced6"))
			var px: int = wx + 2
			while px < wx + ww - 3:
				var pw: int = rng.randi_range(2, 4)
				c.rect(px, sy - 5, pw, 5, Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.7, 0.95)))
				px += pw + 1
		_obj(wx + ww - 22, 90, 16, 10, Color("#ffcc33"))
		c.rect(wx + ww - 18, 93, 8, 4, RED)
	# Sliding glass doors.
	_obj(86, 88, 28, 44, Color("#9aa0a8"))
	c.gradient(88, 90, 12, 42, Color("#cfe4ee"), Color("#9ab8c6"), 4)
	c.gradient(100, 90, 12, 42, Color("#cfe4ee"), Color("#9ab8c6"), 4)
	c.vline(100, 90, 42, Color("#7a8088"))
	c.rect(90, 80, 20, 4, Color("#2a2f36"))
	c.rect(92, 81, 6, 2, Color("#4cd964"))
	# Trolleys parked along the wall.
	for i: int in 4:
		var tx: int = 150 + i * 10
		c.rect(tx, 118, 14, 8, Color(0.7, 0.72, 0.76, 0.9))
		for gx: int in range(tx + 1, tx + 14, 3):
			c.vline(gx, 119, 6, Color("#e9ecef"))
		c.px(tx + 2, 130, INK)
		c.px(tx + 12, 130, INK)
		c.line(tx + 13, 118, tx + 16, 113, METAL)
	_street(308)


# --- Restaurant (door at x 92) ----------------------------------------------------


func _restaurant() -> void:
	_sky_and_city(194)
	var brick: Color = Color("#6a3a2e")
	c.rect(0, 20, 192, 112, brick)
	c.vline(191, 20, 112, Palette.shade(brick, 0.2))
	for by: int in range(22, 132, 4):
		for bx: int in range(((by / 4) % 2) * 6, 192, 12):
			c.hline(bx, by, mini(11, 191 - bx), Palette.light(brick, 0.06))
	for col: int in 4:
		var wx: int = 14 + col * 46
		_obj(wx, 30, 18, 18, Color("#d9c9a8"))
		c.gradient(wx + 1, 31, 16, 16, Color("#8fb6d6"), Color("#5a7a96"), 3)
	# Neon wine glass and a squiggle as the sign.
	_obj(56, 56, 80, 14, Color("#1d1d24"))
	c.line(70, 59, 74, 64, Color("#ff4fa3"))
	c.line(78, 59, 74, 64, Color("#ff4fa3"))
	c.vline(74, 64, 4, Color("#ff4fa3"))
	c.hline(71, 67, 7, Color("#ff4fa3"))
	for i: int in 40:
		c.px(86 + i, 63 + roundi(sin(i * 0.5) * 2.5), Color("#5ce1e6"))
	# Arched windows: white tablecloths, candles and diners.
	for wx: int in [12, 122]:
		_obj(wx - 2, 82, 54, 44, Color("#3a2a24"))
		c.ellipse(wx + 25, 84, 25, 8, Color("#3a2a24"))
		c.gradient(wx, 84, 50, 40, WARM, WARM_DEEP, 4)
		c.ellipse(wx + 25, 86, 23, 6, WARM)
		for tx: int in [wx + 6, wx + 30]:
			c.rect(tx, 112, 14, 3, WHITE)
			c.vline(tx + 7, 115, 9, Color("#3a2a24"))
			c.rect(tx + 6, 108, 2, 4, WHITE)
			c.px(tx + 6, 107, Color("#ffcc33"))
			_silhouette(tx - 5, 118, Color("#4a2a3a"))
			_silhouette(tx + 12, 118, Color("#2a3a4a"))
	# Door with a small awning, brass handle, shrubs and a menu stand.
	_obj(72, 80, 40, 7, Color("#8a1f1a"))
	c.rect(74, 87, 36, 2, Color(0, 0, 0, 0.25))
	_obj(82, 90, 20, 42, Color("#4a2a1e"))
	c.gradient(85, 94, 14, 16, WARM, WARM_DEEP, 3)
	c.rect(98, 112, 2, 4, Color("#d9a43c"))
	_potted_shrub(66, 132)
	_potted_shrub(106, 132)
	c.vline(126, 116, 16, Color("#2a2f36"))
	_obj(120, 106, 12, 12, Color("#f3eee4"))
	for i: int in 3:
		c.hline(122, 109 + i * 3, 8, Color("#8a8f98"))
	_street(304)


# --- Gas station (kiosk door at x 30, pump at x 92) --------------------------------


func _gas_station() -> void:
	_sky_and_city(270)
	# Kiosk with a window and a door.
	var kiosk: Color = Color("#f2efe9")
	c.rect(0, 74, 56, 58, kiosk)
	_obj(0, 70, 58, 8, Color("#3a6fb5"))
	_shop_window(6, 86, 14, 22, Color("#9aa0a8"))
	_obj(22, 92, 18, 40, Color("#9aa0a8"))
	c.gradient(24, 94, 14, 38, Color("#cfe4ee"), Color("#9ab8c6"), 4)
	_shop_window(42, 86, 12, 22, Color("#9aa0a8"))
	for i: int in 3:
		c.rect(8 + i * 4, 98, 3, 8, Color.from_hsv(rng.randf(), 0.6, 0.85))
	# Canopy on two pillars with lights underneath.
	_obj(60, 30, 220, 12, WHITE)
	c.rect(60, 38, 220, 3, Color("#3a6fb5"))
	c.rect(60, 42, 220, 2, Color("#c9ced6"))
	for lx: int in range(74, 280, 28):
		c.rect(lx, 44, 10, 2, Color("#fff4cf"))
	for pillar_x: int in [70, 262]:
		_obj(pillar_x, 44, 6, 88, Color("#e9ecef"))
	# Pump island and the pump: the scene draws the counter on its display.
	_obj(70, 126, 50, 6, Color("#c9c4bc"))
	_obj(82, 86, 22, 40, Color("#e9ecef"))
	c.rect(82, 86, 22, 6, Color("#3a6fb5"))
	c.rect(85, 95, 16, 10, Color("#1d2433"))
	c.rect(86, 110, 5, 3, Color("#2a2f36"))
	c.rect(93, 110, 5, 3, Color("#2a2f36"))
	c.rect(101, 106, 4, 9, Color("#2a2f36"))
	c.vline(104, 112, 10, Color("#2a2f36"))
	# Price board on a pole: three rows of orange digits.
	c.rect(296, 70, 3, 62, Color("#6e737b"))
	_obj(282, 26, 32, 46, Color("#1d2433"))
	c.rect(282, 26, 32, 6, Color("#3a6fb5"))
	var prices: Array[String] = ["58", "62", "71"]
	for row: int in 3:
		c.rect(285, 35 + row * 12, 8, 7, [Color("#4f9a4a"), Color("#ffcc33"), Color("#3a3a44")][row])
		_digits(prices[row], 296, 36 + row * 12, Color("#ff9a3c"))
	_street(330)


func _digits(text: String, x: int, y: int, color: Color) -> void:
	var cursor: int = x
	for digit: String in text:
		var glyph: String = IntroScene.GLYPHS.get(digit, "")
		for i: int in glyph.length():
			if glyph[i] == "1":
				c.px(cursor + i % 3, y + i / 3, color)
		cursor += 4
