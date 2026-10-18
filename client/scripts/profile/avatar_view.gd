class_name AvatarView
extends Control
## Square profile picture: a template portrait on a coloured background or an uploaded picture.
## The player's own character ("me") repaints when the outfit changes.

const BORDER: int = 2

var avatar_id: String = ""
var user_id: String = ""
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

var _texture: Texture2D


func _init(side: float = 32.0) -> void:
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	Appearance.changed.connect(_on_appearance_changed)
	Backend.account.custom_avatar_loaded.connect(_on_custom_avatar_loaded)


func show_avatar(p_avatar_id: String, p_user_id: String = "") -> void:
	avatar_id = p_avatar_id
	user_id = p_user_id
	_texture = Backend.account.get_custom_avatar(user_id) if avatar_id == AvatarCatalog.CUSTOM else AvatarCatalog.template_texture(avatar_id)
	queue_redraw()


## A colleague's own character as the avatar, painted from their outfit.
func show_outfit(outfit: Dictionary, p_user_id: String = "") -> void:
	avatar_id = AvatarCatalog.DEFAULT + ":" + p_user_id
	user_id = p_user_id
	_texture = CharacterSprite.outfit_portrait(outfit)
	queue_redraw()


## Uploaded pictures are downloaded on first use; redraw when ours arrives.
func _on_custom_avatar_loaded(loaded_user_id: String) -> void:
	if avatar_id == AvatarCatalog.CUSTOM and loaded_user_id == user_id:
		show_avatar(avatar_id, user_id)


func _on_appearance_changed() -> void:
	if avatar_id == AvatarCatalog.DEFAULT:
		show_avatar(avatar_id, user_id)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var inner: Rect2 = rect.grow(-BORDER)
	draw_rect(inner, AvatarCatalog.background(avatar_id) if avatar_id != AvatarCatalog.CUSTOM else UiStyle.SHADE)
	if _texture != null:
		_draw_picture(inner)
	draw_rect(rect.grow(-BORDER / 2.0), UiStyle.RED if selected else UiStyle.INK, false, BORDER)


func _draw_picture(inner: Rect2) -> void:
	var texture_size: Vector2 = _texture.get_size()
	# Whole-pixel scaling keeps pixel art sharp; photos are scaled to fill.
	var scale_factor: float = minf(inner.size.x / texture_size.x, inner.size.y / texture_size.y)
	if avatar_id != AvatarCatalog.CUSTOM:
		scale_factor = maxf(1.0, floorf(scale_factor * 1.15))
	var drawn: Vector2 = texture_size * scale_factor
	var origin: Vector2 = (inner.position + Vector2((inner.size.x - drawn.x) / 2.0, inner.size.y - drawn.y)).round()
	var visible_part: Rect2 = Rect2(origin, drawn).intersection(inner)
	var source: Rect2 = Rect2((visible_part.position - origin) / scale_factor, visible_part.size / scale_factor)
	draw_texture_rect_region(_texture, visible_part, source)
