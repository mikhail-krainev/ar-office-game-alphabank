extends GdUnitTestSuite

## Map sizes of server/content/home.json; the server keeps placed items inside them.
const SERVER_SIZES: Dictionary[String, Vector2i] = {
	"studio20": Vector2i(14, 12), "flat40": Vector2i(16, 18), "flat60": Vector2i(20, 20),
	"loft120": Vector2i(22, 27), "house240": Vector2i(26, 38),
}


func test_every_apartment_is_valid_and_matches_the_server() -> void:
	for id: String in ApartmentLayouts.IDS:
		var layout: HomeLayout = ApartmentLayouts.create(id)
		assert_str(layout.apartment_id).is_equal(id)
		assert_array(Array(layout.validate())).override_failure_message("%s: %s" % [id, layout.validate()]).is_empty()
		assert_that(layout.size).override_failure_message(id).is_equal(SERVER_SIZES[id])


func test_every_spot_and_door_is_reachable() -> void:
	for id: String in ApartmentLayouts.IDS:
		var layout: HomeLayout = ApartmentLayouts.create(id)
		var kept: Array[Vector2i] = []
		for use: HomeLayout.Interactable in layout.interactables:
			kept.append(use.stand_cell)
		assert_bool(HomeDecor._all_reachable(layout, Rect2i(), null, kept)).override_failure_message(id).is_true()


func test_each_apartment_has_the_home_objects() -> void:
	for id: String in ApartmentLayouts.IDS:
		var kinds: Array[HomeLayout.Kind] = []
		for use: HomeLayout.Interactable in ApartmentLayouts.create(id).interactables:
			kinds.append(use.kind)
		for kind: HomeLayout.Kind in [HomeLayout.Kind.WARDROBE, HomeLayout.Kind.DOOR, HomeLayout.Kind.GARAGE]:
			assert_bool(kinds.has(kind)).override_failure_message("%s lacks %s" % [id, kind]).is_true()


func test_the_house_has_a_garage_fireplace_and_yard() -> void:
	var house: HomeLayout = ApartmentLayouts.create("house240")
	assert_bool(house.car_rect.has_area()).is_true()
	assert_object(house.find_room(&"yard")).is_not_null()
	assert_object(house.find_prop("fireplace", Vector2i(2, 19))).is_not_null()
	assert_object(house.find_prop("pool", Vector2i(9, 32))).is_not_null()


func test_unknown_apartment_is_the_studio() -> void:
	assert_str(ApartmentLayouts.create("castle").apartment_id).is_equal(ApartmentLayouts.STUDIO)


func test_posters_hang_on_walls_and_furniture_stands_on_floors() -> void:
	var studio: HomeLayout = ApartmentLayouts.create("studio20")
	# (4, 1) is a free wall face of the studio, (5, 7) its free floor.
	assert_str(HomeDecor.placement_error(studio, "poster_tiger", Vector2i(4, 1))).is_equal(HomeDecor.OK)
	assert_str(HomeDecor.placement_error(studio, "poster_tiger", Vector2i(5, 7))).is_equal(HomeDecor.ERROR_WALL)
	assert_str(HomeDecor.placement_error(studio, "plant_big", Vector2i(5, 7))).is_equal(HomeDecor.OK)
	assert_str(HomeDecor.placement_error(studio, "plant_big", Vector2i(4, 1))).is_equal(HomeDecor.ERROR_FLOOR)
	# The front door, the bed and the spot in front of the wardrobe are taken.
	assert_str(HomeDecor.placement_error(studio, "poster_tiger", Vector2i(6, 1))).is_equal(HomeDecor.ERROR_TAKEN)
	assert_str(HomeDecor.placement_error(studio, "plant_big", Vector2i(1, 4))).is_equal(HomeDecor.ERROR_TAKEN)
	assert_str(HomeDecor.placement_error(studio, "plant_big", Vector2i(3, 4))).is_equal(HomeDecor.ERROR_BLOCKS)


func test_rugs_lie_under_furniture_but_not_on_rugs() -> void:
	var studio: HomeLayout = ApartmentLayouts.create("studio20")
	studio.add_prop("armchair", 5, 8)
	assert_str(HomeDecor.placement_error(studio, "rug_bedroom", Vector2i(4, 7))).is_equal(HomeDecor.OK)
	studio.add_prop("rug_bedroom", 4, 7)
	assert_str(HomeDecor.placement_error(studio, "rug_living", Vector2i(3, 6))).is_equal(HomeDecor.ERROR_TAKEN)
	assert_str(HomeDecor.placement_error(studio, "cactus", Vector2i(4, 7))).is_equal(HomeDecor.OK)


func test_furniture_never_cuts_off_the_bathroom() -> void:
	var studio: HomeLayout = ApartmentLayouts.create("studio20")
	# The bathroom door (9, 4) is reached only through (8, 4), between the fridge and the stove;
	# a plant on (7, 4), the last free cell next to it, would lock the bathroom.
	assert_str(HomeDecor.placement_error(studio, "plant_big", Vector2i(7, 4))).is_equal(HomeDecor.ERROR_BLOCKS)
	assert_str(HomeDecor.placement_error(studio, "rug_bedroom", Vector2i(5, 7))).is_equal(HomeDecor.OK)


func test_decor_follows_the_saved_items() -> void:
	var studio: HomeLayout = ApartmentLayouts.create("studio20")
	var built_in: int = studio.props.size()
	var placed: Array[BackendHome.Placed] = [BackendHome.Placed.new("cactus", Vector2i(5, 7)), BackendHome.Placed.new("throne", Vector2i(5, 8))]
	studio.set_decor(placed)
	assert_int(studio.decor_props().size()).is_equal(1)
	studio.set_decor([])
	assert_int(studio.props.size()).is_equal(built_in)


func test_home_state_counts_free_copies() -> void:
	var state: BackendHome.State = BackendHome.parse_state({
		"apartment": "studio20", "max_owned": 10,
		"items": [{"id": "cactus", "name": "Кактус", "kind": "furniture", "price": 120, "owned": 3, "elsewhere": 1}],
		"decor": {"palette": "scandi", "placed": [{"item": "cactus", "x": 5, "y": 7}]},
	})
	assert_str(state.palette).is_equal("scandi")
	assert_int(state.free_copies("cactus")).is_equal(1)
	assert_int(state.free_copies("unknown")).is_equal(0)


func test_every_palette_of_the_server_has_colours() -> void:
	for id: String in ["scandi", "japandi", "loft", "minimal", "memphis", "miami", "deco"]:
		assert_object(HomePalettes.material(id)).override_failure_message(id).is_not_null()
	assert_object(HomePalettes.material(HomePalettes.ORIGINAL)).is_null()


func test_tapped_cell_places_posters_at_the_top_of_the_wall() -> void:
	var studio: HomeLayout = ApartmentLayouts.create("studio20")
	assert_that(HomeDecor.cell_for_tap(studio, "poster_tiger", Vector2i(4, 7))).is_equal(Vector2i(4, 1))
	assert_that(HomeDecor.cell_for_tap(studio, "coffee_table", Vector2i(5, 7))).is_equal(Vector2i(4, 7))
