class_name CasinoArt
extends RefCounted
## Shared drawing of felt, playing cards and chips for the 21 and roulette tables. Everything is
## drawn with primitives (no glyphs for suits), so it stays crisp on the pixel-snapped viewport.

const FELT: Color = Color("#0f5a46")
const FELT_DARK: Color = Color("#0a4135")
const FELT_LINE: Color = Color("#2f8a6a")
const FELT_TEXT: Color = Color("#8cc9ad")
const WOOD: Color = Color("#4a2c1b")
const WOOD_DARK: Color = Color("#2c190f")
const BRASS: Color = Color("#e5b85c")
const BRASS_DARK: Color = Color("#9c7633")
const CARD_FACE: Color = Color("#fbfaf8")
const CARD_EDGE: Color = Color("#c9c1b4")
const CARD_RED: Color = Color("#d3261c")
const CARD_BACK: Color = Color("#23232b")
const CARD_INK: Color = Color("#1d1d1f")
const POCKET_RED: Color = Color("#c8281e")
const POCKET_BLACK: Color = Color("#1c1d26")
const POCKET_GREEN: Color = Color("#13915a")
const WIN: Color = Color("#22a865")
const GOLD_TEXT: Color = Color("#ffd86b")
const LOSE: Color = Color("#e2463a")
const RANKS: Array[String] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const REDS: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
const MARK: Texture2D = preload("res://assets/brand/alfa_mark_small.png")

static var _boxes: Dictionary[String, StyleBoxFlat] = {}


static func font() -> Font:
	return ThemeDB.fallback_font


static func text_width(text: String, size: int) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text whose visual centre is `center`.
static func draw_text_centered(ci: CanvasItem, center: Vector2, text: String, size: int, color: Color) -> void:
	var f: Font = font()
	var baseline: float = center.y + (f.get_ascent(size) - f.get_descent(size)) / 2.0
	ci.draw_string(f, Vector2(roundf(center.x - text_width(text, size) / 2.0), roundf(baseline)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_text_left(ci: CanvasItem, left_center: Vector2, text: String, size: int, color: Color) -> void:
	var f: Font = font()
	var baseline: float = left_center.y + (f.get_ascent(size) - f.get_descent(size)) / 2.0
	ci.draw_string(f, Vector2(roundf(left_center.x), roundf(baseline)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func box(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var key: String = "%s|%s|%d|%d" % [bg.to_html(), border.to_html(), border_width, radius]
	if not _boxes.has(key):
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = bg
		style.border_color = border
		style.set_border_width_all(border_width)
		style.set_corner_radius_all(radius)
		style.anti_aliasing = false
		style.draw_center = bg.a > 0.0
		_boxes[key] = style
	return _boxes[key]


## Green cloth with a wooden rail and a thin brass line inside it.
static func draw_felt(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_style_box(box(FELT, WOOD, 3, 10), rect)
	ci.draw_style_box(box(Color.TRANSPARENT, FELT_LINE, 1, 7), rect.grow(-6))


static func pocket_color(number: int) -> Color:
	if number == 0:
		return POCKET_GREEN
	return POCKET_RED if REDS.has(number) else POCKET_BLACK


static func color_name(number: int) -> String:
	if number == 0:
		return "ЗЕРО"
	return "КРАСНОЕ" if REDS.has(number) else "ЧЁРНОЕ"


static func rank_name(card: int) -> String:
	return RANKS[card % 13]


## Suits: 0 spades, 1 hearts, 2 diamonds, 3 clubs.
static func suit_of(card: int) -> int:
	return (card / 13) % 4


static func is_red_card(card: int) -> bool:
	var suit: int = suit_of(card)
	return suit == 1 or suit == 2


## Total the way the server counts it; `soft` when an ace still counts as 11.
static func hand_value(cards: Array) -> Dictionary:
	var total: int = 0
	var aces: int = 0
	for card: Variant in cards:
		var rank: int = int(card) % 13
		if rank == 0:
			total += 11
			aces += 1
		else:
			total += mini(rank + 1, 10)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return {"total": total, "soft": aces > 0}


static func draw_suit(ci: CanvasItem, center: Vector2, size: float, suit: int, color: Color) -> void:
	var s: float = size
	match suit:
		1:
			ci.draw_circle(center + Vector2(-s * 0.24, -s * 0.12), s * 0.27, color)
			ci.draw_circle(center + Vector2(s * 0.24, -s * 0.12), s * 0.27, color)
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-s * 0.5, -s * 0.04), center + Vector2(s * 0.5, -s * 0.04), center + Vector2(0, s * 0.5)]), color)
		2:
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -s * 0.5), center + Vector2(s * 0.36, 0), center + Vector2(0, s * 0.5), center + Vector2(-s * 0.36, 0)]), color)
		0:
			ci.draw_circle(center + Vector2(-s * 0.24, s * 0.08), s * 0.26, color)
			ci.draw_circle(center + Vector2(s * 0.24, s * 0.08), s * 0.26, color)
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-s * 0.49, s * 0.02), center + Vector2(s * 0.49, s * 0.02), center + Vector2(0, -s * 0.5)]), color)
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, s * 0.1), center + Vector2(s * 0.18, s * 0.5), center + Vector2(-s * 0.18, s * 0.5)]), color)
		_:
			ci.draw_circle(center + Vector2(0, -s * 0.24), s * 0.22, color)
			ci.draw_circle(center + Vector2(-s * 0.25, s * 0.06), s * 0.22, color)
			ci.draw_circle(center + Vector2(s * 0.25, s * 0.06), s * 0.22, color)
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -s * 0.05), center + Vector2(s * 0.18, s * 0.5), center + Vector2(-s * 0.18, s * 0.5)]), color)


## A card at `rect`; `squash` (0..1) narrows it around its centre for the flip animation.
static func draw_card(ci: CanvasItem, rect: Rect2, card: int, face_up: bool, squash: float = 1.0) -> void:
	var width: float = maxf(2.0, roundf(rect.size.x * squash))
	var r: Rect2 = Rect2(Vector2(roundf(rect.position.x + (rect.size.x - width) / 2.0), roundf(rect.position.y)), Vector2(width, rect.size.y))
	ci.draw_rect(Rect2(r.position + Vector2(1, 2), r.size), Color(0, 0, 0, 0.28))
	if not face_up:
		ci.draw_style_box(box(CARD_BACK, CARD_FACE, 2, 3), r)
		if squash > 0.6:
			ci.draw_style_box(box(Color.TRANSPARENT, CARD_RED, 1, 2), r.grow(-4))
			var mark: Vector2 = Vector2(minf(20, r.size.x - 10), minf(24, r.size.y - 12))
			mark = Vector2(mark.y * 20.0 / 24.0, mark.y) if mark.x / 20.0 > mark.y / 24.0 else Vector2(mark.x, mark.x * 24.0 / 20.0)
			ci.draw_texture_rect(MARK, Rect2((r.get_center() - mark / 2.0).round(), mark.round()), false)
		return
	ci.draw_style_box(box(CARD_FACE, CARD_EDGE, 1, 3), r)
	if squash < 0.6:
		return
	var color: Color = CARD_RED if is_red_card(card) else CARD_INK
	var suit: int = suit_of(card)
	var rank: String = rank_name(card)
	if r.size.y < 30:
		draw_text_centered(ci, r.position + Vector2(r.size.x / 2.0, r.size.y * 0.34), rank, 8, color)
		draw_suit(ci, r.position + Vector2(r.size.x / 2.0, r.size.y * 0.72), r.size.x * 0.42, suit, color)
		return
	var corner_size: int = 11 if r.size.y >= 46 else 9
	draw_text_centered(ci, r.position + Vector2(8, 9), rank, corner_size, color)
	draw_suit(ci, r.position + Vector2(8, 20), 7, suit, color)
	draw_suit(ci, r.get_center() + Vector2(2, 5), r.size.x * 0.46, suit, color)


static func chip_color(value: int) -> Color:
	if value <= 1:
		return Color("#e9e4d8")
	if value <= 5:
		return Color("#d3261c")
	if value <= 10:
		return Color("#2f6fd0")
	if value <= 20:
		return Color("#1f9a5b")
	if value <= 50:
		return Color("#e0701f")
	if value <= 100:
		return Color("#26262d")
	if value <= 500:
		return Color("#8e3fd1")
	if value <= 1000:
		return Color("#b8860b")
	if value <= 5000:
		return Color("#c42a74")
	return Color("#0f8a8f")


static func short_amount(value: int) -> String:
	if value >= 10000:
		return "%dK" % (value / 1000)
	if value >= 1000:
		return String.num(value / 1000.0, 1).trim_suffix(".0") + "K"
	return str(value)


## Casino chip with edge stripes and the amount in the middle.
static func draw_chip(ci: CanvasItem, center: Vector2, radius: float, value: int, ring: Color = Color.TRANSPARENT) -> void:
	var color: Color = chip_color(value)
	var c: Vector2 = center.round()
	ci.draw_circle(c + Vector2(0, 1.5), radius, Color(0, 0, 0, 0.35))
	if ring.a > 0.0:
		ci.draw_circle(c, radius + 2, ring)
	ci.draw_circle(c, radius, color.darkened(0.35))
	ci.draw_circle(c, radius - 1, color)
	var stripe: Color = Color.WHITE if value > 1 else Color("#b0a998")
	for i: int in 6:
		var angle: float = TAU * i / 6.0
		ci.draw_arc(c, radius - 2.0, angle - 0.17, angle + 0.17, 4, stripe, maxf(2.0, radius * 0.22))
	ci.draw_circle(c, radius * 0.62, color.lightened(0.12))
	ci.draw_arc(c, radius * 0.62, 0, TAU, 24, stripe.darkened(0.1) if value > 1 else Color("#b0a998"), 1)
	var text: String = short_amount(value)
	var size: int = 8 if radius >= 12 else (7 if text.length() <= 2 else 6)
	draw_text_centered(ci, c, text, size, CARD_INK if value <= 1 else Color.WHITE)


## Rounded tag with text, e.g. a hand total.
static func draw_badge(ci: CanvasItem, center: Vector2, text: String, size: int, bg: Color, fg: Color = Color.WHITE) -> void:
	var width: float = text_width(text, size) + 10.0
	var height: float = size + 7.0
	var rect: Rect2 = Rect2((center - Vector2(width, height) / 2.0).round(), Vector2(roundf(width), roundf(height)))
	ci.draw_style_box(box(bg, bg.darkened(0.35), 1, 4), rect)
	draw_text_centered(ci, rect.get_center(), text, size, fg)
