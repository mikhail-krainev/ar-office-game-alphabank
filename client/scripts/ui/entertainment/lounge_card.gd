class_name LoungeCard
extends Button
## Alfa identity on the face of a memory card. Hidden identities are never received from the server.

const MARK: Texture2D = preload("res://assets/brand/alfa_mark_small.png")
const SYMBOLS: Array[String] = ["АЛЬФА", "КОТ", "ОФИС", "КОФЕ", "КАРТА", "МЕРЧ", "КЕПКА", "БАГ", "КОИН", "ЧАТ", "КЛЮЧ", "ПОДАРОК", "ДОМ", "МАШИНА", "QR", "РОСТ", "ИГРА", "ИДЕЯ"]
var identity: int = -1
var matched: bool = false


func _init(value: int = -1, found: bool = false) -> void:
	identity = value
	matched = found
	custom_minimum_size = Vector2(45, 54)
	focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, UiStyle.panel(Color("#24242d") if value < 0 else UiStyle.PAPER, 5, 2))
	disabled = matched
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var center: Vector2 = size / 2.0
	if identity < 0:
		draw_texture_rect(MARK, Rect2(center - Vector2(10, 13), Vector2(20, 24)), false)
		return
	var ink: Color = UiStyle.RED if identity % 2 == 0 else UiStyle.INK
	var font: Font = ThemeDB.fallback_font
	# A distinct emblem and caption distinguish pairs without relying on colour alone.
	match identity % 6:
		0:
			draw_texture_rect(MARK, Rect2(center - Vector2(9, 18), Vector2(18, 20)), false)
		1:
			draw_circle(center + Vector2(0, -7), 9, ink)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-9, -11), center + Vector2(-10, -22), center + Vector2(-1, -14)]), ink)
			draw_colored_polygon(PackedVector2Array([center + Vector2(9, -11), center + Vector2(10, -22), center + Vector2(1, -14)]), ink)
			draw_circle(center + Vector2(-3, -8), 1.5, Color.WHITE)
			draw_circle(center + Vector2(3, -8), 1.5, Color.WHITE)
		2:
			draw_rect(Rect2(center + Vector2(-9, -20), Vector2(18, 24)), ink)
			for x: int in 2:
				for y: int in 3:
					draw_rect(Rect2(center + Vector2(-6 + x * 7, -17 + y * 6), Vector2(3, 3)), Color.WHITE)
		3:
			draw_rect(Rect2(center + Vector2(-9, -17), Vector2(16, 17)), ink)
			draw_arc(center + Vector2(8, -10), 5, -PI / 2, PI / 2, 12, ink, 2)
		4:
			draw_rect(Rect2(center + Vector2(-13, -18), Vector2(26, 17)), ink)
			draw_line(center + Vector2(-10, -11), center + Vector2(10, -11), Color.WHITE, 3)
		5:
			draw_rect(Rect2(center + Vector2(-10, -16), Vector2(20, 19)), ink)
			draw_line(center + Vector2(0, -16), center + Vector2(0, 3), Color.WHITE, 3)
	var caption: String = SYMBOLS[identity % SYMBOLS.size()]
	var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	draw_string(font, Vector2(center.x - width / 2, size.y - 7), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, ink)
	if matched:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color("#30ad80"), false, 2)
