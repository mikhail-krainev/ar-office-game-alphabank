extends GdUnitTestSuite
## Texts and locks of the working-time limits: durations, countdowns and the task schedule.


func before() -> void:
	TranslationServer.set_locale("ru")


func test_minutes_in_words() -> void:
	assert_str(TimeText.minutes(60)).is_equal("1 час")
	assert_str(TimeText.minutes(60, true)).is_equal("1 часа")
	assert_str(TimeText.minutes(120, true)).is_equal("2 часов")
	assert_str(TimeText.minutes(30)).is_equal("30 минут")
	assert_str(TimeText.minutes(21)).is_equal("21 минуту")
	assert_str(TimeText.minutes(3)).is_equal("3 минуты")
	assert_str(TimeText.minutes(90)).is_equal("1 ч 30 мин")


func test_countdowns() -> void:
	assert_str(TimeText.countdown(299)).is_equal("04:59")
	assert_str(TimeText.countdown(0)).is_equal("00:00")
	assert_str(TimeText.countdown(-5)).is_equal("00:00")
	assert_str(TimeText.countdown(3725)).is_equal("1:02:05")
	assert_str(TimeText.short_minutes(61)).is_equal("2 мин")


func test_schedule_locks() -> void:
	var schedule: BackendModels.TaskSchedule = BackendParser.task_schedule(
		{
			"cooldown_minutes": 30,
			"next_task_in": 600,
			"window_start": "08:00",
			"window_end": "20:00",
			"in_window": true
		}
	)
	assert_str(schedule.lock_reason()).is_equal("task_cooldown")
	assert_int(schedule.cooldown_left()).is_between(599, 600)
	schedule.next_task_in = 0
	assert_str(schedule.lock_reason()).is_equal("")
	schedule.in_window = false
	assert_str(schedule.lock_reason()).is_equal("outside_task_window")
	# An old server without a schedule never locks the tasks.
	assert_str(BackendParser.task_schedule(null).lock_reason()).is_equal("")


func test_play_status() -> void:
	var status: BackendModels.PlayStatus = BackendParser.play_status(
		{"state": "resting", "seconds_left": 120, "rest_minutes": 30}, ""
	)
	assert_bool(status.ok).is_true()
	assert_int(status.state).is_equal(BackendModels.PlayStatus.State.RESTING)
	assert_int(status.seconds_left).is_equal(120)
	assert_bool(BackendParser.play_status({}, "network").ok).is_false()
