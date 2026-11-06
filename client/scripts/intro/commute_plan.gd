class_name CommutePlan
extends RefCounted
## Picks the shots of a trip so the commute is not the same every day: the route (motorway, city
## traffic or both) and, most days, a stop on the way (coffee, the gas station, the grocery store,
## dinner out). The stop of the last trip is not repeated next time; it is kept in user://.

const STATE_PATH: String = "user://commute.cfg"
const STOP_CHANCE: float = 0.8
const NIGHT_MOTORWAY_CHANCE: float = 0.3


static func morning_stops() -> Array[Script]:
	return [CoffeeStopScene, GasStationScene, GroceryStopScene]


static func evening_stops() -> Array[Script]:
	return [RestaurantStopScene, GroceryStopScene, GasStationScene]


## Morning: out of the courtyard, the road and a stop in some order, the office entrance.
static func morning(rng: RandomNumberGenerator, last_stop: String = "") -> Array[Script]:
	var route: Array[Script] = []
	match rng.randi() % 3:
		0:
			route = [AutobahnScene, TrafficScene]
		1:
			route = [AutobahnScene]
		_:
			route = [TrafficScene]
	var stop: Script = _pick_stop(rng, morning_stops(), last_stop)
	if stop != null:
		route.insert(rng.randi_range(0, route.size()), stop)
	var shots: Array[Script] = [ParkingScene]
	shots.append_array(route)
	shots.append(ArrivalScene)
	return shots


## Evening: out of the office, the city lights (and sometimes the motorway) with a stop, home, sleep.
static func evening(rng: RandomNumberGenerator, last_stop: String = "") -> Array[Script]:
	var route: Array[Script] = [NightCityScene]
	if rng.randf() < NIGHT_MOTORWAY_CHANCE:
		route.append(AutobahnScene)
	var stop: Script = _pick_stop(rng, evening_stops(), last_stop)
	if stop != null:
		route.insert(rng.randi_range(0, route.size()), stop)
	var shots: Array[Script] = [LeaveOfficeScene]
	shots.append_array(route)
	shots.append_array([HomeArrivalScene, SleepScene])
	return shots


## The stop among `shots`, or "" for a trip without one.
static func stop_of(shots: Array[Script]) -> String:
	for shot: Script in shots:
		if morning_stops().has(shot) or evening_stops().has(shot):
			return shot.get_global_name()
	return ""


static func load_last_stop(direction: String) -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(STATE_PATH) != OK:
		return ""
	return str(config.get_value("last_stop", direction, ""))


static func save_last_stop(direction: String, stop: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(STATE_PATH)
	config.set_value("last_stop", direction, stop)
	var error: Error = config.save(STATE_PATH)
	if error != OK:
		push_warning("Could not save %s: %s" % [STATE_PATH, error_string(error)])


static func _pick_stop(rng: RandomNumberGenerator, stops: Array[Script], last_stop: String) -> Script:
	if rng.randf() >= STOP_CHANCE:
		return null
	var fresh: Array[Script] = []
	for stop: Script in stops:
		if stop.get_global_name() != last_stop:
			fresh.append(stop)
	if fresh.is_empty():
		fresh = stops
	return fresh[rng.randi() % fresh.size()]
