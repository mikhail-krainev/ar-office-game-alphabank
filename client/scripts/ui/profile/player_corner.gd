class_name PlayerCorner
extends Node
## Inbox bell with an unread badge and the player's avatar in the HUD corner. The avatar opens the
## profile page, the bell opens the inbox. Adds both panels to the scene it is attached to.

const BUTTON_SIDE: float = 30.0

var _inbox: InboxPanel
var _lounge: LoungePanel
var _profile: ProfilePanel
var _bell: Button
var _badge: Label
var _avatar: AvatarView


## Builds the corner buttons in `hud` and the panels under `scene`.
static func attach(scene: Node, hud: Hud) -> PlayerCorner:
	var corner: PlayerCorner = PlayerCorner.new()
	corner.name = "PlayerCorner"
	scene.add_child(corner)
	corner._build(scene, hud)
	return corner


func is_open() -> bool:
	return _inbox.is_open() or _profile.is_open() or _lounge.is_open()


func open_inbox() -> void:
	if not is_open():
		_inbox.open()


func open_profile() -> void:
	if not is_open():
		_profile.open()


func _build(scene: Node, hud: Hud) -> void:
	_lounge = LoungePanel.new()
	scene.add_child(_lounge)
	var games: Button = UiStyle.make_button("Игры", false, 10)
	games.custom_minimum_size = Vector2(40, BUTTON_SIDE)
	games.pressed.connect(func() -> void: if not is_open(): _lounge.open())
	hud.add_corner(games)
	_inbox = InboxPanel.new()
	_inbox.name = "InboxPanel"
	scene.add_child(_inbox)
	_profile = ProfilePanel.new()
	_profile.name = "ProfilePanel"
	scene.add_child(_profile)

	_bell = UiStyle.make_button("", false, 11)
	_bell.custom_minimum_size = Vector2(BUTTON_SIDE, BUTTON_SIDE)
	_bell.tooltip_text = tr("INBOX_TITLE")
	_bell.pressed.connect(open_inbox)
	var icon: Control = Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.draw.connect(_draw_bell.bind(icon))
	_bell.add_child(icon)
	_badge = UiStyle.make_label("", 8, Color.WHITE)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.position = Vector2(BUTTON_SIDE - 12.0, -4.0)
	_badge.size = Vector2(14, 12)
	_badge.visible = false
	var badge_back: StyleBoxFlat = UiStyle.panel(UiStyle.RED, 6, 0)
	_badge.add_theme_stylebox_override("normal", badge_back)
	_bell.add_child(_badge)
	hud.add_corner(_bell)

	var avatar_button: Button = UiStyle.make_button("", false, 11)
	avatar_button.custom_minimum_size = Vector2(BUTTON_SIDE, BUTTON_SIDE)
	avatar_button.tooltip_text = tr("PROFILE_TITLE")
	avatar_button.pressed.connect(open_profile)
	for state: String in ["normal", "hover", "pressed"]:
		avatar_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_avatar = AvatarView.new(BUTTON_SIDE)
	avatar_button.add_child(_avatar)
	hud.add_corner(avatar_button)

	Notifications.unread_changed.connect(_on_unread_changed)
	_on_unread_changed(Notifications.unread)
	Backend.profile_changed.connect(_on_profile_changed)
	if Backend.profile != null:
		_on_profile_changed(Backend.profile)


func _on_unread_changed(count: int) -> void:
	_badge.visible = count > 0
	_badge.text = str(count) if count < 10 else "9+"


func _on_profile_changed(profile: BackendModels.Profile) -> void:
	_avatar.show_avatar(profile.avatar, profile.user_id)


## 12x13 pixel bell centred in the button.
func _draw_bell(icon: Control) -> void:
	var origin: Vector2 = ((icon.size - Vector2(12, 13)) / 2.0).round()
	var ink: Color = UiStyle.INK
	var r: Callable = func(x: float, y: float, w: float, h: float) -> void:
		icon.draw_rect(Rect2(origin + Vector2(x, y), Vector2(w, h)), ink)
	r.call(5, 0, 2, 1)
	r.call(3, 1, 6, 1)
	r.call(2, 2, 8, 6)
	r.call(1, 8, 10, 1)
	r.call(0, 9, 12, 2)
	r.call(5, 11, 2, 2)
	icon.draw_rect(Rect2(origin + Vector2(3, 3), Vector2(1, 4)), Color(1, 1, 1, 0.5))
