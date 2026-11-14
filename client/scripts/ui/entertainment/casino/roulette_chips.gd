class_name RouletteChips
extends Control
## Chip rack: the chosen chip value for the next tap on the board, plus this round's own stake and
## the balance on the right. Chips worth more than the balance are greyed out. The chips sit in two
## rows: small values on top, large ones below, shifted half a step.

signal chip_selected(value: int)

const VALUES: Array[int] = [5, 10, 20, 50, 100, 500, 1000, 5000, 10000]
const PER_ROW: int = 5
const RADIUS: float = 14.0
const SPACING: float = 33.0
const ROW_STEP: float = 33.0
const RACK_HEIGHT: float = 78.0

var selected: int = 10
var balance: int = 0
var my_total: int = 0

var _lift: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, RACK_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_state(new_balance: int, total: int) -> void:
	balance = new_balance
	my_total = total
	if selected > balance:
		for value: int in VALUES:
			if value <= balance:
				selected = value
	queue_redraw()


func _process(delta: float) -> void:
	var moving: bool = false
	for value: int in VALUES:
		var target: float = 5.0 if value == selected else 0.0
		var now: float = move_toward(float(_lift.get(value, 0.0)), target, delta * 40.0)
		moving = moving or not is_equal_approx(now, float(_lift.get(value, 0.0)))
		_lift[value] = now
	if moving:
		queue_redraw()


func _chip_center(index: int) -> Vector2:
	var row: int = index / PER_ROW
	var column: int = index % PER_ROW
	var x: float = RADIUS + 6.0 + column * SPACING + row * SPACING / 2.0
	return Vector2(x, size.y / 2.0 + 2.0 + (row - 0.5) * ROW_STEP)


func _draw() -> void:
	draw_style_box(CasinoArt.box(CasinoArt.WOOD, CasinoArt.WOOD_DARK, 2, 8), Rect2(Vector2.ZERO, size))
	for i: int in VALUES.size():
		var value: int = VALUES[i]
		var center: Vector2 = _chip_center(i) - Vector2(0, float(_lift.get(value, 0.0)))
		CasinoArt.draw_chip(self, center, RADIUS, value, CasinoArt.GOLD_TEXT if value == selected else Color.TRANSPARENT)
		if value > balance:
			draw_circle(center, RADIUS + 1, Color(0.17, 0.1, 0.06, 0.7))
	var info_x: float = _chip_center(PER_ROW - 1).x + RADIUS + 8.0
	var info_center: float = (info_x + size.x - 4.0) / 2.0
	var middle: float = size.y / 2.0
	CasinoArt.draw_text_centered(self, Vector2(info_center, middle - 14), "МОЯ СТАВКА", 7, Color("#d9c3a3"))
	CasinoArt.draw_text_centered(self, Vector2(info_center, middle), str(my_total), 13, CasinoArt.GOLD_TEXT)
	CasinoArt.draw_text_centered(self, Vector2(info_center, middle + 14), "баланс %d" % balance, 7, Color("#d9c3a3"))


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	for i: int in VALUES.size():
		if button.position.distance_to(_chip_center(i)) <= RADIUS + 4.0 and VALUES[i] <= balance:
			selected = VALUES[i]
			chip_selected.emit(selected)
			queue_redraw()
			accept_event()
			return
