class_name MapLayout
extends RefCounted
## Description of a 3/4-view floor: rooms with wall faces, doors between them and props.
## Subclasses fill the data in _init() and call finalize().

enum Cell { CAP, FACE, FLOOR, DOOR, ENTRANCE }

const TILE_SIZE: int = OfficeTiles.SIZE


class Room:
	extends RefCounted

	var id: StringName
	var name_key: String
	## Includes the wall-face rows at the top.
	var rect: Rect2i
	var style: OfficeTiles.Style
	var face_rows: int

	func _init(p_id: StringName, p_name_key: String, p_rect: Rect2i, p_style: OfficeTiles.Style, p_face_rows: int) -> void:
		id = p_id
		name_key = p_name_key
		rect = p_rect
		style = p_style
		face_rows = p_face_rows

	func floor_rect() -> Rect2i:
		return Rect2i(rect.position + Vector2i(0, face_rows), rect.size - Vector2i(0, face_rows))


class Prop:
	extends RefCounted

	var id: String
	var cell: Vector2i

	func _init(p_id: String, p_cell: Vector2i) -> void:
		id = p_id
		cell = p_cell


var size: Vector2i = Vector2i.ONE
var spawn_cell: Vector2i = Vector2i.ZERO
var rooms: Array[Room] = []
var doors: Array[Rect2i] = []
## Glass entrance cells drawn over the bottom wall; not walkable.
var entrances: Array[Rect2i] = []
var props: Array[Prop] = []
## Lift to the other floors: the wall prop's footprint and the floor cell in front of its doors.
## Empty when the floor has no lift.
var elevator: Rect2i = Rect2i()
var elevator_cell: Vector2i = Vector2i.ZERO
## Floor cells blocked by something that is not a prop, e.g. the car parked in the home garage.
var solid_rects: Array[Rect2i] = []

var _cells: PackedInt32Array = PackedInt32Array()


func add_room(id: StringName, name_key: String, rect: Rect2i, style: OfficeTiles.Style, face_rows: int = 2) -> void:
	rooms.append(Room.new(id, name_key, rect, style, face_rows))


func add_prop(id: String, x: int, y: int) -> void:
	props.append(Prop.new(id, Vector2i(x, y)))


## Lift doors on a wall face at (x, y); the player waits on the floor cell right below them.
func add_elevator(x: int, y: int) -> void:
	add_prop("elevator", x, y)
	elevator = Rect2i(Vector2i(x, y), PropCatalog.footprint("elevator"))
	@warning_ignore("integer_division")
	elevator_cell = Vector2i(x + elevator.size.x / 2, y + elevator.size.y)


func has_elevator() -> bool:
	return elevator.has_area()


func finalize() -> void:
	_cells.resize(size.x * size.y)
	_cells.fill(Cell.CAP)
	for room: Room in rooms:
		for y: int in range(room.rect.position.y, room.rect.end.y):
			for x: int in range(room.rect.position.x, room.rect.end.x):
				var is_face: bool = y < room.rect.position.y + room.face_rows
				_cells[y * size.x + x] = Cell.FACE if is_face else Cell.FLOOR
	for door: Rect2i in doors:
		_fill(door, Cell.DOOR)
	for entrance: Rect2i in entrances:
		_fill(entrance, Cell.ENTRANCE)


func get_room_at(cell: Vector2i) -> Room:
	for room: Room in rooms:
		if room.rect.has_point(cell):
			return room
	return null


func find_room(id: StringName) -> Room:
	for room: Room in rooms:
		if room.id == id:
			return room
	return null


func cell_type(cell: Vector2i) -> Cell:
	if not Rect2i(Vector2i.ZERO, size).has_point(cell):
		return Cell.CAP
	return _cells[cell.y * size.x + cell.x] as Cell


func is_walkable_cell(cell: Vector2i) -> bool:
	var type: Cell = cell_type(cell)
	return type == Cell.FLOOR or type == Cell.DOOR


func find_prop(id: String, cell: Vector2i) -> Prop:
	for prop: Prop in props:
		if prop.id == id and prop.cell == cell:
			return prop
	return null


## Returns human-readable problems with the layout data; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if not is_walkable_cell(spawn_cell):
		errors.append("Spawn cell %s is not walkable" % spawn_cell)
	if has_elevator() and not is_walkable_cell(elevator_cell):
		errors.append("Elevator cell %s is not walkable" % elevator_cell)
	for prop: Prop in props:
		if not PropCatalog.DEFS.has(prop.id):
			errors.append("Unknown prop '%s'" % prop.id)
			continue
		var footprint: Rect2i = Rect2i(prop.cell, PropCatalog.footprint(prop.id))
		for y: int in range(footprint.position.y, footprint.end.y):
			for x: int in range(footprint.position.x, footprint.end.x):
				var type: Cell = cell_type(Vector2i(x, y))
				var expected_face: bool = PropCatalog.kind(prop.id) == PropCatalog.Kind.WALL
				if expected_face and type != Cell.FACE:
					errors.append("Wall prop '%s' at %s is not on a wall face" % [prop.id, prop.cell])
				elif not expected_face and type != Cell.FLOOR:
					errors.append("Prop '%s' at %s covers a non-floor cell %s" % [prop.id, prop.cell, Vector2i(x, y)])
	return errors


func _fill(rect: Rect2i, type: Cell) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			_cells[y * size.x + x] = type
