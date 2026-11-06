class_name ChatPanel
extends ModalPanel
## Colleagues in the office now and the chats: the office chat, the department chat and direct
## messages. The list shows who scanned the entry code and is still in the office (a tap opens the
## mini profile, the envelope a direct chat) and every chat with its unread count. A chat shows the
## messages of the last week with an input at the bottom; the panel asks the server for new messages
## every few seconds while it is open (there is no realtime socket: all chat goes through RPCs).

const LIST_REFRESH_SECONDS: float = 10.0
const CHAT_REFRESH_SECONDS: float = 3.0
const AVATAR_SIDE: float = 28.0
const PREVIEW_LENGTH: int = 40
const INPUT_HEIGHT: float = 34.0
const MINE_COLOR: Color = Color("#ffe6e3")
const UNREAD_COLOR: Color = Color("#fff3ea")

## The chat on screen; empty `_kind` = the list.
var _kind: String = ""
var _user_id: String = ""
var _chat_name: String = ""
var _refresh_left: float = 0.0
var _loading: bool = false
var _sending: bool = false
var _last_message_id: String = ""
var _footer: VBoxContainer
var _input: LineEdit
## A refused message (too fast, too long, no office Wi-Fi) under the input.
var _status: Label
var _back: Button


func _init() -> void:
	super("CHAT_TITLE")
	_back = UiStyle.make_button("←", false, 14)
	_back.custom_minimum_size = Vector2(34, 30)
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(open)
	add_header_control(_back)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 2)
	_status = UiStyle.make_label("", 9, UiStyle.RED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	_footer.add_child(_status)
	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	_footer.add_child(input_row)
	_input = LineEdit.new()
	_input.max_length = BackendChat.MAX_TEXT
	_input.placeholder_text = TranslationServer.translate("CHAT_PLACEHOLDER")
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, INPUT_HEIGHT)
	_input.add_theme_font_size_override("font_size", 11)
	_input.text_submitted.connect(func(_text: String) -> void: _send())
	input_row.add_child(_input)
	var send: Button = UiStyle.make_button(TranslationServer.translate("CHAT_SEND"), true, 11)
	send.custom_minimum_size = Vector2(0, INPUT_HEIGHT)
	send.pressed.connect(_send)
	input_row.add_child(send)
	add_footer(_footer)


## The list of colleagues and chats.
func open() -> void:
	_kind = ""
	_user_id = ""
	_input.release_focus()
	show_panel()
	_show_chrome()
	await _reload()


## A direct chat with a colleague (the envelope in the list or the colleague's mini profile).
func open_direct(user_id: String, colleague_name: String) -> void:
	_open_chat(BackendChat.DIRECT, user_id, colleague_name)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0 and not _loading:
		_reload()


func _open_chat(kind: String, user_id: String, chat_name: String) -> void:
	_kind = kind
	_user_id = user_id
	_chat_name = chat_name
	_last_message_id = ""
	show_panel(INPUT_HEIGHT + 6.0)
	_show_chrome()
	content.add_child(make_text(tr("CHAT_LOADING"), 11, UiStyle.MUTED))
	await _reload()


## Title, back button and input for the current view.
func _show_chrome() -> void:
	var in_chat: bool = not _kind.is_empty()
	_back.visible = in_chat
	_footer.visible = in_chat
	_status.visible = false
	set_title(_chat_name if in_chat else tr("CHAT_TITLE"))
	set_subtitle(tr("CHAT_KIND_" + _kind.to_upper()) if in_chat else tr("CHAT_SUBTITLE"))


func _reload() -> void:
	_loading = true
	if _kind.is_empty():
		_refresh_left = LIST_REFRESH_SECONDS
		await _reload_list()
	else:
		_refresh_left = CHAT_REFRESH_SECONDS
		await _reload_chat()
	_loading = false


# --- The list ----------------------------------------------------------------------


func _reload_list() -> void:
	var overview: BackendChat.Overview = await Backend.chat.overview()
	var players: Array[BackendModels.OfficePlayer] = await Backend.social.office_players()
	if not visible or not _kind.is_empty():
		return
	clear()
	if not overview.ok:
		content.add_child(make_text(_error_text(overview.error), 11, UiStyle.RED))
		return
	content.add_child(UiStyle.make_label(tr("CHAT_CHATS"), 12, UiStyle.MUTED))
	for channel: BackendChat.Channel in [overview.office, overview.department]:
		if channel != null:
			content.add_child(_make_channel_row(channel))
	for channel: BackendChat.Channel in overview.direct:
		content.add_child(_make_channel_row(channel))
	content.add_child(UiStyle.make_label(tr("CHAT_IN_OFFICE") % players.size(), 12, UiStyle.MUTED))
	if players.is_empty():
		content.add_child(make_text(tr("CHAT_NOBODY_HERE"), 10, UiStyle.MUTED))
	for player: BackendModels.OfficePlayer in players:
		content.add_child(_make_colleague_row(player))


func _make_channel_row(channel: BackendChat.Channel) -> Control:
	var card: PanelContainer = make_card(
		UNREAD_COLOR if channel.unread > 0 else UiStyle.SHADE, UiStyle.RED if channel.unread > 0 else Color.TRANSPARENT
	)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)
	if channel.kind == BackendChat.DIRECT:
		var avatar: AvatarView = AvatarView.new(AVATAR_SIDE)
		avatar.show_avatar(channel.avatar, channel.user_id)
		row.add_child(avatar)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var title: String = (
		channel.name
		if channel.kind == BackendChat.DIRECT
		else "%s · %s" % [tr("CHAT_KIND_" + channel.kind.to_upper()), channel.name]
	)
	column.add_child(UiStyle.make_label(title, 11))
	column.add_child(UiStyle.make_label(_preview(channel.last), 9, UiStyle.MUTED))
	if channel.unread > 0:
		row.add_child(UiStyle.make_label(str(channel.unread), 12, UiStyle.RED))
	var chat_name: String = channel.name
	_make_pressable(
		card,
		func() -> void:
			Backend.chat.mark_seen(channel.unread)
			_open_chat(channel.kind, channel.user_id, chat_name)
	)
	return card


func _preview(message: BackendChat.Message) -> String:
	if message == null:
		return tr("CHAT_NO_MESSAGES")
	var author: String = tr("CHAT_ME") if message.mine else message.name
	var text: String = (
		message.text if message.text.length() <= PREVIEW_LENGTH else message.text.left(PREVIEW_LENGTH - 1) + "…"
	)
	return "%s: %s" % [author, text]


func _make_colleague_row(player: BackendModels.OfficePlayer) -> Control:
	var colleague: BackendModels.Colleague = player.colleague
	var card: PanelContainer = make_card()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)
	var avatar: AvatarView = AvatarView.new(AVATAR_SIDE)
	if player.character_avatar:
		avatar.show_outfit(player.outfit, colleague.user_id)
	else:
		avatar.show_avatar(colleague.avatar, colleague.user_id)
	row.add_child(avatar)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	column.add_child(UiStyle.make_label(colleague.name, 11))
	var details: String = NotificationTexts.department(colleague.department)
	var room: MapLayout.Room = OfficeFloors.find_room(colleague.room)
	if room != null:
		details += " · " + tr(room.name_key)
	column.add_child(UiStyle.make_label(details, 9, UiStyle.MUTED))
	ColleagueProfiles.make_tappable(column, colleague.user_id)
	ColleagueProfiles.make_tappable(avatar, colleague.user_id)
	var write: Button = UiStyle.make_button("✉", false, 13)
	write.custom_minimum_size = Vector2(34, 28)
	write.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	write.pressed.connect(open_direct.bind(colleague.user_id, colleague.name))
	row.add_child(write)
	return card


## A tap (not a drag of the list) on `control` runs `action`.
func _make_pressable(control: Control, action: Callable) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	var pressed_at: Array[Vector2] = []
	control.gui_input.connect(
		func(event: InputEvent) -> void:
			var press: Variant = Minigame.press_position(event)
			if press != null:
				pressed_at.assign([press as Vector2])
			elif Minigame.is_release(event) and not pressed_at.is_empty():
				var mouse: InputEventMouseButton = event as InputEventMouseButton
				if mouse != null and mouse.position.distance_to(pressed_at[0]) <= ColleagueProfiles.TAP_SLOP:
					action.call()
				pressed_at.clear()
	)


# --- A chat -------------------------------------------------------------------------


func _reload_chat() -> void:
	var kind: String = _kind
	var user_id: String = _user_id
	var history: BackendChat.History = await Backend.chat.history(kind, user_id)
	if not visible or kind != _kind or user_id != _user_id:
		return
	if not history.ok:
		clear()
		content.add_child(make_text(_error_text(history.error), 11, UiStyle.RED))
		return
	var newest: String = history.messages[-1].id if not history.messages.is_empty() else "-"
	if newest == _last_message_id:
		return
	var follow: bool = _last_message_id.is_empty() or is_scrolled_to_end()
	_last_message_id = newest
	_show_messages(history.messages)
	if follow:
		scroll_to_end()


func _show_messages(messages: Array[BackendChat.Message]) -> void:
	clear()
	if messages.is_empty():
		content.add_child(make_text(tr("CHAT_EMPTY"), 10, UiStyle.MUTED))
	for message: BackendChat.Message in messages:
		content.add_child(_make_message(message))


func _make_message(message: BackendChat.Message) -> Control:
	var card: PanelContainer = make_card(MINE_COLOR if message.mine else UiStyle.SHADE)
	card.size_flags_horizontal = Control.SIZE_SHRINK_END if message.mine else Control.SIZE_SHRINK_BEGIN
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	card.add_child(column)
	var header: String = WorkCalendar.stamp(message.at)
	if not message.mine and _kind != BackendChat.DIRECT:
		header = "%s · %s" % [message.name, header]
	var meta: Label = UiStyle.make_label(header, 8, UiStyle.MUTED)
	column.add_child(meta)
	if not message.mine:
		ColleagueProfiles.make_tappable(meta, message.sender_id)
	column.add_child(make_text(message.text, 11, UiStyle.INK, content_width * 0.8))
	return card


func _send() -> void:
	var text: String = _input.text.strip_edges()
	if text.is_empty() or _sending or _kind.is_empty():
		return
	_sending = true
	var sent: BackendChat.Sent = await Backend.chat.send(_kind, _user_id, text)
	_sending = false
	_status.text = _error_text(sent.error) if not sent.ok else ""
	_status.visible = not sent.ok
	if not sent.ok:
		return
	_input.text = ""
	_last_message_id = ""
	_refresh_left = 0.0


func _error_text(error: String) -> String:
	var key: String = "ERROR_" + (error if not error.is_empty() else "server").to_upper()
	var text: String = tr(key)
	return text if text != key else tr("ERROR_SERVER")
