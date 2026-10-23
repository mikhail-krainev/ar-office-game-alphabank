class_name ColleagueWalker
extends Node2D
## Another player who is in the office now, on the office map: their own character in the outfit
## they put together, walking around by itself like the player's character. Above the head: a small
## round avatar and the name; a ring around the avatar when today's mood story exists. A tap on the
## character or the tag opens the mini profile (OfficeColleagues).

const SPEED: float = 40.0
const PAUSE_MIN: float = 3.0
const PAUSE_MAX: float = 9.0
const WANDER_RADIUS: int = 8
const WANDER_TRIES: int = 10
const HIT_RECT: Rect2 = Rect2(-14, -64, 28, 68)
const TAG_Y: float = -54.0
const AVATAR_RADIUS: float = 7.0
const NAME_SIZE: int = 10
const NAME_MAX: int = 14
const STORY_RING: Color = Color("#ff2e88")
## The name tag reacts to taps a little around it: a finger is wider than the 10 px text.
const TAG_TAP_MARGIN: float = 6.0

var player: BackendModels.OfficePlayer

var _map: WorldMap
var _body: CharacterSprite
var _portrait: Texture2D
var _path: PackedVector2Array = PackedVector2Array()
var _pause_left: float = 0.0
var _time: float = 0.0
## Room the colleague scanned last; walks stay inside it when it is on this floor.
var _home_room: MapLayout.Room


func setup(p_player: BackendModels.OfficePlayer, map: WorldMap, start_cell: Vector2i) -> void:
	_map = map
	name = "Colleague_" + p_player.colleague.user_id
	_body = CharacterSprite.new()
	add_child(_body)
	_body.setup_outfit(p_player.outfit)
	global_position = _map.cell_to_world(start_cell)
	_pause_left = randf_range(0.5, PAUSE_MAX)
	Backend.account.custom_avatar_loaded.connect(_on_custom_avatar_loaded)
	update_player(p_player)


## New data from the server (status, story, outfit) for the same colleague.
func update_player(p_player: BackendModels.OfficePlayer) -> void:
	if player != null and Outfit.key(player.outfit) != Outfit.key(p_player.outfit):
		_body.queue_free()
		_body = CharacterSprite.new()
		add_child(_body)
		_body.setup_outfit(p_player.outfit)
	player = p_player
	_home_room = (
		OfficeFloors.find_room(player.colleague.room)
		if player.colleague.floor_id == OfficeFloors.current
		else null
	)
	_portrait = _avatar_texture()
	queue_redraw()


func _on_custom_avatar_loaded(user_id: String) -> void:
	if player != null and user_id == player.colleague.user_id:
		_portrait = _avatar_texture()
		queue_redraw()


## The character or the name tag with the avatar.
func is_hit(world_position: Vector2) -> bool:
	var local: Vector2 = world_position - global_position
	return HIT_RECT.has_point(local) or _tag_rect().grow(TAG_TAP_MARGIN).has_point(local)


func _tag_text() -> String:
	var text: String = player.colleague.name
	return text.left(NAME_MAX - 1) + "…" if text.length() > NAME_MAX else text


## The avatar circle and the name above the head, centred on the character.
func _tag_rect() -> Rect2:
	var text_width: float = ThemeDB.fallback_font.get_string_size(_tag_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	var tag_width: float = AVATAR_RADIUS * 2.0 + 3.0 + text_width
	return Rect2(-tag_width / 2.0, TAG_Y - AVATAR_RADIUS, tag_width, AVATAR_RADIUS * 2.0)


func _avatar_texture() -> Texture2D:
	var colleague: BackendModels.Colleague = player.colleague
	if player.character_avatar:
		return CharacterSprite.outfit_portrait(player.outfit)
	if colleague.avatar == AvatarCatalog.CUSTOM:
		return Backend.account.get_custom_avatar(colleague.user_id)
	return AvatarCatalog.template_texture(colleague.avatar)


func _process(delta: float) -> void:
	_time += delta
	if player.has_mood:
		queue_redraw()
	if _path.is_empty():
		_body.set_walking(false)
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pick_walk()
		return
	var to_target: Vector2 = _path[0] - global_position
	var step: float = SPEED * delta
	if to_target.length() <= step:
		global_position = _path[0]
		_path.remove_at(0)
		if _path.is_empty():
			_pause_left = randf_range(PAUSE_MIN, PAUSE_MAX)
			_body.face(Vector2.from_angle(randf() * TAU))
	else:
		global_position += to_target.normalized() * step
		_body.set_walking(true, to_target)


func _pick_walk() -> void:
	_pause_left = randf_range(PAUSE_MIN, PAUSE_MAX)
	var origin: Vector2i = _map.world_to_cell(global_position)
	for i: int in WANDER_TRIES:
		var cell: Vector2i = (
			origin
			+ Vector2i(
				randi_range(-WANDER_RADIUS, WANDER_RADIUS),
				randi_range(-WANDER_RADIUS, WANDER_RADIUS)
			)
		)
		if not _map.is_walkable(cell):
			continue
		if _home_room != null and _map.get_room_at(cell) != _home_room:
			continue
		_path = _map.find_path(global_position, cell)
		if not _path.is_empty():
			return


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = _tag_text()
	var left: float = _tag_rect().position.x
	var center: Vector2 = Vector2(left + AVATAR_RADIUS, TAG_Y)
	if player.has_mood:
		# A story ring like in messengers, breathing to invite a tap.
		var glow: float = 0.6 + 0.4 * sin(_time * 4.0)
		draw_arc(center, AVATAR_RADIUS + 2.0, 0.0, TAU, 20, Color(STORY_RING, glow), 2.0)
	draw_circle(center, AVATAR_RADIUS + 0.5, UiStyle.INK)
	draw_circle(center, AVATAR_RADIUS - 0.5, AvatarCatalog.background(player.colleague.user_id))
	if _portrait != null:
		var side: float = AVATAR_RADIUS * 1.6
		draw_texture_rect(
			_portrait, Rect2(center - Vector2(side, side) / 2.0, Vector2(side, side)), false
		)
	var baseline: Vector2 = Vector2(
		left + AVATAR_RADIUS * 2.0 + 3.0, TAG_Y + font.get_ascent(NAME_SIZE) / 2.0 - 1.0
	)
	draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, 3, UiStyle.INK
	)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, Color.WHITE)
