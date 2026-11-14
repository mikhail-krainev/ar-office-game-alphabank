class_name OfficeColleagues
extends Node
## The other players who are in the office now, as characters on the office map (ColleagueWalker).
## The list comes from the server (office_players) and is refreshed every REFRESH_SECONDS: newcomers
## appear in their room, those who left disappear, and a colleague whose character moved to another
## room walks there. Every player sees a colleague in the same room (shown_room): where their own
## character is on their screen (report_position), else the room of their last door code, else one
## picked from their id. Only colleagues of this floor are shown, at most MAX_WALKERS of them: the
## server sends the whole office (the chat lists everyone), the map keeps who is already drawn.

const REFRESH_SECONDS: float = 5.0
const WALKER_SCRIPT: GDScript = preload("res://scripts/world/colleague_walker.gd")
const SPAWN_SEARCH_RADIUS: int = 6
## The office map draws at most this many colleagues of the floor.
const MAX_WALKERS: int = 30

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
		var room_id: StringName = shown_room(player)
		if OfficeFloors.floor_of_room(room_id) != OfficeFloors.current:
			continue
		var room: MapLayout.Room = _map.layout.find_room(room_id)
		var id: String = player.colleague.user_id
		if _walkers.has(id):
			seen[id] = true
			_walkers[id].update_player(player, room)
			continue
		# Who left is removed below; their place goes to a newcomer on the next refresh.
		if _walkers.size() >= MAX_WALKERS:
			continue
		var cell: Vector2i = _random_cell(room)
		if cell == WorldMap.INVALID_CELL:
			continue
		var walker: ColleagueWalker = WALKER_SCRIPT.new()
		_entities.add_child(walker)
		walker.setup(player, _map, cell, room)
		seen[id] = true
		_walkers[id] = walker
	for id: String in _walkers.keys():
		if not seen.has(id):
			_walkers[id].queue_free()
			_walkers.erase(id)


## The room the colleague is drawn in, the same on every screen: their character's room, else the
## room of their last door code, else a room of the main floor picked from their id.
static func shown_room(player: BackendModels.OfficePlayer) -> StringName:
	for room_id: StringName in [player.map_room, player.colleague.room]:
		if room_id != &"" and OfficeFloors.floor_of_room(room_id) != &"":
			return room_id
	var rooms: Array[MapLayout.Room] = OfficeFloors.layout(OfficeFloors.HQ).rooms
	if rooms.is_empty():
		return &""
	var ids: Array[String] = []
	for room: MapLayout.Room in rooms:
		ids.append(String(room.id))
	ids.sort()
	return StringName(ids[absi(player.colleague.user_id.hash()) % ids.size()])


## A walkable cell somewhere in the room.
func _random_cell(room: MapLayout.Room) -> Vector2i:
	if room == null:
		return WorldMap.INVALID_CELL
	var floor_rect: Rect2i = room.floor_rect()
	var target: Vector2i = (
		floor_rect.position
		+ Vector2i(randi_range(0, floor_rect.size.x - 1), randi_range(0, floor_rect.size.y - 1))
	)
	return _map.find_nearest_walkable(_map.cell_to_world(target), SPAWN_SEARCH_RADIUS)
