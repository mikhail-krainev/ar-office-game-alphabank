class_name OfficeColleagues
extends Node
## The other players who are in the office now, as characters on the office map (ColleagueWalker).
## The list comes from the server (office_players) and is refreshed every REFRESH_SECONDS: newcomers
## appear at the entrance or in their room, those who left disappear. Only colleagues of this floor
## are shown: the room of their last door code decides the floor (no room: the main floor).

const REFRESH_SECONDS: float = 45.0
const WALKER_SCRIPT: GDScript = preload("res://scripts/world/colleague_walker.gd")
const SPAWN_SEARCH_RADIUS: int = 6

var _map: WorldMap
var _entities: Node2D
var _walkers: Dictionary[String, ColleagueWalker] = {}
var _refresh_left: float = 0.0
var _refreshing: bool = false


func setup(map: WorldMap, entities: Node2D) -> void:
	_map = map
	_entities = entities


func _process(delta: float) -> void:
	if Backend.profile == null:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0 and not _refreshing:
		_refresh()


## The colleague whose character or name tag is at the point, or null.
func hit(world_position: Vector2) -> BackendModels.OfficePlayer:
	for walker: ColleagueWalker in _walkers.values():
		if walker.is_hit(world_position):
			return walker.player
	return null


func refresh_now() -> void:
	_refresh_left = 0.0


func _refresh() -> void:
	_refreshing = true
	var players: Array[BackendModels.OfficePlayer] = await Backend.social.office_players()
	_refreshing = false
	_refresh_left = REFRESH_SECONDS
	if not is_inside_tree():
		return
	var seen: Dictionary[String, bool] = {}
	for player: BackendModels.OfficePlayer in players:
		if player.colleague.floor_id != OfficeFloors.current:
			continue
		var id: String = player.colleague.user_id
		seen[id] = true
		if _walkers.has(id):
			_walkers[id].update_player(player)
			continue
		var cell: Vector2i = _spawn_cell(player)
		if cell == WorldMap.INVALID_CELL:
			continue
		var walker: ColleagueWalker = WALKER_SCRIPT.new()
		_entities.add_child(walker)
		walker.setup(player, _map, cell)
		_walkers[id] = walker
	for id: String in _walkers.keys():
		if not seen.has(id):
			_walkers[id].queue_free()
			_walkers.erase(id)


## In the colleague's room when it is known, else anywhere on the floor near a random room.
func _spawn_cell(player: BackendModels.OfficePlayer) -> Vector2i:
	var rooms: Array[MapLayout.Room] = _map.layout.rooms
	var room: MapLayout.Room = _map.layout.find_room(player.colleague.room)
	if room == null and not rooms.is_empty():
		room = rooms.pick_random()
	if room == null:
		return WorldMap.INVALID_CELL
	var floor_rect: Rect2i = room.floor_rect()
	var target: Vector2i = (
		floor_rect.position
		+ Vector2i(randi_range(0, floor_rect.size.x - 1), randi_range(0, floor_rect.size.y - 1))
	)
	return _map.find_nearest_walkable(_map.cell_to_world(target), SPAWN_SEARCH_RADIUS)
