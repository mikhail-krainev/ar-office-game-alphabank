class_name OfficeLayout
extends MapLayout
## The Alfa-Bank office main floor: rooms, doors, wall faces and props. The lift in the reception
## goes up to the product analytics floor (AnalyticsLayout).


func _init() -> void:
	size = Vector2i(64, 28)
	spawn_cell = Vector2i(24, 25)
	var s: Dictionary = OfficeTiles.Style
	add_room(&"cabinet", "ROOM_CABINET", Rect2i(1, 1, 12, 9), s.WOOD)
	add_room(&"open_space", "ROOM_OPEN_SPACE", Rect2i(14, 1, 20, 9), s.OFFICE)
	add_room(&"meeting", "ROOM_MEETING", Rect2i(35, 1, 12, 9), s.WOOD)
	add_room(&"design", "ROOM_DESIGN", Rect2i(48, 1, 15, 26), s.PARTY)
	add_room(&"corridor", "ROOM_CORRIDOR", Rect2i(1, 11, 46, 4), s.CORRIDOR, 1)
	add_room(&"kitchen", "ROOM_KITCHEN", Rect2i(1, 16, 14, 11), s.KITCHEN)
	add_room(&"reception", "ROOM_RECEPTION", Rect2i(16, 16, 16, 11), s.MARBLE)
	add_room(&"lounge", "ROOM_LOUNGE", Rect2i(33, 16, 14, 11), s.LOUNGE)
	doors = [
		Rect2i(6, 10, 2, 2), Rect2i(23, 10, 2, 2), Rect2i(40, 10, 2, 2), Rect2i(47, 12, 1, 3),
		Rect2i(7, 15, 2, 3), Rect2i(22, 15, 4, 3), Rect2i(39, 15, 2, 3),
	]
	entrances = [Rect2i(23, 27, 2, 1)]
	_add_props()
	_add_details()
	finalize()


func _add_props() -> void:
	# Director's office.
	add_prop("window", 2, 1)
	add_prop("frame_picture", 5, 1)
	add_prop("clock", 7, 1)
	add_prop("window", 9, 1)
	add_prop("rug_office", 4, 4)
	add_prop("bookshelf", 1, 3)
	add_prop("bookshelf", 2, 3)
	add_prop("plant_big", 12, 3)
	add_prop("office_chair", 6, 4)
	add_prop("director_desk", 5, 5)
	add_prop("filing_cabinet", 12, 6)
	add_prop("armchair_leather", 1, 7)
	add_prop("chair", 5, 7)
	add_prop("chair", 7, 7)
	add_prop("sofa_leather", 9, 8)
	add_prop("plant_small", 1, 9)
	# Open space.
	for window_x: int in [14, 18, 27, 31]:
		add_prop("window", window_x, 1)
	add_prop("whiteboard", 22, 1)
	add_prop("poster_alfa", 25, 1)
	add_prop("plant_big", 14, 3)
	add_prop("printer", 33, 3)
	add_prop("water_cooler", 33, 5)
	add_prop("plant_big", 33, 9)
	for row_y: int in [4, 7]:
		for desk_x: int in [15, 17, 21, 23, 27, 29]:
			add_prop("desk", desk_x, row_y)
			add_prop("office_chair", desk_x, row_y + 1)
	# Meeting room.
	add_prop("window", 35, 1)
	add_prop("tv", 39, 1)
	add_prop("whiteboard", 43, 1)
	add_prop("clock", 46, 1)
	add_prop("plant_big", 35, 3)
	add_prop("plant_big", 46, 3)
	for chair_x: int in range(38, 44):
		add_prop("chair", chair_x, 4)
	add_prop("meeting_table", 38, 5)
	for chair_x: int in range(38, 44):
		add_prop("chair", chair_x, 7)
	add_prop("plant_small", 46, 9)
	# Corridor.
	add_prop("logo_small", 3, 11)
	add_prop("frame_picture", 10, 11)
	add_prop("window_small", 15, 11)
	add_prop("fire_extinguisher", 19, 11)
	add_prop("logo_small", 30, 11)
	add_prop("frame_picture", 35, 11)
	add_prop("window_small", 44, 11)
	add_prop("plant_big", 1, 12)
	add_prop("plant_small", 18, 12)
	add_prop("plant_small", 33, 12)
	add_prop("plant_big", 46, 12)
	# Kitchen.
	for cabinet_x: int in range(1, 7):
		add_prop("kitchen_cabinets", cabinet_x, 16)
	add_prop("menu_board", 10, 16)
	add_prop("window", 12, 16)
	add_prop("fridge", 1, 18)
	add_prop("counter", 2, 18)
	add_prop("counter_sink", 3, 18)
	add_prop("counter", 4, 18)
	add_prop("coffee_machine", 5, 18)
	add_prop("microwave", 6, 18)
	add_prop("water_cooler", 13, 18)
	add_prop("vending", 14, 18)
	for table: Vector2i in [Vector2i(3, 21), Vector2i(9, 21), Vector2i(3, 24), Vector2i(9, 24)]:
		add_prop("chair", table.x, table.y - 1)
		add_prop("chair", table.x + 1, table.y - 1)
		add_prop("cafe_table", table.x, table.y)
	add_prop("plant_small", 1, 26)
	add_prop("plant_big", 14, 26)
	# Reception.
	add_prop("logo_sign", 17, 16)
	add_elevator(26, 16)
	add_prop("world_clocks", 29, 16)
	add_prop("logo_floor", 23, 22)
	add_prop("plant_big", 16, 18)
	add_prop("plant_big", 31, 18)
	add_prop("reception_desk", 21, 20)
	add_prop("sofa_red", 17, 23)
	add_prop("coffee_table", 17, 25)
	add_prop("sofa_red", 28, 23)
	add_prop("coffee_table", 29, 25)
	add_prop("plant_big", 16, 26)
	add_prop("plant_big", 31, 26)
	# Lounge.
	add_prop("window", 34, 16)
	add_prop("frame_picture", 37, 16)
	add_prop("tv", 42, 16)
	add_prop("clock", 46, 16)
	add_prop("rug_lounge", 40, 20)
	add_prop("floor_lamp", 45, 18)
	add_prop("bookshelf", 46, 18)
	add_prop("sofa_red", 41, 19)
	add_prop("ping_pong", 34, 21)
	add_prop("coffee_table", 41, 21)
	add_prop("armchair", 44, 21)
	add_prop("bean_bag", 38, 24)
	add_prop("bean_bag", 40, 25)
	add_prop("plant_big", 33, 26)
	add_prop("plant_big", 46, 26)
	# Design department.
	add_prop("shelf_bottles", 50, 1)
	add_prop("neon_sign", 57, 1)
	add_prop("logo_small", 62, 1)
	add_prop("plant_big", 48, 3)
	add_prop("plant_big", 62, 3)
	add_prop("bar_counter", 50, 4)
	for stool_x: int in range(50, 56):
		add_prop("bar_stool", stool_x, 5)
	add_prop("speaker", 57, 5)
	add_prop("dj_booth", 58, 5)
	add_prop("speaker", 61, 5)
	add_prop("rug_party", 50, 8)
	add_prop("sofa_green", 58, 9)
	add_prop("party_table", 59, 11)
	add_prop("party_table", 52, 14)
	add_prop("party_table", 56, 15)
	add_prop("speaker", 62, 14)
	for row_y: int in [19, 23]:
		for desk_x: int in [49, 53, 57]:
			add_prop("design_desk", desk_x, row_y)
			add_prop("office_chair", desk_x, row_y + 1)
	add_prop("plant_big", 48, 26)
	add_prop("plant_big", 62, 26)


## Everyday office things around the furniture: bins, binders, the notice board, coats and bikes.
func _add_details() -> void:
	add_prop("ac_unit", 11, 1)
	add_prop("coat_stand", 12, 4)
	add_prop("bin_office", 8, 6)
	add_prop("notice_board", 16, 1)
	add_prop("ac_unit", 20, 1)
	add_prop("binder_shelf", 29, 2)
	add_prop("bin_office", 19, 4)
	add_prop("bin_office", 25, 7)
	add_prop("paper_box", 31, 3)
	add_prop("water_bottles", 33, 6)
	add_prop("recycle_bins", 31, 9)
	add_prop("coat_stand", 14, 9)
	add_prop("ac_unit", 37, 1)
	add_prop("flipchart", 45, 5)
	add_prop("bin_office", 36, 8)
	add_prop("first_aid", 20, 11)
	add_prop("exit_sign", 26, 11)
	add_prop("exit_sign", 42, 11)
	add_prop("first_aid", 9, 17)
	add_prop("recycle_bins", 10, 18)
	add_prop("coat_stand", 17, 18)
	add_prop("umbrella_stand", 30, 18)
	add_prop("plant_hanging", 38, 16)
	add_prop("book_stack", 45, 19)
	add_prop("bike", 60, 17)
	add_prop("coat_stand", 62, 18)
	add_prop("bin_office", 52, 20)
