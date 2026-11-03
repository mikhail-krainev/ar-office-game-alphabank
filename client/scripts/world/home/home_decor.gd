class_name HomeDecor
extends RefCounted
## Where an interior item fits in a HomeLayout. Posters hang on wall faces, furniture and rugs stand
## on the floor; nothing overlaps an item of its own layer, furniture keeps off the spots the player
## uses (and the door), and a blocking piece never cuts off a room. The server checks ownership and
## bounds; the shape of the apartment is known only here.

const OK: String = ""
const ERROR_WALL: String = "DECOR_ERROR_WALL"
const ERROR_FLOOR: String = "DECOR_ERROR_FLOOR"
const ERROR_TAKEN: String = "DECOR_ERROR_TAKEN"
const ERROR_BLOCKS: String = "DECOR_ERROR_BLOCKS"
const NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## OK or the error key (a translation key) why `item_id` cannot stand with its top-left cell at
## `cell`. `ignore` is a placed prop that is being moved; `occupied` are cells someone stands on.
static func placement_error(layout: HomeLayout, item_id: String, cell: Vector2i, ignore: MapLayout.Prop = null, occupied: Array[Vector2i] = []) -> String:
	if not PropCatalog.DEFS.has(item_id):
		return ERROR_FLOOR
	var kind: PropCatalog.Kind = PropCatalog.kind(item_id)
	var area: Rect2i = Rect2i(cell, PropCatalog.footprint(item_id))
	var wanted: MapLayout.Cell = MapLayout.Cell.FACE if kind == PropCatalog.Kind.WALL else MapLayout.Cell.FLOOR
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if layout.cell_type(Vector2i(x, y)) != wanted:
				return ERROR_WALL if kind == PropCatalog.Kind.WALL else ERROR_FLOOR
	for prop: MapLayout.Prop in layout.props:
		if prop == ignore or not _same_layer(kind, PropCatalog.kind(prop.id)):
			continue
		if Rect2i(prop.cell, PropCatalog.footprint(prop.id)).intersects(area):
			return ERROR_TAKEN
	if kind != PropCatalog.Kind.FURNITURE:
		return OK
	for rect: Rect2i in layout.solid_rects:
		if rect.intersects(area):
			return ERROR_TAKEN
	var kept: Array[Vector2i] = [layout.spawn_cell]
	kept.append_array(occupied)
	for use_spot: HomeLayout.Interactable in layout.interactables:
		kept.append(use_spot.stand_cell)
	for kept_cell: Vector2i in kept:
		if area.has_point(kept_cell):
			return ERROR_BLOCKS
	if PropCatalog.is_blocking(item_id) and not _all_reachable(layout, area, ignore, kept):
		return ERROR_BLOCKS
	return OK


## Rugs lie under furniture, so floor items share a layer only with their own kind.
static func _same_layer(a: PropCatalog.Kind, b: PropCatalog.Kind) -> bool:
	return a == b


## With `extra` blocked too, the player can still walk from the spawn to every kept cell and door.
static func _all_reachable(layout: HomeLayout, extra: Rect2i, ignore: MapLayout.Prop, kept: Array[Vector2i]) -> bool:
	var blocked: Dictionary[Vector2i, bool] = {}
	for prop: MapLayout.Prop in layout.props:
		if prop == ignore or PropCatalog.kind(prop.id) != PropCatalog.Kind.FURNITURE or not PropCatalog.is_blocking(prop.id):
			continue
		_mark(blocked, Rect2i(prop.cell, PropCatalog.footprint(prop.id)))
	for rect: Rect2i in layout.solid_rects:
		_mark(blocked, rect)
	_mark(blocked, extra)
	var seen: Dictionary[Vector2i, bool] = {layout.spawn_cell: true}
	var queue: Array[Vector2i] = [layout.spawn_cell]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for step: Vector2i in NEIGHBOURS:
			var next: Vector2i = current + step
			if seen.has(next) or blocked.has(next) or not layout.is_walkable_cell(next):
				continue
			seen[next] = true
			queue.append(next)
	for target: Vector2i in kept:
		if not seen.has(target):
			return false
	for door: Rect2i in layout.doors:
		for y: int in range(door.position.y, door.end.y):
			for x: int in range(door.position.x, door.end.x):
				if not seen.has(Vector2i(x, y)):
					return false
	return true


static func _mark(cells: Dictionary[Vector2i, bool], rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			cells[Vector2i(x, y)] = true


## The top-left cell that puts `item_id` under a tap at `tap_cell`: furniture stands with its front
## row on the tapped cell, posters hang at the top of the tapped room's wall.
static func cell_for_tap(layout: HomeLayout, item_id: String, tap_cell: Vector2i) -> Vector2i:
	var footprint: Vector2i = PropCatalog.footprint(item_id)
	@warning_ignore("integer_division")
	var cell: Vector2i = tap_cell - Vector2i(footprint.x / 2, footprint.y - 1)
	if PropCatalog.kind(item_id) != PropCatalog.Kind.WALL:
		return cell
	var room: MapLayout.Room = layout.get_room_at(tap_cell)
	if room != null:
		cell.y = room.rect.position.y
	return cell


## The placed interior prop under `world_position` (rects from WorldMap), or null.
static func prop_at(layout: HomeLayout, map: WorldMap, world_position: Vector2) -> MapLayout.Prop:
	var found: MapLayout.Prop = null
	for prop: MapLayout.Prop in layout.decor_props():
		if map.get_prop_rect(prop.id, prop.cell).has_point(world_position):
			# The front-most (lowest) item wins, like the y-sorted drawing.
			if found == null or prop.cell.y >= found.cell.y:
				found = prop
	return found
