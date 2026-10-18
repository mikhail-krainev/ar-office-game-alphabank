extends GdUnitTestSuite

const IMAGE_RECT: Rect2 = Rect2(10, 20, 200, 100)


func test_anchor_follows_the_face_landmarks() -> void:
	var face: SensorModels.Face = SensorModels.Face.new(Rect2(0.2, 0.2, 0.4, 0.6), 0.9)
	face.left_eye = Vector2(0.3, 0.4)
	face.right_eye = Vector2(0.5, 0.5)
	face.top = Vector2(0.4, 0.2)
	face.chin = Vector2(0.4, 0.8)
	var anchor: ArAnchor = ArAnchor.of_face(face, IMAGE_RECT)
	assert_that(anchor.left_eye).is_equal(Vector2(70, 60))
	assert_that(anchor.right_eye).is_equal(Vector2(110, 70))
	assert_that(anchor.eye_center()).is_equal(Vector2(90, 65))
	assert_float(anchor.eye_span()).is_equal_approx(Vector2(40, 10).length(), 0.001)
	# The right eye is lower: the head leans right, the stickers turn with it.
	assert_float(anchor.roll()).is_greater(0.0)


func test_anchor_without_landmarks_uses_the_face_box() -> void:
	var face: SensorModels.Face = SensorModels.Face.new(Rect2(0.25, 0.2, 0.5, 0.6))
	var anchor: ArAnchor = ArAnchor.of_face(face, IMAGE_RECT)
	assert_float(anchor.roll()).is_equal(0.0)
	assert_that(anchor.top).is_equal(Vector2(110, 40))
	assert_that(anchor.chin).is_equal(Vector2(110, 100))
	assert_float(anchor.left_eye.y).is_equal_approx(40 + 60 * ArAnchor.EYE_LINE, 0.001)
	assert_bool(anchor.left_eye.x < anchor.right_eye.x).is_true()


func test_faces_json_carries_the_ar_points() -> void:
	var json: String = (
		JSON
		. stringify(
			{
				"faces":
				[
					{
						"x": 0.1,
						"y": 0.2,
						"w": 0.3,
						"h": 0.4,
						"eyes": [0.15, 0.3, 0.35, 0.31],
						"top": [0.25, 0.2],
						"chin": [0.25, 0.6]
					},
					{
						"x": 0.5,
						"y": 0.2,
						"w": 0.3,
						"h": 0.4,
						"eyes": [0.1, "x", 0.2, 0.3],
						"top": [0.6, 0.2],
						"chin": [0.6, 0.6]
					},
				]
			}
		)
	)
	var faces: Array[SensorModels.Face] = SensorModels.parse_faces(json)
	assert_bool(faces[0].has_anchors()).is_true()
	assert_that(faces[0].right_eye).is_equal(Vector2(0.35, 0.31))
	assert_that(faces[0].chin).is_equal(Vector2(0.25, 0.6))
	assert_bool(faces[1].has_anchors()).is_false()


func test_labels_json_carries_the_box_and_the_target_locates_it() -> void:
	var json: String = (
		JSON
		. stringify(
			{
				"labels":
				[
					{"id": "coffee mug", "confidence": 0.7},
					{"id": "cup", "confidence": 0.6, "box": [0.2, 0.3, 0.25, 0.3]},
					{"id": "laptop", "confidence": 0.9, "box": [0.0, 0.0, 1.0, 1.0]},
				]
			}
		)
	)
	var labels: Array[SensorModels.ObjectLabel] = SensorModels.parse_labels(json)
	assert_bool(labels[0].bounds.has_area()).is_false()
	var mug: OfficeObjects.Target = OfficeObjects.from_ids(["mug"])[0]
	# The classifier label is more confident but has no box: the lock goes to the detector's cup.
	assert_that(mug.locate(labels)).is_equal(Rect2(0.2, 0.3, 0.25, 0.3))
	var plant: OfficeObjects.Target = OfficeObjects.from_ids(["plant"])[0]
	assert_bool(plant.locate(labels).has_area()).is_false()
