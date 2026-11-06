class_name LivedInPropPainter
extends PropPainterBase
## Everyday clutter that makes the apartment look lived in: shelves, a laundry basket, a drying
## rack, slippers by the bed, boxes, a sleeping cat. Built into the apartments, not sold.

const FABRIC: Color = Color("#d9cbb5")
const CARDBOARD: Color = Color("#c9a26b")
const PORCELAIN: Color = Color("#f4f3ef")
const CAT: Color = Color("#e08a3c")


func paint(id: String, w: int, h: int) -> bool:
	match id:
		"wall_shelf":
			_wall_shelf(w, h)
		"spice_rack":
			_spice_rack(w, h)
		"bath_shelf":
			_bath_shelf(w, h)
		"wall_sconce":
			_sconce(w, h)
		"photo_collage":
			_photo_collage(w, h)
		"plant_hanging":
			_plant_hanging(w, h)
		"laundry_basket":
			_laundry_basket(w, h)
		"side_table":
			_side_table(w, h)
		"book_stack":
			_book_stack(w, h)
		"slippers":
			_slippers()
		"sneakers":
			_sneakers()
		"umbrella_stand":
			_umbrella_stand(w, h)
		"backpack":
			_backpack(w, h)
		"counter_dishes":
			_counter_dishes(w, h)
		"vacuum":
			_vacuum(w, h)
		"ironing_board":
			_ironing_board(w, h)
		"boxes_stack":
			_boxes_stack(w, h)
		"floor_fan":
			_floor_fan(w, h)
		"rug_runner":
			_rug_runner(w, h)
		"rug_round":
			_rug_round(w, h)
		"bin_small":
			_bin_small(w, h)
		"cat_bed":
			_cat_bed(w, h)
		"dryer_rack":
			_dryer_rack(w, h)
		_:
			return false
	return true


func _books_row(x: int, base_y: int, width: int, max_h: int) -> void:
	var bx: int = x
	while bx < x + width:
		var bw: int = mini(rng.randi_range(2, 3), x + width - bx)
		var bh: int = rng.randi_range(max_h - 3, max_h)
		var hue: Color = Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.85))
		if rng.randf() < 0.15:
			hue = Palette.ALFA_RED
		c.rect(bx, base_y - bh, bw, bh, hue)
		c.px(bx, base_y - bh + 1, Palette.light(hue, 0.25))
		bx += bw
	c.hline(x, base_y - 1, width, Color(0, 0, 0, 0.12))


func _wall_shelf(w: int, h: int) -> void:
	_books_row(2, h - 4, 14, 10)
	c.rect(19, h - 9, 6, 5, Color("#c9754a"))
	for i: int in 5:
		c.ellipse(20 + i, h - 11 - (i % 2) * 2, 2, 1.5, LEAF if i % 2 else Palette.light(LEAF, 0.15))
	c.line(22, h - 14, 26, h - 6, Palette.shade(LEAF, 0.1))
	c.rect(0, h - 4, w, 3, OAK)
	c.hline(0, h - 4, w, Palette.light(OAK, 0.15))
	c.hline(0, h - 2, w, Palette.shade(OAK, 0.25))
	c.rect(4, h - 1, 2, 1, METAL)
	c.rect(w - 6, h - 1, 2, 1, METAL)


func _spice_rack(w: int, h: int) -> void:
	for row: int in 2:
		var y: int = 1 + row * 7
		for i: int in 5:
			var x: int = 2 + i * 6
			var lid: Color = [Palette.ALFA_RED, Color("#3a3a44"), Color("#d9a43c"), Color("#4f9a4a"), Color("#e07a3f")][(i + row) % 5]
			c.rect(x, y + 1, 4, 4, Color(0.85, 0.9, 0.92, 0.9))
			c.rect(x, y + 3, 4, 2, [Color("#b5452b"), Color("#d9b04a"), Color("#6a8a3c"), Color("#7a4a2a")][(i * 3 + row) % 4])
			c.hline(x, y, 4, lid)
		c.rect(0, y + 5, w, 2, WALNUT)
	c.hline(0, h - 2, w, Palette.shade(WALNUT, 0.25))


func _bath_shelf(w: int, h: int) -> void:
	c.rect(1, h - 4, w - 2, 2, Color(0.85, 0.93, 0.96, 0.9))
	c.hline(1, h - 2, w - 2, METAL)
	var bottles: Array = [[2, 10, Color("#5ac8d8")], [7, 13, Palette.WHITE], [12, 8, Color("#f59ab0")], [17, 11, Color("#4f9a4a")]]
	for bottle: Array in bottles:
		var bx: int = bottle[0]
		var bh: int = bottle[1]
		c.rect(bx, h - 4 - bh, 4, bh, bottle[2])
		c.vline(bx, h - 4 - bh, bh, Palette.light(bottle[2], 0.2))
		c.rect(bx + 1, h - 6 - bh, 2, 2, Palette.shade(bottle[2], 0.3))
	c.rect(21, h - 8, 3, 4, Color("#f6ead0"))


func _sconce(w: int, h: int) -> void:
	c.ellipse(w / 2.0, h / 2.0 + 1, 6, 8, Color(1.0, 0.85, 0.5, 0.18))
	c.rect(w / 2 - 1, 8, 2, 8, METAL)
	c.rect(w / 2 - 3, 14, 6, 3, Palette.shade(METAL, 0.2))
	c.polygon(PackedVector2Array([Vector2(1, 9), Vector2(3, 1), Vector2(w - 3, 1), Vector2(w - 1, 9)]), Color("#f6ead0"))
	c.hline(2, 8, w - 4, Color("#e3cfa6"))


func _photo_collage(_w: int, _h: int) -> void:
	var frames: Array = [
		[1, 3, 16, 12, Color("#a9d6ee"), Color("#4f9a4a")], [20, 1, 14, 18, Color("#f2c27a"), Color("#c96a4a")],
		[37, 5, 16, 11, Color("#7a6ad8"), Color("#ff9a3c")], [6, 18, 12, 10, Color("#f59ab0"), Color("#fbfaf8")],
		[38, 18, 12, 10, Color("#5ce1e6"), Color("#3a7bd5")],
	]
	for frame: Array in frames:
		var x: int = frame[0]
		var y: int = frame[1]
		var fw: int = frame[2]
		var fh: int = frame[3]
		c.rect(x, y, fw, fh, INK if frame[0] != 20 else OAK)
		c.rect(x + 1, y + 1, fw - 2, fh - 2, Palette.WHITE)
		c.gradient(x + 2, y + 2, fw - 4, fh - 4, frame[4], frame[5], 3)
		c.ellipse(x + fw / 2.0, y + fh - 4.0, 2.0, 2.5, Color("#3a3a44"))
		c.px(x + fw / 2, y + fh - 7, Palette.SKIN_TONES[(x / 6) % 4])
	c.line(24, 22, 30, 26, Color("#d9a43c"))
	c.rect(22, 22, 3, 3, Color("#f6ead0"))


func _plant_hanging(w: int, h: int) -> void:
	c.line(w / 2, 0, 4, 10, Color("#8a6a4a"))
	c.line(w / 2, 0, w - 5, 10, Color("#8a6a4a"))
	c.ellipse(w / 2.0, 12, 6, 3, Color("#f3eee4"))
	c.rect(w / 2 - 6, 11, 12, 4, Color("#f3eee4"))
	c.hline(w / 2 - 6, 14, 12, Color("#d9d2c6"))
	for i: int in 8:
		var x: int = rng.randi_range(2, w - 3)
		var length: int = rng.randi_range(6, h - 12)
		for k: int in length:
			c.px(x + roundi(sin(k * 0.6 + i) * 1.2), 13 + k, LEAF if k % 3 else Palette.light(LEAF, 0.2))
	for i: int in 5:
		c.ellipse(w / 2.0 - 4 + i * 2, 10.0 - (i % 2), 2.0, 1.5, Palette.light(LEAF, 0.1))


func _laundry_basket(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	var wicker: Color = Color("#c9a071")
	box(2, 8, w - 4, 3, h - 11, wicker)
	for y: int in range(12, h - 2, 3):
		for x: int in range(3 + (y % 2) * 2, w - 3, 4):
			c.px(x, y, Palette.shade(wicker, 0.2))
	c.ellipse(8, 7, 5, 3, Color("#6f8fb8"))
	c.ellipse(15, 6, 5, 4, Palette.WHITE)
	c.ellipse(12, 4, 4, 2, Palette.ALFA_RED)
	c.line(17, 5, 21, 12, Color("#3a3a44"))
	c.line(18, 5, 22, 12, Color("#3a3a44"))


func _side_table(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	box(1, 16, w - 2, 4, 3, OAK)
	c.vline(3, 23, h - 25, Palette.shade(OAK, 0.2))
	c.vline(w - 4, 23, h - 25, Palette.shade(OAK, 0.2))
	c.hline(3, h - 6, w - 6, Palette.shade(OAK, 0.1))
	c.rect(3, 12, 9, 4, Color("#3a7bd5"))
	c.rect(4, 9, 7, 3, Palette.WHITE)
	c.hline(4, 10, 7, Color("#c9ced6"))
	c.rect(14, 12, 4, 4, Palette.WHITE)
	c.rect(18, 13, 1, 2, Palette.WHITE)
	c.px(15, 11, Color(1, 1, 1, 0.5))
	c.rect(4, h - 10, 12, 3, Palette.ALFA_RED)
	c.rect(5, h - 13, 10, 3, Color("#f6ead0"))


func _book_stack(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1, 2)
	var y: int = h - 4
	for i: int in 3:
		var color: Color = [Color("#3a7bd5"), Palette.ALFA_RED, Color("#4f9a4a")][i]
		var x: int = 1 + rng.randi_range(0, 2)
		c.rect(x, y - 3, w - 4, 4, color)
		c.hline(x + 1, y - 2, w - 6, Color("#f6ead0"))
		c.hline(x, y - 3, w - 4, Palette.light(color, 0.2))
		y -= 4


func _slippers() -> void:
	for x: int in [2, 11]:
		c.ellipse(x + 3.5, 5, 3.5, 4, Color("#e8a0b0"))
		c.ellipse(x + 3.5, 3.5, 3.0, 2.0, Color("#f6eef2"))
		c.ellipse(x + 3.5, 6.5, 2.5, 2.0, Palette.shade(Color("#e8a0b0"), 0.15))


func _sneakers() -> void:
	for i: int in 2:
		var x: int = 1 + i * 13
		var y: int = 2 + i
		c.rect(x, y + 2, 11, 5, Palette.WHITE)
		c.rect(x, y + 6, 11, 2, Color("#c9ced6"))
		c.rect(x + 1, y, 5, 3, Palette.WHITE)
		c.line(x + 3, y + 3, x + 8, y + 5, Palette.ALFA_RED)
		c.px(x + 2, y + 1, INK)


func _umbrella_stand(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	c.line(4, 2, 6, h - 14, Color("#3a3a44"))
	c.rect(3, 0, 3, 3, Color("#3a3a44"))
	c.polygon(PackedVector2Array([Vector2(7, 2), Vector2(12, 4), Vector2(11, h - 14), Vector2(8, h - 14)]), Palette.ALFA_RED)
	c.line(9, 0, 9, 3, WALNUT)
	box(1, h - 16, w - 2, 2, 14, Color("#5a5d64"))
	c.hline(2, h - 10, w - 4, Palette.light(Color("#5a5d64"), 0.15))


func _backpack(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	var bag: Color = Color("#3a3a44")
	c.ellipse(w / 2.0, 7, 7, 6, bag)
	c.rect(2, 7, w - 4, h - 10, bag)
	c.rect(4, 12, w - 8, h - 16, Palette.light(bag, 0.1))
	c.hline(4, 12, w - 8, METAL)
	c.rect(w / 2 - 2, 1, 4, 3, Palette.shade(bag, 0.2))
	c.rect(5, h - 7, 3, 2, Palette.ALFA_RED)


func _counter_dishes(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	box(0, 14, w, 6, h - 22, WHITE_DESK)
	c.rect(2, 26, w - 4, h - 32, Palette.shade(WHITE_DESK, 0.04))
	c.vline(w / 2, 26, h - 32, Palette.shade(WHITE_DESK, 0.18))
	c.px(w / 2 - 3, 30, METAL)
	c.px(w / 2 + 2, 30, METAL)
	c.rect(3, 4, 16, 12, METAL)
	c.rect(4, 13, 14, 2, Palette.shade(METAL, 0.2))
	for i: int in 4:
		c.ellipse(6 + i * 3.5, 9, 1.5, 5, PORCELAIN if i % 2 == 0 else Color("#cfe4ee"))
	c.rect(21, 11, 9, 4, Color("#d9a76a"))
	c.hline(21, 11, 9, Palette.light(Color("#d9a76a"), 0.2))
	c.rect(23, 8, 3, 3, Color("#f6ead0"))
	c.rect(27, 6, 3, 5, Palette.ALFA_RED)


func _vacuum(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	c.vline(w / 2 + 2, 0, h - 10, METAL)
	c.rect(w / 2, 0, 5, 3, Color("#3a3a44"))
	c.rect(3, h - 14, w - 6, 9, Color("#7a6ad8"))
	c.hline(3, h - 14, w - 6, Palette.light(Color("#7a6ad8"), 0.2))
	c.rect(5, h - 12, 5, 4, Color(0.7, 0.8, 0.9, 0.7))
	c.rect(1, h - 5, w - 2, 3, Color("#3a3a44"))


func _ironing_board(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 4)
	c.line(10, 14, w - 12, h - 3, METAL)
	c.line(w - 12, 14, 10, h - 3, METAL)
	c.polygon(PackedVector2Array([Vector2(2, 8), Vector2(w - 12, 6), Vector2(w - 1, 10), Vector2(w - 12, 14), Vector2(2, 13)]), Color("#a9c7d4"))
	for x: int in range(4, w - 12, 5):
		c.px(x, 10, Palette.WHITE)
	c.rect(6, 4, 12, 5, Palette.WHITE)
	c.polygon(PackedVector2Array([Vector2(26, 9), Vector2(34, 6), Vector2(38, 9)]), Color("#3a3a44"))
	c.rect(27, 4, 8, 2, Palette.ALFA_RED)


func _boxes_stack(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	box(1, h - 18, w - 2, 4, 14, CARDBOARD)
	c.vline(w / 2, h - 18, 4, Palette.shade(CARDBOARD, 0.25))
	box(4, h - 32, w - 9, 4, 13, Palette.light(CARDBOARD, 0.06))
	c.rect(7, h - 26, 10, 3, Palette.WHITE)
	c.hline(8, h - 25, 7, Color("#5a5d64"))
	c.rect(w - 9, h - 12, 4, 4, Palette.ALFA_RED)


func _floor_fan(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	c.ellipse(w / 2.0, h - 4, 7, 2, Color("#d9d7d2"))
	c.vline(w / 2, 16, h - 20, METAL)
	c.ellipse(w / 2.0, 9, 8.5, 8.5, Color("#c9ced6"))
	c.ellipse(w / 2.0, 9, 7.5, 7.5, Color("#e9ecef"))
	for i: int in 3:
		var angle: float = i * TAU / 3.0
		c.ellipse(w / 2.0 + cos(angle) * 4.0, 9 + sin(angle) * 4.0, 2.5, 2.5, Color("#a9c7d4"))
	c.ellipse(w / 2.0, 9, 1.5, 1.5, INK)
	for k: int in 4:
		c.hline(w / 2 - 7, 3 + k * 4, 15, Color(0.6, 0.62, 0.66, 0.35))


func _rug_runner(w: int, h: int) -> void:
	var base: Color = Color("#8a3a3a")
	c.rect(0, 0, w, h, base)
	c.rect(2, 2, w - 4, h - 4, Palette.light(base, 0.08))
	for y: int in range(6, h - 4, 8):
		c.polygon(PackedVector2Array([Vector2(w / 2.0, y), Vector2(w / 2.0 + 6, y + 4), Vector2(w / 2.0, y + 8), Vector2(w / 2.0 - 6, y + 4)]), Color("#d9a43c"))
		c.px(w / 2, y + 4, base)
	for x: int in range(1, w, 3):
		c.px(x, 0, Color("#f3eee4"))
		c.px(x, h - 1, Color("#f3eee4"))


func _rug_round(w: int, h: int) -> void:
	var base: Color = Color("#6f8fb8")
	c.ellipse(w / 2.0, h / 2.0, w / 2.0, h / 2.0, Palette.shade(base, 0.1))
	c.ellipse(w / 2.0, h / 2.0, w / 2.0 - 3, h / 2.0 - 2, base)
	c.ellipse(w / 2.0, h / 2.0, w / 2.0 - 10, h / 2.0 - 6, Color("#f3eee4"))
	c.ellipse(w / 2.0, h / 2.0, w / 2.0 - 16, h / 2.0 - 9, Palette.light(base, 0.1))


func _bin_small(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1, 2)
	box(1, 2, w - 2, 2, h - 5, Color("#d9d7d2"))
	c.rect(2, 1, w - 4, 2, Color("#c9ced6"))
	c.rect(3, 6, 2, 3, Color("#f3eee4"))


func _cat_bed(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	c.ellipse(w / 2.0, h - 6, w / 2.0 - 1, 5, Color("#8a6a9a"))
	c.ellipse(w / 2.0, h - 7, w / 2.0 - 4, 3.5, Color("#c9b8d6"))
	# A ginger cat curled up asleep.
	c.ellipse(w / 2.0 - 1, h - 9, 7, 4, CAT)
	c.ellipse(w / 2.0 + 5, h - 10, 3.5, 3, CAT)
	c.px(w / 2 + 3, h - 13, CAT)
	c.px(w / 2 + 7, h - 13, CAT)
	c.hline(w / 2 + 4, h - 10, 2, INK)
	c.line(w / 2 - 7, h - 8, w / 2 - 2, h - 6, Palette.light(CAT, 0.2))
	for x: int in [w / 2 - 4, w / 2 - 1, w / 2 + 2]:
		c.vline(x, h - 12, 2, Palette.shade(CAT, 0.2))


func _dryer_rack(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 3)
	c.line(4, 10, 12, h - 3, METAL)
	c.line(w - 5, 10, w - 13, h - 3, METAL)
	c.line(12, 10, 4, h - 3, METAL)
	c.line(w - 13, 10, w - 5, h - 3, METAL)
	for y: int in [8, 11]:
		c.hline(2, y, w - 4, Palette.light(METAL, 0.2))
	var clothes: Array = [[5, 7, Palette.WHITE], [13, 10, Color("#6f8fb8")], [24, 8, Palette.ALFA_RED], [33, 12, Color("#f6eef2")], [42, 7, Color("#4f9a4a")]]
	for item: Array in clothes:
		var x: int = item[0]
		var length: int = item[1]
		c.rect(x, 8, 6, length, item[2])
		c.vline(x + 5, 8, length, Palette.shade(item[2], 0.12))
		c.px(x + 2, 7, Color("#ff9ab0"))
