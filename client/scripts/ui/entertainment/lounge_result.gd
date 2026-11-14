class_name LoungeResult
extends CanvasLayer
## The settled roulette sector and net results, briefly covering the whole viewport.


func _init(room: Dictionary = {}) -> void:
	layer = 38
	var root: ColorRect = ColorRect.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.color = Color("#15151bef")
	add_child(root)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	var sector: int = int(room.get("result", 0))
	var number: Label = UiStyle.make_label(str(sector), 80, Color.WHITE)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(number)
	var caption: String = "ЗЕЛЁНОЕ" if sector == 0 else ("КРАСНОЕ" if LoungeTable.REDS.has(sector) else "ЧЁРНОЕ")
	var color: Label = UiStyle.make_label(caption, 22, Color.WHITE)
	color.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(color)
	var gains: Dictionary = room.get("gains", {})
	for winning: bool in [true, false]:
		column.add_child(UiStyle.make_label("Выиграли" if winning else "Проиграли / без изменения", 14, UiStyle.GOLD))
		for player: Dictionary in room.get("players", []):
			var id: String = str(player.get("id", ""))
			if gains.has(id) and (int(gains[id]) > 0) == winning:
				column.add_child(UiStyle.make_label("%s: %+d койнов" % [player.get("name", ""), int(gains[id])], 12, Color.WHITE))


func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	queue_free()
