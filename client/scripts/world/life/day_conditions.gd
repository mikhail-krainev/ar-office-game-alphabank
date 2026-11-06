class_name DayConditions
extends RefCounted
## Weather and daylight shared by the window views, the ambience and the commute scenes. The time
## of day is the phone's clock; the weather is picked once per date, so every scene of one day
## agrees whether it rains.

const RAIN_CHANCE: float = 0.35
const DAWN_HOUR: float = 6.5
const DUSK_HOUR: float = 19.5
## Sky gradient (top, bottom) at a few hours of the day; colours in between are blended.
const SKY_KEYS: Array[float] = [0.0, 5.5, 7.5, 12.0, 17.5, 20.0, 22.0, 24.0]
const SKY_TOPS: Array[Color] = [
	Color("#0b1026"), Color("#1d2147"), Color("#7fb6e6"), Color("#6fb0ea"), Color("#7fa6d8"), Color("#3a2f6a"),
	Color("#141a3a"), Color("#0b1026"),
]
const SKY_BOTTOMS: Array[Color] = [
	Color("#1d2147"), Color("#e89a6a"), Color("#f2d6b0"), Color("#d6ebf6"), Color("#f2c27a"), Color("#e0705a"),
	Color("#2a2a5a"), Color("#1d2147"),
]
const RAIN_TINT: Color = Color(0.62, 0.66, 0.72)

## Tests and the dev tour pin the conditions; a negative value means "use the clock".
static var forced_hour: float = -1.0
static var forced_rain: int = -1


## Local hour with minutes as a fraction, 0..24.
static func hour() -> float:
	if forced_hour >= 0.0:
		return forced_hour
	var now: Dictionary = Time.get_datetime_dict_from_system()
	return float(now.hour) + float(now.minute) / 60.0


static func is_night(at_hour: float = hour()) -> bool:
	return at_hour < DAWN_HOUR or at_hour >= DUSK_HOUR


static func is_raining() -> bool:
	if forced_rain >= 0:
		return forced_rain == 1
	return rain_on(Time.get_date_string_from_system())


## Whether it rains on `date` ("YYYY-MM-DD"): the same answer every time for one date.
static func rain_on(date: String) -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("rain:" + date)
	return rng.randf() < RAIN_CHANCE


## Sky gradient at `at_hour`: [top, bottom], greyed out in the rain.
static func sky(at_hour: float = hour(), raining: bool = is_raining()) -> Array[Color]:
	var index: int = 0
	while index < SKY_KEYS.size() - 2 and at_hour >= SKY_KEYS[index + 1]:
		index += 1
	var k: float = inverse_lerp(SKY_KEYS[index], SKY_KEYS[index + 1], clampf(at_hour, 0.0, 24.0))
	var top: Color = SKY_TOPS[index].lerp(SKY_TOPS[index + 1], k)
	var bottom: Color = SKY_BOTTOMS[index].lerp(SKY_BOTTOMS[index + 1], k)
	if raining:
		var grey: float = 0.55 if not is_night(at_hour) else 0.25
		top = top.lerp(Color(top.get_luminance(), top.get_luminance(), top.get_luminance()) * RAIN_TINT, grey)
		bottom = bottom.lerp(Color(bottom.get_luminance(), bottom.get_luminance(), bottom.get_luminance()) * RAIN_TINT, grey)
	return [top, bottom]


## 0 at noon, 1 deep at night: how dark the streets and buildings look.
static func darkness(at_hour: float = hour()) -> float:
	if at_hour >= DAWN_HOUR + 1.0 and at_hour <= DUSK_HOUR - 1.0:
		return 0.0
	if at_hour > DUSK_HOUR - 1.0:
		return clampf((at_hour - (DUSK_HOUR - 1.0)) / 2.0, 0.0, 1.0)
	return clampf(((DAWN_HOUR + 1.0) - at_hour) / 2.0, 0.0, 1.0)
