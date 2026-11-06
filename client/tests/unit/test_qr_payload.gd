extends GdUnitTestSuite


func test_parses_room_code() -> void:
	var payload: QrPayload = QrPayload.parse("alfaoffice://room/kitchen")
	assert_int(payload.kind).is_equal(QrPayload.Kind.ROOM)
	assert_str(payload.value).is_equal("kitchen")


func test_scheme_and_kind_are_case_insensitive() -> void:
	var payload: QrPayload = QrPayload.parse("  AlfaOffice://USER/colleague-anna ")
	assert_int(payload.kind).is_equal(QrPayload.Kind.USER)
	assert_str(payload.value).is_equal("colleague-anna")


func test_make_and_parse_round_trip() -> void:
	var payload: QrPayload = QrPayload.parse(QrPayload.presence("hq.123.abcdef"))
	assert_int(payload.kind).is_equal(QrPayload.Kind.PRESENCE)
	assert_str(payload.value).is_equal("hq.123.abcdef")


func test_rejects_foreign_and_malformed_codes() -> void:
	for text: String in [
		"WIFI:S:Guest;T:WPA;P:secret;;",
		"https://example.com/room/kitchen",
		"alfaoffice://room",
		"alfaoffice://room/kitchen/extra",
		"alfaoffice://printer/1",
		"alfaoffice://room/kitchen?x=1",
		"alfaoffice://room/кухня",
	]:
		assert_bool(QrPayload.parse(text).is_valid()).override_failure_message(text).is_false()


func test_user_code_keeps_the_signed_value_and_names_the_user() -> void:
	var code: String = "0b6e4c1e-5a0f-4c51-9d64-2f1e8a7b3c90.179000000.a1b2c3d4e5f60718293a"
	var payload: QrPayload = QrPayload.parse(QrPayload.user(code))
	assert_int(payload.kind).is_equal(QrPayload.Kind.USER)
	assert_str(payload.value).is_equal(code)
	assert_str(QrPayload.user_id_of(payload.value)).is_equal("0b6e4c1e-5a0f-4c51-9d64-2f1e8a7b3c90")
