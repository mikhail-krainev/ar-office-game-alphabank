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


func test_bug_hunt_is_a_task_game_only() -> void:
	# The bug hunt left the entertainment menu: it is a joint daily task now.
	assert_bool(LoungePanel.TASK_GAMES.has("bug_hunt")).is_true()
	assert_bool(LoungePanel.TITLES.has("bug_hunt")).is_true()


func test_choice_prompt_tells_dismiss_from_second_answer() -> void:
	var prompt: ChoicePrompt = auto_free(ChoicePrompt.new())
	add_child(prompt)
	for expected: ChoicePrompt.Choice in [ChoicePrompt.Choice.DISMISSED, ChoicePrompt.Choice.SECOND, ChoicePrompt.Choice.FIRST]:
		prompt._answered.emit.call_deferred(expected)
		var answer: ChoicePrompt.Choice = await prompt.choose("?", "Вместе", "Одному")
		assert_int(answer).is_equal(expected)
	prompt._answered.emit.call_deferred(ChoicePrompt.Choice.DISMISSED)
	assert_bool(await prompt.ask("?", "Да", "Нет")).is_false()


func test_roulette_roster_lists_everyone_at_the_table() -> void:
	var roster: RouletteRoster = auto_free(RouletteRoster.new())
	var players: Array = [
		{"id": "a", "name": "Аня", "avatar": "me", "outfit": {}}, {"id": "b", "name": "Пётр", "avatar": "me", "outfit": {}},
		{"id": "c", "name": "Оля", "avatar": "me", "outfit": {}, "departed": true},
	]
	roster.set_state(players, {0: 60}, {}, false, false)
	assert_int(roster._row.get_child_count()).is_equal(2)
	assert_str(roster._amounts["a"].text).is_equal("60")
	assert_str(roster._amounts["b"].text).is_equal("—")
	roster.set_state(players, {0: 60}, {"a": 300, "b": -50}, true, false)
	assert_str(roster._amounts["a"].text).is_equal("+300")
	assert_str(roster._amounts["b"].text).is_equal("−50")


func test_blackjack_result_comes_from_the_server() -> void:
	var table: BlackjackTable = auto_free(BlackjackTable.new())
	var me: String = Backend.get_user_id()
	table.update_room({"phase": "finished", "players": [{"id": me, "cards": [9, 8]}], "outcomes": {me: "push"}, "winners": [me]})
	assert_str(table._outcome()).is_equal("push")
	table.update_room({"phase": "finished", "players": [{"id": me, "cards": [9, 8]}], "outcomes": {}})
	assert_str(table._outcome()).is_equal("lose")
