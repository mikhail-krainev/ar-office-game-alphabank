class_name LoungeTable
extends Control
## Shared table: actual equipped characters, profile pictures and a continuously animated wheel.

const SECTORS: Array[int] = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const REDS: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
const SEATS: Array[Vector2] = [Vector2(150, 239), Vector2(35, 182), Vector2(35, 71), Vector2(150, 33), Vector2(265, 71), Vector2(265, 182)]
var room: Dictionary = {}
var _angle: float = 0.0
var _ball: float = 0.0
var _elapsed: float = 0.0
var _settled: bool = false
var _settling: bool = false
var _chips: Array[Dictionary] = []


func _init(data: Dictionary = {}) -> void:
	room = data
	custom_minimum_size = Vector2(300, 265)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var players: Array = room.get("players", [])
	set_meta("seat_key", JSON.stringify(players))
	if room.get("game", "") == "blackjack" and players.size() == 1 and not str(room.get("message", "")).is_empty():
		var bubble: PanelContainer = PanelContainer.new()
		bubble.position = Vector2(177, 3)
		bubble.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 5, 5))
		var phrase: Label = UiStyle.make_label(str(room.get("message", "")), 8)
		phrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		phrase.custom_minimum_size.x = 108
		bubble.add_child(phrase)
		add_child(bubble)
	for i: int in mini(players.size(), 6):
		var p: Dictionary = players[i]
		if p.get("departed", false):
			continue
		var seat: Vector2 = SEATS[i]
		if players.size() <= 6:
			var character: CharacterSprite = CharacterSprite.new()
			character.position = seat
			add_child(character)
			character.setup_outfit(p.get("outfit", {}))
			character.face(Vector2.DOWN if seat.y < 130 else Vector2.UP)
		var avatar: AvatarView = AvatarView.new(18)
		avatar.position = seat + Vector2(-40, 2)
		add_child(avatar)
		if p.get("character_avatar", false):
			avatar.show_outfit(p.get("outfit", {}), str(p.get("id", "")))
		else:
			avatar.show_avatar(str(p.get("avatar", "me")), str(p.get("id", "")))
		var label: Label = UiStyle.make_label(str(p.get("name", "")), 8, UiStyle.INK)
		label.position = seat + Vector2(-20, 4)
		label.size.x = 72
		label.clip_text = true
		add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	if room.get("phase", "") == "spinning":
		_angle += delta * 2.8
		_ball -= delta * maxf(1.0, 8.0 - _elapsed * 0.8)
	elif room.get("phase", "") == "result" and not _settling:
		_settling = true
		var index: int = SECTORS.find(int(room.get("result", 0)))
		var target: float = -PI / 2.0 - (float(index) + 0.5) * TAU / 37.0
		target += ceilf((_angle - target) / TAU) * TAU
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(self, "_angle", target + TAU * 2.0, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "_ball", -PI / 2.0 + floorf((_ball + PI / 2) / TAU) * TAU - TAU * 2.0, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.chain().tween_callback(func() -> void: _settled = true)
	for chip: Dictionary in _chips:
		chip["progress"] = minf(1.0, float(chip["progress"]) + delta * 2.0)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = Vector2(150, 132)
	var oval: PackedVector2Array = PackedVector2Array()
	for i: int in 65:
		var a: float = TAU * i / 64.0
		oval.append(c + Vector2(cos(a) * 142, sin(a) * 84))
	draw_colored_polygon(oval, Color("#24242d"))
	var inner: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in oval:
		inner.append(c + (point - c) * 0.9)
	draw_colored_polygon(inner, Color("#114b43"))
	if room.get("game", "") == "roulette":
		_draw_wheel(c)
		var font: Font = ThemeDB.fallback_font
		for i: int in 3:
			var rect: Rect2 = Rect2(44 + i * 72, 205, 66, 22)
			draw_rect(rect, [UiStyle.RED, Color("#15151b"), Color("#15834c")][i])
			draw_string(font, rect.position + Vector2(4, 14), ["КРАСНОЕ", "ЧЁРНОЕ", "НОЛЬ"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		for chip: Dictionary in _chips:
			var point: Vector2 = (chip["from"] as Vector2).lerp(chip["to"], smoothstep(0, 1, float(chip["progress"])))
			draw_circle(point, 5, UiStyle.GOLD)
			draw_circle(point, 3, Color.WHITE, false, 1)
	else:
		var font: Font = ThemeDB.fallback_font
		draw_string(font, c + Vector2(-39, 0), "АЛЬФА · 21", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e5d1a0"))
		var players: Array = room.get("players", [])
		for i: int in mini(players.size(), 6):
			var p: Dictionary = players[i]
			var seat: Vector2 = c.lerp(SEATS[i], 0.54)
			var cards: Array = p.get("cards", [])
			var count: int = cards.size() if not cards.is_empty() else int(p.get("card_count", 0))
			for j: int in mini(count, 5):
				var rect: Rect2 = Rect2(seat + Vector2(j * 10 - 14, -8), Vector2(17, 23))
				draw_rect(rect, Color.WHITE if not cards.is_empty() else UiStyle.RED)
				if not cards.is_empty():
					draw_string(font, rect.position + Vector2(2, 13), card_name(int(cards[j])), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiStyle.INK)
		if players.size() == 1:
			draw_circle(Vector2(150, 14), 9, Color("#9a9ca4"))
			draw_rect(Rect2(139, 23, 22, 15), Color("#9a9ca4"))
			draw_string(font, Vector2(130, 49), "ДИЛЕР", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiStyle.INK)
			var dealer: Array = room.get("dealer", [])
			for j: int in dealer.size():
				draw_string(font, Vector2(130 + j * 16, 77), card_name(int(dealer[j])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _draw_wheel(c: Vector2) -> void:
	for i: int in 37:
		var a: float = _angle + i * TAU / 37.0
		var b: float = _angle + (i + 1) * TAU / 37.0
		var color: Color = Color("#15965b") if SECTORS[i] == 0 else (UiStyle.RED if REDS.has(SECTORS[i]) else Color("#1a1b25"))
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a) * 66, c + Vector2.from_angle(b) * 66]), color)
		var middle: Vector2 = c + Vector2.from_angle((a + b) / 2.0) * 57
		draw_string(ThemeDB.fallback_font, middle + Vector2(-3, 2), str(SECTORS[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	draw_arc(c, 68, 0, TAU, 80, UiStyle.GOLD, 3)
	draw_arc(c, 43, 0, TAU, 80, UiStyle.GOLD, 2)
	draw_circle(c, 18, Color("#392f28"))
	draw_line(c - Vector2(14, 0), c + Vector2(14, 0), UiStyle.GOLD, 3)
	draw_line(c - Vector2(0, 14), c + Vector2(0, 14), UiStyle.GOLD, 3)
	draw_circle(c + Vector2.from_angle(_ball) * 48, 3.5, Color.WHITE)
	if _settled:
		var sector: int = int(room.get("result", 0))
		var text: String = "%d · %s" % [sector, "ЗЕЛЁНОЕ" if sector == 0 else ("КРАСНОЕ" if REDS.has(sector) else "ЧЁРНОЕ")]
		draw_rect(Rect2(31, 99, 238, 58), Color("#161822"))
		draw_string(ThemeDB.fallback_font, Vector2(45, 136), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)


static func card_name(card: int) -> String:
	var rank: int = card % 13
	return ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank]


func update_room(data: Dictionary) -> void:
	var old_phase: String = str(room.get("phase", ""))
	var old_bets: Array = room.get("bets", [])
	var new_bets: Array = data.get("bets", [])
	if int(room.get("round", 0)) != int(data.get("round", 0)):
		_chips.clear()
		old_bets = []
	for i: int in range(old_bets.size(), new_bets.size()):
		var bet: Dictionary = new_bets[i]
		var field: String = str(bet.get("field", ""))
		var target: Vector2 = Vector2(77, 216) if field == "red" else (Vector2(149, 216) if field == "black" else Vector2(221, 216))
		_chips.append({"from": SEATS[int(bet.get("player", 0)) % SEATS.size()], "to": target + Vector2((i % 4) * 3, -(i % 3) * 2), "progress": 0.0})
	room = data
	if old_phase != str(data.get("phase", "")):
		_elapsed = 0
		_settling = false
		_settled = false
	# New seats are rebuilt without resetting the wheel or chips.
	if JSON.stringify(data.get("players", [])) != get_meta("seat_key", "") :
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		_ready()
