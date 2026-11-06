class_name WindowView
extends Control
## The street behind a window, drawn over the glass of a window prop: the sky of the current hour,
## drifting clouds, the city with lights that go on and off, cars and buses, people walking (with
## umbrellas in the rain), birds by day and planes by night. `elevated` is an office window high
## above the street: the city fills the view and the traffic is small and far below.

const FPS: float = 15.0
const FRAME: Color = Color("#d9d4cc")
const SHEEN: Color = Color(1, 1, 1, 0.22)
const CAR_COLORS: Array[Color] = [
	Color("#ef3124"), Color("#f4f3ef"), Color("#3a3a44"), Color("#3a7bd5"), Color("#d9a43c"), Color("#8f949c"), Color("#4f9a4a"),
]
const COAT_COLORS: Array[Color] = [Color("#3a3a44"), Color("#6f8fb8"), Color("#c96a4a"), Color("#7a5234"), Color("#4f9a4a"), Color("#e8a0b0")]
const UMBRELLA_COLORS: Array[Color] = [Color("#ef3124"), Color("#3a3a44"), Color("#3a7bd5"), Color("#d9a43c")]
const LIT: Color = Color(1.0, 0.86, 0.5)
const HEADLIGHT: Color = Color(1.0, 0.95, 0.7)
const TAIL_LIGHT: Color = Color(1.0, 0.25, 0.2)
const CONDITIONS_REFRESH: float = 30.0
const MAX_CARS: int = 5
const MAX_PEOPLE: int = 4


## Something moving along the street: a car, a bus, an ambulance or a person.
class Mover:
	extends RefCounted

	var x: float
	var speed: float
	var y: float
	var length: float
	var color: Color
	var accent: Color
	var kind: StringName


var elevated: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hour: float = 12.0
var _raining: bool = false
var _darkness: float = 0.0
var _sky: Array[Color] = []
var _buildings: Array[Rect2] = []
var _lit_seed: int = 0
var _cars: Array[Mover] = []
var _people: Array[Mover] = []
var _clouds: Array[Vector2] = []
var _birds: Vector2 = Vector2(-100, 0)
var _plane: Vector2 = Vector2(-100, 0)
var _drops: Array[Vector2] = []
var _time: float = 0.0
var _redraw_left: float = 0.0
var _conditions_left: float = 0.0
var _spawn_left: float = 0.0
var _person_left: float = 0.0
var _mullion: bool = false


## `glass` is the glass area in the parent's coordinates; `seed_value` keeps one window's city
## the same between visits.
func setup(glass: Rect2, p_elevated: bool, seed_value: int, mullion: bool) -> void:
	position = glass.position
	size = glass.size
	elevated = p_elevated
	_mullion = mullion
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = seed_value
	_lit_seed = seed_value
	_refresh_conditions()
	_build_city()
	for i: int in 3:
		_clouds.append(Vector2(_rng.randf_range(0, size.x), _rng.randf_range(2, size.y * 0.3)))
	for i: int in 6:
		_drops.append(Vector2(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y)))
	for i: int in 2:
		_spawn_car(_rng.randf_range(0, size.x))
	_spawn_person(_rng.randf_range(0, size.x))


## An ambulance races past with its lights flashing (LocationLife plays the siren).
func spawn_ambulance() -> void:
	var car: Mover = _spawn_car(-1.0)
	if car != null:
		car.kind = &"ambulance"
		car.color = Color("#f4f3ef")
		car.speed = signf(car.speed) * _scaled(46.0)


func _process(delta: float) -> void:
	_time += delta
	_conditions_left -= delta
	if _conditions_left <= 0.0:
		_refresh_conditions()
	_move(delta)
	_redraw_left -= delta
	if _redraw_left <= 0.0 and _is_on_screen():
		_redraw_left = 1.0 / FPS
		queue_redraw()


func _refresh_conditions() -> void:
	_conditions_left = CONDITIONS_REFRESH
	_hour = DayConditions.hour()
	_raining = DayConditions.is_raining()
	_darkness = DayConditions.darkness(_hour)
	_sky = DayConditions.sky(_hour, _raining)


func _horizon() -> float:
	return roundf(size.y * (0.8 if elevated else 0.62))


func _scaled(value: float) -> float:
	return value * (0.45 if elevated else 1.0)


func _build_city() -> void:
	var x: float = -2.0
	var top: float = size.y * (0.15 if elevated else 0.3)
	while x < size.x:
		var width: float = _rng.randf_range(4, 10)
		var height: float = _rng.randf_range(top, _horizon() - 2.0)
		_buildings.append(Rect2(x, height, width, _horizon() - height))
		x += width + _rng.randf_range(0, 2)


func _spawn_car(at_x: float) -> Mover:
	if _cars.size() >= MAX_CARS:
		return null
	var car: Mover = Mover.new()
	var to_right: bool = _rng.randf() < 0.5
	var horizon: float = _horizon()
	car.kind = &"bus" if _rng.randf() < 0.12 else &"car"
	car.length = roundf(_scaled(16.0 if car.kind == &"bus" else _rng.randf_range(7, 9)))
	car.speed = _scaled(_rng.randf_range(14, 28)) * (1.0 if to_right else -1.0)
	car.y = horizon + (_scaled(4.0) if to_right else _scaled(7.0)) + 1.0
	car.x = at_x if at_x >= 0.0 else (-car.length if to_right else size.x)
	car.color = Color("#d9a43c") if car.kind == &"bus" else CAR_COLORS[_rng.randi() % CAR_COLORS.size()]
	_cars.append(car)
	return car


func _spawn_person(at_x: float) -> void:
	if elevated or _people.size() >= MAX_PEOPLE:
		return
	var person: Mover = Mover.new()
	var to_right: bool = _rng.randf() < 0.5
	person.kind = &"person"
	person.speed = _rng.randf_range(4, 7) * (1.0 if to_right else -1.0)
	person.y = size.y - 2.0 - _rng.randi_range(0, 2)
	person.x = at_x if at_x >= 0.0 else (-3.0 if to_right else size.x + 1.0)
	person.color = COAT_COLORS[_rng.randi() % COAT_COLORS.size()]
	person.accent = UMBRELLA_COLORS[_rng.randi() % UMBRELLA_COLORS.size()]
	_people.append(person)


func _move(delta: float) -> void:
	for movers: Array[Mover] in [_cars, _people]:
		for i: int in range(movers.size() - 1, -1, -1):
			var mover: Mover = movers[i]
			mover.x += mover.speed * delta
			if mover.x < -mover.length - 4.0 or mover.x > size.x + 4.0:
				movers.remove_at(i)
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left = _rng.randf_range(0.8, 3.5)
		_spawn_car(-1.0)
	_person_left -= delta
	if _person_left <= 0.0:
		_person_left = _rng.randf_range(2.0, 6.0)
		_spawn_person(-1.0)
	for i: int in _clouds.size():
		_clouds[i].x = fposmod(_clouds[i].x + delta * 1.2, size.x + 24.0)
	if _birds.x < -50.0 and not _raining and _darkness < 0.5 and _rng.randf() < delta / 20.0:
		_birds = Vector2(-8, _rng.randf_range(3, size.y * 0.3))
	elif _birds.x >= -50.0:
		_birds.x += delta * 9.0
		if _birds.x > size.x + 8.0:
			_birds.x = -100.0
	if _plane.x < -50.0 and _rng.randf() < delta / 30.0:
		_plane = Vector2(size.x + 2.0, _rng.randf_range(2, size.y * 0.2))
	elif _plane.x >= -50.0:
		_plane.x -= delta * 4.0
		if _plane.x < -4.0:
			_plane.x = -100.0
	if _raining:
		for i: int in _drops.size():
			_drops[i].y += delta * _rng.randf_range(1.0, 5.0)
			if _drops[i].y > size.y:
				_drops[i] = Vector2(_rng.randf_range(0, size.x), 0)


func _is_on_screen() -> bool:
	var view: Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	return view.intersects(get_global_rect())


func _draw() -> void:
	_draw_sky()
	_draw_city()
	_draw_street()
	_draw_weather()
	draw_line(Vector2(2, size.y - 3), Vector2(minf(size.x * 0.25, 10.0), 1), SHEEN)
	if _mullion:
		draw_rect(Rect2(floorf(size.x / 2.0), 0, 1, size.y), FRAME)


func _draw_sky() -> void:
	var bands: int = 6
	for i: int in bands:
		var y0: float = roundf(_horizon() * i / bands)
		var y1: float = roundf(_horizon() * (i + 1) / bands)
		draw_rect(Rect2(0, y0, size.x, y1 - y0), _sky[0].lerp(_sky[1], float(i) / (bands - 1)))
	var arc: float = clampf((_hour - 5.0) / 16.0, 0.0, 1.0)
	var orb: Vector2 = Vector2(roundf(size.x * (0.15 + 0.7 * arc)), roundf(size.y * 0.32 - sin(arc * PI) * size.y * 0.22))
	if not _raining:
		if _darkness > 0.5:
			draw_rect(Rect2(orb, Vector2(2, 2)), Color(0.95, 0.95, 0.85))
			for i: int in 5:
				var star: Vector2 = Vector2((i * 37 + _lit_seed) % int(size.x), (i * 13 + _lit_seed / 7) % int(maxf(_horizon() * 0.6, 1.0)))
				if fmod(_time * 0.7 + i, 3.0) > 0.4:
					draw_rect(Rect2(star, Vector2.ONE), Color(1, 1, 1, 0.6))
		else:
			draw_circle(orb + Vector2(1, 1), 2.5, Color(1.0, 0.95, 0.7, 0.9))
	var cloud_color: Color = Color(1, 1, 1, 0.75).lerp(Color(0.4, 0.42, 0.5, 0.6), maxf(_darkness, 0.6 if _raining else 0.0))
	for cloud: Vector2 in _clouds:
		var x: float = roundf(cloud.x - 12.0)
		draw_rect(Rect2(x, cloud.y, 9, 2), cloud_color)
		draw_rect(Rect2(x + 2, cloud.y - 1, 5, 1), cloud_color)
	if _birds.x >= -50.0:
		for i: int in 3:
			var bird: Vector2 = (_birds + Vector2(-i * 3, i * 2 - (i % 2) * 3)).round()
			var flap: float = 1.0 if fmod(_time * 6.0 + i, 2.0) < 1.0 else 0.0
			draw_rect(Rect2(bird + Vector2(-1, -flap), Vector2.ONE), Color(0.15, 0.15, 0.2))
			draw_rect(Rect2(bird, Vector2.ONE), Color(0.15, 0.15, 0.2))
			draw_rect(Rect2(bird + Vector2(1, -flap), Vector2.ONE), Color(0.15, 0.15, 0.2))
	if _plane.x >= -50.0:
		draw_rect(Rect2(_plane.round(), Vector2(3, 1)), Color(0.85, 0.87, 0.9) if _darkness < 0.5 else Color(0.2, 0.2, 0.3))
		if fmod(_time, 1.0) < 0.3:
			draw_rect(Rect2(_plane.round() + Vector2(1, 1), Vector2.ONE), TAIL_LIGHT)


func _draw_city() -> void:
	var wall: Color = Color("#b7c9d3").lerp(Color("#2a2f45"), _darkness)
	if _raining:
		wall = wall.lerp(Color("#8a929c"), 0.35)
	var minute: int = int(_time / 4.0)
	for i: int in _buildings.size():
		var building: Rect2 = _buildings[i]
		draw_rect(building, wall if i % 2 == 0 else wall.darkened(0.08))
		for wy: int in range(int(building.position.y) + 2, int(_horizon()) - 1, 3):
			for wx: int in range(int(building.position.x) + 1, int(building.end.x) - 1, 3):
				var cell_hash: int = absi(hash(Vector3i(wx, wy, _lit_seed + (minute if (wx + wy) % 7 == 0 else 0))))
				if _darkness > 0.3 and cell_hash % 3 == 0:
					draw_rect(Rect2(wx, wy, 1, 1), Color(LIT, 0.55 + 0.4 * _darkness))
				elif _darkness <= 0.3 and cell_hash % 4 == 0:
					draw_rect(Rect2(wx, wy, 1, 1), Color(1, 1, 1, 0.35))


func _draw_street() -> void:
	var horizon: float = _horizon()
	var dim: float = 1.0 - 0.6 * _darkness
	var road: Color = Color("#5a5d64") * Color(dim, dim, dim)
	draw_rect(Rect2(0, horizon, size.x, size.y - horizon), Color("#c9c4bc") * Color(dim, dim, dim))
	var road_height: float = roundf(_scaled(10.0))
	draw_rect(Rect2(0, horizon + 1, size.x, road_height), road)
	if _raining:
		draw_rect(Rect2(0, horizon + 1, size.x, 1), Color(0.8, 0.85, 0.9, 0.3))
	for dash: int in range(1, int(size.x), 6):
		draw_rect(Rect2(dash, horizon + 1 + roundf(road_height / 2.0), 3, 1), Color(1, 1, 1, 0.5 * dim))
	for car: Mover in _cars:
		_draw_car(car)
	for person: Mover in _people:
		_draw_person(person)
	if not elevated and _darkness > 0.3:
		var lamp_x: float = roundf(size.x * 0.7)
		draw_rect(Rect2(lamp_x, horizon - 8, 1, size.y), Color("#3a3f46"))
		draw_circle(Vector2(lamp_x, horizon - 8), 4.0, Color(LIT, 0.25 * _darkness))
		draw_rect(Rect2(lamp_x - 1, horizon - 8, 2, 1), LIT)


func _draw_car(car: Mover) -> void:
	var x: float = roundf(car.x)
	var height: float = maxf(1.0, roundf(_scaled(car.length * (0.45 if car.kind == &"bus" else 0.35))))
	var body: Rect2 = Rect2(x, car.y - height, car.length, height)
	draw_rect(body, car.color.darkened(0.5 * _darkness))
	if not elevated:
		draw_rect(Rect2(x + 1, car.y - height, car.length - 2, 1), Color(0.6, 0.8, 0.95).darkened(0.4 * _darkness))
		draw_rect(Rect2(x + 1, car.y, 1, 1), Color.BLACK)
		draw_rect(Rect2(x + car.length - 2, car.y, 1, 1), Color.BLACK)
	var front: float = body.end.x if car.speed > 0.0 else x - 1.0
	var back: float = x - 1.0 if car.speed > 0.0 else body.end.x
	if _darkness > 0.3 or _raining:
		draw_rect(Rect2(front, car.y - 1, 1, 1), HEADLIGHT)
		draw_rect(Rect2(back, car.y - 1, 1, 1), TAIL_LIGHT)
		if not elevated:
			draw_rect(Rect2(front + (1.0 if car.speed > 0.0 else -4.0), car.y - 1, 4, 1), Color(HEADLIGHT, 0.3))
	if car.kind == &"ambulance":
		var flash: bool = fmod(_time * 6.0, 2.0) < 1.0
		draw_rect(Rect2(x + 2, car.y - height - 1, 2, 1), Color("#ff2a2a") if flash else Color("#2a6aff"))
		draw_rect(Rect2(x + car.length / 2.0 - 1, car.y - height + 1, 2, 1), Color("#ef3124"))


func _draw_person(person: Mover) -> void:
	var x: float = roundf(person.x)
	var y: float = person.y
	var dim: Color = Color(1, 1, 1).darkened(0.5 * _darkness)
	var step: bool = fmod(_time * 4.0 + person.x, 2.0) < 1.0
	draw_rect(Rect2(x, y - 1, 1, 1), Color("#2a2a33") * dim)
	draw_rect(Rect2(x + (1 if step else 0), y, 1, 1), Color("#2a2a33") * dim)
	draw_rect(Rect2(x, y - 4, 2, 3), person.color * dim)
	draw_rect(Rect2(x, y - 5, 2, 1), Palette.SKIN_TONES[absi(int(person.speed * 10.0)) % 4] * dim)
	if _raining:
		draw_rect(Rect2(x - 1, y - 7, 4, 1), person.accent * dim)
		draw_rect(Rect2(x, y - 8, 2, 1), person.accent * dim)


func _draw_weather() -> void:
	if not _raining:
		return
	var streak: Color = Color(0.8, 0.86, 0.95, 0.45)
	for i: int in 14:
		var x: float = fposmod(i * 7.3 + _time * 30.0, size.x + 6.0) - 3.0
		var y: float = fposmod(i * 11.7 + _time * 70.0, size.y + 6.0) - 3.0
		draw_line(Vector2(roundf(x), roundf(y)), Vector2(roundf(x) - 1, roundf(y) + 3), streak)
	for drop: Vector2 in _drops:
		draw_rect(Rect2(drop.round(), Vector2(1, 2)), Color(0.9, 0.95, 1.0, 0.55))
