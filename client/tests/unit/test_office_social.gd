extends GdUnitTestSuite
## Bug hunt geometry, the mood canvas and the office players list.

const VIEW: Vector2 = Vector2(240, 180)


func test_turning_the_phone_turns_the_view() -> void:
	var swarm: BugSwarm = BugSwarm.new(0)
	# Turning left (positive rate about the device y axis) for one second at 30 degrees per second.
	swarm.update(1.0, Vector3(0, 30, 0))
	assert_float(swarm.view_yaw).is_equal_approx(-30.0, 0.001)
	swarm.update(1.0, Vector3(20, 0, 0))
	assert_float(swarm.view_pitch).is_equal_approx(20.0, 0.001)
	swarm.update(10.0, Vector3(100, 0, 0))
	assert_float(swarm.view_pitch).is_equal(BugSwarm.VIEW_PITCH_LIMIT)


func test_a_bug_ahead_is_in_the_middle_and_can_be_caught() -> void:
	var swarm: BugSwarm = BugSwarm.new(0)
	var bug: BugSwarm.Bug = BugSwarm.Bug.new(0.0, 0.0, 0.0)
	swarm.bugs.append(bug)
	assert_that(swarm.project(bug, VIEW)).is_equal(VIEW / 2.0)
	(
		assert_object(swarm.catch_at(VIEW / 2.0 + Vector2(BugSwarm.HIT_RADIUS * 2.0, 0), VIEW))
		. is_null()
	)
	assert_object(swarm.catch_at(VIEW / 2.0 + Vector2(5, 5), VIEW)).is_same(bug)
	assert_int(swarm.caught_count()).is_equal(1)
	# A caught bug cannot be caught twice.
	assert_object(swarm.catch_at(VIEW / 2.0, VIEW)).is_null()


func test_bugs_behind_are_out_of_view_and_the_arrow_points_the_short_way() -> void:
	var swarm: BugSwarm = BugSwarm.new(0)
	var behind_right: BugSwarm.Bug = BugSwarm.Bug.new(170.0, 0.0, 0.0)
	swarm.bugs.append(behind_right)
	assert_bool(swarm.is_visible(behind_right, VIEW)).is_false()
	assert_float(swarm.nearest_turn()).is_equal_approx(170.0, 0.001)
	swarm.view_yaw = -100.0
	# From -100 the bug at 170 is 90 degrees to the left across the back.
	assert_float(swarm.nearest_turn()).is_equal_approx(-90.0, 0.001)


func test_a_new_swarm_surrounds_the_player() -> void:
	var swarm: BugSwarm = BugSwarm.new(8, 42)
	assert_int(swarm.bugs.size()).is_equal(8)
	var visible: int = (
		swarm
		. bugs
		. filter(func(bug: BugSwarm.Bug) -> bool: return swarm.is_visible(bug, VIEW))
		. size()
	)
	assert_int(visible).is_less(8)
	for bug: BugSwarm.Bug in swarm.bugs:
		assert_float(bug.pitch).is_between(BugSwarm.PITCH_MIN, BugSwarm.PITCH_MAX)


func test_mood_canvas_paints_strokes_without_gaps() -> void:
	var canvas: MoodCanvas = MoodCanvas.new()
	assert_bool(canvas.is_empty()).is_true()
	canvas.stroke(Vector2i(0, 10), Vector2i(20, 10), 2, Color.RED)
	assert_bool(canvas.is_empty()).is_false()
	for x: int in 21:
		assert_float(canvas.image.get_pixel(x, 10).a).override_failure_message(str(x)).is_equal(1.0)
	# Off the edge is clipped, not an error.
	canvas.stroke(Vector2i(63, 63), Vector2i(70, 70), 4, Color.BLUE)
	var png: PackedByteArray = canvas.image.save_png_to_buffer()
	var back: Image = Image.new()
	assert_int(back.load_png_from_buffer(png)).is_equal(OK)
	assert_that(back.get_size()).is_equal(Vector2i(MoodCanvas.SIDE, MoodCanvas.SIDE))
	canvas.clear()
	assert_bool(canvas.is_empty()).is_true()


func test_office_players_carry_outfit_story_and_streak() -> void:
	var data: Dictionary = {
		"players":
		[
			{
				"user_id": "u1",
				"name": "Аня",
				"department": "design",
				"avatar": "fox",
				"room": "lounge",
				"streak": 4,
				"has_mood": true,
				"character_avatar": true,
				"outfit": {"top": "alfa_hoodie", "hat": "cap"},
			},
			"garbage"
		]
	}
	var players: Array[BackendModels.OfficePlayer] = BackendParser.office_players(data)
	assert_int(players.size()).is_equal(1)
	var player: BackendModels.OfficePlayer = players[0]
	assert_str(player.colleague.name).is_equal("Аня")
	assert_int(player.streak).is_equal(4)
	assert_bool(player.has_mood and player.character_avatar).is_true()
	assert_str(str(player.outfit["top"])).is_equal("alfa_hoodie")
	# The rest of the outfit is filled with defaults, so the character is always drawable.
	assert_bool(player.outfit.has("shoes")).is_true()
	assert_object(CharacterSprite.outfit_frames(player.outfit)).is_not_null()
