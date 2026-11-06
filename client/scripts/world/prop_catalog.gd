class_name PropCatalog
extends RefCounted
## Prop definitions shared by the art generator and the map.
## FURNITURE: y-sorted sprite, bottom-centre anchored to its footprint; blocks cells when `blocking`.
## WALL: drawn on wall faces, top-left anchored to its cell, centred over its footprint width.
## DECAL: floor sprite under characters, centred on its footprint.

enum Kind { FURNITURE, WALL, DECAL }

const TEXTURE_PATH: String = "res://assets/props/props.png"
const MANIFEST_PATH: String = "res://assets/props/props.json"

## id: [kind, sprite size px, footprint cells, blocking]
const DEFS: Dictionary[String, Array] = {
	# Office.
	"desk": [Kind.FURNITURE, Vector2i(64, 52), Vector2i(2, 1), true],
	"office_chair": [Kind.FURNITURE, Vector2i(24, 34), Vector2i(1, 1), false],
	"chair": [Kind.FURNITURE, Vector2i(20, 30), Vector2i(1, 1), false],
	"bookshelf": [Kind.FURNITURE, Vector2i(32, 64), Vector2i(1, 1), true],
	"filing_cabinet": [Kind.FURNITURE, Vector2i(28, 40), Vector2i(1, 1), true],
	"printer": [Kind.FURNITURE, Vector2i(32, 40), Vector2i(1, 1), true],
	"water_cooler": [Kind.FURNITURE, Vector2i(20, 48), Vector2i(1, 1), true],
	"plant_big": [Kind.FURNITURE, Vector2i(28, 52), Vector2i(1, 1), true],
	"plant_small": [Kind.FURNITURE, Vector2i(22, 34), Vector2i(1, 1), true],
	"director_desk": [Kind.FURNITURE, Vector2i(96, 60), Vector2i(3, 1), true],
	"armchair_leather": [Kind.FURNITURE, Vector2i(30, 40), Vector2i(1, 1), true],
	"sofa_leather": [Kind.FURNITURE, Vector2i(96, 46), Vector2i(3, 1), true],
	"meeting_table": [Kind.FURNITURE, Vector2i(192, 64), Vector2i(6, 2), true],
	# Kitchen, reception, lounge.
	"fridge": [Kind.FURNITURE, Vector2i(32, 70), Vector2i(1, 1), true],
	"counter": [Kind.FURNITURE, Vector2i(32, 46), Vector2i(1, 1), true],
	"counter_sink": [Kind.FURNITURE, Vector2i(32, 46), Vector2i(1, 1), true],
	"coffee_machine": [Kind.FURNITURE, Vector2i(32, 58), Vector2i(1, 1), true],
	"microwave": [Kind.FURNITURE, Vector2i(32, 56), Vector2i(1, 1), true],
	"vending": [Kind.FURNITURE, Vector2i(32, 72), Vector2i(1, 1), true],
	"cafe_table": [Kind.FURNITURE, Vector2i(56, 42), Vector2i(2, 1), true],
	"reception_desk": [Kind.FURNITURE, Vector2i(192, 58), Vector2i(6, 1), true],
	"sofa_red": [Kind.FURNITURE, Vector2i(96, 46), Vector2i(3, 1), true],
	"coffee_table": [Kind.FURNITURE, Vector2i(64, 34), Vector2i(2, 1), true],
	"ping_pong": [Kind.FURNITURE, Vector2i(96, 60), Vector2i(3, 2), true],
	"armchair": [Kind.FURNITURE, Vector2i(32, 40), Vector2i(1, 1), true],
	"bean_bag": [Kind.FURNITURE, Vector2i(30, 26), Vector2i(1, 1), true],
	"floor_lamp": [Kind.FURNITURE, Vector2i(20, 60), Vector2i(1, 1), true],
	# Design department.
	"bar_counter": [Kind.FURNITURE, Vector2i(192, 50), Vector2i(6, 1), true],
	"bar_stool": [Kind.FURNITURE, Vector2i(16, 26), Vector2i(1, 1), false],
	"dj_booth": [Kind.FURNITURE, Vector2i(96, 58), Vector2i(3, 1), true],
	"speaker": [Kind.FURNITURE, Vector2i(28, 60), Vector2i(1, 1), true],
	"sofa_green": [Kind.FURNITURE, Vector2i(96, 46), Vector2i(3, 1), true],
	"party_table": [Kind.FURNITURE, Vector2i(28, 40), Vector2i(1, 1), true],
	"design_desk": [Kind.FURNITURE, Vector2i(64, 58), Vector2i(2, 1), true],
	# Product analytics floor.
	"standing_desk": [Kind.FURNITURE, Vector2i(60, 56), Vector2i(2, 1), true],
	"phone_booth": [Kind.FURNITURE, Vector2i(32, 72), Vector2i(1, 1), true],
	"cube_pouf": [Kind.FURNITURE, Vector2i(22, 20), Vector2i(1, 1), false],
	"data_wall": [Kind.WALL, Vector2i(124, 58), Vector2i(4, 2), false],
	"kanban_board": [Kind.WALL, Vector2i(60, 44), Vector2i(2, 2), false],
	"funnel_board": [Kind.WALL, Vector2i(58, 44), Vector2i(2, 2), false],
	"neon_chart": [Kind.WALL, Vector2i(30, 40), Vector2i(1, 2), false],
	"elevator": [Kind.WALL, Vector2i(60, 62), Vector2i(2, 2), false],
	# Apartment.
	"bed_double": [Kind.FURNITURE, Vector2i(64, 84), Vector2i(2, 3), true],
	"nightstand": [Kind.FURNITURE, Vector2i(24, 40), Vector2i(1, 1), true],
	"wardrobe": [Kind.FURNITURE, Vector2i(60, 76), Vector2i(2, 1), true],
	"dumbbells": [Kind.FURNITURE, Vector2i(28, 16), Vector2i(1, 1), false],
	"bathtub": [Kind.FURNITURE, Vector2i(96, 44), Vector2i(3, 1), true],
	"toilet": [Kind.FURNITURE, Vector2i(22, 36), Vector2i(1, 1), true],
	"bath_sink": [Kind.FURNITURE, Vector2i(32, 46), Vector2i(1, 1), true],
	"washing_machine": [Kind.FURNITURE, Vector2i(30, 40), Vector2i(1, 1), true],
	"shoe_rack": [Kind.FURNITURE, Vector2i(32, 28), Vector2i(1, 1), true],
	"hall_mirror": [Kind.FURNITURE, Vector2i(22, 58), Vector2i(1, 1), true],
	"tv_console": [Kind.FURNITURE, Vector2i(96, 32), Vector2i(3, 1), true],
	"sofa_back": [Kind.FURNITURE, Vector2i(96, 42), Vector2i(3, 1), true],
	"pizza_table": [Kind.FURNITURE, Vector2i(64, 36), Vector2i(2, 1), true],
	"laptop_desk": [Kind.FURNITURE, Vector2i(64, 58), Vector2i(2, 1), true],
	"gaming_chair": [Kind.FURNITURE, Vector2i(26, 40), Vector2i(1, 1), false],
	"guitar": [Kind.FURNITURE, Vector2i(20, 46), Vector2i(1, 1), true],
	"pizza_boxes": [Kind.FURNITURE, Vector2i(32, 40), Vector2i(1, 1), true],
	"stove": [Kind.FURNITURE, Vector2i(32, 48), Vector2i(1, 1), true],
	"counter_kettle": [Kind.FURNITURE, Vector2i(32, 52), Vector2i(1, 1), true],
	"trash_bin": [Kind.FURNITURE, Vector2i(20, 30), Vector2i(1, 1), true],
	"poster_band": [Kind.WALL, Vector2i(26, 38), Vector2i(1, 2), false],
	"mirror_bath": [Kind.WALL, Vector2i(24, 28), Vector2i(1, 1), false],
	"towel_rail": [Kind.WALL, Vector2i(26, 28), Vector2i(1, 1), false],
	"coat_rack": [Kind.WALL, Vector2i(32, 44), Vector2i(1, 2), false],
	"front_door": [Kind.WALL, Vector2i(44, 62), Vector2i(2, 2), false],
	"key_hook": [Kind.WALL, Vector2i(22, 20), Vector2i(1, 1), false],
	"calendar_alfa": [Kind.WALL, Vector2i(22, 28), Vector2i(1, 1), false],
	"rug_bedroom": [Kind.DECAL, Vector2i(96, 64), Vector2i(3, 2), false],
	"bath_mat": [Kind.DECAL, Vector2i(52, 26), Vector2i(2, 1), false],
	"doormat": [Kind.DECAL, Vector2i(48, 24), Vector2i(2, 1), false],
	"rug_living": [Kind.DECAL, Vector2i(128, 96), Vector2i(4, 3), false],
	# Home interior the player buys, and the house: fireplace, garage, backyard.
	"fireplace": [Kind.FURNITURE, Vector2i(96, 72), Vector2i(3, 1), true],
	"garage_door": [Kind.WALL, Vector2i(124, 60), Vector2i(4, 2), false],
	"tree": [Kind.FURNITURE, Vector2i(64, 100), Vector2i(2, 1), true],
	"lounger": [Kind.FURNITURE, Vector2i(28, 58), Vector2i(1, 2), true],
	"bbq_grill": [Kind.FURNITURE, Vector2i(30, 44), Vector2i(1, 1), true],
	"pool": [Kind.FURNITURE, Vector2i(160, 96), Vector2i(5, 3), true],
	"aquarium": [Kind.FURNITURE, Vector2i(60, 56), Vector2i(2, 1), true],
	"record_player": [Kind.FURNITURE, Vector2i(30, 40), Vector2i(1, 1), true],
	"arcade_cabinet": [Kind.FURNITURE, Vector2i(32, 74), Vector2i(1, 1), true],
	"egg_chair": [Kind.FURNITURE, Vector2i(32, 52), Vector2i(1, 1), true],
	"cactus": [Kind.FURNITURE, Vector2i(20, 38), Vector2i(1, 1), true],
	"poster_synthwave": [Kind.WALL, Vector2i(26, 38), Vector2i(1, 2), false],
	"poster_palms": [Kind.WALL, Vector2i(26, 38), Vector2i(1, 2), false],
	"poster_tiger": [Kind.WALL, Vector2i(26, 38), Vector2i(1, 2), false],
	"neon_heart": [Kind.WALL, Vector2i(26, 24), Vector2i(1, 1), false],
	"art_abstract": [Kind.WALL, Vector2i(56, 44), Vector2i(2, 2), false],
	# Wall decor.
	"window": [Kind.WALL, Vector2i(56, 52), Vector2i(2, 2), false],
	"window_small": [Kind.WALL, Vector2i(26, 24), Vector2i(1, 1), false],
	"poster_alfa": [Kind.WALL, Vector2i(26, 34), Vector2i(1, 2), false],
	"clock": [Kind.WALL, Vector2i(16, 16), Vector2i(1, 1), false],
	"whiteboard": [Kind.WALL, Vector2i(60, 40), Vector2i(2, 2), false],
	"tv": [Kind.WALL, Vector2i(80, 46), Vector2i(3, 2), false],
	"frame_picture": [Kind.WALL, Vector2i(24, 20), Vector2i(1, 1), false],
	"fire_extinguisher": [Kind.WALL, Vector2i(12, 24), Vector2i(1, 1), false],
	"logo_sign": [Kind.WALL, Vector2i(120, 56), Vector2i(4, 2), false],
	"logo_small": [Kind.WALL, Vector2i(24, 26), Vector2i(1, 1), false],
	"kitchen_cabinets": [Kind.WALL, Vector2i(32, 28), Vector2i(1, 1), false],
	"menu_board": [Kind.WALL, Vector2i(48, 34), Vector2i(2, 2), false],
	"world_clocks": [Kind.WALL, Vector2i(64, 22), Vector2i(2, 1), false],
	"shelf_bottles": [Kind.WALL, Vector2i(192, 44), Vector2i(6, 2), false],
	"neon_sign": [Kind.WALL, Vector2i(112, 44), Vector2i(4, 2), false],
	# Lived-in apartment details, built in (LivedInPropPainter).
	"wall_shelf": [Kind.WALL, Vector2i(30, 18), Vector2i(1, 1), false],
	"spice_rack": [Kind.WALL, Vector2i(32, 16), Vector2i(1, 1), false],
	"bath_shelf": [Kind.WALL, Vector2i(26, 22), Vector2i(1, 1), false],
	"wall_sconce": [Kind.WALL, Vector2i(12, 18), Vector2i(1, 1), false],
	"photo_collage": [Kind.WALL, Vector2i(54, 30), Vector2i(2, 1), false],
	"plant_hanging": [Kind.WALL, Vector2i(18, 30), Vector2i(1, 1), false],
	"laundry_basket": [Kind.FURNITURE, Vector2i(24, 26), Vector2i(1, 1), true],
	"side_table": [Kind.FURNITURE, Vector2i(22, 34), Vector2i(1, 1), true],
	"book_stack": [Kind.FURNITURE, Vector2i(16, 16), Vector2i(1, 1), false],
	"slippers": [Kind.DECAL, Vector2i(20, 10), Vector2i(1, 1), false],
	"sneakers": [Kind.DECAL, Vector2i(26, 12), Vector2i(1, 1), false],
	"umbrella_stand": [Kind.FURNITURE, Vector2i(14, 36), Vector2i(1, 1), true],
	"backpack": [Kind.FURNITURE, Vector2i(18, 22), Vector2i(1, 1), false],
	"counter_dishes": [Kind.FURNITURE, Vector2i(32, 52), Vector2i(1, 1), true],
	"vacuum": [Kind.FURNITURE, Vector2i(18, 32), Vector2i(1, 1), true],
	"ironing_board": [Kind.FURNITURE, Vector2i(52, 34), Vector2i(2, 1), true],
	"boxes_stack": [Kind.FURNITURE, Vector2i(28, 34), Vector2i(1, 1), true],
	"floor_fan": [Kind.FURNITURE, Vector2i(18, 40), Vector2i(1, 1), true],
	"rug_runner": [Kind.DECAL, Vector2i(28, 60), Vector2i(1, 2), false],
	"rug_round": [Kind.DECAL, Vector2i(60, 30), Vector2i(2, 1), false],
	"bin_small": [Kind.FURNITURE, Vector2i(12, 16), Vector2i(1, 1), false],
	"cat_bed": [Kind.FURNITURE, Vector2i(26, 18), Vector2i(1, 1), false],
	"dryer_rack": [Kind.FURNITURE, Vector2i(52, 34), Vector2i(2, 1), true],
	# Office details (OfficeDetailPropPainter).
	"notice_board": [Kind.WALL, Vector2i(56, 40), Vector2i(2, 2), false],
	"ac_unit": [Kind.WALL, Vector2i(44, 16), Vector2i(2, 1), false],
	"binder_shelf": [Kind.WALL, Vector2i(60, 22), Vector2i(2, 1), false],
	"first_aid": [Kind.WALL, Vector2i(18, 16), Vector2i(1, 1), false],
	"exit_sign": [Kind.WALL, Vector2i(26, 12), Vector2i(1, 1), false],
	"paper_box": [Kind.FURNITURE, Vector2i(22, 16), Vector2i(1, 1), false],
	"recycle_bins": [Kind.FURNITURE, Vector2i(60, 34), Vector2i(2, 1), true],
	"coat_stand": [Kind.FURNITURE, Vector2i(22, 58), Vector2i(1, 1), true],
	"bin_office": [Kind.FURNITURE, Vector2i(14, 18), Vector2i(1, 1), false],
	"water_bottles": [Kind.FURNITURE, Vector2i(28, 38), Vector2i(1, 1), true],
	"server_rack": [Kind.FURNITURE, Vector2i(30, 70), Vector2i(1, 1), true],
	"bike": [Kind.FURNITURE, Vector2i(60, 36), Vector2i(2, 1), true],
	"flipchart": [Kind.FURNITURE, Vector2i(28, 58), Vector2i(1, 1), true],
	# Floor decals.
	"rug_office": [Kind.DECAL, Vector2i(128, 96), Vector2i(4, 3), false],
	"rug_lounge": [Kind.DECAL, Vector2i(128, 96), Vector2i(4, 3), false],
	"rug_party": [Kind.DECAL, Vector2i(160, 96), Vector2i(5, 3), false],
	"logo_floor": [Kind.DECAL, Vector2i(64, 76), Vector2i(2, 2), false],
}


static func kind(id: String) -> Kind:
	return DEFS[id][0]


static func sprite_size(id: String) -> Vector2i:
	return DEFS[id][1]


static func footprint(id: String) -> Vector2i:
	return DEFS[id][2]


static func is_blocking(id: String) -> bool:
	return DEFS[id][3]
