class_name ColleagueProfilePanel
extends ModalPanel
## Mini profile of a colleague tapped on the office map: their avatar and character, name,
## department, status and streak, and today's "Mood of the day" story when there is one. The story
## plays like in messengers: full width, a bar runs out, then the profile comes back.

const AVATAR_SIDE: float = 56.0
const STORY_SECONDS: float = 5.0
const STORY_SIDE: float = 192.0
## The colleague's character next to the avatar, in whole pixels.
const FIGURE_SCALE: float = 1.5

var _player: BackendModels.OfficePlayer
var _story_bar: ProgressBar
var _story_left: float = 0.0


func _init() -> void:
	super("COLLEAGUE_PROFILE_TITLE")


func open(player: BackendModels.OfficePlayer) -> void:
	_player = player
	show_panel()
	set_title(player.colleague.name)
	set_subtitle(NotificationTexts.department(player.colleague.department))
	_show_profile()


func _show_profile() -> void:
	clear()
	_story_left = 0.0
	var colleague: BackendModels.Colleague = _player.colleague
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var avatar: AvatarView = AvatarView.new(AVATAR_SIDE)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(avatar)
	if _player.character_avatar:
		avatar.show_outfit(_player.outfit, colleague.user_id)
	else:
		avatar.show_avatar(colleague.avatar, colleague.user_id)
	var figure: TextureRect = TextureRect.new()
	figure.texture = _figure_texture()
	figure.custom_minimum_size = Vector2(CharacterSprite.FRAME) * FIGURE_SCALE
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(figure)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	column.add_child(UiStyle.make_label(tr("COLLEAGUE_STREAK") % _player.streak, 13, UiStyle.RED))
	if not colleague.status.is_empty():
		var status: Label = make_text(
			"«%s»" % colleague.status, 10, UiStyle.MUTED, content_width - AVATAR_SIDE - 90.0
		)
		column.add_child(status)
	var room: MapLayout.Room = OfficeFloors.find_room(colleague.room)
	if room != null:
		column.add_child(
			UiStyle.make_label(tr("COLLEAGUE_SEEN_IN") % tr(room.name_key), 9, UiStyle.MUTED)
		)
	if _player.has_mood:
		var story: Button = UiStyle.make_button(tr("COLLEAGUE_WATCH_STORY"), true, 12)
		story.custom_minimum_size = Vector2(0, 34)
		story.pressed.connect(_show_story)
		content.add_child(story)
	else:
		content.add_child(make_text(tr("COLLEAGUE_NO_STORY"), 10, UiStyle.MUTED))


## The front frame of the colleague's character, as they dressed it.
func _figure_texture() -> Texture2D:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = CharacterSprite.outfit_sheet(_player.outfit)
	atlas.region = Rect2(Vector2.ZERO, Vector2(CharacterSprite.FRAME))
	return atlas


func _show_story() -> void:
	clear()
	content.add_child(make_text(tr("COLLEAGUE_STORY_LOADING"), 11, UiStyle.MUTED))
	var mood: Image = await Backend.social.get_mood(_player.colleague.user_id)
	if not visible:
		return
	clear()
	if mood == null:
		content.add_child(make_text(tr("COLLEAGUE_STORY_GONE"), 11, UiStyle.MUTED))
		return
	_story_bar = ProgressBar.new()
	_story_bar.show_percentage = false
	_story_bar.custom_minimum_size = Vector2(0, 4)
	_story_bar.max_value = STORY_SECONDS
	_story_bar.value = STORY_SECONDS
	content.add_child(_story_bar)
	content.add_child(
		UiStyle.make_label(tr("COLLEAGUE_STORY_TITLE") % _player.colleague.name, 11, UiStyle.MUTED)
	)
	var picture: TextureRect = TextureRect.new()
	picture.texture = ImageTexture.create_from_image(mood)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.custom_minimum_size = Vector2(STORY_SIDE, STORY_SIDE)
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_STOP
	picture.gui_input.connect(
		func(event: InputEvent) -> void:
			if Minigame.press_position(event) != null:
				_show_profile()
	)
	content.add_child(picture)
	_story_left = STORY_SECONDS


func _process(delta: float) -> void:
	if _story_left <= 0.0 or not visible:
		return
	_story_left -= delta
	if is_instance_valid(_story_bar):
		_story_bar.value = _story_left
	if _story_left <= 0.0:
		_show_profile()
