class_name CharacterSprite
extends Node2D
## Four-direction animated character with a soft ground shadow. Origin is at the feet.
## The "player" look is painted at runtime from the current outfit and repaints when it changes.

const PLAYER_ID: String = "player"
const FRAME: Vector2i = CharacterPainter.FRAME
const FEET_Y: int = CharacterPainter.BODY_OFFSET.y + 46
const SHADOW_COLOR: Color = Color(0.2, 0.12, 0.1, 0.28)
## Head-and-shoulders region inside a frame, for dialogue portraits.
const PORTRAIT_REGION: Rect2 = Rect2(CharacterPainter.BODY_OFFSET.x + 4, CharacterPainter.BODY_OFFSET.y, 24, 26)

static var _frames_cache: Dictionary[String, SpriteFrames] = {}
static var _player_frames: SpriteFrames
static var _player_sheet: Texture2D
## Sheets painted from colleagues' outfits, by Outfit.key().
static var _outfit_sheets: Dictionary[String, Texture2D] = {}

var facing: Vector2 = Vector2.DOWN
var bounce: float = 0.0

var _look_id: String = ""
var _sprite: AnimatedSprite2D
var _walking: bool = false
var _time: float = 0.0


func setup(look_id: String) -> void:
	_look_id = look_id
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = load_frames(look_id)
	_sprite.position = Vector2(0, FRAME.y / 2.0 - FEET_Y)
	add_child(_sprite)
	if look_id == PLAYER_ID:
		Appearance.changed.connect(_on_appearance_changed)
	_apply()


## A colleague's character, painted from the outfit they put together in their wardrobe.
func setup_outfit(outfit: Dictionary) -> void:
	_look_id = ""
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = outfit_frames(outfit)
	_sprite.position = Vector2(0, FRAME.y / 2.0 - FEET_Y)
	add_child(_sprite)
	_apply()


static func outfit_sheet(outfit: Dictionary) -> Texture2D:
	var key: String = Outfit.key(outfit)
	if not _outfit_sheets.has(key):
		var canvas: PixelCanvas = PixelCanvas.create(CharacterPainter.sheet_size())
		CharacterPainter.new(Outfit.to_look(outfit)).paint_sheet(canvas)
		_outfit_sheets[key] = ImageTexture.create_from_image(canvas.image)
	return _outfit_sheets[key]


static func outfit_frames(outfit: Dictionary) -> SpriteFrames:
	var key: String = "outfit|" + Outfit.key(outfit)
	if not _frames_cache.has(key):
		_frames_cache[key] = _build_frames(outfit_sheet(outfit))
	return _frames_cache[key]


## Head and shoulders of a colleague's character, for avatars.
static func outfit_portrait(outfit: Dictionary) -> AtlasTexture:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = outfit_sheet(outfit)
	atlas.region = PORTRAIT_REGION
	return atlas


func set_walking(walking: bool, direction: Vector2 = Vector2.ZERO) -> void:
	if direction.length_squared() > 0.0001:
		facing = direction
	_walking = walking
	_apply()


func face(direction: Vector2) -> void:
	set_walking(false, direction)


static func sheet_texture(look_id: String) -> Texture2D:
	if look_id == PLAYER_ID:
		return Appearance.get_sheet()
	return load("res://assets/characters/%s.png" % look_id)


static func portrait_texture(look_id: String) -> AtlasTexture:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet_texture(look_id)
	atlas.region = PORTRAIT_REGION
	return atlas


static func load_frames(look_id: String) -> SpriteFrames:
	if look_id == PLAYER_ID:
		var sheet: Texture2D = Appearance.get_sheet()
		if _player_frames == null or _player_sheet != sheet:
			_player_sheet = sheet
			_player_frames = _build_frames(sheet)
		return _player_frames
	if not _frames_cache.has(look_id):
		_frames_cache[look_id] = _build_frames(sheet_texture(look_id))
	return _frames_cache[look_id]


static func _build_frames(sheet: Texture2D) -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	for row: int in 3:
		var suffix: String = ["down", "up", "side"][row]
		var idle: StringName = StringName("idle_" + suffix)
		var walk: StringName = StringName("walk_" + suffix)
		frames.add_animation(idle)
		frames.add_animation(walk)
		frames.set_animation_speed(idle, 1.6)
		frames.set_animation_speed(walk, 9.0)
		for column: int in CharacterPainter.COLUMNS:
			var region: AtlasTexture = AtlasTexture.new()
			region.atlas = sheet
			region.region = Rect2(column * FRAME.x, row * FRAME.y, FRAME.x, FRAME.y)
			frames.add_frame(idle if column < 2 else walk, region)
	return frames


func _on_appearance_changed() -> void:
	var animation: StringName = _sprite.animation
	_sprite.sprite_frames = load_frames(_look_id)
	_sprite.play(animation)


func _process(delta: float) -> void:
	_time += delta
	if bounce > 0.0:
		_sprite.position.y = FRAME.y / 2.0 - FEET_Y - absf(sin(_time * 9.0)) * bounce
	else:
		_sprite.position.y = FRAME.y / 2.0 - FEET_Y


func _apply() -> void:
	if _sprite == null:
		return
	var suffix: String = "side"
	if absf(facing.y) > absf(facing.x):
		suffix = "down" if facing.y > 0.0 else "up"
	_sprite.flip_h = suffix == "side" and facing.x < 0.0
	var animation: StringName = StringName(("walk_" if _walking else "idle_") + suffix)
	if _sprite.animation != animation or not _sprite.is_playing():
		_sprite.play(animation)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 10.0, SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
