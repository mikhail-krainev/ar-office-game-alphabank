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
	var straight: PaperToss.Throw = toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size)
	assert_bool(straight.hit).is_true()
	var weak: PaperToss.Throw = toss.throw(Vector2(0, -size.y * 0.15), size)
	assert_bool(weak.hit).is_false()
	# The wind carries the ball off; aiming against it brings it back.
	toss.wind = PaperToss.WIND_MAX
	assert_bool(toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size).hit).is_false()
	var against: float = -PaperToss.WIND_MAX / PaperToss.AIM_RANGE * size.x
	assert_bool(toss.throw(Vector2(against, -size.y * PaperToss.IDEAL_POWER), size).hit).is_true()
	# A swipe far to the side misses.
	toss.wind = 0.0
	assert_bool(toss.throw(Vector2(size.x * 0.5, -size.y * PaperToss.IDEAL_POWER), size).hit).is_false()


func test_bin_and_hand_stay_inside_the_view() -> void:
	var size: Vector2 = Vector2(288, 270)
	var view: Rect2 = Rect2(Vector2.ZERO, size)
	var camera: ArCamera = PaperToss.default_camera(view)
	var opening: Vector3 = camera.project(Vector3(0, PaperToss.BIN_HEIGHT, PaperToss.BIN_DISTANCE))
	var bin_foot: Vector3 = camera.project(Vector3(0, 0, PaperToss.BIN_DISTANCE))
	var hand: Vector3 = camera.project(PaperToss.hand_point(camera))
	for point: Vector3 in [opening, bin_foot, hand]:
		assert_float(point.z).is_greater(0.0)
		assert_bool(view.has_point(Vector2(point.x, point.y))).is_true()
	assert_float(opening.x).is_equal_approx(size.x / 2.0, 0.01)
	# The bin stands on the floor: its foot is lower in the picture than its opening, and the ball
	# waits in the hand below both.
	assert_float(bin_foot.y).is_greater(opening.y)
	assert_float(hand.y).is_greater(bin_foot.y)
	# Nearer is bigger.
	assert_float(hand.z).is_greater(opening.z)
	assert_vector(PaperToss.hand_point(camera)).is_equal_approx(PaperToss.HAND, Vector3.ONE * 0.001)


func test_floor_point_is_where_the_bin_shows() -> void:
	var view: Rect2 = Rect2(0, 0, 288, 270)
	var camera: ArCamera = ArCamera.new(view, DevicePose.tilted(40.0), PaperToss.eye())
	var spot: Vector3 = camera.floor_point(Vector2(200, 180))
	assert_float(spot.y).is_equal_approx(0.0, 0.0001)
	var back: Vector3 = camera.project(spot)
	assert_vector(Vector2(back.x, back.y)).is_equal_approx(Vector2(200, 180), Vector2.ONE * 0.01)
	# Looking at the horizon or up never reaches the floor.
	assert_that(ArCamera.new(view, DevicePose.tilted(-10.0), PaperToss.eye()).floor_point(view.get_center())).is_null()


func test_bin_stays_in_the_room_when_the_phone_turns() -> void:
	var view: Rect2 = Rect2(0, 0, 288, 270)
	var pose: DevicePose = DevicePose.new(PaperToss.CAMERA_TILT)
	var bin: Vector3 = Vector3(0, 0, PaperToss.BIN_DISTANCE)
	var start: Vector3 = ArCamera.new(view, pose.basis, PaperToss.eye()).project(bin)
	# Turning the phone to the right (clockwise seen from above) moves the bin to the left.
	for frame: int in 30:
		pose.update(1.0 / 30.0, Vector3(0, -20, 0), Vector3.ZERO, false)
	var camera: ArCamera = ArCamera.new(view, pose.basis, PaperToss.eye())
	assert_float(camera.project(bin).x).is_less(start.x - 10.0)
	assert_float(camera.heading()).is_greater(0.0)


func test_pose_levels_by_gravity() -> void:
	var pose: DevicePose = DevicePose.new()
	# Upright phone tilted 30 degrees down: gravity (pointing up at rest) leans towards the screen.
	var tilt: float = deg_to_rad(30.0)
	var gravity: Vector3 = Vector3(0, cos(tilt), sin(tilt)) * DevicePose.GRAVITY
	pose.update(0.016, Vector3.ZERO, gravity, true)
	var ahead: Vector3 = pose.forward()
	assert_float(rad_to_deg(asin(-ahead.y))).is_equal_approx(30.0, 0.1)
	assert_float(ahead.x).is_equal_approx(0.0, 0.001)


func test_farther_bin_needs_a_harder_throw() -> void:
	var toss: PaperToss = PaperToss.new(13)
	var size: Vector2 = Vector2(288, 270)
	toss.wind = 0.0
	toss.bin = Vector3(0.8, 0, 2.4)
	var heading: float = toss.bin_yaw()
	assert_bool(toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size, heading).hit).is_false()
	var hit: PaperToss.Throw = toss.throw(Vector2(0, -size.y * toss.needed_power()), size, heading)
	assert_bool(hit.hit).is_true()
	assert_float(Vector2(hit.rest.x - toss.bin.x, hit.rest.z - toss.bin.z).length()).is_less(PaperToss.BIN_BOTTOM_RADIUS)


func test_paper_ball_flight_ends_at_the_landing() -> void:
	var toss: PaperToss = PaperToss.new(5)
	var flight: PaperToss.Throw = toss.throw(Vector2(40, -150), Vector2(288, 270))
	assert_vector(PaperToss.flight_point(flight, 0.0)).is_equal_approx(flight.start, Vector3.ONE * 0.001)
	assert_vector(PaperToss.flight_point(flight, 1.0)).is_equal_approx(flight.target, Vector3.ONE * 0.001)
	assert_vector(PaperToss.settle_point(flight, 1.0)).is_equal_approx(flight.rest, Vector3.ONE * 0.001)


func test_paper_ball_rests_where_it_belongs() -> void:
	var toss: PaperToss = PaperToss.new(3)
	var size: Vector2 = Vector2(288, 270)
	toss.wind = 0.0
	var hit: PaperToss.Throw = toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size)
	var inside: Vector2 = Vector2(hit.rest.x, hit.rest.z - PaperToss.BIN_DISTANCE)
	assert_float(inside.length()).is_less(PaperToss.BIN_BOTTOM_RADIUS)
	assert_float(hit.target.y).is_equal_approx(PaperToss.BIN_HEIGHT, 0.001)
	# Too strong flies over the bin and lands on the floor behind it.
	var over: PaperToss.Throw = toss.throw(Vector2(0, -size.y * 0.9), size)
	assert_bool(over.hit).is_false()
	assert_float(over.rest.z).is_greater(PaperToss.BIN_DISTANCE + PaperToss.BIN_TOP_RADIUS)
	assert_float(over.rest.y).is_equal_approx(PaperToss.BALL_RADIUS, 0.001)
	# Just off to the side strikes the rim and bounces out of the bin.
	toss.wind = PaperToss.BIN_HALF_WIDTH + 0.5
	var rim: PaperToss.Throw = toss.throw(Vector2(0, -size.y * PaperToss.IDEAL_POWER), size)
	assert_bool(rim.hit).is_false()
	assert_float(rim.hop).is_equal(PaperToss.RIM_HOP)
	var outside: Vector2 = Vector2(rim.rest.x, rim.rest.z - PaperToss.BIN_DISTANCE)
	assert_float(outside.length()).is_greater(PaperToss.BIN_TOP_RADIUS + PaperToss.BALL_RADIUS)


func test_graffiti_spray_paints_a_core_with_overspray() -> void:
	var canvas: GraffitiCanvas = GraffitiCanvas.new(9)
	assert_bool(canvas.has_enough_paint()).is_false()
	canvas.spray(Vector2(20, 40), Vector2(60, 40), GraffitiCanvas.FAT, Color.RED)
	assert_bool(canvas.has_enough_paint()).is_true()
	# The line is solid in the middle, nothing lands farther than the nozzle reaches.
	for x: int in range(20, 61, 5):
		assert_float(canvas.image.get_pixel(x, 40).a).is_equal_approx(1.0, 0.01)
	var reach: int = ceili(GraffitiCanvas.FAT) + 1
	for y: int in GraffitiCanvas.HEIGHT:
		if absi(y - 40) > reach:
			assert_float(canvas.image.get_pixel(40, y).a).override_failure_message("row %d" % y).is_equal(0.0)
	# The PNG fits the shared wall on the server (graffiti.go).
	var sent: Image = Image.new()
	sent.load_png_from_buffer(Marshalls.base64_to_raw(canvas.to_png_base64()))
	assert_vector(Vector2(sent.get_size())).is_equal(Vector2(GraffitiCanvas.WIDTH, GraffitiCanvas.HEIGHT))


func test_graffiti_paint_piled_up_runs_down() -> void:
	var canvas: GraffitiCanvas = GraffitiCanvas.new(4)
	for puff: int in 200:
		canvas.spray(Vector2(70, 20), Vector2(70, 20), GraffitiCanvas.THIN, Color.WHITE)
	var below_before: int = _painted_below(canvas, 20 + ceili(GraffitiCanvas.THIN) + 1)
	for frame: int in 120:
		canvas.update(1.0 / 30.0)
	assert_int(_painted_below(canvas, 20 + ceili(GraffitiCanvas.THIN) + 1)).is_greater(below_before)
	assert_bool(canvas.update(0.1)).is_false()


func _painted_below(canvas: GraffitiCanvas, top: int) -> int:
	var count: int = 0
	for y: int in range(top, GraffitiCanvas.HEIGHT):
		for x: int in GraffitiCanvas.WIDTH:
			if canvas.image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func test_graffiti_paint_lands_where_the_finger_meets_the_wall() -> void:
	var view: Rect2 = Rect2(0, 0, 288, 192)
	var pose: DevicePose = DevicePose.new(5.0)
	var camera: ArCamera = ArCamera.new(view, pose.basis, PaperToss.eye())
	var plane: GraffitiWallPlane = GraffitiWallPlane.facing(camera, view)
	# The wall hangs in front, square to the look, and its middle is in the middle of the view.
	var middle: Vector3 = camera.project(plane.point(Vector2(GraffitiCanvas.WIDTH, GraffitiCanvas.HEIGHT) / 2.0))
	assert_vector(Vector2(middle.x, middle.y)).is_equal_approx(view.get_center(), Vector2.ONE * 1.0)
	assert_float(Vector2(plane.centre.x, plane.centre.z).length()).is_equal_approx(GraffitiWallPlane.DISTANCE, 0.001)
	var corner: Vector3 = camera.project(plane.point(Vector2(20, 30)))
	var pixel: Vector2 = plane.pixel_at(camera, Vector2(corner.x, corner.y))
	assert_vector(pixel).is_equal_approx(Vector2(20, 30), Vector2.ONE * 0.05)
	# Turned away from the wall, the finger's ray never reaches it.
	for frame: int in 60:
		pose.update(1.0 / 30.0, Vector3(0, 100, 0), Vector3.ZERO, false)
	var away: ArCamera = ArCamera.new(view, pose.basis, PaperToss.eye())
	assert_that(plane.pixel_at(away, view.get_center())).is_null()


func test_world_pose_from_the_tracking_engine() -> void:
	var pose: SensorModels.WorldPose = SensorModels.WorldPose.parse("0.1,1.3,-0.2,0,0.38268,0,0.92388,58")
	assert_vector(pose.position).is_equal_approx(Vector3(0.1, 1.3, -0.2), Vector3.ONE * 0.0001)
	assert_float(pose.field_of_view).is_equal(58.0)
	# The camera turned 45 degrees to the left looks that way in the room.
	var camera: ArCamera = ArCamera.new(Rect2(0, 0, 288, 270), Basis(pose.rotation), Vector3(0.1, 1.3, 0.2), pose.field_of_view)
	assert_float(camera.heading()).is_equal_approx(-45.0, 0.01)
	for broken: String in ["", "1,2,3", "a,b,c,d,e,f,g,h", "0,0,0,0,0,0,0,50"]:
		assert_that(SensorModels.WorldPose.parse(broken)).override_failure_message(broken).is_null()


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
