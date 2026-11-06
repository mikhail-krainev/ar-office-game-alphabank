class_name ApartmentLayouts
extends RefCounted
## The five apartments of server/content/home.json, from the 20 m² studio to the 240 m² house with a
## fireplace, a backyard and a garage. Map sizes must match `width`/`height` there: the server keeps
## placed items inside them. The free floor and wall space is left for the interior the player buys.

const STUDIO: String = "studio20"
const IDS: Array[String] = ["studio20", "flat40", "flat60", "loft120", "house240"]

const K: Dictionary = {
	"remark": HomeLayout.Kind.REMARK, "wardrobe": HomeLayout.Kind.WARDROBE, "laptop": HomeLayout.Kind.LAPTOP,
	"door": HomeLayout.Kind.DOOR, "garage": HomeLayout.Kind.GARAGE,
}


## The apartment `id`; the studio for an unknown id.
static func create(id: String) -> HomeLayout:
	var layout: HomeLayout = HomeLayout.new()
	match id:
		"flat40":
			_flat40(layout)
		"flat60":
			_flat60(layout)
		"loft120":
			_loft120(layout)
		"house240":
			_house240(layout)
		_:
			id = STUDIO
			_studio20(layout)
	layout.apartment_id = id
	layout.finish_built_in()
	return layout


## `uses`: [remark id, kind key of K, prop id, prop x, prop y, stand x, stand y].
static func _uses(layout: HomeLayout, uses: Array) -> void:
	for entry: Array in uses:
		layout.use(entry[0], K[entry[1]], entry[2], entry[3], entry[4], entry[5], entry[6])


static func _studio20(layout: HomeLayout) -> void:
	var s: Dictionary = OfficeTiles.Style
	layout.size = Vector2i(14, 12)
	layout.spawn_cell = Vector2i(5, 6)
	layout.add_room(&"studio", "HOME_ROOM_STUDIO", Rect2i(1, 1, 8, 10), s.LIVING)
	layout.add_room(&"bathroom", "HOME_ROOM_BATHROOM", Rect2i(10, 1, 3, 6), s.BATH)
	layout.doors = [Rect2i(9, 4, 1, 2)]
	layout.add_props([
		["window", 1, 1], ["calendar_alfa", 3, 1], ["key_hook", 5, 1], ["front_door", 6, 1], ["coat_rack", 8, 1],
		["doormat", 6, 3], ["bed_double", 1, 3], ["wardrobe", 3, 3],
		["fridge", 8, 3], ["stove", 8, 5], ["counter_sink", 8, 6],
		["laptop_desk", 1, 8], ["gaming_chair", 1, 9],
		["towel_rail", 10, 1], ["mirror_bath", 11, 1],
		["toilet", 10, 3], ["bath_sink", 11, 3], ["washing_machine", 12, 3], ["bathtub", 10, 6],
	])
	# Lived-in details: everyday things lying around, so the rooms do not look like a showroom.
	layout.add_props([
		["wall_sconce", 5, 2], ["bath_shelf", 11, 2],
		["slippers", 3, 5], ["sneakers", 5, 4], ["laundry_basket", 1, 7], ["backpack", 3, 9], ["bin_small", 7, 6],
		["bin_small", 12, 5],
	])
	_uses(layout, [
		["bed", "remark", "bed_double", 1, 3, 2, 6], ["wardrobe", "wardrobe", "wardrobe", 3, 3, 3, 4],
		["keys", "garage", "key_hook", 5, 1, 5, 3], ["door", "door", "front_door", 6, 1, 6, 3],
		["calendar", "remark", "calendar_alfa", 3, 1, 4, 4], ["fridge", "remark", "fridge", 8, 3, 8, 4],
		["stove", "remark", "stove", 8, 5, 7, 5], ["laptop", "laptop", "laptop_desk", 1, 8, 2, 9],
		["toilet", "remark", "toilet", 10, 3, 10, 4], ["sink", "remark", "bath_sink", 11, 3, 11, 4],
		["washing_machine", "remark", "washing_machine", 12, 3, 12, 4], ["bathtub", "remark", "bathtub", 10, 6, 11, 5],
	])


static func _flat40(layout: HomeLayout) -> void:
	var s: Dictionary = OfficeTiles.Style
	layout.size = Vector2i(16, 18)
	layout.spawn_cell = Vector2i(8, 13)
	layout.add_room(&"bedroom", "HOME_ROOM_BEDROOM", Rect2i(1, 1, 8, 8), s.BEDROOM)
	layout.add_room(&"bathroom", "HOME_ROOM_BATHROOM", Rect2i(10, 1, 5, 8), s.BATH)
	layout.add_room(&"living", "HOME_ROOM_KITCHEN_LIVING", Rect2i(1, 10, 14, 7), s.LIVING)
	layout.doors = [Rect2i(4, 9, 2, 3), Rect2i(12, 9, 2, 3)]
	layout.add_props([
		["window", 1, 1], ["bed_double", 3, 3], ["nightstand", 2, 3], ["nightstand", 5, 3], ["wardrobe", 7, 3],
		["laptop_desk", 1, 7], ["gaming_chair", 1, 8], ["plant_small", 8, 8],
		["towel_rail", 10, 1], ["mirror_bath", 13, 1], ["window_small", 14, 1],
		["bathtub", 10, 3], ["bath_sink", 13, 3], ["toilet", 14, 3], ["washing_machine", 10, 7], ["bath_mat", 12, 5],
		["window", 1, 10], ["tv", 6, 10], ["key_hook", 9, 10], ["front_door", 10, 10], ["coat_rack", 14, 10],
		["doormat", 10, 12], ["tv_console", 6, 12], ["sofa_back", 6, 15], ["bookshelf", 1, 12], ["plant_big", 1, 16],
		["fridge", 14, 13], ["stove", 14, 14], ["counter_kettle", 14, 15], ["cafe_table", 11, 15],
	])
	# Lived-in details: everyday things lying around, so the rooms do not look like a showroom.
	layout.add_props([
		["photo_collage", 3, 1], ["wall_shelf", 6, 2], ["bath_shelf", 12, 2], ["wall_sconce", 3, 11],
		["slippers", 3, 6], ["laundry_basket", 8, 5], ["dryer_rack", 6, 7], ["bin_small", 14, 5],
		["sneakers", 12, 13], ["rug_round", 6, 14], ["side_table", 9, 15], ["book_stack", 2, 13], ["cat_bed", 1, 15],
		["backpack", 3, 12], ["bin_small", 14, 16],
	])
	_uses(layout, [
		["bed", "remark", "bed_double", 3, 3, 4, 6], ["wardrobe", "wardrobe", "wardrobe", 7, 3, 7, 4],
		["laptop", "laptop", "laptop_desk", 1, 7, 2, 8],
		["bathtub", "remark", "bathtub", 10, 3, 11, 4], ["sink", "remark", "bath_sink", 13, 3, 13, 4],
		["toilet", "remark", "toilet", 14, 3, 14, 4], ["washing_machine", "remark", "washing_machine", 10, 7, 11, 7],
		["keys", "garage", "key_hook", 9, 10, 9, 12], ["door", "door", "front_door", 10, 10, 10, 12],
		["coats", "remark", "coat_rack", 14, 10, 14, 12], ["tv", "remark", "tv_console", 6, 12, 7, 13],
		["sofa", "remark", "sofa_back", 6, 15, 5, 15], ["bookshelf", "remark", "bookshelf", 1, 12, 2, 12],
		["plant", "remark", "plant_big", 1, 16, 2, 16], ["fridge", "remark", "fridge", 14, 13, 13, 13],
		["stove", "remark", "stove", 14, 14, 13, 14], ["kettle", "remark", "counter_kettle", 14, 15, 13, 15],
		["table", "remark", "cafe_table", 11, 15, 11, 16],
	])


static func _flat60(layout: HomeLayout) -> void:
	var s: Dictionary = OfficeTiles.Style
	layout.size = Vector2i(20, 20)
	layout.spawn_cell = Vector2i(6, 14)
	layout.add_room(&"bedroom", "HOME_ROOM_BEDROOM", Rect2i(1, 1, 7, 8), s.BEDROOM)
	layout.add_room(&"bathroom", "HOME_ROOM_BATHROOM", Rect2i(9, 1, 4, 8), s.BATH)
	layout.add_room(&"study", "HOME_ROOM_STUDY", Rect2i(14, 1, 5, 8), s.CARPET)
	layout.add_room(&"living", "HOME_ROOM_LIVING", Rect2i(1, 10, 11, 9), s.LIVING)
	layout.add_room(&"kitchen", "HOME_ROOM_KITCHEN", Rect2i(13, 10, 6, 9), s.HOME_KITCHEN)
	layout.doors = [Rect2i(3, 9, 2, 3), Rect2i(10, 9, 2, 3), Rect2i(15, 9, 2, 3), Rect2i(12, 14, 1, 3)]
	layout.add_props([
		["window", 1, 1], ["bed_double", 2, 3], ["nightstand", 1, 3], ["nightstand", 4, 3], ["wardrobe", 6, 3],
		["dumbbells", 7, 8],
		["towel_rail", 9, 1], ["window_small", 12, 1], ["bathtub", 9, 3], ["toilet", 12, 3], ["bath_sink", 9, 6],
		["washing_machine", 12, 6],
		["window", 14, 1], ["clock", 18, 1], ["laptop_desk", 14, 3], ["gaming_chair", 14, 4], ["bookshelf", 18, 3],
		["guitar", 18, 8], ["plant_small", 14, 8],
		["window", 1, 10], ["calendar_alfa", 5, 10], ["key_hook", 6, 10], ["front_door", 7, 10], ["coat_rack", 9, 10],
		["doormat", 7, 12], ["tv_console", 1, 13], ["pizza_table", 1, 15], ["sofa_back", 1, 17], ["floor_lamp", 4, 17],
		["shoe_rack", 9, 12], ["plant_big", 11, 18],
		["window", 13, 10], ["kitchen_cabinets", 17, 10], ["kitchen_cabinets", 18, 10],
		["fridge", 13, 12], ["stove", 17, 12], ["counter_sink", 18, 12], ["cafe_table", 15, 15], ["trash_bin", 18, 18],
	])
	# Lived-in details: everyday things lying around, so the rooms do not look like a showroom.
	layout.add_props([
		["photo_collage", 3, 1], ["wall_sconce", 5, 2], ["slippers", 2, 6], ["laundry_basket", 7, 5],
		["floor_fan", 1, 7], ["bath_shelf", 10, 2], ["bin_small", 12, 8], ["wall_shelf", 16, 2], ["boxes_stack", 18, 6],
		["book_stack", 17, 5], ["backpack", 16, 3], ["wall_sconce", 5, 11], ["plant_hanging", 6, 11],
		["rug_round", 5, 15], ["side_table", 5, 17], ["cat_bed", 10, 16], ["sneakers", 9, 13], ["vacuum", 11, 17],
		["spice_rack", 17, 11], ["counter_dishes", 18, 13],
	])
	_uses(layout, [
		["bed", "remark", "bed_double", 2, 3, 3, 6], ["wardrobe", "wardrobe", "wardrobe", 6, 3, 6, 4],
		["dumbbells", "remark", "dumbbells", 7, 8, 6, 8],
		["bathtub", "remark", "bathtub", 9, 3, 10, 4], ["toilet", "remark", "toilet", 12, 3, 12, 4],
		["sink", "remark", "bath_sink", 9, 6, 10, 6], ["washing_machine", "remark", "washing_machine", 12, 6, 11, 6],
		["laptop", "laptop", "laptop_desk", 14, 3, 15, 4], ["bookshelf", "remark", "bookshelf", 18, 3, 17, 4],
		["guitar", "remark", "guitar", 18, 8, 17, 8],
		["calendar", "remark", "calendar_alfa", 5, 10, 5, 12], ["keys", "garage", "key_hook", 6, 10, 6, 12],
		["door", "door", "front_door", 7, 10, 7, 12], ["coats", "remark", "coat_rack", 9, 10, 8, 13],
		["tv", "remark", "tv_console", 1, 13, 2, 14], ["sofa", "remark", "sofa_back", 1, 17, 4, 18],
		["plant", "remark", "plant_big", 11, 18, 10, 18],
		["fridge", "remark", "fridge", 13, 12, 13, 13], ["stove", "remark", "stove", 17, 12, 17, 13],
		["table", "remark", "cafe_table", 15, 15, 15, 16], ["trash", "remark", "trash_bin", 18, 18, 17, 18],
	])


static func _loft120(layout: HomeLayout) -> void:
	var s: Dictionary = OfficeTiles.Style
	layout.size = Vector2i(22, 27)
	layout.spawn_cell = Vector2i(10, 15)
	layout.add_room(&"bedroom", "HOME_ROOM_BEDROOM", Rect2i(1, 1, 10, 10), s.BEDROOM)
	layout.add_room(&"bathroom", "HOME_ROOM_SPA", Rect2i(12, 1, 9, 10), s.BATH)
	layout.add_room(&"hall", "HOME_ROOM_HALL", Rect2i(1, 12, 20, 4), s.HALL)
	layout.add_room(&"living", "HOME_ROOM_LIVING", Rect2i(1, 17, 12, 9), s.LIVING)
	layout.add_room(&"kitchen", "HOME_ROOM_KITCHEN", Rect2i(14, 17, 7, 9), s.HOME_KITCHEN)
	layout.doors = [Rect2i(5, 11, 2, 3), Rect2i(15, 11, 2, 3), Rect2i(6, 16, 2, 3), Rect2i(16, 16, 2, 3), Rect2i(13, 21, 1, 3)]
	layout.add_props([
		["window", 2, 1], ["clock", 9, 1], ["bed_double", 2, 3], ["nightstand", 1, 3], ["nightstand", 4, 3],
		["wardrobe", 8, 3], ["rug_bedroom", 4, 7], ["dumbbells", 9, 9], ["plant_small", 1, 10],
		["towel_rail", 12, 1], ["mirror_bath", 14, 1], ["window_small", 18, 1], ["bath_sink", 14, 3], ["toilet", 18, 3],
		["washing_machine", 20, 3], ["bathtub", 12, 9], ["bath_mat", 15, 6], ["plant_big", 20, 10],
		["coat_rack", 2, 12], ["key_hook", 9, 12], ["frame_picture", 10, 12], ["calendar_alfa", 12, 12],
		["front_door", 19, 12], ["hall_mirror", 1, 14], ["shoe_rack", 3, 14], ["doormat", 19, 14], ["plant_big", 11, 14],
		["tv", 2, 17], ["window", 9, 17], ["clock", 12, 17], ["tv_console", 2, 19], ["rug_living", 2, 21],
		["pizza_table", 3, 22], ["sofa_back", 2, 24], ["floor_lamp", 5, 24], ["laptop_desk", 10, 19],
		["gaming_chair", 10, 20], ["bookshelf", 12, 19], ["guitar", 12, 25], ["plant_big", 1, 25],
		["window", 14, 17], ["kitchen_cabinets", 18, 17], ["kitchen_cabinets", 19, 17], ["kitchen_cabinets", 20, 17],
		["fridge", 14, 19], ["microwave", 15, 19], ["stove", 18, 19], ["counter_sink", 19, 19], ["counter_kettle", 20, 19],
		["cafe_table", 16, 22], ["trash_bin", 20, 25], ["plant_small", 14, 25],
	])
	# Lived-in details: everyday things lying around, so the rooms do not look like a showroom.
	layout.add_props([
		["photo_collage", 5, 1], ["wall_sconce", 1, 2], ["slippers", 2, 6], ["book_stack", 5, 3],
		["laundry_basket", 10, 4], ["floor_fan", 10, 7], ["bath_shelf", 16, 2], ["bin_small", 19, 3],
		["dryer_rack", 18, 8], ["umbrella_stand", 18, 14], ["sneakers", 4, 14], ["wall_sconce", 13, 12],
		["wall_sconce", 17, 12], ["wall_shelf", 8, 18], ["plant_hanging", 11, 18], ["side_table", 6, 24],
		["cat_bed", 1, 22], ["backpack", 9, 20], ["boxes_stack", 1, 19], ["spice_rack", 18, 18], ["bin_small", 15, 25],
	])
	_uses(layout, [
		["bed", "remark", "bed_double", 2, 3, 3, 6], ["wardrobe", "wardrobe", "wardrobe", 8, 3, 8, 4],
		["dumbbells", "remark", "dumbbells", 9, 9, 8, 9],
		["sink", "remark", "bath_sink", 14, 3, 14, 4], ["toilet", "remark", "toilet", 18, 3, 18, 4],
		["washing_machine", "remark", "washing_machine", 20, 3, 20, 4], ["bathtub", "remark", "bathtub", 12, 9, 13, 8],
		["coats", "remark", "coat_rack", 2, 12, 2, 14], ["mirror", "remark", "hall_mirror", 1, 14, 1, 15],
		["keys", "garage", "key_hook", 9, 12, 9, 14], ["calendar", "remark", "calendar_alfa", 12, 12, 12, 14],
		["door", "door", "front_door", 19, 12, 19, 14], ["plant", "remark", "plant_big", 11, 14, 11, 15],
		["tv", "remark", "tv_console", 2, 19, 3, 20], ["laptop", "laptop", "laptop_desk", 10, 19, 11, 20],
		["bookshelf", "remark", "bookshelf", 12, 19, 12, 20], ["guitar", "remark", "guitar", 12, 25, 11, 25],
		["sofa", "remark", "sofa_back", 2, 24, 2, 25], ["pizza", "remark", "pizza_table", 3, 22, 5, 22],
		["window", "remark", "window", 9, 17, 9, 19],
		["fridge", "remark", "fridge", 14, 19, 14, 20], ["stove", "remark", "stove", 18, 19, 18, 20],
		["kettle", "remark", "counter_kettle", 20, 19, 20, 20], ["table", "remark", "cafe_table", 16, 22, 16, 23],
		["trash", "remark", "trash_bin", 20, 25, 19, 25],
	])


static func _house240(layout: HomeLayout) -> void:
	var s: Dictionary = OfficeTiles.Style
	layout.size = Vector2i(26, 38)
	layout.spawn_cell = Vector2i(12, 15)
	layout.add_room(&"garage", "HOME_ROOM_GARAGE", Rect2i(1, 1, 8, 10), s.CONCRETE)
	layout.add_room(&"bedroom", "HOME_ROOM_BEDROOM", Rect2i(10, 1, 8, 10), s.BEDROOM)
	layout.add_room(&"bathroom", "HOME_ROOM_BATHROOM", Rect2i(19, 1, 6, 10), s.BATH)
	layout.add_room(&"hall", "HOME_ROOM_HALL", Rect2i(1, 12, 24, 4), s.HALL)
	layout.add_room(&"living", "HOME_ROOM_LIVING", Rect2i(1, 17, 14, 11), s.LIVING)
	layout.add_room(&"kitchen", "HOME_ROOM_KITCHEN", Rect2i(16, 17, 9, 11), s.HOME_KITCHEN)
	layout.add_room(&"yard", "HOME_ROOM_YARD", Rect2i(1, 29, 24, 8), s.GRASS)
	layout.doors = [
		Rect2i(4, 11, 2, 3), Rect2i(13, 11, 2, 3), Rect2i(21, 11, 2, 3), Rect2i(7, 16, 2, 3), Rect2i(19, 16, 2, 3),
		Rect2i(15, 22, 1, 3), Rect2i(5, 28, 4, 3), Rect2i(19, 28, 2, 3),
	]
	# The car stands across the garage, the rear bumper to the left.
	layout.car_rect = Rect2i(2, 6, 5, 2)
	layout.car_origin = Vector2(2 * MapLayout.TILE_SIZE + 4, 8 * MapLayout.TILE_SIZE - 6)
	layout.add_props([
		["garage_door", 2, 1], ["window_small", 7, 1], ["plant_small", 8, 10],
		["window", 11, 1], ["clock", 16, 1], ["bed_double", 13, 3], ["nightstand", 12, 3], ["nightstand", 15, 3],
		["wardrobe", 16, 3], ["rug_bedroom", 12, 7], ["plant_small", 10, 10],
		["towel_rail", 19, 1], ["window_small", 21, 1], ["mirror_bath", 23, 1], ["bathtub", 19, 3], ["bath_sink", 23, 3],
		["toilet", 24, 3], ["washing_machine", 24, 8], ["bath_mat", 22, 6],
		["coat_rack", 2, 12], ["frame_picture", 8, 12], ["calendar_alfa", 11, 12], ["key_hook", 15, 12],
		["front_door", 16, 12], ["frame_picture", 19, 12], ["doormat", 16, 14], ["shoe_rack", 18, 14],
		["hall_mirror", 24, 14], ["plant_big", 1, 14],
		["window", 5, 17], ["window", 11, 17], ["clock", 14, 17], ["fireplace", 2, 19], ["rug_living", 1, 21],
		["coffee_table", 2, 22], ["sofa_back", 2, 24], ["armchair", 5, 22], ["floor_lamp", 1, 24],
		["bookshelf", 14, 19], ["plant_big", 1, 27], ["plant_big", 14, 27],
		["window", 16, 17], ["kitchen_cabinets", 22, 17], ["kitchen_cabinets", 23, 17], ["kitchen_cabinets", 24, 17],
		["fridge", 16, 19], ["microwave", 17, 19], ["stove", 22, 19], ["counter_sink", 23, 19],
		["counter_kettle", 24, 19], ["cafe_table", 19, 23], ["trash_bin", 24, 27], ["plant_small", 16, 27],
		["tree", 1, 32], ["tree", 22, 33], ["pool", 9, 32], ["lounger", 15, 32], ["lounger", 17, 32],
		["bbq_grill", 20, 35],
	])
	# Lived-in details: everyday things lying around, so the rooms do not look like a showroom.
	layout.add_props([
		["wall_shelf", 6, 1], ["boxes_stack", 8, 3], ["bike", 1, 10], ["recycle_bins", 6, 9],
		["photo_collage", 13, 1], ["slippers", 12, 6], ["laundry_basket", 17, 6], ["floor_fan", 10, 3],
		["ironing_board", 16, 9], ["bath_shelf", 20, 2], ["dryer_rack", 19, 9], ["bin_small", 22, 3],
		["umbrella_stand", 19, 14], ["sneakers", 17, 15], ["wall_sconce", 6, 12], ["wall_sconce", 23, 12],
		["photo_collage", 9, 18], ["plant_hanging", 13, 18], ["side_table", 5, 24], ["cat_bed", 4, 20],
		["book_stack", 13, 19], ["spice_rack", 22, 18], ["counter_dishes", 21, 19],
	])
	_uses(layout, [
		["garage_car", "remark", "garage_door", 2, 1, 4, 9],
		["bed", "remark", "bed_double", 13, 3, 13, 6], ["wardrobe", "wardrobe", "wardrobe", 16, 3, 16, 4],
		["bathtub", "remark", "bathtub", 19, 3, 20, 4], ["sink", "remark", "bath_sink", 23, 3, 23, 4],
		["toilet", "remark", "toilet", 24, 3, 24, 4], ["washing_machine", "remark", "washing_machine", 24, 8, 23, 8],
		["coats", "remark", "coat_rack", 2, 12, 2, 14], ["calendar", "remark", "calendar_alfa", 11, 12, 11, 14],
		["keys", "garage", "key_hook", 15, 12, 15, 14], ["door", "door", "front_door", 16, 12, 16, 14],
		["mirror", "remark", "hall_mirror", 24, 14, 24, 15],
		["fireplace", "remark", "fireplace", 2, 19, 3, 20], ["sofa", "remark", "sofa_back", 2, 24, 2, 25],
		["bookshelf", "remark", "bookshelf", 14, 19, 13, 20], ["plant", "remark", "plant_big", 14, 27, 13, 27],
		["fridge", "remark", "fridge", 16, 19, 16, 20], ["stove", "remark", "stove", 22, 19, 22, 20],
		["kettle", "remark", "counter_kettle", 24, 19, 24, 20], ["table", "remark", "cafe_table", 19, 23, 19, 24],
		["trash", "remark", "trash_bin", 24, 27, 23, 27],
		["yard", "remark", "pool", 9, 32, 11, 35], ["grill", "remark", "bbq_grill", 20, 35, 20, 36],
		["lounger", "remark", "lounger", 15, 32, 15, 34], ["tree", "remark", "tree", 1, 32, 1, 33],
	])
