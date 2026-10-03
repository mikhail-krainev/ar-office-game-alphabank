extends GdUnitTestSuite


func _labels(values: Dictionary) -> Array[SensorModels.ObjectLabel]:
	var result: Array[SensorModels.ObjectLabel] = []
	for id: String in values:
		result.append(SensorModels.ObjectLabel.new(id, values[id]))
	return result


func _target(id: String) -> OfficeObjects.Target:
	for target: OfficeObjects.Target in OfficeObjects.defaults():
		if target.id == id:
			return target
	return null


func test_target_matches_any_of_its_labels() -> void:
	var mug: OfficeObjects.Target = _target("mug")
	assert_float(mug.confidence_in(_labels({"coffee mug": 0.71, "person": 0.4}))).is_equal_approx(0.71, 0.001)
	assert_float(mug.confidence_in(_labels({"cup": 0.6, "coffee mug": 0.9}))).is_equal_approx(0.9, 0.001)
	assert_bool(mug.is_recognized(_labels({"cup": 0.9}))).is_true()


func test_low_confidence_and_other_objects_do_not_count() -> void:
	var mug: OfficeObjects.Target = _target("mug")
	assert_bool(mug.is_recognized(_labels({"cup": OfficeObjects.MIN_CONFIDENCE - 0.01}))).is_false()
	assert_bool(mug.is_recognized(_labels({"chair": 0.99, "potted plant": 0.98}))).is_false()
	assert_float(mug.confidence_in([])).is_equal(0.0)


func test_targets_are_unique_and_named() -> void:
	var ids: Array[String] = []
	var labels: Array[String] = []
	for target: OfficeObjects.Target in OfficeObjects.defaults():
		assert_bool(ids.has(target.id)).override_failure_message(target.id).is_false()
		ids.append(target.id)
		assert_str(tr(target.name_key)).override_failure_message(target.name_key).is_not_equal(target.name_key)
		assert_bool(target.labels.is_empty()).is_false()
		for label: String in target.labels:
			# One label must not belong to two targets, otherwise a round could be won by the wrong thing.
			assert_bool(labels.has(label)).override_failure_message(label).is_false()
			labels.append(label)


func test_from_ids_filters_and_falls_back() -> void:
	var picked: Array[OfficeObjects.Target] = OfficeObjects.from_ids(["mug", "clock"])
	assert_int(picked.size()).is_equal(2)
	assert_array(picked.map(func(target: OfficeObjects.Target) -> String: return target.id)).contains(["mug", "clock"])
	assert_int(OfficeObjects.from_ids([]).size()).is_equal(OfficeObjects.defaults().size())
	assert_int(OfficeObjects.from_ids(["nothing"]).size()).is_equal(OfficeObjects.defaults().size())


func test_all_labels_has_no_duplicates() -> void:
	var labels: PackedStringArray = OfficeObjects.all_labels()
	var seen: Array[String] = []
	for label: String in labels:
		assert_bool(seen.has(label)).override_failure_message(label).is_false()
		seen.append(label)
