class_name AnalyticsLayout
extends MapLayout
## Product analytics department, one floor above the main office: open space with standing desks,
## a data lab with a dashboard wall, a coffee point and the "Hypothesis" workshop. Tasks on this
## floor are about meeting people from other departments.


func _init() -> void:
	size = Vector2i(44, 26)
	var s: Dictionary = OfficeTiles.Style
	add_room(&"pa_open_space", "ROOM_PA_OPEN_SPACE", Rect2i(1, 1, 26, 10), s.CARPET)
	add_room(&"pa_data_lab", "ROOM_PA_DATA_LAB", Rect2i(28, 1, 15, 10), s.CONCRETE)
	add_room(&"pa_corridor", "ROOM_PA_CORRIDOR", Rect2i(1, 12, 42, 3), s.CORRIDOR, 1)
	add_room(&"pa_hall", "ROOM_PA_HALL", Rect2i(1, 16, 12, 9), s.CONCRETE)
	add_room(&"pa_coffee", "ROOM_PA_COFFEE", Rect2i(14, 16, 13, 9), s.LOUNGE)
	add_room(&"pa_workshop", "ROOM_PA_WORKSHOP", Rect2i(28, 16, 15, 9), s.CARPET)
	doors = [
		Rect2i(12, 11, 2, 2), Rect2i(34, 11, 2, 2),
		Rect2i(10, 15, 2, 3), Rect2i(19, 15, 2, 3), Rect2i(34, 15, 2, 3),
	]
	add_elevator(4, 16)
	spawn_cell = elevator_cell
	_add_props()
	_add_details()
	finalize()


func _add_props() -> void:
	# Open space: standing desks on the left, regular desks on the right, phone booths for calls.
	add_prop("window", 2, 1)
	add_prop("kanban_board", 6, 1)
	add_prop("neon_chart", 10, 1)
	add_prop("whiteboard", 13, 1)
	add_prop("window", 17, 1)
	add_prop("poster_alfa", 20, 1)
	add_prop("window", 23, 1)
	add_prop("plant_big", 1, 3)
	for desk: Vector2i in [Vector2i(2, 5), Vector2i(5, 5), Vector2i(2, 8), Vector2i(5, 8)]:
		add_prop("standing_desk", desk.x, desk.y)
	add_prop("cube_pouf", 9, 5)
	add_prop("cube_pouf", 12, 5)
	add_prop("coffee_table", 10, 6)
	add_prop("cube_pouf", 9, 7)
	add_prop("cube_pouf", 12, 7)
	for row_y: int in [5, 8]:
		for desk_x: int in [15, 18, 21]:
			add_prop("desk", desk_x, row_y)
			add_prop("office_chair", desk_x, row_y + 1)
	add_prop("phone_booth", 25, 4)
	add_prop("phone_booth", 25, 6)
	add_prop("plant_small", 26, 9)
	# Data lab.
	add_prop("window", 28, 1)
	add_prop("data_wall", 31, 1)
	add_prop("tv", 36, 1)
	add_prop("clock", 40, 1)
	add_prop("plant_big", 42, 3)
	for chair_x: int in range(31, 37):
		add_prop("chair", chair_x, 4)
	add_prop("meeting_table", 31, 5)
	for chair_x: int in range(31, 37):
		add_prop("chair", chair_x, 7)
	add_prop("bean_bag", 40, 8)
	add_prop("armchair", 41, 6)
	add_prop("plant_small", 28, 9)
	# Corridor.
	add_prop("logo_small", 3, 12)
	add_prop("frame_picture", 8, 12)
	add_prop("window_small", 16, 12)
	add_prop("fire_extinguisher", 22, 12)
	add_prop("frame_picture", 29, 12)
	add_prop("window_small", 39, 12)
	add_prop("plant_small", 1, 13)
	add_prop("plant_small", 42, 13)
	# Lift hall.
	add_prop("logo_small", 7, 16)
	add_prop("frame_picture", 9, 16)
	add_prop("plant_big", 1, 18)
	add_prop("plant_big", 12, 18)
	add_prop("sofa_red", 6, 21)
	add_prop("coffee_table", 7, 23)
	add_prop("plant_big", 1, 24)
	add_prop("plant_big", 12, 24)
	# Coffee point.
	for cabinet_x: int in range(14, 18):
		add_prop("kitchen_cabinets", cabinet_x, 16)
	add_prop("menu_board", 22, 16)
	add_prop("window", 24, 16)
	add_prop("fridge", 14, 18)
	add_prop("coffee_machine", 15, 18)
	add_prop("counter", 16, 18)
	add_prop("counter_kettle", 17, 18)
	add_prop("vending", 26, 18)
	for table: Vector2i in [Vector2i(15, 21), Vector2i(21, 21), Vector2i(15, 24)]:
		add_prop("chair", table.x, table.y - 1)
		add_prop("chair", table.x + 1, table.y - 1)
		add_prop("cafe_table", table.x, table.y)
	add_prop("plant_big", 26, 24)
	# Hypothesis workshop.
	add_prop("whiteboard", 29, 16)
	add_prop("funnel_board", 32, 16)
	add_prop("tv", 37, 16)
	add_prop("clock", 41, 16)
	add_prop("rug_lounge", 31, 20)
	add_prop("cube_pouf", 31, 21)
	add_prop("coffee_table", 32, 21)
	add_prop("cube_pouf", 34, 21)
	add_prop("cube_pouf", 32, 22)
	add_prop("cube_pouf", 33, 22)
	add_prop("standing_desk", 29, 18)
	add_prop("plant_big", 42, 18)
	add_prop("bean_bag", 40, 22)
	add_prop("bean_bag", 41, 24)
	add_prop("plant_big", 28, 24)


## Everyday office things around the furniture: servers, binders, bins, a bike in the lift hall.
func _add_details() -> void:
	add_prop("ac_unit", 8, 1)
	add_prop("ac_unit", 21, 1)
	add_prop("binder_shelf", 15, 2)
	add_prop("bin_office", 4, 6)
	add_prop("paper_box", 24, 9)
	add_prop("coat_stand", 1, 10)
	add_prop("server_rack", 42, 5)
	add_prop("server_rack", 42, 6)
	add_prop("notice_board", 41, 1)
	add_prop("exit_sign", 24, 12)
	add_prop("first_aid", 25, 12)
	add_prop("bike", 2, 24)
	add_prop("umbrella_stand", 11, 19)
	add_prop("recycle_bins", 24, 18)
	add_prop("flipchart", 41, 20)
	add_prop("bin_office", 30, 22)
