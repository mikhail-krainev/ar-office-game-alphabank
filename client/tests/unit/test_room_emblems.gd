extends GdUnitTestSuite
## Room emblems: every office room has its own emblem and picture.


func test_every_office_room_has_one_emblem() -> void:
	var rooms: Array[StringName] = []
	for floor_id: StringName in OfficeFloors.ORDER:
		for room: MapLayout.Room in OfficeFloors.layout(floor_id).rooms:
			rooms.append(room.id)
	assert_int(RoomEmblems.ids().size()).is_equal(rooms.size())
	for room_id: StringName in rooms:
		var emblem_id: String = RoomEmblems.emblem_of(room_id)
		assert_str(emblem_id).override_failure_message("no emblem for %s" % room_id).is_not_empty()
		assert_str(String(RoomEmblems.room_of(emblem_id))).is_equal(String(room_id))


func test_every_emblem_has_a_reference_picture() -> void:
	for emblem_id: String in RoomEmblems.ids():
		var picture: Image = RoomEmblems.reference_image(emblem_id)
		assert_object(picture).override_failure_message(emblem_id).is_not_null()
		assert_int(maxi(picture.get_width(), picture.get_height())).is_equal(RoomEmblems.REFERENCE_SIDE)


func test_unknown_emblem_names_no_room() -> void:
	assert_str(String(RoomEmblems.room_of("printer"))).is_empty()


func test_catalog_skips_entries_without_a_safe_id() -> void:
	var text: String = '{"emblems": [{"id": "cat_box", "room": "lounge"}, {"id": "../x", "room": "kitchen"}]}'
	assert_error(func() -> void: RoomEmblems.parse_catalog(text)).is_push_error(
		'Room emblem catalog: bad entry { "id": "../x", "room": "kitchen" }'
	)
	var rooms: Dictionary[String, StringName] = RoomEmblems.parse_catalog(text)
	assert_int(rooms.size()).is_equal(1)
	assert_str(String(rooms["cat_box"])).is_equal("lounge")
