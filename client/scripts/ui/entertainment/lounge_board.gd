class_name LoungeBoard
extends Control
## Checkers board with piece selection, movement tweening and four-player chaos pickups.

signal action_requested(action: String, extra: Dictionary)

const MARK: Texture2D = preload("res://assets/brand/alfa_mark_small.png")
const COLORS: Array[Color] = [Color("#ef3124"), Color("#252631"), Color("#437fbc"), Color("#d49c27")]
var room: Dictionary = {}
var selected: int = -1
var use_power: bool = false
var _moving_from: int = -1
var _moving_to: int = -1
var _progress: float = 1.0
var _old_board: Array = []


func _init(data: Dictionary = {}) -> void:
	room = data
	selected = int(data.get("chain", -1))
	custom_minimum_size = Vector2(288, 288)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var board: Array = room.get("board", [])
	if board.is_empty():
		return
	var n: int = int(sqrt(board.size()))
	var cell: float = 288.0 / n
	var font: Font = ThemeDB.fallback_font
	var bonuses: Dictionary = room.get("bonuses", {})
	var blocked: Dictionary = room.get("blocked", {})
	var entries: Dictionary = room.get("portal_entries", {})
	for i: int in board.size():
		var x: int = i % n
		var y: int = i / n
		if n == 12 and not ((x >= 4 and x < 8) or (y >= 4 and y < 8)):
			continue
		var rect: Rect2 = Rect2(x * cell, y * cell, cell, cell)
		draw_rect(rect, Color("#ddd5cd") if (x + y) % 2 == 0 else Color("#79656a"))
		if entries.values().has(i):
			draw_rect(rect.grow(-2), Color("#a348e4"), false, 2)
		if i == selected:
			draw_rect(rect.grow(-1), UiStyle.GOLD, false, 3)
		if bonuses.has(str(i)):
			draw_circle(rect.get_center(), cell * 0.32, Color("#a348e4"))
			draw_string(font, rect.position + Vector2(6, cell * 0.7), "П" if bonuses[str(i)] == "portal" else "Б", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		if blocked.has(str(i)):
			draw_line(rect.position, rect.end, UiStyle.RED, 3)
			draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), UiStyle.RED, 3)
		var piece: int = int(board[i])
		if piece > 0 and not (i == _moving_to and _progress < 1):
			_piece(rect.get_center(), cell, piece)
	if _moving_to >= 0 and _progress < 1:
		var start: Vector2 = Vector2(_moving_from % n + 0.5, _moving_from / n + 0.5) * cell
		var finish: Vector2 = Vector2(_moving_to % n + 0.5, _moving_to / n + 0.5) * cell
		_piece(start.lerp(finish, _progress), cell, int(_old_board[_moving_from]))


func _piece(center: Vector2, cell: float, piece: int) -> void:
	var color: Color = COLORS[(piece - 1) % 4]
	draw_circle(center + Vector2(0, 2), cell * 0.38, Color("#25212c"))
	draw_circle(center, cell * 0.37, color)
	draw_arc(center, cell * 0.29, 0, TAU, 20, Color.WHITE, 1)
	draw_circle(center, cell * 0.23, Color.WHITE)
	draw_texture_rect(MARK, Rect2(center - Vector2(cell * 0.13, cell * 0.18), Vector2(cell * 0.26, cell * 0.32)), false)
	if piece > 4:
		draw_arc(center, cell * 0.4, 0, TAU, 20, UiStyle.GOLD, 2)
	# Different ring counts also distinguish the four sides.
	for j: int in (piece - 1) % 4:
		draw_circle(center + Vector2(-5 + j * 5, cell * 0.23), 1.2, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	var point: Variant = Minigame.press_position(event)
	if point == null:
		return
	var board: Array = room.get("board", [])
	if board.is_empty():
		return
	var n: int = int(sqrt(board.size()))
	var cell: float = 288.0 / n
	var position_in_board: Vector2 = point
	var x: int = int(position_in_board.x / cell)
	var y: int = int(position_in_board.y / cell)
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	var index: int = y * n + x
	if selected < 0:
		if use_power and _my_power() == "barrier":
			action_requested.emit("power", {"to": index})
		elif int(board[index]) > 0:
			selected = index
			queue_redraw()
	else:
		var from: int = selected
		selected = -1
		action_requested.emit("power" if use_power else "move", {"index": from, "to": index})
		queue_redraw()


func _my_power() -> String:
	var powers: Dictionary = room.get("powers", {})
	return str(powers.get(str(room.get("turn", 0)), ""))


func animate_from(previous: Array) -> void:
	var board: Array = room.get("board", [])
	if previous.size() != board.size():
		return
	var removed: Array[int] = []
	for i: int in board.size():
		if int(previous[i]) > 0 and int(board[i]) == 0:
			removed.append(i)
	for i: int in board.size():
		if int(previous[i]) == 0 and int(board[i]) > 0:
			for origin: int in removed:
				if (int(previous[origin]) - 1) % 4 == (int(board[i]) - 1) % 4:
					_moving_from = origin
					_moving_to = i
					_old_board = previous
					_progress = 0
					return


func _ready() -> void:
	if _progress < 1:
		var tween: Tween = create_tween()
		tween.tween_property(self, "_progress", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.finished.connect(queue_redraw)


func _process(_delta: float) -> void:
	if _progress < 1:
		queue_redraw()
