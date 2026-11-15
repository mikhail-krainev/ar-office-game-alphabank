class_name RouletteBoard
extends Control
## Betting layout: zero, numbers 1–36 in three rows and red / black below. A tap places the chosen
## chip on the field (`bet_requested`); chips show this player's total per field, every colleague
## who bet on a field has a small chip of their seat colour there. The winning field glows after
## the wheel has stopped.

signal bet_requested(field: String)

const ZERO_WIDTH: float = 24.0
const CELL_HEIGHT: float = 26.0
const GAP: float = 2.0
const OUTSIDE_HEIGHT: float = 30.0
const TAP_SLOP: float = 10.0

const SEAT_CHIP_RADIUS: float = 4.5
const SEAT_CHIP_STEP: float = 7.0
const SEAT_CHIPS_MAX: int = 8

## Field -> total coins of this player.
var my_bets: Dictionary = {}
## Field -> seat indexes of the colleagues who bet on it, in betting order.
var other_bets: Dictionary = {}
var enabled: bool = false
var winner: int = -1

var _clock: float = 0.0
var _press: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _flash_field: String = ""
var _flash_at: float = -10.0


func _init() -> void:
	custom_minimum_size = Vector2(0, CELL_HEIGHT * 3 + GAP * 3 + OUTSIDE_HEIGHT + 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _process(delta: float) -> void:
	_clock += delta
	if winner >= 0 or _clock - _flash_at < 0.4:
		queue_redraw()


func set_state(mine: Dictionary, others: Dictionary, is_enabled: bool, winning: int) -> void:
	my_bets = mine
	other_bets = others
	enabled = is_enabled
	winner = winning
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	queue_redraw()


func _inner() -> Rect2:
	return Rect2(Vector2(6, 6), size - Vector2(12, 12))


func _cell_width() -> float:
	return (_inner().size.x - ZERO_WIDTH - GAP) / 12.0


## Every field with its rectangle, in drawing order.
func _fields() -> Array[Array]:
	var inner: Rect2 = _inner()
	var result: Array[Array] = []
	result.append(["green", Rect2(inner.position, Vector2(ZERO_WIDTH, CELL_HEIGHT * 3 + GAP * 2))])
	var cell: float = _cell_width()
	for column: int in 12:
		for row: int in 3:
			var number: int = column * 3 + (3 - row)
			var x: float = inner.position.x + ZERO_WIDTH + GAP + column * cell
			var rect: Rect2 = Rect2(Vector2(roundf(x), inner.position.y + row * (CELL_HEIGHT + GAP)), Vector2(roundf(x + cell - GAP) - roundf(x), CELL_HEIGHT))
			result.append(["n%d" % number, rect])
	var top: float = inner.position.y + CELL_HEIGHT * 3 + GAP * 3
	var half: float = roundf((inner.size.x - GAP) / 2.0)
	result.append(["red", Rect2(Vector2(inner.position.x, top), Vector2(half, OUTSIDE_HEIGHT))])
	result.append(["black", Rect2(Vector2(inner.position.x + half + GAP, top), Vector2(inner.size.x - half - GAP, OUTSIDE_HEIGHT))])
	return result


static func field_number(field: String) -> int:
	if field == "green":
		return 0
	return int(field.substr(1)) if field.begins_with("n") else -1


func _wins(field: String) -> bool:
	if winner < 0:
		return false
	if field == "red":
		return CasinoArt.REDS.has(winner)
	if field == "black":
		return winner != 0 and not CasinoArt.REDS.has(winner)
	return field_number(field) == winner


func _draw() -> void:
	CasinoArt.draw_felt(self, Rect2(Vector2.ZERO, size))
	var pulse: float = 0.5 + 0.5 * sin(_clock * 6.0)
	for entry: Array in _fields():
		var field: String = entry[0]
		var rect: Rect2 = entry[1]
		var number: int = field_number(field)
		var color: Color = CasinoArt.POCKET_RED if field == "red" else (CasinoArt.POCKET_BLACK if field == "black" else CasinoArt.pocket_color(number))
		draw_style_box(CasinoArt.box(color, color.darkened(0.4), 1, 3), rect)
		if field == "red" or field == "black":
			CasinoArt.draw_text_centered(self, rect.get_center() + Vector2(-14, 0), "КРАСНОЕ" if field == "red" else "ЧЁРНОЕ", 10, Color.WHITE)
			CasinoArt.draw_text_centered(self, rect.get_center() + Vector2(rect.size.x / 2.0 - 16, 0), "×2", 9, CasinoArt.GOLD_TEXT)
		elif field == "green":
			CasinoArt.draw_text_centered(self, rect.get_center() + Vector2(0, -8), "0", 11, Color.WHITE)
			CasinoArt.draw_text_centered(self, rect.get_center() + Vector2(0, 10), "×36", 7, CasinoArt.GOLD_TEXT)
		else:
			CasinoArt.draw_text_centered(self, rect.get_center(), str(number), 10 if number < 10 else 9, Color.WHITE)
		if _wins(field):
			draw_style_box(CasinoArt.box(Color(1, 0.85, 0.4, 0.25 + 0.3 * pulse), CasinoArt.GOLD_TEXT, 2, 3), rect.grow(1))
		elif winner >= 0:
			draw_rect(rect, Color(0, 0, 0, 0.35))
		if field == _flash_field and _clock - _flash_at < 0.4:
			draw_style_box(CasinoArt.box(Color(1, 1, 1, 0.5 * (1.0 - (_clock - _flash_at) / 0.4)), Color.TRANSPARENT, 0, 3), rect)
	for entry: Array in _fields():
		var amount: int = int(my_bets.get(entry[0], 0))
		if amount > 0:
			var rect: Rect2 = entry[1]
			var chip_center: Vector2 = rect.get_center() if entry[0] not in ["red", "black"] else rect.get_center() + Vector2(rect.size.x / 2.0 - 48, 0)
			CasinoArt.draw_chip(self, chip_center, minf(11.0, minf(rect.size.x, rect.size.y) / 2.0 + 1.0), amount, CasinoArt.GOLD_TEXT)
	# Colleagues' chips lie on top, along the upper edge, so a player's own chip never hides them.
	for entry: Array in _fields():
		_draw_seat_chips(entry[1], other_bets.get(entry[0], []))
	if not enabled and winner < 0:
		draw_style_box(CasinoArt.box(Color(0.04, 0.12, 0.1, 0.45), Color.TRANSPARENT, 0, 10), Rect2(Vector2.ZERO, size))


func _draw_seat_chips(rect: Rect2, seats: Array) -> void:
	if seats.is_empty():
		return
	var capacity: int = clampi(int((rect.size.x - 2.0) / SEAT_CHIP_STEP), 1, SEAT_CHIPS_MAX)
	# A crowded field keeps its last place for a "more" mark.
	var shown: int = seats.size() if seats.size() <= capacity else capacity - 1
	var at: Vector2 = rect.position + Vector2(SEAT_CHIP_RADIUS + 1.0, SEAT_CHIP_RADIUS + 1.0)
	for i: int in shown:
		CasinoArt.draw_seat_chip(self, at + Vector2(i * SEAT_CHIP_STEP, 0), SEAT_CHIP_RADIUS, CasinoArt.seat_color(int(seats[i])))
	if shown < seats.size():
		CasinoArt.draw_text_centered(self, at + Vector2(shown * SEAT_CHIP_STEP, 0), "+", 8, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_pressing = true
		_press = button.position
		return
	if not _pressing:
		return
	_pressing = false
	if not enabled or button.position.distance_to(_press) > TAP_SLOP:
		return
	for entry: Array in _fields():
		if (entry[1] as Rect2).grow(GAP / 2.0).has_point(button.position):
			_flash_field = entry[0]
			_flash_at = _clock
			bet_requested.emit(entry[0])
			accept_event()
			return
