extends GdUnitTestSuite
## Every player must see a colleague in the same room of the office map.


func test_character_room_wins_over_door_code_room() -> void:
	var rooms: Array[MapLayout.Room] = OfficeFloors.layout(OfficeFloors.HQ).rooms
	assert_int(rooms.size()).is_greater(1)
	var player: BackendModels.OfficePlayer = _player("u1", rooms[0].id, rooms[1].id)
	assert_str(String(OfficeColleagues.shown_room(player))).is_equal(String(rooms[0].id))
	player.map_room = &""
	assert_str(String(OfficeColleagues.shown_room(player))).is_equal(String(rooms[1].id))


func test_unknown_room_is_the_same_on_every_screen() -> void:
	var first: StringName = OfficeColleagues.shown_room(_player("7f3c-colleague", &"", &""))
	var second: StringName = OfficeColleagues.shown_room(_player("7f3c-colleague", &"", &""))
	assert_str(String(first)).is_not_empty()
	assert_str(String(first)).is_equal(String(second))
	assert_str(String(OfficeFloors.floor_of_room(first))).is_equal(String(OfficeFloors.HQ))


func test_unknown_room_ids_fall_back() -> void:
	var player: BackendModels.OfficePlayer = _player("u2", &"no_such_room", &"")
	assert_str(String(OfficeColleagues.shown_room(player))).is_not_equal("no_such_room")


func _player(user_id: String, map_room: StringName, door_room: StringName) -> BackendModels.OfficePlayer:
	var player: BackendModels.OfficePlayer = BackendModels.OfficePlayer.new()
	player.colleague = BackendModels.Colleague.new()
	player.colleague.user_id = user_id
	player.colleague.room = door_room
	player.map_room = map_room
	return player
