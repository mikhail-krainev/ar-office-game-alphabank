extends GdUnitTestSuite
## The new AR games: pose checks, face commands, paper ball throws and the fortune wheel math.

const LEFT_SHOULDER: Vector2 = Vector2(0.42, 0.4)
const RIGHT_SHOULDER: Vector2 = Vector2(0.58, 0.4)


func _body(pose: StringName) -> Dictionary:
	var landmarks: Dictionary = {
		&"left_shoulder": Vector3(LEFT_SHOULDER.x, LEFT_SHOULDER.y, 0.9),
		&"right_shoulder": Vector3(RIGHT_SHOULDER.x, RIGHT_SHOULDER.y, 0.9),
		&"nose": Vector3(0.5, LEFT_SHOULDER.y - 0.16 * PoseMatcher.NOSE_HEIGHT, 0.9),
	}
	var arms: Dictionary = PoseMatcher.target_points(pose, LEFT_SHOULDER, RIGHT_SHOULDER)
	for joint: StringName in arms:
		var point: Vector2 = arms[joint]
		landmarks[joint] = Vector3(point.x, point.y, 0.9)
	return landmarks


func test_every_ghost_pose_matches_only_itself() -> void:
	for pose: StringName in PoseMatcher.POSES:
		var body: Dictionary = _body(pose)
		for other: StringName in PoseMatcher.POSES:
			assert_bool(PoseMatcher.matches(other, body)).override_failure_message("%s as %s" % [pose, other]).is_equal(other == pose)


func test_arms_down_and_hidden_wrists_match_nothing() -> void:
	var down: Dictionary = _body(&"")
	var hidden: Dictionary = _body(PoseMatcher.HANDS_UP)
	hidden[&"left_wrist"] = Vector3(0.4, 0.1, 0.2)
	for pose: StringName in PoseMatcher.POSES:
		assert_bool(PoseMatcher.matches(pose, down)).override_failure_message(String(pose)).is_false()
	assert_bool(PoseMatcher.matches(PoseMatcher.HANDS_UP, hidden)).is_false()


func test_pose_check_works_mirrored_and_far_away() -> void:
	# Front camera mirrors the picture; a player further away is smaller.
	var left: Vector2 = Vector2(0.55, 0.45)
	var right: Vector2 = Vector2(0.47, 0.45)
	var body: Dictionary = {
		&"left_shoulder": Vector3(left.x, left.y, 0.9), &"right_shoulder": Vector3(right.x, right.y, 0.9),
	}
	var arms: Dictionary = PoseMatcher.target_points(PoseMatcher.T_POSE, left, right)
	for joint: StringName in arms:
		body[joint] = Vector3((arms[joint] as Vector2).x, (arms[joint] as Vector2).y, 0.9)
	assert_bool(PoseMatcher.matches(PoseMatcher.T_POSE, body)).is_true()
	assert_float((arms[&"left_wrist"] as Vector2).x).is_greater(left.x)


func test_pick_gives_different_poses() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var poses: Array[StringName] = PoseMatcher.pick(4, rng)
	assert_int(poses.size()).is_equal(4)
	for pose: StringName in poses:
		assert_int(poses.count(pose)).is_equal(1)


func _face(smile: float, blink_left: float, blink_right: float, jaw: float) -> SensorModels.Face:
	var face: SensorModels.Face = SensorModels.Face.new(Rect2(0.3, 0.3, 0.3, 0.4), smile)
	face.blink_left = blink_left
	face.blink_right = blink_right
	face.jaw_open = jaw
	face.left_eye = Vector2(0.36, 0.45)
	face.right_eye = Vector2(0.54, 0.45)
	face.top = Vector2(0.45, 0.3)
	face.chin = Vector2(0.45, 0.7)
	return face


func test_face_commands() -> void:
	var calm: SensorModels.Face = _face(0.1, 0.05, 0.05, 0.02)
	for command: StringName in FaceCommands.COMMANDS:
		assert_bool(FaceCommands.shows(command, calm, 0.0)).override_failure_message(String(command)).is_false()
	assert_bool(FaceCommands.shows(FaceCommands.SMILE, _face(0.9, 0.05, 0.05, 0.1), 0.0)).is_true()
	assert_bool(FaceCommands.shows(FaceCommands.WINK, _face(0.1, 0.05, 0.8, 0.02), 0.0)).is_true()
	# Both eyes closed is a blink, not a wink.
	assert_bool(FaceCommands.shows(FaceCommands.WINK, _face(0.1, 0.8, 0.8, 0.02), 0.0)).is_false()
	assert_bool(FaceCommands.shows(FaceCommands.OPEN_MOUTH, _face(0.1, 0.05, 0.05, 0.7), 0.0)).is_true()
	assert_bool(FaceCommands.shows(FaceCommands.TILT_HEAD, calm, deg_to_rad(20.0))).is_true()


func test_face_commands_skip_what_the_detector_cannot_see() -> void:
	var box_only: SensorModels.Face = SensorModels.Face.new(Rect2(0.3, 0.3, 0.3, 0.4), 0.2)
	assert_array(FaceCommands.available(box_only)).contains_exactly([FaceCommands.SMILE])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var commands: Array[StringName] = FaceCommands.sequence(FaceCommands.COMMANDS, 8, rng)
	assert_int(commands.size()).is_equal(8)
	for i: int in range(1, commands.size()):
		assert_bool(commands[i] == commands[i - 1]).is_false()


func test_paper_ball_lands_where_aimed() -> void:
	var toss: PaperToss = PaperToss.new(11)
	var size: Vector2 = Vector2(288, 270)
	toss.wind = 0.0
	toss.view_yaw = toss.bin_yaw
	var straight: PaperToss.Throw = toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size)
	assert_bool(straight.hit).is_true()
	var weak: PaperToss.Throw = toss.throw(Vector2(0, -size.y * 0.15), size)
	assert_bool(weak.hit).is_false()
	# The wind carries the ball off; aiming against it brings it back.
	toss.wind = PaperToss.WIND_MAX
	assert_bool(toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size).hit).is_false()
	var against: float = -PaperToss.WIND_MAX / PaperToss.AIM_RANGE * size.x
	assert_bool(toss.throw(Vector2(against, -size.y * PaperToss.IDEAL_POWER), size).hit).is_true()
	# Facing away from the bin never hits.
	toss.wind = 0.0
	toss.view_yaw = wrapf(toss.bin_yaw + 90.0, -180.0, 180.0)
	assert_bool(toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size).hit).is_false()


func test_paper_ball_flight_ends_at_the_landing() -> void:
	var toss: PaperToss = PaperToss.new(5)
	var flight: PaperToss.Throw = toss.throw(Vector2(40, -150), Vector2(288, 270))
	var end: Vector2 = PaperToss.flight_point(flight, 1.0)
	assert_float(end.x).is_equal_approx(flight.landing_yaw, 0.01)
	assert_float(end.y).is_equal_approx(flight.landing_pitch, 0.01)


func test_wheel_stops_on_the_chosen_sector() -> void:
	for count: int in [6, 8]:
		for index: int in count:
			var target: float = WheelView.target_rotation(1.3, index, count, WheelView.SPIN_TURNS, 0.9)
			assert_int(WheelView.sector_at(target, count)).override_failure_message("%d of %d" % [index, count]).is_equal(index)
			assert_float(target).is_greater(1.3 + WheelView.SPIN_TURNS * TAU - 0.01)


func test_wheel_caption() -> void:
	var coins: BackendModels.WheelSector = BackendModels.WheelSector.new()
	coins.kind = "coins"
	coins.coins = 100
	assert_str(WheelView.caption_of(coins)).is_equal("+100")
	var item: BackendModels.WheelSector = BackendModels.WheelSector.new()
	item.kind = "item"
	item.name = "Промокод на кофе"
	assert_str(WheelView.caption_of(item)).is_equal("Промокод")


func test_wheel_card_builds_with_a_pending_win() -> void:
	var state: BackendModels.WheelState = BackendParser.wheel({
		"sectors": [{"kind": "coins", "coins": 100, "chance": 60.0}, {"kind": "item", "item_id": "cap", "name": "Кепка", "rarity": "rare", "icon": 14, "chance": 40.0, "owned": true}],
		"spin_price": 300, "spins_left": 0, "pending": {"sector": 1, "item_id": "cap", "coins": 700, "reason": "owned"},
	})
	assert_int(state.sectors.size()).is_equal(2)
	assert_bool(state.sectors[1].owned).is_true()
	assert_int(state.pending.coins).is_equal(700)
	var card: WheelCard = auto_free(WheelCard.new())
	card.build(state, 300.0)
	assert_int(card.get_child_count()).is_equal(1)
