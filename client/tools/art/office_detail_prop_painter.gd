class_name OfficeDetailPropPainter
extends PropPainterBase
## Small things a real office is full of: the notice board, the air conditioner, binders, recycling
## bins, a coat stand, a parked bike, a server rack and a flip chart.

const CORK: Color = Color("#c9955a")
const CARDBOARD: Color = Color("#c9a26b")
const PLASTIC: Color = Color("#e9ecef")


func paint(id: String, w: int, h: int) -> bool:
	match id:
		"notice_board":
			_notice_board(w, h)
		"ac_unit":
			_ac_unit(w, h)
		"binder_shelf":
			_binder_shelf(w, h)
		"first_aid":
			_first_aid(w, h)
		"exit_sign":
			_exit_sign(w, h)
		"paper_box":
			_paper_box(w, h)
		"recycle_bins":
			_recycle_bins(w, h)
		"coat_stand":
			_coat_stand(w, h)
		"bin_office":
			_bin_office(w, h)
		"water_bottles":
			_water_bottles(w, h)
		"server_rack":
			_server_rack(w, h)
		"bike":
			_bike(w, h)
		"flipchart":
			_flipchart(w, h)
		_:
			return false
	return true


func _notice_board(w: int, h: int) -> void:
	c.rect(0, 0, w, h - 6, OAK)
	c.rect(2, 2, w - 4, h - 10, CORK)
	for i: int in 70:
		c.px(rng.randi_range(3, w - 4), rng.randi_range(3, h - 10), Palette.shade(CORK, 0.12))
	var notes: Array = [
		[4, 4, 12, 10, Color("#fff27a")], [18, 3, 14, 12, Palette.WHITE], [34, 5, 10, 9, Color("#ff9ab0")],
		[45, 3, 8, 11, Color("#a8e6a1")], [6, 17, 16, 10, Palette.WHITE], [25, 18, 11, 9, Color("#a9d6ee")],
		[38, 17, 14, 12, Color("#fff27a")],
	]
	for note: Array in notes:
		var x: int = note[0]
		var y: int = note[1]
		c.rect(x + 1, y + 1, note[2], note[3], Color(0, 0, 0, 0.15))
		c.rect(x, y, note[2], note[3], note[4])
		for line_y: int in range(y + 3, y + note[3] - 1, 2):
			c.hline(x + 2, line_y, rng.randi_range(3, note[2] - 4), Color("#8f949c"))
		c.px(x + note[2] / 2, y + 1, Palette.ALFA_RED)
	c.rect(19, 6, 5, 3, Palette.ALFA_RED)


func _ac_unit(w: int, h: int) -> void:
	c.rect(1, 1, w - 2, h - 3, Palette.WHITE)
	c.hline(1, 1, w - 2, Color("#ffffff"))
	c.rect(1, h - 6, w - 2, 4, Color("#dfe3e8"))
	for x: int in range(4, w - 4, 2):
		c.vline(x, h - 5, 2, Color("#b9c0c8"))
	c.px(w - 6, 4, Color("#4cd964"))
	c.rect(4, 4, 8, 2, Color("#c9ced6"))
	c.hline(1, h - 2, w - 2, Color("#c9ced6"))


func _binder_shelf(w: int, h: int) -> void:
	var x: int = 2
	while x < w - 4:
		var bw: int = rng.randi_range(4, 5)
		var color: Color = [Palette.ALFA_RED, Color("#3a7bd5"), Color("#3a3a44"), Palette.WHITE, Color("#d9a43c")][rng.randi() % 5]
		if rng.randf() < 0.12:
			x += 3
			continue
		c.rect(x, 3, bw, h - 7, color)
		c.vline(x, 3, h - 7, Palette.light(color, 0.15))
		c.rect(x + 1, 6, bw - 2, 3, Palette.WHITE if color != Palette.WHITE else Color("#c9ced6"))
		c.ellipse(x + bw / 2.0, h - 8, 1.0, 1.0, Palette.shade(color, 0.3))
		x += bw
	c.rect(0, h - 4, w, 3, Color("#b9c0c8"))
	c.hline(0, h - 4, w, Color("#dfe3e8"))


func _first_aid(w: int, h: int) -> void:
	c.rect(0, 0, w, h, Palette.WHITE)
	c.rect(1, 1, w - 2, h - 2, Color("#4f9a4a"))
	c.rect(w / 2 - 1, 3, 3, h - 6, Palette.WHITE)
	c.rect(4, h / 2 - 1, w - 8, 3, Palette.WHITE)


func _exit_sign(w: int, h: int) -> void:
	c.rect(0, 0, w, h, Color("#2e8b57"))
	c.rect(1, 1, w - 2, h - 2, Color("#4cd964"))
	c.ellipse(6, 3, 1.5, 1.5, Palette.WHITE)
	c.line(6, 5, 5, 8, Palette.WHITE)
	c.line(5, 6, 8, 7, Palette.WHITE)
	c.line(5, 8, 3, 10, Palette.WHITE)
	c.line(5, 8, 8, 10, Palette.WHITE)
	c.rect(12, 4, 10, 4, Palette.WHITE)
	c.polygon(PackedVector2Array([Vector2(20, 2), Vector2(24, 6), Vector2(20, 10)]), Palette.WHITE)


func _paper_box(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1, 2)
	box(1, 5, w - 2, 4, h - 8, CARDBOARD)
	c.rect(4, 2, 8, 4, Palette.WHITE)
	c.rect(10, 1, 8, 5, Palette.WHITE)
	c.hline(10, 3, 8, Color("#3a7bd5"))
	c.rect(4, 11, 7, 3, Palette.WHITE)


func _recycle_bins(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	var colors: Array[Color] = [Color("#3a7bd5"), Color("#d9a43c"), Color("#4f9a4a")]
	for i: int in 3:
		var x: int = 1 + i * 20
		box(x, 4, 18, 4, h - 8, colors[i])
		c.rect(x + 5, 5, 8, 2, INK)
		c.rect(x + 6, 14, 6, 6, Palette.WHITE)
		c.line(x + 7, 18, x + 9, 15, colors[i])
		c.line(x + 9, 15, x + 11, 18, colors[i])


func _coat_stand(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	c.vline(w / 2, 4, h - 8, WALNUT)
	c.ellipse(w / 2.0, h - 3, 7, 2, Palette.shade(WALNUT, 0.1))
	for side: int in [-1, 1]:
		c.line(w / 2, 6, w / 2 + side * 6, 2, WALNUT)
	c.polygon(PackedVector2Array([Vector2(w / 2.0 - 1, 5), Vector2(w / 2.0 - 9, 10), Vector2(w / 2.0 - 8, 34), Vector2(w / 2.0, 34)]), Color("#3a3a44"))
	c.vline(w / 2 - 4, 10, 22, Palette.light(Color("#3a3a44"), 0.15))
	c.polygon(PackedVector2Array([Vector2(w / 2.0 + 1, 5), Vector2(w / 2.0 + 8, 9), Vector2(w / 2.0 + 7, 26), Vector2(w / 2.0 + 1, 26)]), Color("#c9955a"))
	c.ellipse(w / 2.0 + 6, 4, 3, 2, Palette.ALFA_RED)


func _bin_office(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1, 2)
	c.polygon(PackedVector2Array([Vector2(1, 3), Vector2(w - 1, 3), Vector2(w - 3, h - 2), Vector2(3, h - 2)]), Color("#5a5d64"))
	c.ellipse(w / 2.0, 3, w / 2.0 - 1, 2, Color("#2a2f36"))
	c.rect(4, 1, 4, 3, Palette.WHITE)


func _water_bottles(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	c.rect(2, h - 8, w - 4, 6, METAL)
	for i: int in 2:
		var x: int = 3 + i * 12
		c.rect(x, h - 22, 10, 14, Color(0.6, 0.82, 0.95, 0.9))
		c.rect(x + 3, h - 25, 4, 3, Color("#3a7bd5"))
		c.vline(x + 1, h - 21, 12, Color(1, 1, 1, 0.5))
	c.rect(9, h - 35, 10, 12, Color(0.6, 0.82, 0.95, 0.9))
	c.rect(12, h - 36, 4, 2, Color("#3a7bd5"))


func _server_rack(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 1)
	box(1, 0, w - 2, 4, h - 6, Color("#2a2f36"))
	for y: int in range(8, h - 6, 5):
		c.rect(4, y, w - 8, 4, Color("#3a404a"))
		c.hline(4, y, w - 8, Color("#4a515c"))
		for k: int in 3:
			c.px(6 + k * 2, y + 2, [Color("#4cd964"), Color("#4fb3ff"), Color("#ffcc00")][(y + k) % 3])
		c.hline(w - 12, y + 2, 6, Color("#22262c"))


func _bike(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 3)
	for cx: int in [12, w - 12]:
		for k: int in 48:
			var angle: float = k * TAU / 48.0
			for radius: float in [9.0, 10.0]:
				c.px(roundi(cx + cos(angle) * radius), roundi(h - 12 + sin(angle) * radius), INK)
			if k % 6 == 0:
				c.line(cx, h - 12, roundi(cx + cos(angle) * 8.0), roundi(h - 12 + sin(angle) * 8.0), Color(0.6, 0.62, 0.66, 0.6))
		c.ellipse(cx, h - 12, 1.5, 1.5, METAL)
	c.line(12, h - 12, 27, h - 12, Palette.ALFA_RED)
	c.line(27, h - 12, 22, h - 26, Palette.ALFA_RED)
	c.line(22, h - 26, 40, h - 26, Palette.ALFA_RED)
	c.line(40, h - 26, 27, h - 12, Palette.ALFA_RED)
	c.line(40, h - 26, w - 12, h - 12, Palette.ALFA_RED)
	c.line(12, h - 12, 22, h - 26, Palette.ALFA_RED)
	c.rect(18, h - 30, 8, 2, INK)
	c.line(40, h - 26, 42, h - 32, METAL)
	c.hline(38, h - 33, 8, INK)


func _flipchart(w: int, h: int) -> void:
	ground_shadow(w / 2.0, h - 2, w / 2.0 - 2)
	c.line(4, h - 2, w / 2 - 2, 22, METAL)
	c.line(w - 5, h - 2, w / 2 + 2, 22, METAL)
	c.rect(2, 2, w - 4, 34, Palette.WHITE)
	c.rect(2, 1, w - 4, 3, Color("#5a5d64"))
	c.line(5, 26, 10, 18, Palette.ALFA_RED)
	c.line(10, 18, 15, 22, Palette.ALFA_RED)
	c.line(15, 22, 22, 10, Palette.ALFA_RED)
	c.hline(5, 30, 16, Color("#3a7bd5"))
	c.hline(5, 8, 10, Color("#3a3a44"))
	c.rect(4, 36, w - 8, 2, Color("#c9ced6"))
