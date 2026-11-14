class_name ProfilePanel
extends ModalPanel
## The player's page: avatar (a ready-made portrait or an uploaded picture), name, department and a
## status under the avatar; the office streak as a number or as an attendance calendar; totals and
## the history of completed tasks; the notification switch.

const TEMPLATE_COLUMNS: int = 7
## The server enforces the same limit.
const STATUS_MAX_LENGTH: int = 60
const HISTORY_DAYS: int = 14

var _page: BackendModels.ProfilePage
var _show_calendar: bool = false
var _busy: bool = false
var _toast: Label
var _status_editor: HBoxContainer
var _status_input: LineEdit
var _day_details: VBoxContainer


func _init() -> void:
	super("PROFILE_TITLE")


func open() -> void:
	show_panel()
	await _reload()


func _reload() -> void:
	_page = await Backend.account.get_profile_page()
	clear()
	_toast = make_text("", 10, UiStyle.RED)
	content.add_child(_make_identity())
	content.add_child(_toast)
	content.add_child(_make_avatar_picker())
	content.add_child(_make_streak())
	content.add_child(_make_totals())
	content.add_child(_make_history())
	content.add_child(_make_notifications())
	var loans: Button = UiStyle.make_button("Долги и переводы", false, 12)
	loans.pressed.connect(func() -> void:
		var panel: LoungeLoans = LoungeLoans.new()
		get_parent().add_child(panel)
		panel.closed.connect(panel.queue_free)
		panel.open()
	)
	content.add_child(loans)
	content.add_child(_make_sign_out())


## Another player can sign in on the same phone; the progress stays with each account.
func _make_sign_out() -> Button:
	var button: Button = UiStyle.make_button(tr("PROFILE_SIGN_OUT"), false, 10)
	button.custom_minimum_size = Vector2(0, 28)
	button.pressed.connect(func() -> void:
		button.disabled = true
		await Backend.sign_out()
	)
	return button


func _show_toast(text: String) -> void:
	_toast.text = text


func _section(title_key: String) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(UiStyle.make_label(tr(title_key).to_upper(), 10, UiStyle.RED))
	return column


# --- Identity and status ------------------------------------------------------------


func _make_identity() -> Control:
	var profile: BackendModels.Profile = _page.profile
	var card: PanelContainer = make_card()
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var avatar: AvatarView = AvatarView.new(64.0)
	row.add_child(avatar)
	avatar.show_avatar(profile.avatar, profile.user_id)
	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiStyle.make_label(profile.display_name, 14))
	info.add_child(UiStyle.make_label(NotificationTexts.department(profile.department), 9, UiStyle.MUTED))
	var has_status: bool = not profile.status.is_empty()
	var status: Label = make_text(profile.status if has_status else tr("PROFILE_STATUS_EMPTY"), 11, UiStyle.INK if has_status else UiStyle.MUTED, content_width - 100.0)
	info.add_child(status)
	var edit: Button = UiStyle.make_button(tr("PROFILE_STATUS_EDIT"), false, 10)
	edit.custom_minimum_size = Vector2(0, 24)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(edit)

	_status_editor = HBoxContainer.new()
	_status_editor.add_theme_constant_override("separation", 4)
	_status_editor.visible = false
	column.add_child(_status_editor)
	_status_input = LineEdit.new()
	_status_input.max_length = STATUS_MAX_LENGTH
	_status_input.placeholder_text = tr("PROFILE_STATUS_PLACEHOLDER")
	_status_input.text = profile.status
	_status_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_input.add_theme_font_size_override("font_size", 11)
	_status_input.text_submitted.connect(func(_text: String) -> void: _save_status())
	_status_editor.add_child(_status_input)
	var save: Button = UiStyle.make_button(tr("PROFILE_STATUS_SAVE"), true, 10)
	save.custom_minimum_size = Vector2(0, 28)
	save.pressed.connect(_save_status)
	_status_editor.add_child(save)
	edit.pressed.connect(func() -> void:
		_status_editor.visible = not _status_editor.visible
		if _status_editor.visible:
			_status_input.grab_focus()
	)
	return card


func _save_status() -> void:
	if _busy:
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.account.set_status(_status_input.text)
	_busy = false
	if not result.ok:
		_show_toast(tr("ERROR_" + result.error.to_upper()))
		return
	await _reload()


# --- Avatar ----------------------------------------------------------------------


func _make_avatar_picker() -> Control:
	var section: VBoxContainer = _section("PROFILE_AVATAR")
	var grid: GridContainer = GridContainer.new()
	grid.columns = TEMPLATE_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	section.add_child(grid)
	var side: float = floorf((content_width - 4.0 * (TEMPLATE_COLUMNS - 1)) / TEMPLATE_COLUMNS)
	var options: Array[String] = AvatarCatalog.TEMPLATES.duplicate()
	if _page.has_custom_avatar:
		options.push_front(AvatarCatalog.CUSTOM)
	for avatar_id: String in options:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(side, side)
		button.focus_mode = Control.FOCUS_NONE
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var view: AvatarView = AvatarView.new(side)
		view.selected = avatar_id == _page.profile.avatar
		button.add_child(view)
		view.show_avatar(avatar_id, _page.profile.user_id)
		button.pressed.connect(_choose_avatar.bind(avatar_id))
		grid.add_child(button)
	var upload: Button = UiStyle.make_button(tr("PROFILE_AVATAR_UPLOAD"), false, 10)
	upload.custom_minimum_size = Vector2(0, 28)
	upload.disabled = not PlatformServices.has_feature(PlatformBackend.Feature.PHOTO_LIBRARY)
	upload.pressed.connect(_upload_avatar)
	section.add_child(upload)
	if upload.disabled:
		section.add_child(make_text(tr("PROFILE_AVATAR_NO_GALLERY"), 9, UiStyle.MUTED))
	return section


func _choose_avatar(avatar_id: String) -> void:
	if _busy or avatar_id == _page.profile.avatar:
		return
	_busy = true
	var result: BackendModels.ActionResult = await Backend.account.set_avatar(avatar_id)
	_busy = false
	if not result.ok:
		_show_toast(tr("ERROR_" + result.error.to_upper()))
		return
	await _reload()


func _upload_avatar() -> void:
	if _busy:
		return
	_busy = true
	var image: Image = await PlatformServices.pick_image()
	if image == null:
		_busy = false
		_show_toast(tr("PROFILE_AVATAR_CANCELLED"))
		return
	var result: BackendModels.ActionResult = await Backend.account.upload_avatar(image)
	_busy = false
	if not result.ok:
		_show_toast(tr("ERROR_" + result.error.to_upper()))
		return
	await _reload()


# --- Streak and calendar ----------------------------------------------------------


func _make_streak() -> Control:
	var section: VBoxContainer = _section("PROFILE_STREAK")
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	section.add_child(tabs)
	for calendar: bool in [false, true]:
		var active: bool = calendar == _show_calendar
		var tab: Button = UiStyle.make_button(tr("PROFILE_VIEW_CALENDAR") if calendar else tr("PROFILE_VIEW_STREAK"), active, 11)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 28)
		tab.pressed.connect(func() -> void:
			if _show_calendar != calendar:
				_show_calendar = calendar
				_reload()
		)
		tabs.add_child(tab)
	var card: PanelContainer = make_card()
	section.add_child(card)
	card.add_child(_make_calendar() if _show_calendar else _make_streak_number())
	return section


func _make_streak_number() -> Control:
	var profile: BackendModels.Profile = _page.profile
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var number: Label = UiStyle.make_label(str(profile.streak_days), 34, UiStyle.RED)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.label_settings.shadow_color = Color(UiStyle.INK, 0.25)
	number.label_settings.shadow_offset = Vector2(2, 2)
	column.add_child(number)
	var caption: Label = UiStyle.make_label(tr("PROFILE_STREAK_DAYS"), 10, UiStyle.INK)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	var details: Label = make_text(tr("PROFILE_STREAK_DETAILS") % [_page.best_streak, UiStyle.format_multiplier(profile.multiplier)], 10, UiStyle.MUTED)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(details)
	var hint: String = tr("PROFILE_TODAY_PRESENT")
	if not profile.present_today:
		hint = tr("PROFILE_TODAY_CHECK_IN") % WorkCalendar.short_date(_page.today) if WorkCalendar.is_workday(_page.today) else tr("PROFILE_TODAY_WEEKEND")
	var today: Label = make_text(hint, 10, UiStyle.INK if profile.present_today else UiStyle.RED)
	today.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(today)
	return column


func _make_calendar() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var heatmap: CalendarHeatmap = CalendarHeatmap.new()
	heatmap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	heatmap.setup(_page.days, _page.today)
	column.add_child(heatmap)
	var legend: HBoxContainer = HBoxContainer.new()
	legend.add_theme_constant_override("separation", 4)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(legend)
	for entry: Array in [[CalendarHeatmap.EMPTY, "CAL_LEGEND_NONE"], [CalendarHeatmap.OFFICE, "CAL_LEGEND_OFFICE"], [UiStyle.RED, "CAL_LEGEND_BUSY"]]:
		var swatch: ColorRect = ColorRect.new()
		swatch.color = entry[0]
		swatch.custom_minimum_size = Vector2(9, 9)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		legend.add_child(UiStyle.make_label(tr(str(entry[1])), 8, UiStyle.MUTED))
	_day_details = VBoxContainer.new()
	_day_details.add_theme_constant_override("separation", 1)
	column.add_child(_day_details)
	heatmap.day_selected.connect(_show_day)
	if not _page.days.is_empty():
		_show_day(_page.days[_page.days.size() - 1])
	return column


func _show_day(record: BackendModels.DayRecord) -> void:
	for child: Node in _day_details.get_children():
		child.queue_free()
	var state: String = tr("CAL_DAY_PRESENT") if record.present else tr("CAL_DAY_ABSENT")
	_day_details.add_child(UiStyle.make_label("%s · %s" % [WorkCalendar.short_date(record.day), state], 10, UiStyle.INK))
	for task: Dictionary in record.tasks:
		_day_details.add_child(_task_line(task))


func _task_line(task: Dictionary) -> Label:
	var reward: int = int(task.get("reward", 0))
	var text: String = "· %s" % str(task.get("title", ""))
	if reward > 0:
		text += "  +%d" % reward
	return make_text(text, 9, UiStyle.MUTED)


# --- Totals and history -----------------------------------------------------------


func _make_totals() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for entry: Array in [
		[_page.office_days_total, "PROFILE_TOTAL_DAYS"], [_page.tasks_total, "PROFILE_TOTAL_TASKS"],
		[_page.coins_earned_total, "PROFILE_TOTAL_COINS"],
	]:
		var tile: PanelContainer = make_card()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		tile.add_child(column)
		column.add_child(UiStyle.make_label(str(entry[0]), 16, UiStyle.INK))
		column.add_child(UiStyle.make_label(tr(str(entry[1])), 8, UiStyle.MUTED))
		row.add_child(tile)
	return row


func _make_history() -> Control:
	var section: VBoxContainer = _section("PROFILE_HISTORY")
	var shown: int = 0
	for index: int in range(_page.days.size() - 1, -1, -1):
		var record: BackendModels.DayRecord = _page.days[index]
		if record.tasks.is_empty():
			continue
		var card: PanelContainer = make_card()
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		card.add_child(column)
		var header: String = WorkCalendar.short_date(record.day)
		if record.earned > 0:
			header += "  ·  +%d" % record.earned
		column.add_child(UiStyle.make_label(header, 10, UiStyle.INK))
		for task: Dictionary in record.tasks:
			column.add_child(_task_line(task))
		section.add_child(card)
		shown += 1
		if shown >= HISTORY_DAYS:
			break
	if shown == 0:
		section.add_child(make_text(tr("PROFILE_HISTORY_EMPTY"), 10, UiStyle.MUTED))
	return section


# --- Notifications ---------------------------------------------------------------


func _make_notifications() -> Control:
	var section: VBoxContainer = _section("PROFILE_NOTIFICATIONS")
	if not Notifications.is_supported():
		section.add_child(make_text(tr("PROFILE_NOTIFICATIONS_UNSUPPORTED"), 10, UiStyle.MUTED))
		return section
	var enabled: bool = Notifications.is_enabled()
	section.add_child(make_text(tr("PROFILE_NOTIFICATIONS_ON") if enabled else tr("PROFILE_NOTIFICATIONS_OFF"), 10, UiStyle.MUTED))
	var toggle: Button = UiStyle.make_button(tr("PROFILE_NOTIFICATIONS_DISABLE") if enabled else tr("PROFILE_NOTIFICATIONS_ENABLE"), not enabled, 11)
	toggle.custom_minimum_size = Vector2(0, 30)
	toggle.pressed.connect(func() -> void:
		if Notifications.is_enabled():
			Notifications.disable()
		elif not await Notifications.enable():
			_show_toast(tr("PROFILE_NOTIFICATIONS_DENIED"))
		_reload()
	)
	section.add_child(toggle)
	return section
