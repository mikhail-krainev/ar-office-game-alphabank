class_name HomeDecorPropPainter
extends PropPainterBase
## Interior items the player buys for the apartment (posters, aquarium, arcade, chairs) and the
## house props: fireplace, garage door, backyard tree, pool, loungers and the grill.

const NEON_PINK: Color = Color("#ff4fa3")
const NEON_CYAN: Color = Color("#5ce1e6")
const SUNSET: Color = Color("#ff9a3c")
const WATER: Color = Color("#3fa9d6")
const STONE: Color = Color("#b9b3aa")
const CANVAS: Color = Color("#f3eee4")


func paint(id: String, w: int, h: int) -> bool:
	match id:
		"fireplace":
			_fireplace(w, h)
		"garage_door":
			_garage_door(w, h)
		"tree":
			_tree(w, h)
		"lounger":
			_lounger(w, h)
		"bbq_grill":
			_grill(w, h)
		"pool":
			_pool(w, h)
		"aquarium":
			_aquarium(w, h)
		"record_player":
			_record_player(w, h)
		"arcade_cabinet":
			_arcade(w, h)
		"egg_chair":
			_egg_chair(w, h)
		"cactus":
			_cactus(w, h)
		"poster_synthwave":
			_poster_synthwave(w, h)
		"poster_palms":
			_poster_palms(w, h)
		"poster_tiger":
			_poster_tiger(w, h)
		"neon_heart":
			_neon_heart(w, h)
		"art_abstract":
			_art_abstract(w, h)
		_:
			return false
	return true


func _fireplace(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	# Concrete slab with a wide firebox: a minimalist built-in fireplace.
	box(2, 0, w - 4, 4, h - 6, Color("#d9d6d0"))
	c.rect(4, 6, w - 8, 2, Palette.shade(STONE, 0.05))
	var box_x: int = 12
	var box_w: int = w - 24
	c.rect(box_x, 18, box_w, h - 30, INK)
	c.rect(box_x + 2, 20, box_w - 4, h - 34, Color("#2a1712"))
	# Logs and flames.
	c.rect(box_x + 10, h - 18, box_w - 20, 3, Color("#6b3f22"))
	c.rect(box_x + 16, h - 20, box_w - 32, 3, Color("#7d4a28"))
	for i: int in 9:
		var fx: float = box_x + 12 + i * (box_w - 24) / 8.0
		var flame_h: float = rng.randf_range(8.0, 16.0)
		c.ellipse(fx, h - 20 - flame_h / 2.0, 3.2, flame_h / 2.0, SUNSET)
		c.ellipse(fx, h - 19 - flame_h / 3.0, 1.8, flame_h / 3.0, Color("#ffd75e"))
	c.ellipse(w / 2.0, h - 16, box_w / 2.0 - 4, 3, Color(1.0, 0.55, 0.2, 0.35))
	c.hline(box_x, 18, box_w, Palette.light(INK, 0.15))
	# Hearth.
	box(6, h - 10, w - 12, 3, 5, Color("#4a4c50"))


func _garage_door(w: int, h: int) -> void:
	var metal: Color = Color("#cfd2d6")
	c.rect(0, 0, w, h, Color("#55585e"))
	c.rect(4, 4, w - 8, h - 4, metal)
	for y: int in range(4, h, 7):
		c.hline(4, y, w - 8, Palette.shade(metal, 0.18))
		c.hline(4, y + 1, w - 8, Palette.light(metal, 0.1))
	c.rect(w / 2 - 8, h - 14, 16, 3, Palette.shade(metal, 0.35))
	c.rect(w - 14, 8, 6, 3, Palette.ALFA_RED)


func _tree(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 3, w / 2.0 - 4, 4)
	var bark: Color = Color("#6b4a32")
	c.rect(w / 2 - 3, h - 34, 6, 32, bark)
	c.vline(w / 2 - 2, h - 34, 32, Palette.light(bark, 0.12))
	c.line(w / 2, h - 30, w / 2 + 12, h - 44, bark)
	c.line(w / 2, h - 34, w / 2 - 10, h - 48, bark)
	var crowns: Array[Vector3] = [
		Vector3(w / 2.0, 30, 26), Vector3(w / 2.0 - 14, 42, 16), Vector3(w / 2.0 + 14, 40, 17), Vector3(w / 2.0, 18, 18),
	]
	for crown: Vector3 in crowns:
		c.ellipse(crown.x, crown.y + 2, crown.z, crown.z * 0.82, Palette.shade(LEAF, 0.22))
	for crown: Vector3 in crowns:
		c.ellipse(crown.x, crown.y, crown.z - 2, crown.z * 0.8 - 2, LEAF)
	for i: int in 40:
		var leaf_x: float = rng.randf_range(10.0, w - 10.0)
		var leaf_y: float = rng.randf_range(6.0, 58.0)
		c.ellipse(leaf_x, leaf_y, 2.5, 1.6, Palette.light(LEAF, 0.18) if i % 2 else Palette.shade(LEAF, 0.1))


func _lounger(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	var frame: Color = Color("#e9e4da")
	var cushion: Color = Color("#f2f0ea")
	c.rect(3, 4, w - 6, h - 10, frame)
	c.rect(5, 2, w - 10, 16, Palette.light(cushion, 0.05))
	c.hline(5, 18, w - 10, Palette.shade(frame, 0.2))
	c.rect(5, 20, w - 10, h - 28, cushion)
	for y: int in range(24, h - 8, 6):
		c.hline(6, y, w - 12, Palette.shade(cushion, 0.08))
	c.rect(9, 6, 10, 6, NEON_CYAN)
	c.rect(4, h - 6, 3, 4, INK)
	c.rect(w - 7, h - 6, 3, 4, INK)


func _grill(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	for x: int in [6, w - 9]:
		c.rect(x, 22, 3, h - 24, INK)
	c.ellipse(w / 2.0, 18, 13, 9, Color("#2a2a30"))
	c.ellipse(w / 2.0, 13, 12, 5, Color("#3a3a44"))
	for x: int in range(6, w - 6, 3):
		c.vline(x, 10, 6, Color("#8f949c"))
	c.ellipse(11, 12, 3, 1.5, Color("#9b3b2a"))
	c.ellipse(19, 13, 3, 1.5, Color("#9b3b2a"))
	c.line(12, 6, 10, 0, Color(0.85, 0.85, 0.85, 0.4))
	c.line(19, 7, 21, 1, Color(0.85, 0.85, 0.85, 0.3))


func _pool(w: int, h: int) -> void:
	var deck: Color = Color("#d8cbb4")
	c.rect(0, 0, w, h, deck)
	for x: int in range(0, w, 8):
		c.vline(x, 0, h, Palette.shade(deck, 0.08))
	c.rect(8, 8, w - 16, h - 16, Color("#e9eef0"))
	c.rect(10, 10, w - 20, h - 20, WATER)
	c.rect(10, 10, w - 20, 5, Palette.shade(WATER, 0.25))
	for i: int in 26:
		var x: int = rng.randi_range(14, w - 22)
		var y: int = rng.randi_range(18, h - 14)
		c.hline(x, y, rng.randi_range(4, 8), Palette.light(WATER, 0.3))
	c.rect(w - 22, 8, 2, 14, Color("#c9ced6"))
	c.rect(w - 16, 8, 2, 14, Color("#c9ced6"))
	for y: int in [12, 16, 20]:
		c.hline(w - 22, y, 8, Color("#c9ced6"))
	c.ellipse(30, h / 2.0, 7, 4, Palette.ALFA_RED)
	c.ellipse(30, h / 2.0, 4, 2, WATER)


func _aquarium(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	box(2, h - 18, w - 4, 4, 14, WALNUT)
	c.rect(3, 4, w - 6, h - 22, Color("#2a3a44"))
	c.gradient(5, 6, w - 10, h - 26, Color("#4fc3e8"), Color("#1f6f9c"), 5)
	c.rect(5, h - 26, w - 10, 4, Color("#e0c88f"))
	for x: int in [12, 20, 44]:
		c.line(x, h - 24, x + rng.randi_range(-3, 3), h - 38, LEAF)
	var fish: Array[Color] = [SUNSET, Palette.ALFA_RED, Color("#f7c948"), NEON_CYAN]
	for i: int in fish.size():
		var fx: float = 12 + i * 11
		var fy: float = 14 + (i % 2) * 8
		c.ellipse(fx, fy, 3, 1.6, fish[i])
		c.px(int(fx) - 4, int(fy), fish[i])
	for i: int in 5:
		c.px(48, 8 + i * 4, Color(1, 1, 1, 0.6))
	c.hline(3, 4, w - 6, Color("#8f949c"))
	c.line(7, 8, 14, 22, Color(1, 1, 1, 0.18))


func _record_player(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	for x: int in [4, w - 7]:
		c.rect(x, 18, 3, h - 20, WALNUT)
	box(1, 16, w - 2, 3, 8, WALNUT)
	for i: int in 4:
		c.vline(5 + i * 5, 27, 8, [Palette.ALFA_RED, NEON_CYAN, Color("#f7c948"), Palette.WHITE][i])
	box(2, 8, w - 4, 6, 3, Color("#3a3a44"))
	c.ellipse(w / 2.0 - 2, 11, 9, 3, INK)
	c.ellipse(w / 2.0 - 2, 11, 3, 1, Palette.ALFA_RED)
	c.line(w - 6, 8, w - 10, 12, METAL)


func _arcade(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	var body: Color = Color("#2b1846")
	c.rect(3, 2, w - 6, h - 4, body)
	c.rect(3, 2, w - 6, 10, NEON_PINK)
	c.hline(5, 6, w - 10, Palette.WHITE)
	c.rect(6, 14, w - 12, 20, INK)
	c.rect(8, 16, w - 16, 16, Color("#120a24"))
	c.rect(10, 26, 5, 3, NEON_CYAN)
	c.rect(16, 20, 3, 3, Color("#f7c948"))
	c.hline(9, 30, w - 18, NEON_PINK)
	box(2, 36, w - 4, 6, 4, Palette.shade(body, 0.1))
	c.rect(8, 37, 2, 4, INK)
	c.ellipse(9, 37, 2, 1.5, Palette.ALFA_RED)
	c.ellipse(19, 39, 1.5, 1.2, NEON_CYAN)
	c.ellipse(24, 39, 1.5, 1.2, Color("#f7c948"))
	c.vline(3, 12, h - 16, NEON_CYAN)
	c.vline(w - 4, 12, h - 16, NEON_CYAN)
	c.rect(12, h - 18, 8, 4, Palette.shade(body, 0.3))


func _egg_chair(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 4)
	c.rect(w / 2 - 1, h - 12, 3, 10, METAL)
	c.ellipse(w / 2.0, h - 3, 9, 2, METAL)
	c.ellipse(w / 2.0, 22, 15, 21, Palette.WHITE)
	c.ellipse(w / 2.0, 24, 11, 16, Color("#e3473d"))
	c.ellipse(w / 2.0, 30, 9, 8, Palette.shade(Color("#e3473d"), 0.15))
	c.ellipse(w / 2.0 - 5, 16, 3, 6, Color(1, 1, 1, 0.25))


func _cactus(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 3)
	box(4, h - 12, w - 8, 3, 9, Color("#c9785a"))
	var green: Color = Color("#4f8a4a")
	c.rect(w / 2 - 3, 6, 6, h - 18, green)
	c.ellipse(w / 2.0, 6, 3, 3, green)
	c.rect(2, 14, 3, 8, green)
	c.hline(2, 21, 6, green)
	c.rect(w - 5, 10, 3, 9, green)
	c.hline(w - 8, 18, 6, green)
	c.vline(w / 2 - 1, 5, h - 18, Palette.light(green, 0.18))
	for y: int in range(8, h - 14, 4):
		c.px(w / 2 + 2, y, Palette.WHITE)
	c.px(w / 2, 2, NEON_PINK)
	c.px(w / 2 + 1, 3, NEON_PINK)


func _poster_frame(w: int, h: int, inner: Color) -> void:
	c.rect(0, 0, w, h, INK)
	c.rect(1, 1, w - 2, h - 2, inner)


func _poster_synthwave(w: int, h: int) -> void:
	_poster_frame(w, h, Color("#1a0b2e"))
	c.gradient(2, 2, w - 4, h / 2 - 2, Color("#2b1846"), Color("#ff4fa3"), 5)
	c.ellipse(w / 2.0, h / 2.0 - 2, 7, 7, SUNSET)
	for y: int in [h / 2 - 5, h / 2 - 2, h / 2 + 1]:
		c.hline(4, y, w - 8, Color("#ff4fa3"))
	c.rect(2, h / 2 + 2, w - 4, h / 2 - 4, Color("#120a24"))
	for y: int in range(h / 2 + 4, h - 2, 4):
		c.hline(2, y, w - 4, NEON_CYAN)
	for x: int in range(-8, w + 8, 6):
		c.line(w / 2, h / 2 + 2, x, h - 3, Color(0.36, 0.88, 0.9, 0.7))


func _poster_palms(w: int, h: int) -> void:
	_poster_frame(w, h, Color("#ffe7c2"))
	c.gradient(2, 2, w - 4, h - 4, Color("#ffcf8a"), Color("#ff7a7a"), 6)
	c.ellipse(w / 2.0, h - 14, 8, 8, Color("#fff1c9"))
	c.rect(2, h - 10, w - 4, 8, Color("#4b6cb7"))
	for palm_x: int in [7, 18]:
		c.line(palm_x, h - 10, palm_x + 2, 10, Color("#3a2a20"))
		for angle: float in [-2.6, -2.0, -1.2, -0.5]:
			var tip: Vector2 = Vector2(palm_x + 2, 10) + Vector2(cos(angle), sin(angle) * 0.6) * 7
			c.line(palm_x + 2, 10, roundi(tip.x), roundi(tip.y), Color("#2f4a2a"))


func _poster_tiger(w: int, h: int) -> void:
	_poster_frame(w, h, Color("#14110f"))
	var fur: Color = Color("#f08a24")
	c.ellipse(w / 2.0, h / 2.0, 9, 11, fur)
	c.ellipse(w / 2.0 - 7, h / 2.0 - 10, 3, 3, fur)
	c.ellipse(w / 2.0 + 7, h / 2.0 - 10, 3, 3, fur)
	c.ellipse(w / 2.0, h / 2.0 + 5, 5, 4, Palette.WHITE)
	for stripe: int in [-6, -2, 2, 6]:
		c.line(w / 2 + stripe, h / 2 - 9, w / 2 + stripe / 2, h / 2 - 4, INK)
	c.px(w / 2 - 4, h / 2 - 2, Color("#5ce1a0"))
	c.px(w / 2 + 4, h / 2 - 2, Color("#5ce1a0"))
	c.rect(w / 2 - 1, h / 2 + 3, 3, 2, Color("#e3473d"))
	c.hline(3, h - 5, w - 6, NEON_PINK)


func _neon_heart(w: int, h: int) -> void:
	var glow: Color = Color(1.0, 0.31, 0.64, 0.25)
	c.ellipse(w / 2.0, h / 2.0, w / 2.0, h / 2.0, glow)
	var heart: PackedVector2Array = PackedVector2Array([
		Vector2(w / 2.0, h - 4), Vector2(3, h / 2.0 - 1), Vector2(4, 5), Vector2(9, 3), Vector2(w / 2.0, 7),
		Vector2(w - 9, 3), Vector2(w - 4, 5), Vector2(w - 3, h / 2.0 - 1),
	])
	for i: int in heart.size():
		var a: Vector2 = heart[i]
		var b: Vector2 = heart[(i + 1) % heart.size()]
		c.line(roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y), NEON_PINK)
	c.px(w / 2, h - 5, Palette.WHITE)
	c.px(6, 6, Palette.WHITE)


func _art_abstract(w: int, h: int) -> void:
	c.rect(0, 0, w, h, Color("#8a7a66"))
	c.rect(2, 2, w - 4, h - 4, CANVAS)
	c.ellipse(18, 18, 11, 11, Palette.ALFA_RED)
	c.rect(28, 6, 20, 14, Color("#2b4a8a"))
	c.polygon(PackedVector2Array([Vector2(8, h - 4), Vector2(30, 22), Vector2(46, h - 4)]), Color("#f7c948"))
	c.line(4, 30, w - 5, 12, INK)
	c.rect(40, 26, 10, 10, INK)
