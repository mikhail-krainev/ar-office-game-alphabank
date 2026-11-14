class_name ClickerBoard
extends VBoxContainer
## Leaderboard of all colleagues by all-time points. A tap on a row opens that colleague's cat.

var _rules: ClickerRules
var _list: VBoxContainer
var _card: VBoxContainer
var _status: Label


func _init(rules: ClickerRules) -> void:
	_rules = rules
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


func _ready() -> void:
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 4)
	_card.visible = false
	add_child(_card)
	_status = UiStyle.make_label("Загружаю рейтинг…", 10, UiStyle.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	add_child(_list)
	var result: Dictionary = await Backend.clicker.top()
	if not is_inside_tree():
		return
	if not result.get("ok", false):
		_status.text = "Рейтинг не загрузился. Попробуй ещё раз позже."
		return
	var entries: Array = result.get("entries", [])
	_status.text = "Пока никто не гладил кота." if entries.is_empty() else "Лучшие коты офиса за всё время"
	var mine: Variant = result.get("me")
	var listed_me: bool = false
	for item: Variant in entries:
		listed_me = listed_me or bool((item as Dictionary).get("me", false))
		_add_row(item)
	if mine is Dictionary and not listed_me:
		_add_row(mine)


func _add_row(entry: Dictionary) -> void:
	var button: Button = Button.new()
	button.flat = false
	button.custom_minimum_size = Vector2(0, 40)
	var mine: bool = entry.get("me", false)
	button.add_theme_stylebox_override("normal", UiStyle.panel(Color("#fff3c4") if mine else UiStyle.SHADE, 6, 4))
	button.add_theme_stylebox_override("hover", UiStyle.panel(Color("#ffe9a3") if mine else UiStyle.PAPER_EDGE, 6, 4))
	button.add_theme_stylebox_override("pressed", UiStyle.panel(UiStyle.PAPER_EDGE, 6, 4))
	_list.add_child(button)
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	button.add_child(row)
	var rank: Label = UiStyle.make_label("#%d" % int(entry.get("rank", 0)), 11, UiStyle.RED if int(entry.get("rank", 0)) <= 3 else UiStyle.INK)
	rank.custom_minimum_size = Vector2(30, 0)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(rank)
	var icon: ClickerCat = ClickerCat.new(36)
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	icon.pixel_scale = 1
	icon.interactive = false
	icon.plain = true
	# The 128 px sprite shrinks to an icon: smooth it instead of dropping pixels.
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.gold = int(entry.get("gold", 0))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name_label: Label = UiStyle.make_label(("Ты" if mine else str(entry.get("name", "Коллега"))), 10)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var total: Label = UiStyle.make_label(ClickerNumbers.format(float(entry.get("total", 0))), 10, UiStyle.INK)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(total)
	button.pressed.connect(func() -> void: _open_card(entry))


func _open_card(entry: Dictionary) -> void:
	for child: Node in _card.get_children():
		_card.remove_child(child)
		child.queue_free()
	_card.visible = true
	var title: Label = UiStyle.make_label("#%d · %s" % [int(entry.get("rank", 0)), "Ты" if entry.get("me", false) else str(entry.get("name", "Коллега"))], 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(title)
	var cat: ClickerCat = ClickerCat.new(206)
	cat.gold = int(entry.get("gold", 0))
	cat.interactive = false
	cat.title_text = ClickerNumbers.format(float(entry.get("total", 0)))
	cat.detail_text = _rules.gold_name(cat.gold)
	_card.add_child(cat)
	var info: Label = UiStyle.make_label("Сейчас в копилке: %s · за тап: %s · перерождений: %d" % [ClickerNumbers.format(float(entry.get("points", 0))), ClickerNumbers.format(float(entry.get("tap_value", 1))), int(entry.get("rebirths", 0))], 9, UiStyle.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(info)
	var close: Button = UiStyle.make_button("Скрыть", false, 10)
	close.custom_minimum_size.y = 32
	close.pressed.connect(func() -> void: _card.visible = false)
	_card.add_child(close)
