class_name LoungeRoster
extends GridContainer
## Compact avatar/name roster for roulette rooms too large for full character seats.


func _init(players: Array = []) -> void:
	columns = 3
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 5)
	for player: Dictionary in players:
		if player.get("departed", false):
			continue
		var column: VBoxContainer = VBoxContainer.new()
		column.custom_minimum_size.x = 90
		var avatar: AvatarView = AvatarView.new(24)
		column.add_child(avatar)
		if player.get("character_avatar", false):
			avatar.show_outfit(player.get("outfit", {}), str(player.get("id", "")))
		else:
			avatar.show_avatar(str(player.get("avatar", "me")), str(player.get("id", "")))
		var name_label: Label = UiStyle.make_label(str(player.get("name", "")), 9)
		name_label.custom_minimum_size.x = 90
		name_label.clip_text = true
		column.add_child(name_label)
		add_child(column)
