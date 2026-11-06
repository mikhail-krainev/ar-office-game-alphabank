class_name LocationLife
extends Node2D
## Life around the player at home and in the office: the street behind every window (WindowView),
## the hum of the city and the rain, neighbours talking behind the wall, colleagues' phones and
## printers, the player's footsteps and the sounds of what the character does at home (water in the
## sink, a frying pan, dishes). Sounds come from assets/audio (tools/generate_audio.gd).

enum Place { HOME, OFFICE }

const AUDIO_DIR: String = "res://assets/audio/"
const BUS: StringName = &"SFX"
const STEP_DISTANCE: float = 15.0
const STEP_DB: float = -15.0
const SOFT_STEP_DB: float = -22.0
const SOFT_FLOORS: Array[OfficeTiles.Style] = [
	OfficeTiles.Style.CARPET, OfficeTiles.Style.BEDROOM, OfficeTiles.Style.GRASS, OfficeTiles.Style.LOUNGE,
]
const EVENT_PAUSE_MIN: float = 4.0
const EVENT_PAUSE_MAX: float = 11.0
## Street sounds get this much louder next to a window.
const WINDOW_BOOST_DB: float = 9.0
const WINDOW_NEAR: float = 48.0
const WINDOW_FAR: float = 260.0
const DUCK_DB: float = -40.0
const DUCK_SPEED: float = 30.0
const POSITIONAL_RANGE: float = 220.0
const AMBULANCE_CHANCE: float = 0.7

## Remark id of a home object: [sound, seconds a loop plays (0: one-shot), volume dB].
const USE_SOUNDS: Dictionary[String, Array] = {
	"sink": ["water_loop", 2.5, -8.0], "bathtub": ["water_loop", 3.5, -6.0], "stove": ["sizzle_loop", 3.0, -8.0],
	"grill": ["sizzle_loop", 3.0, -6.0], "kettle": ["kettle", 0.0, -8.0], "fridge": ["clink", 0.0, -6.0],
	"table": ["dishes", 0.0, -7.0], "toilet": ["flush", 0.0, -6.0], "washing_machine": ["washer_loop", 4.0, -10.0],
	"laptop": ["typing", 0.0, -2.0], "wardrobe": ["rustle", 0.0, -6.0], "coats": ["rustle", 0.0, -8.0],
	"bed": ["rustle", 0.0, -9.0], "tv": ["tv_loop", 0.0, -10.0], "guitar": ["guitar", 0.0, -5.0],
	"bookshelf": ["page_flip", 0.0, -6.0], "dumbbells": ["clank", 0.0, -6.0], "trash": ["rustle", 0.0, -9.0],
	"keys": ["clink", 0.0, -10.0], "pizza": ["dishes", 0.0, -10.0],
}
## Props that sound all the time: [sound, volume dB].
const PROP_LOOPS: Dictionary[String, Array] = {
	"fridge": ["hum_loop", -22.0], "fireplace": ["fire_loop", -4.0], "aquarium": ["water_loop", -26.0],
	"server_rack": ["hum_loop", -14.0], "vending": ["hum_loop", -22.0],
}
const WASHER_RUNNING_CHANCE: float = 0.3

var place: Place = Place.HOME
var _map: WorldMap
var _player: Node2D
var _is_quiet: Callable
var _views: Array[WindowView] = []
var _window_points: Array[Vector2] = []
var _street_loops: Array[AudioStreamPlayer] = []
var _base_db: Dictionary[AudioStreamPlayer, float] = {}
var _ducked: float = 0.0
var _event_left: float = 3.0
var _last_step_position: Vector2 = Vector2.INF
var _walked: float = 0.0
var _streams: Dictionary[String, AudioStream] = {}


## `is_quiet` returns true while a panel or a minigame is open: the ambience fades down then.
func setup(map: WorldMap, player: Node2D, p_place: Place, is_quiet: Callable) -> void:
	_map = map
	_player = player
	place = p_place
	_is_quiet = is_quiet
	_add_window_views()
	_start_ambience()
	_start_prop_loops()


## The character uses a home object (`id` from home_remarks.json) standing at `at`.
func play_use(id: String, at: Vector2) -> void:
	var entry: Array = USE_SOUNDS.get(id, [])
	if entry.is_empty():
		return
	var player: AudioStreamPlayer2D = _play_at(entry[0], at, entry[2])
	if player != null and float(entry[1]) > 0.0:
		_loop_stream(player.stream)
		get_tree().create_timer(entry[1]).timeout.connect(_fade_out.bind(player))


func _process(delta: float) -> void:
	if _map == null:
		return
	var quiet: bool = _is_quiet.is_valid() and bool(_is_quiet.call())
	_ducked = move_toward(_ducked, DUCK_DB if quiet else 0.0, DUCK_SPEED * delta)
	var street_db: float = _window_boost()
	for player: AudioStreamPlayer in _base_db:
		var boost: float = street_db if _street_loops.has(player) else 0.0
		player.volume_db = _base_db[player] + boost + _ducked
	_update_steps(quiet)
	if quiet:
		return
	_event_left -= delta
	if _event_left <= 0.0:
		_event_left = randf_range(EVENT_PAUSE_MIN, EVENT_PAUSE_MAX)
		_play_event()


# --- Windows and ambience --------------------------------------------------------


func _add_window_views() -> void:
	for prop: MapLayout.Prop in _map.layout.props:
		if prop.id != "window" and prop.id != "window_small":
			continue
		var rect: Rect2 = _map.get_prop_rect(prop.id, prop.cell)
		if not rect.has_area():
			continue
		var origin: Vector2 = _map.to_local(rect.position)
		var view: WindowView = WindowView.new()
		view.setup(Rect2(origin + Vector2(3, 3), rect.size - Vector2(6, 10)), place == Place.OFFICE, hash(prop.cell), prop.id == "window")
		_map.add_overlay(view)
		_views.append(view)
		_window_points.append(rect.get_center())


func _start_ambience() -> void:
	var raining: bool = DayConditions.is_raining()
	_street_loops.append(_loop("street_loop", -24.0 if place == Place.HOME else -30.0))
	if raining:
		_street_loops.append(_loop("rain_loop", -24.0 if place == Place.HOME else -28.0))
	if place == Place.OFFICE:
		_loop("office_chatter_loop", -20.0)
		_loop("hum_loop", -30.0)


func _start_prop_loops() -> void:
	var washer_running: bool = randf() < WASHER_RUNNING_CHANCE
	for prop: MapLayout.Prop in _map.layout.props:
		var entry: Array = PROP_LOOPS.get(prop.id, [])
		if prop.id == "washing_machine" and washer_running:
			entry = ["washer_loop", -18.0]
		if entry.is_empty():
			continue
		var player: AudioStreamPlayer2D = _play_at(entry[0], _prop_center(prop), entry[1])
		if player != null:
			_loop_stream(player.stream)


## Louder street when the player stands by a window.
func _window_boost() -> float:
	if _window_points.is_empty() or _player == null:
		return 0.0
	var nearest: float = INF
	for point: Vector2 in _window_points:
		nearest = minf(nearest, point.distance_to(_player.global_position))
	return WINDOW_BOOST_DB * (1.0 - clampf(inverse_lerp(WINDOW_NEAR, WINDOW_FAR, nearest), 0.0, 1.0))


# --- Random events ---------------------------------------------------------------


func _play_event() -> void:
	var events: Array[Array] = _home_events() if place == Place.HOME else _office_events()
	var total: float = 0.0
	for event: Array in events:
		total += float(event[0])
	var pick: float = randf() * total
	for event: Array in events:
		pick -= float(event[0])
		if pick <= 0.0:
			(event[1] as Callable).call()
			return


## [weight, action] pairs for the apartment: neighbours, the stairwell and the street.
func _home_events() -> Array[Array]:
	var day: bool = not DayConditions.is_night()
	var events: Array[Array] = [
		[3.0, _sound.bind("neighbor_voice", -22.0, randf_range(0.85, 1.1))],
		[2.0, _sound.bind("neighbor_voice2", -22.0, randf_range(0.9, 1.1))],
		[1.0, _sound.bind("tv_loop", -26.0, 1.0)],
		[1.0, _sound.bind("laugh", -24.0, randf_range(0.85, 1.05))],
		[1.0, _sound.bind("dog_bark", -24.0, randf_range(0.9, 1.1))],
		[1.2, _sound.bind("door_slam", -22.0, randf_range(0.9, 1.1))],
		[1.5, _street.bind("horn" if randf() < 0.5 else "horn2", -26.0)],
		[0.8, _street.bind("tram_bell", -22.0)],
		[0.4, _siren],
	]
	if day:
		events.append([0.5, _sound.bind("drill", -24.0, 1.0)])
	if day and not DayConditions.is_raining():
		events.append([1.5, _street.bind("birds", -20.0)])
	if DayConditions.is_raining():
		events.append([0.5, _street.bind("thunder", -14.0)])
	return events


## [weight, action] pairs for the office: phones, keyboards, the printer, the coffee machine.
func _office_events() -> Array[Array]:
	return [
		[2.0, _at_prop.bind(["desk", "standing_desk", "design_desk"], "phone_ring", -10.0)],
		[3.0, _at_prop.bind(["desk", "standing_desk", "design_desk"], "typing", -4.0)],
		[1.0, _at_prop.bind(["printer"], "printer", -8.0)],
		[1.0, _at_prop.bind(["coffee_machine"], "coffee_machine", -8.0)],
		[1.0, _at_prop.bind(["counter_sink", "counter"], "dishes", -10.0)],
		[0.8, _at_prop.bind(["elevator"], "chime", -12.0)],
		[1.5, _sound.bind("laugh", -20.0, randf_range(0.9, 1.2))],
		[0.4, _siren],
		[0.5, _street.bind("horn2", -30.0)],
	]


func _siren() -> void:
	_street("siren", -22.0 if place == Place.HOME else -28.0)
	for view: WindowView in _views:
		if randf() < AMBULANCE_CHANCE:
			view.spawn_ambulance()


func _street(sound: String, volume_db: float) -> void:
	_sound(sound, volume_db + _window_boost(), randf_range(0.95, 1.05))


## A one-shot by a random prop of one of `prop_ids`; nothing when the floor has none.
func _at_prop(prop_ids: Array, sound: String, volume_db: float) -> void:
	var candidates: Array[MapLayout.Prop] = []
	for prop: MapLayout.Prop in _map.layout.props:
		if prop_ids.has(prop.id):
			candidates.append(prop)
	if not candidates.is_empty():
		_play_at(sound, _prop_center(candidates.pick_random()), volume_db, randf_range(0.95, 1.05))


# --- Footsteps -------------------------------------------------------------------


func _update_steps(quiet: bool) -> void:
	if _player == null:
		return
	var position_now: Vector2 = _player.global_position
	if _last_step_position == Vector2.INF:
		_last_step_position = position_now
	_walked += position_now.distance_to(_last_step_position)
	_last_step_position = position_now
	if _walked < STEP_DISTANCE:
		return
	_walked = 0.0
	if quiet:
		return
	var room: MapLayout.Room = _map.get_room_at(_map.world_to_cell(position_now))
	var soft: bool = room != null and SOFT_FLOORS.has(room.style)
	_sound("step", SOFT_STEP_DB if soft else STEP_DB, randf_range(0.85, 1.15) * (0.8 if soft else 1.0))


# --- Players ---------------------------------------------------------------------


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path: String = AUDIO_DIR + sound + ".wav"
		if not ResourceLoader.exists(path):
			push_warning("Missing sound " + path)
			return null
		_streams[sound] = load(path)
	return _streams[sound]


func _sound(sound: String, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = _stream(sound)
	if stream == null:
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _play_at(sound: String, at: Vector2, volume_db: float, pitch: float = 1.0) -> AudioStreamPlayer2D:
	var stream: AudioStream = _stream(sound)
	if stream == null:
		return null
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = POSITIONAL_RANGE
	player.attenuation = 1.5
	player.finished.connect(player.queue_free)
	add_child(player)
	player.global_position = at
	player.play()
	return player


## A non-positional ambience loop; its volume follows the window distance and the panels.
func _loop(sound: String, volume_db: float) -> AudioStreamPlayer:
	var stream: AudioStream = _stream(sound)
	if stream == null:
		return null
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = volume_db
	_loop_stream(stream)
	add_child(player)
	player.play(randf() * stream.get_length())
	_base_db[player] = volume_db
	return player


## Imported WAVs do not loop by themselves; this sets forward looping over the whole sound.
static func _loop_stream(stream: AudioStream) -> void:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null or wav.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * wav.mix_rate)


func _fade_out(player: AudioStreamPlayer2D) -> void:
	if not is_instance_valid(player):
		return
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", -60.0, 0.4)
	tween.tween_callback(player.queue_free)


func _prop_center(prop: MapLayout.Prop) -> Vector2:
	var area: Vector2 = Vector2(PropCatalog.footprint(prop.id) * MapLayout.TILE_SIZE)
	return _map.to_global(Vector2(prop.cell * MapLayout.TILE_SIZE) + area / 2.0)
