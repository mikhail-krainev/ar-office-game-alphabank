class_name CoopInvitePanel
extends ModalPanel
## Joint task: colleagues in the office now, one row each (avatar, name, "Invite"). The server sends
## the invitation to the colleague's inbox and opens the player's room for the task; "Go to the room"
## hands that room to the entertainment panel, where the game itself runs.

signal room_requested(room: Dictionary)

const AVATAR_SIDE: float = 28.0
const INVITE_WIDTH: float = 96.0

var _task: BackendModels.TaskInfo
var _room: Dictionary = {}
var _busy: bool = false
var _status: Label
var _open_room: Button


func _init() -> void:
	super("COOP_TITLE")


func open(task: BackendModels.TaskInfo) -> void:
	_task = task
	_room = {}
	show_panel()
	set_subtitle(task.title)
	clear()
	content.add_child(make_text(tr("COOP_HINT"), 10, UiStyle.MUTED))
	var loading: Label = make_text("…", 11)
	content.add_child(loading)
	var result: Dictionary = await Backend.lounge.coop_people(task.id)
	if not visible or _task != task:
		return
	loading.queue_free()
	if not result.get("ok", false):
		content.add_child(
			make_text(tr("ERROR_" + str(result.get("error", "")).to_upper()), 11, UiStyle.RED)
		)
		return
	_room = result.get("room", {}) if result.get("room") is Dictionary else {}
	var people: Array = result.get("people", []) if result.get("people") is Array else []
	if people.is_empty():
		content.add_child(make_text(tr("COOP_NOBODY"), 11))
	for person: Variant in people:
		if person is Dictionary:
			content.add_child(_make_row(person))
	_status = make_text("", 10, UiStyle.RED)
	content.add_child(_status)
	_open_room = UiStyle.make_button(tr("COOP_OPEN_ROOM"), true, 12)
	_open_room.custom_minimum_size.y = 36
	_open_room.disabled = _room.is_empty()
	_open_room.pressed.connect(_go_to_room)
	content.add_child(_open_room)


func _make_row(person: Dictionary) -> Control:
	var user_id: String = str(person.get("user_id", ""))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var avatar: AvatarView = AvatarView.new(AVATAR_SIDE)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	avatar.show_avatar(str(person.get("avatar", "")), user_id)
	var name_label: Label = UiStyle.make_label(str(person.get("name", "")), 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	row.add_child(name_label)
	var invite: Button = UiStyle.make_button(tr("COOP_INVITE"), true, 10)
	invite.custom_minimum_size = Vector2(INVITE_WIDTH, 30)
	invite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if person.get("joined", false):
		_mark(invite, "COOP_JOINED")
	elif person.get("invited", false):
		_mark(invite, "COOP_INVITED")
	invite.pressed.connect(_invite.bind(user_id, invite))
	row.add_child(invite)
	ColleagueProfiles.make_tappable(avatar, user_id)
	return row


func _invite(user_id: String, button: Button) -> void:
	if _busy:
		return
	_busy = true
	button.disabled = true
	var result: Dictionary = await Backend.lounge.invite(_task.id, user_id)
	_busy = false
	if not visible or not is_instance_valid(button):
		return
	if not result.get("ok", false):
		button.disabled = false
		_status.text = tr("ERROR_" + str(result.get("error", "")).to_upper())
		return
	_status.text = ""
	_mark(button, "COOP_INVITED")
	if result.get("room") is Dictionary:
		_room = result["room"]
	_open_room.disabled = _room.is_empty()


static func _mark(button: Button, key: String) -> void:
	button.text = TranslationServer.translate(key)
	button.disabled = true


func _go_to_room() -> void:
	if _room.is_empty():
		return
	close_panel()
	room_requested.emit(_room)
