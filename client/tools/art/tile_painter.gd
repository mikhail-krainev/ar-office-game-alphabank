class_name TilePainter
extends RefCounted
## Paints the 32px office tile atlas described by OfficeTiles.

const S: int = OfficeTiles.SIZE

var c: PixelCanvas
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func paint() -> Image:
	c = PixelCanvas.create(Vector2i(OfficeTiles.COLUMNS * S, OfficeTiles.Style.size() * S))
	for style: int in OfficeTiles.Style.size():
		for variant: int in OfficeTiles.FLOOR_VARIANTS:
			_cell(variant, style)
			rng.seed = style * 100 + variant
			_floor(style, variant)
		_cell(OfficeTiles.COL_FACE_UPPER, style)
		_face(style, true)
		_cell(OfficeTiles.COL_FACE_LOWER, style)
		_face(style, false)
	_cell(OfficeTiles.COL_CAP, 0)
	_cap()
	_cell(OfficeTiles.COL_SHADOW, 0)
	for y: int in 14:
		c.hline(0, y, S, Color(0.18, 0.12, 0.1, 0.32 * pow(1.0 - y / 14.0, 1.6)))
	return c.image


func _cell(column: int, row: int) -> void:
	c.set_cell(Rect2i(column * S, row * S, S, S))


func _speckle(base: Color, amount: int, strength: float) -> void:
	for i: int in amount:
		var x: int = rng.randi_range(0, S - 1)
		var y: int = rng.randi_range(0, S - 1)
		c.px(x, y, Palette.shade(base, strength) if rng.randf() < 0.6 else Palette.light(base, strength))


func _floor(style: int, variant: int) -> void:
	match style:
		OfficeTiles.Style.OFFICE:
			var base: Color = Color("#c9ccd3")
			c.rect(0, 0, S, S, base)
			for y: int in range(0, S, 2):
				for x: int in range((y / 2) % 2, S, 2):
					c.px(x, y, Palette.shade(base, 0.03))
			_speckle(base, 14 + variant * 4, 0.06)
			c.hline(0, S - 1, S, Palette.shade(base, 0.07))
			c.vline(S - 1, 0, S, Palette.shade(base, 0.07))
		OfficeTiles.Style.WOOD:
			var oak: Color = Color("#d8b88a")
			for block: int in 4:
				var bx: int = (block % 2) * 16
				var by: int = (block / 2) * 16
				var horizontal: bool = (block + variant) % 2 == 0
				for plank: int in 4:
					var tint: Color = oak if (plank + block + variant) % 3 else Palette.shade(oak, 0.05)
					if horizontal:
						c.rect(bx, by + plank * 4, 16, 4, tint)
						c.hline(bx, by + plank * 4 + 3, 16, Palette.shade(oak, 0.12))
					else:
						c.rect(bx + plank * 4, by, 4, 16, tint)
						c.vline(bx + plank * 4 + 3, by, 16, Palette.shade(oak, 0.12))
			_speckle(oak, 10, 0.05)
		OfficeTiles.Style.KITCHEN:
			var cream: Color = Color("#eee7da")
			var grout: Color = Color("#d3c8b6")
			c.rect(0, 0, S, S, grout)
			for ty: int in 2:
				for tx: int in 2:
					var tint: Color = cream if (tx + ty + variant) % 4 != 3 else Color("#e6ddd0")
					c.rect(tx * 16 + 1, ty * 16 + 1, 14, 14, tint)
					c.hline(tx * 16 + 2, ty * 16 + 2, 5, Palette.light(tint, 0.06))
		OfficeTiles.Style.MARBLE:
			var marble: Color = Color("#f2efea")
			c.rect(0, 0, S, S, marble)
			var vein: Color = Color("#d9d3ca")
			var y0: int = rng.randi_range(0, S)
			var y1: int = rng.randi_range(0, S)
			c.line(0, y0, S - 1, y1, vein)
			c.line(rng.randi_range(0, 15), 0, rng.randi_range(16, 31), S - 1, Color(vein, 0.5))
			c.hline(0, S - 1, S, Color("#e2ddd5"))
			c.vline(S - 1, 0, S, Color("#e2ddd5"))
		OfficeTiles.Style.CORRIDOR:
			var vinyl: Color = Color("#dcd8d1")
			c.rect(0, 0, S, S, vinyl)
			_speckle(vinyl, 22, 0.05)
			c.hline(0, S - 1, S, Palette.shade(vinyl, 0.05))
		OfficeTiles.Style.LOUNGE:
			var plank: Color = Color("#c79d6d")
			for row: int in 4:
				var offset: int = (row * 11 + variant * 7) % 32
				var tint: Color = plank if row % 2 == 0 else Palette.light(plank, 0.04)
				c.rect(0, row * 8, S, 8, tint)
				c.hline(0, row * 8 + 7, S, Palette.shade(plank, 0.14))
				c.vline(offset, row * 8, 7, Palette.shade(plank, 0.14))
				c.hline((offset + 9) % 28, row * 8 + 3, 4, Palette.shade(plank, 0.06))
		OfficeTiles.Style.PARTY:
			var dark: Color = Color("#4a1f4f")
			for ty: int in 2:
				for tx: int in 2:
					var tint: Color = dark if (tx + ty) % 2 == 0 else Color("#5d2a63")
					c.rect(tx * 16, ty * 16, 16, 16, tint)
					c.line(tx * 16 + 2, ty * 16 + 5, tx * 16 + 5, ty * 16 + 2, Color(1, 1, 1, 0.12))
			if variant == 2:
				c.rect(6, 20, 3, 2, Color(1, 1, 1, 0.1))
		OfficeTiles.Style.BEDROOM:
			var carpet: Color = Color("#cdbfae")
			c.rect(0, 0, S, S, carpet)
			for y: int in S:
				for x: int in range(y % 2, S, 2):
					c.px(x, y, Palette.shade(carpet, 0.025))
			_speckle(carpet, 30 + variant * 6, 0.05)
		OfficeTiles.Style.BATH:
			var tile: Color = Color("#e8f1f4")
			var grout: Color = Color("#b8ccd3")
			c.rect(0, 0, S, S, grout)
			for ty: int in 4:
				for tx: int in 4:
					var accent: bool = variant == 2 and tx == 1 and ty == 2
					var tint: Color = Color("#7fb3c9") if accent else (tile if (tx + ty) % 2 == 0 else Color("#dfeaee"))
					c.rect(tx * 8 + 1, ty * 8 + 1, 7, 7, tint)
					c.px(tx * 8 + 2, ty * 8 + 2, Palette.light(tint, 0.08))
		OfficeTiles.Style.HALL:
			var laminate: Color = Color("#b79f84")
			for row: int in 4:
				var offset: int = (row * 13 + variant * 5) % 32
				var tint: Color = laminate if (row + variant) % 3 else Palette.shade(laminate, 0.04)
				c.rect(0, row * 8, S, 8, tint)
				c.hline(0, row * 8 + 7, S, Palette.shade(laminate, 0.12))
				c.vline(offset, row * 8, 7, Palette.shade(laminate, 0.12))
				c.hline((offset + 11) % 26, row * 8 + 3, 5, Palette.light(laminate, 0.05))
		OfficeTiles.Style.LIVING:
			var oak: Color = Color("#c99a66")
			for y: int in S:
				for x: int in S:
					var block: int = ((x + y) / 8 + (x - y + 64) / 8) % 2
					var along: int = ((x + y) if block == 0 else (x - y + 64)) % 8
					var tint: Color = oak if block == 0 else Palette.shade(oak, 0.06)
					if along == 0:
						tint = Palette.shade(oak, 0.16)
					c.px(x, y, tint)
			_speckle(oak, 8, 0.05)
		OfficeTiles.Style.HOME_KITCHEN:
			var terracotta: Color = Color("#c9785a")
			var cream: Color = Color("#efe4d2")
			for ty: int in 2:
				for tx: int in 2:
					var tint: Color = terracotta if (tx + ty) % 2 == 0 else cream
					c.rect(tx * 16, ty * 16, 16, 16, tint)
					c.hline(tx * 16, ty * 16, 16, Palette.light(tint, 0.06))
					c.vline(tx * 16 + 15, ty * 16, 16, Palette.shade(tint, 0.08))
			_speckle(cream, 6, 0.04)
		OfficeTiles.Style.CARPET:
			var teal: Color = Color("#3c6f73")
			c.rect(0, 0, S, S, teal)
			for y: int in S:
				for x: int in range(y % 2, S, 2):
					c.px(x, y, Palette.shade(teal, 0.04))
			_speckle(teal, 26 + variant * 6, 0.07)
			c.hline(0, S - 1, S, Palette.shade(teal, 0.1))
			c.vline(S - 1, 0, S, Palette.shade(teal, 0.1))
		OfficeTiles.Style.CONCRETE:
			var concrete: Color = Color("#9fa3a8")
			c.rect(0, 0, S, S, concrete)
			_speckle(concrete, 40 + variant * 8, 0.06)
			if variant == 1:
				c.line(4, 22, 13, 27, Palette.shade(concrete, 0.08))
			c.hline(0, S - 1, S, Palette.shade(concrete, 0.12))
			c.vline(S - 1, 0, S, Palette.shade(concrete, 0.12))
		OfficeTiles.Style.GRASS:
			var grass: Color = Color("#6fae4f")
			c.rect(0, 0, S, S, grass)
			for i: int in 70 + variant * 10:
				var x: int = rng.randi_range(0, S - 1)
				var y: int = rng.randi_range(1, S - 1)
				var blade: Color = Palette.light(grass, 0.12) if rng.randf() < 0.5 else Palette.shade(grass, 0.12)
				c.px(x, y, blade)
				c.px(x, y - 1, Palette.light(blade, 0.06))
			if variant == 2:
				c.px(9, 12, Color("#f7f2d0"))
				c.px(22, 25, Color("#f7c948"))
		OfficeTiles.Style.DOOR:
			c.rect(0, 0, S, S, Color("#cfc8bd"))
			c.hline(0, 1, S, Color("#b3aa9d"))
			c.hline(0, S - 2, S, Color("#b3aa9d"))
			for x: int in range(2, S, 4):
				c.vline(x, 4, 24, Color(0, 0, 0, 0.05))


func _face(style: int, upper: bool) -> void:
	var wall: Color = Color("#eeebe6")
	match style:
		OfficeTiles.Style.WOOD:
			wall = Color("#e9dfd0")
		OfficeTiles.Style.KITCHEN:
			wall = Color("#f3efe8")
		OfficeTiles.Style.MARBLE:
			wall = Color("#f7f5f1")
		OfficeTiles.Style.CORRIDOR:
			wall = Color("#e6e2dc")
		OfficeTiles.Style.LOUNGE:
			wall = Color("#e8d6bf")
		OfficeTiles.Style.PARTY:
			wall = Color("#5a2a5e")
		OfficeTiles.Style.BEDROOM:
			wall = Color("#b9c9b0")
		OfficeTiles.Style.BATH:
			wall = Color("#d3e6ec")
		OfficeTiles.Style.HALL:
			wall = Color("#e6d8c3")
		OfficeTiles.Style.LIVING:
			wall = Color("#efdfc6")
		OfficeTiles.Style.HOME_KITCHEN:
			wall = Color("#f1ece4")
		OfficeTiles.Style.CARPET:
			wall = Color("#e4e8e8")
		OfficeTiles.Style.CONCRETE:
			wall = Color("#3a3f48")
		OfficeTiles.Style.GRASS:
			wall = Color("#e9e7e2")
	c.rect(0, 0, S, S, wall)
	if style == OfficeTiles.Style.BEDROOM:
		for x: int in range(0, S, 8):
			c.vline(x + 3, 0, S, Palette.light(wall, 0.05))
			for y: int in range(4, S, 8):
				c.px(x + 7, y, Palette.shade(wall, 0.08))
	elif style == OfficeTiles.Style.LIVING:
		for y: int in range(2, S, 8):
			for x: int in range(0, S, 8):
				c.px(x + 4 * ((y / 8) % 2), y, Palette.shade(wall, 0.1))
	elif style == OfficeTiles.Style.BATH:
		for y: int in range(0, S, 8):
			c.hline(0, y + 7, S, Palette.shade(wall, 0.08))
			for x: int in range(0, S, 8):
				c.vline(x + 7, y, 7, Palette.shade(wall, 0.08))
	if style == OfficeTiles.Style.PARTY:
		var mortar: Color = Color("#3e1a42")
		for row: int in 4:
			c.hline(0, row * 8 + 7, S, mortar)
			var shift: int = 8 if row % 2 else 0
			for x: int in range(shift, S + 1, 16):
				c.vline(x % S, row * 8, 7, mortar)
		if upper:
			c.hline(0, 1, S, Color("#ff4fa3"))
			c.hline(0, 2, S, Color(1.0, 0.31, 0.64, 0.35))
		return
	if style == OfficeTiles.Style.GRASS:
		# The back facade of the house seen from the yard: white render with floor-to-ceiling glass.
		var glass: Color = Color("#9cc3d3")
		c.rect(3, 0 if not upper else 6, S - 6, S if not upper else S - 6, glass)
		c.vline(15, 0, S, Color("#7d8a90"))
		c.line(5, S - 2 if not upper else S - 1, 12, 8, Color(1, 1, 1, 0.35))
		if not upper:
			c.rect(0, 28, S, 4, Color("#8c8f93"))
		else:
			c.hline(0, 3, S, Color("#cfcbc4"))
		return
	if style == OfficeTiles.Style.CONCRETE:
		for y: int in range(3, S, 8):
			c.hline(0, y, S, Palette.light(wall, 0.05))
		if upper:
			c.hline(0, 1, S, Color("#5ce1e6"))
			c.hline(0, 2, S, Color(0.36, 0.88, 0.9, 0.35))
			return
		c.rect(0, 28, S, 4, Color("#23262d"))
		c.hline(0, 28, S, Color("#5ce1e6"))
		return
	if upper:
		for y: int in 5:
			c.hline(0, y, S, Color(0, 0, 0, 0.1 * (1.0 - y / 5.0)))
		return
	match style:
		OfficeTiles.Style.WOOD:
			var panel: Color = Color("#a8794f")
			c.rect(0, 12, S, 20, panel)
			c.hline(0, 12, S, Palette.light(panel, 0.15))
			c.rect(3, 16, 26, 12, Palette.shade(panel, 0.06))
			c.hline(3, 27, 26, Palette.light(panel, 0.08))
		OfficeTiles.Style.KITCHEN:
			for row: int in 5:
				var by: int = 8 + row * 5
				var shift: int = 4 if row % 2 else 0
				c.hline(0, by + 4, S, Color("#c9d3d6"))
				for x: int in range(shift, S + 1, 8):
					c.vline(x % S, by, 4, Color("#c9d3d6"))
				c.rect(0, by, S, 4, Color(0.85, 0.92, 0.94, 0.5))
		OfficeTiles.Style.MARBLE, OfficeTiles.Style.CORRIDOR:
			c.rect(0, 16, S, 3, Palette.ALFA_RED)
			c.hline(0, 19, S, Palette.shade(Palette.ALFA_RED, 0.2))
		OfficeTiles.Style.LOUNGE:
			for x: int in range(0, S, 4):
				c.rect(x, 14, 3, 14, Color("#b98d5e"))
				c.vline(x + 3, 14, 14, Color("#9c7348"))
		OfficeTiles.Style.HALL:
			c.rect(0, 14, S, 14, Color("#cdb99c"))
			c.hline(0, 13, S, Color("#a8876a"))
			c.hline(0, 14, S, Color("#e9dccb"))
		OfficeTiles.Style.HOME_KITCHEN:
			for row: int in 4:
				var by: int = 10 + row * 4
				var shift: int = 5 if row % 2 else 0
				c.rect(0, by, S, 4, Color("#fbfaf8"))
				c.hline(0, by + 3, S, Color("#d5d0c8"))
				for x: int in range(shift, S + 1, 10):
					c.vline(x % S, by, 3, Color("#d5d0c8"))
			c.hline(0, 9, S, Color("#ef3124"))
		OfficeTiles.Style.LIVING:
			c.rect(0, 20, S, 8, Color("#e4cfb0"))
			c.hline(0, 20, S, Color("#c9a97e"))
		OfficeTiles.Style.CARPET:
			c.rect(0, 18, S, 3, Color("#2fb3a6"))
			c.hline(0, 21, S, Palette.shade(Color("#2fb3a6"), 0.2))
	c.rect(0, 28, S, 4, Color("#b8afa3"))
	c.hline(0, 28, S, Color("#cfc7bb"))


func _cap() -> void:
	c.rect(0, 0, S, S, Color("#7a736b"))
	c.rect(2, 2, S - 4, S - 4, Color("#8c857c"))
	for i: int in 6:
		c.px(rng.randi_range(3, 28), rng.randi_range(3, 28), Color("#958e85"))
