class_name WorldMap
extends Node2D
## Builds floors, wall faces and props from a MapLayout and answers pathfinding, room and prop queries.

const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const ENTRANCE_GLASS: Color = Color(0.72, 0.88, 0.95, 0.75)

var layout: MapLayout

@onready var _floor_layer: TileMapLayer = $FloorLayer
@onready var _shadow_layer: TileMapLayer = $ShadowLayer
@onready var _decals: Node2D = $Decals
@onready var _wall_layer: TileMapLayer = $WallLayer
@onready var _wall_decor: Node2D = $WallDecor

var _grid: AStarGrid2D = AStarGrid2D.new()
var _prop_texture: Texture2D
var _prop_regions: Dictionary = {}
## "id@x,y" -> sprite, for tap hit tests.
var _prop_sprites: Dictionary[String, Sprite2D] = {}


## Builds tiles and the walk grid. Call once before populate_props().
func build(p_layout: MapLayout) -> void:
	layout = p_layout
	for error: String in layout.validate():
		push_error("%s: %s" % [layout.get_script().get_global_name(), error])
	var tile_set: TileSet = _make_tile_set()
	for layer: TileMapLayer in [_floor_layer, _shadow_layer, _wall_layer]:
		layer.tile_set = tile_set
	_build_tiles()
	_build_grid()
	for entrance: Rect2i in layout.entrances:
		var glass: ColorRect = ColorRect.new()
		glass.color = ENTRANCE_GLASS
		glass.position = Vector2(entrance.position * MapLayout.TILE_SIZE) + Vector2(0, 6)
		glass.size = Vector2(entrance.size * MapLayout.TILE_SIZE) - Vector2(0, 12)
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wall_decor.add_child(glass)


## Adds furniture to the y-sorted entity container and decor to the map.
func populate_props(entities: Node2D) -> void:
	_prop_texture = load(PropCatalog.TEXTURE_PATH)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(PropCatalog.MANIFEST_PATH))
	_prop_regions = manifest if manifest is Dictionary else {}
	_add_prop_sprites(entities)


## The layout's props changed (the home interior): rebuilds the sprites and the walk grid.
func rebuild_props(entities: Node2D) -> void:
	for sprite: Sprite2D in _prop_sprites.values():
		sprite.queue_free()
	_prop_sprites.clear()
	_grid.fill_solid_region(_grid.region, false)
	_build_grid()
	_add_prop_sprites(entities)


## A sprite of `prop_id` placed at `cell` like a map prop, for previews; null when it has no art.
func make_prop_sprite(prop_id: String, cell: Vector2i) -> Sprite2D:
	if not _prop_regions.has(prop_id):
		return null
	var sprite: Sprite2D = Sprite2D.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	var region: Array = _prop_regions[prop_id]
	atlas.atlas = _prop_texture
	atlas.region = Rect2(region[0], region[1], region[2], region[3])
	sprite.texture = atlas
	sprite.centered = false
	place_prop_sprite(sprite, prop_id, cell)
	return sprite


## Positions a prop sprite of `prop_id` on `cell` (parent-local: the map shares the world origin).
func place_prop_sprite(sprite: Sprite2D, prop_id: String, cell: Vector2i) -> void:
	var size: Vector2 = Vector2(PropCatalog.sprite_size(prop_id))
	var area: Vector2 = Vector2(PropCatalog.footprint(prop_id) * MapLayout.TILE_SIZE)
	var origin: Vector2 = Vector2(cell * MapLayout.TILE_SIZE)
	if PropCatalog.kind(prop_id) == PropCatalog.Kind.FURNITURE:
		sprite.position = origin + Vector2(area.x / 2.0, area.y)
		sprite.offset = Vector2(-roundf(size.x / 2.0), -size.y)
	else:
		sprite.position = origin + ((area - size) / 2.0).floor()
		sprite.offset = Vector2.ZERO


## Recolours floors and walls with a home palette (HomePalettes); null restores the original tiles.
func set_surface_material(material: Material) -> void:
	_floor_layer.material = material
	_wall_layer.material = material


func _add_prop_sprites(entities: Node2D) -> void:
	for prop: MapLayout.Prop in layout.props:
		if not _prop_regions.has(prop.id):
			push_error("Prop '%s' is missing from the atlas manifest" % prop.id)
			continue
		var sprite: Sprite2D = make_prop_sprite(prop.id, prop.cell)
		sprite.name = "%s_%d_%d" % [prop.id, prop.cell.x, prop.cell.y]
		match PropCatalog.kind(prop.id):
			PropCatalog.Kind.FURNITURE:
				entities.add_child(sprite)
			PropCatalog.Kind.WALL:
				_wall_decor.add_child(sprite)
			PropCatalog.Kind.DECAL:
				_decals.add_child(sprite)
		_prop_sprites[_prop_key(prop.id, prop.cell)] = sprite
		if PropCatalog.is_blocking(prop.id):
			var footprint: Rect2i = Rect2i(prop.cell, PropCatalog.footprint(prop.id))
			for y: int in range(footprint.position.y, footprint.end.y):
				for x: int in range(footprint.position.x, footprint.end.x):
					_grid.set_point_solid(Vector2i(x, y))


## World-space rectangle of a placed prop sprite; empty when the prop is unknown.
func get_prop_rect(prop_id: String, cell: Vector2i) -> Rect2:
	var sprite: Sprite2D = _prop_sprites.get(_prop_key(prop_id, cell))
	if sprite == null:
		return Rect2()
	return Rect2(sprite.global_position + sprite.offset, sprite.texture.get_size())


func get_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(layout.size * MapLayout.TILE_SIZE))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i((to_local(world_position) / MapLayout.TILE_SIZE).floor())


func cell_to_world(cell: Vector2i) -> Vector2:
	return to_global(Vector2(cell * MapLayout.TILE_SIZE) + Vector2.ONE * MapLayout.TILE_SIZE / 2.0)


func is_walkable(cell: Vector2i) -> bool:
	return _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell)


## Closest walkable cell to world_position within max_radius cells of its cell, or INVALID_CELL.
func find_nearest_walkable(world_position: Vector2, max_radius: int) -> Vector2i:
	var origin: Vector2i = world_to_cell(world_position)
	var best: Vector2i = INVALID_CELL
	var best_distance: float = INF
	for dy: int in range(-max_radius, max_radius + 1):
		for dx: int in range(-max_radius, max_radius + 1):
			var cell: Vector2i = origin + Vector2i(dx, dy)
			if not is_walkable(cell):
				continue
			var distance: float = cell_to_world(cell).distance_squared_to(world_position)
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


## World-space points from the cell under from_position to target_cell. Empty when unreachable.
func find_path(from_position: Vector2, target_cell: Vector2i) -> PackedVector2Array:
	var from_cell: Vector2i = world_to_cell(from_position)
	if not is_walkable(from_cell):
		from_cell = find_nearest_walkable(from_position, 1)
	if from_cell == INVALID_CELL or not is_walkable(target_cell):
		return PackedVector2Array()
	var path: PackedVector2Array = _grid.get_point_path(from_cell, target_cell)
	for i: int in path.size():
		path[i] = to_global(path[i])
	return path


func get_room_at(cell: Vector2i) -> MapLayout.Room:
	return layout.get_room_at(cell)


func _prop_key(prop_id: String, cell: Vector2i) -> String:
	return "%s@%d,%d" % [prop_id, cell.x, cell.y]


func _make_tile_set() -> TileSet:
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i.ONE * OfficeTiles.SIZE
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(OfficeTiles.TEXTURE_PATH)
	source.texture_region_size = Vector2i.ONE * OfficeTiles.SIZE
	for row: int in OfficeTiles.Style.size():
		for column: int in OfficeTiles.COLUMNS:
			source.create_tile(Vector2i(column, row))
	tile_set.add_source(source, 0)
	return tile_set


func _build_tiles() -> void:
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			var cell: Vector2i = Vector2i(x, y)
			var room: MapLayout.Room = layout.get_room_at(cell)
			var style: OfficeTiles.Style = room.style if room != null else OfficeTiles.Style.CORRIDOR
			var variant: int = absi(hash(cell)) % 7
			variant = 0 if variant < 4 else (1 if variant < 6 else 2)
			var type: MapLayout.Cell = layout.cell_type(cell)
			match type:
				MapLayout.Cell.CAP:
					_wall_layer.set_cell(cell, 0, OfficeTiles.cap_coords())
				MapLayout.Cell.FACE:
					var below: MapLayout.Cell = layout.cell_type(cell + Vector2i.DOWN)
					_wall_layer.set_cell(cell, 0, OfficeTiles.face_coords(style, below == MapLayout.Cell.FACE))
				MapLayout.Cell.FLOOR:
					_floor_layer.set_cell(cell, 0, OfficeTiles.floor_coords(style, variant))
				MapLayout.Cell.DOOR, MapLayout.Cell.ENTRANCE:
					_floor_layer.set_cell(cell, 0, OfficeTiles.floor_coords(OfficeTiles.Style.DOOR, 0))
			var above: MapLayout.Cell = layout.cell_type(cell + Vector2i.UP)
			var walkable: bool = type == MapLayout.Cell.FLOOR or type == MapLayout.Cell.DOOR
			if walkable and (above == MapLayout.Cell.FACE or above == MapLayout.Cell.CAP):
				_shadow_layer.set_cell(cell, 0, OfficeTiles.shadow_coords())


func _build_grid() -> void:
	_grid.region = Rect2i(Vector2i.ZERO, layout.size)
	_grid.cell_size = Vector2.ONE * MapLayout.TILE_SIZE
	_grid.offset = _grid.cell_size * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			if not layout.is_walkable_cell(Vector2i(x, y)):
				_grid.set_point_solid(Vector2i(x, y))
	for rect: Rect2i in layout.solid_rects:
		_grid.fill_solid_region(rect, true)
