extends GdUnitTestSuite
## The built-in props of every map: no two props of the same layer share a cell, and the
## everyday details (LivedInPropPainter, OfficeDetailPropPainter) are really placed.


func _layouts() -> Dictionary[String, MapLayout]:
	var layouts: Dictionary[String, MapLayout] = {"office": OfficeLayout.new(), "analytics": AnalyticsLayout.new()}
	for id: String in ApartmentLayouts.IDS:
		layouts[id] = ApartmentLayouts.create(id)
	return layouts


func test_props_of_one_layer_never_overlap() -> void:
	var layouts: Dictionary[String, MapLayout] = _layouts()
	for name: String in layouts:
		var taken: Dictionary[String, String] = {}
		for prop: MapLayout.Prop in layouts[name].props:
			var footprint: Rect2i = Rect2i(prop.cell, PropCatalog.footprint(prop.id))
			for y: int in range(footprint.position.y, footprint.end.y):
				for x: int in range(footprint.position.x, footprint.end.x):
					var key: String = "%d:%d,%d" % [PropCatalog.kind(prop.id), x, y]
					assert_bool(taken.has(key)).override_failure_message(
						"%s: %s at %s overlaps %s" % [name, prop.id, prop.cell, taken.get(key, "")]
					).is_false()
					taken[key] = prop.id


func test_every_map_is_valid() -> void:
	var layouts: Dictionary[String, MapLayout] = _layouts()
	for name: String in layouts:
		assert_array(Array(layouts[name].validate())).override_failure_message("%s: %s" % [name, layouts[name].validate()]).is_empty()


func test_rooms_are_furnished_with_everyday_things() -> void:
	var details: Array[String] = ["slippers", "laundry_basket", "bin_small", "notice_board", "bin_office", "server_rack"]
	var found: Dictionary[String, bool] = {}
	for layout: MapLayout in _layouts().values():
		for prop: MapLayout.Prop in layout.props:
			found[prop.id] = true
	for id: String in details:
		assert_bool(found.has(id)).override_failure_message(id).is_true()


func test_every_apartment_room_has_a_detail() -> void:
	var lived_in: Array[String] = [
		"wall_shelf", "spice_rack", "bath_shelf", "wall_sconce", "photo_collage", "plant_hanging", "laundry_basket",
		"side_table", "book_stack", "slippers", "sneakers", "umbrella_stand", "backpack", "counter_dishes", "vacuum",
		"ironing_board", "boxes_stack", "floor_fan", "rug_round", "bin_small", "cat_bed", "dryer_rack", "bike", "recycle_bins",
	]
	for id: String in ApartmentLayouts.IDS:
		var layout: HomeLayout = ApartmentLayouts.create(id)
		var rooms_with_details: Dictionary[StringName, bool] = {}
		for prop: MapLayout.Prop in layout.built_in_props():
			if lived_in.has(prop.id):
				rooms_with_details[layout.get_room_at(prop.cell).id] = true
		for room: MapLayout.Room in layout.rooms:
			if room.id == &"yard":
				continue
			assert_bool(rooms_with_details.has(room.id)).override_failure_message("%s: %s" % [id, room.id]).is_true()
