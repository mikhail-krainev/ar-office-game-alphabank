class_name ColleagueCard
extends PanelContainer
## Who to find for a task: avatar, name, department and the room where they were seen last. A tap on
## the card opens the colleague's mini profile.


func _init(colleague: BackendModels.Colleague, width: float) -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.SHADE, 5, 6))
	custom_minimum_size = Vector2(width, 0)
	ColleagueProfiles.make_tappable(self, colleague.user_id)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var avatar: AvatarView = AvatarView.new(44.0)
	row.add_child(avatar)
	avatar.show_avatar(colleague.avatar, colleague.user_id)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	column.add_child(UiStyle.make_label(colleague.name, 13))
	column.add_child(UiStyle.make_label(NotificationTexts.department(colleague.department), 9, UiStyle.MUTED))
	var room: MapLayout.Room = OfficeFloors.find_room(colleague.room)
	if room != null:
		var where: String = "%s · %s" % [tr(room.name_key), tr("FLOOR_SHORT") % OfficeFloors.NUMBERS.get(colleague.floor_id, 0)]
		var place: Label = UiStyle.make_label(tr("COLLEAGUE_USUALLY_AT") % where, 8, UiStyle.RED)
		place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		place.custom_minimum_size = Vector2(width - 72.0, 0)
		column.add_child(place)
