extends GdUnitTestSuite
## The trip planner varies the commute but keeps its frame, and the day's weather is stable.

const TRIPS: int = 200


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_morning_starts_in_the_courtyard_and_ends_at_the_office() -> void:
	var rng: RandomNumberGenerator = _rng(1)
	for i: int in TRIPS:
		var shots: Array[Script] = CommutePlan.morning(rng)
		assert_object(shots.front()).is_equal(ParkingScene)
		assert_object(shots.back()).is_equal(ArrivalScene)
		assert_int(shots.size()).is_between(3, 5)


func test_evening_ends_at_home_in_bed() -> void:
	var rng: RandomNumberGenerator = _rng(2)
	for i: int in TRIPS:
		var shots: Array[Script] = CommutePlan.evening(rng)
		assert_object(shots.front()).is_equal(LeaveOfficeScene)
		assert_array(shots.slice(shots.size() - 2)).is_equal([HomeArrivalScene, SleepScene])
		assert_bool(shots.has(NightCityScene)).is_true()


func test_trips_differ_and_every_stop_shows_up() -> void:
	var rng: RandomNumberGenerator = _rng(3)
	var routes: Dictionary[String, bool] = {}
	var stops: Dictionary[String, bool] = {}
	for i: int in TRIPS:
		var shots: Array[Script] = CommutePlan.morning(rng)
		routes[str(shots.map(func(shot: Script) -> String: return shot.get_global_name()))] = true
		stops[CommutePlan.stop_of(shots)] = true
	assert_int(routes.size()).is_greater(5)
	for stop: Script in CommutePlan.morning_stops():
		assert_bool(stops.has(stop.get_global_name())).override_failure_message(stop.get_global_name()).is_true()
	assert_bool(stops.has("")).override_failure_message("some trips go without a stop").is_true()


func test_the_last_stop_is_not_repeated() -> void:
	var rng: RandomNumberGenerator = _rng(4)
	for i: int in TRIPS:
		var shots: Array[Script] = CommutePlan.evening(rng, "RestaurantStopScene")
		assert_bool(shots.has(RestaurantStopScene)).is_false()


func test_rain_is_the_same_all_day() -> void:
	assert_bool(DayConditions.rain_on("2026-11-06")).is_equal(DayConditions.rain_on("2026-11-06"))
	var rainy: int = 0
	for day: int in range(1, 29):
		if DayConditions.rain_on("2026-02-%02d" % day):
			rainy += 1
	assert_int(rainy).is_between(2, 20)


func test_daylight_follows_the_hour() -> void:
	assert_float(DayConditions.darkness(12.0)).is_equal(0.0)
	assert_float(DayConditions.darkness(23.0)).is_equal(1.0)
	assert_bool(DayConditions.is_night(3.0)).is_true()
	assert_bool(DayConditions.is_night(13.0)).is_false()
	var noon: Array[Color] = DayConditions.sky(12.0, false)
	var night: Array[Color] = DayConditions.sky(23.5, false)
	assert_float(noon[0].get_luminance()).is_greater(night[0].get_luminance())
