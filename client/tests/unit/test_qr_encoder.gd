extends GdUnitTestSuite


func test_short_text_uses_version_1() -> void:
	var matrix: QrEncoder.QrMatrix = QrEncoder.encode("HELLO")
	assert_int(matrix.version).is_equal(1)
	assert_int(matrix.size).is_equal(21)


func test_version_grows_with_payload() -> void:
	assert_int(QrEncoder.encode("x".repeat(14)).version).is_equal(1)
	assert_int(QrEncoder.encode("x".repeat(15)).version).is_equal(2)
	assert_int(QrEncoder.encode("x".repeat(60)).version).is_equal(4)
	assert_int(QrEncoder.encode("x".repeat(200)).version).is_equal(10)


func test_too_long_payload_gives_empty_matrix() -> void:
	assert_bool(QrEncoder.encode("x".repeat(300)).is_empty()).is_true()
	assert_error(func() -> void: QrEncoder.encode("x".repeat(300))).is_push_error("QR payload of 300 bytes is too long")


func test_finder_and_timing_patterns_are_drawn() -> void:
	var matrix: QrEncoder.QrMatrix = QrEncoder.encode(QrPayload.room("kitchen"))
	var last: int = matrix.size - 1
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(last - 6, 0), Vector2i(0, last - 6)]:
		assert_bool(matrix.is_dark(corner.x, corner.y)).is_true()
		assert_bool(matrix.is_dark(corner.x + 3, corner.y + 3)).is_true()
		assert_bool(matrix.is_dark(corner.x + 1, corner.y + 1)).is_false()
	assert_bool(matrix.is_dark(8, 6)).is_true()
	assert_bool(matrix.is_dark(9, 6)).is_false()
	# Dark module next to the bottom-left finder.
	assert_bool(matrix.is_dark(8, matrix.size - 8)).is_true()


func test_reed_solomon_matches_reference() -> void:
	# ISO/IEC 18004 example "01234567", version 1-M: data codewords and their EC codewords.
	var data: PackedByteArray = PackedByteArray([16, 32, 12, 86, 97, 128, 236, 17, 236, 17, 236, 17, 236, 17, 236, 17])
	var ec: PackedByteArray = QrEncoder._rs_remainder(data, QrEncoder._rs_generator(10))
	assert_array(Array(ec)).is_equal([165, 36, 212, 193, 237, 54, 199, 135, 44, 85])


func test_image_has_quiet_zone() -> void:
	var image: Image = QrEncoder.encode("A").to_image(2, 4)
	assert_int(image.get_width()).is_equal((21 + 8) * 2)
	assert_that(image.get_pixel(0, 0)).is_equal(Color.WHITE)
	assert_that(image.get_pixel(8, 8)).is_equal(Color.BLACK)
