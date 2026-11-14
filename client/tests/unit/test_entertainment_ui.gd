extends GdUnitTestSuite
## Navigation and room setup must preserve the office and task boundaries.


func test_room_setup_defers_card_and_roulette_stakes() -> void:
	var panel: LoungePanel = auto_free(LoungePanel.new())
	for game: String in ["blackjack", "roulette"]:
		panel._configure(game)
		assert_bool(panel._stake.visible).is_false()
		await get_tree().process_frame
	panel._configure("memory")
	assert_bool(panel._stake.visible).is_true()
	await get_tree().process_frame


func test_entertainment_requires_office_check_in() -> void:
	var previous: BackendModels.Profile = Backend.profile
	Backend.profile = BackendModels.Profile.new()
	var panel: LoungePanel = auto_free(LoungePanel.new())
	panel.open()
	assert_bool(panel.visible).is_false()
	Backend.profile = previous


func test_completed_squats_offer_continuation() -> void:
	var panel: TaskPanel = auto_free(TaskPanel.new())
	var task: BackendModels.TaskInfo = BackendModels.TaskInfo.new()
	task.id = "squats"
	task.title = "Утренняя зарядка"
	task.completed = true
	var row: Control = auto_free(panel._make_row(task, 300))
	var footer: HBoxContainer = row.get_child(0).get_child(2)
	var button: Button = footer.get_child(footer.get_child_count() - 1)
	assert_str(button.text).is_equal("Продолжить")
	assert_bool(button.disabled).is_false()
	task.completed = false
	task.skipped = true
	var skipped: Control = auto_free(panel._make_row(task, 300))
	var skipped_footer: HBoxContainer = skipped.get_child(0).get_child(2)
	var skipped_button: Button = skipped_footer.get_child(skipped_footer.get_child_count() - 1)
	assert_bool(skipped_button.disabled).is_true()


func test_roulette_rack_offers_large_chips_within_balance() -> void:
	assert_array(RouletteChips.VALUES).contains([500, 1000, 5000, 10000])
	var chips: RouletteChips = auto_free(RouletteChips.new())
	chips.selected = 10000
	chips.set_state(4999, 0)
	assert_int(chips.selected).is_equal(1000)


func test_blackjack_stepper_reaches_ten_thousand() -> void:
	assert_array(LoungeBlackjackView.STAKES).contains([2000, 5000, 10000])
	for stake: int in LoungeBlackjackView.STAKES:
		assert_int(stake % 2).is_equal(0)


func test_every_lounge_game_has_an_icon() -> void:
	var games: Array = LoungePanel.TITLES.keys()
	games.append("clicker")
	for game: String in games:
		assert_bool(ResourceLoader.exists(LoungePanel.GAME_ICON_DIR % game)).override_failure_message(game).is_true()
