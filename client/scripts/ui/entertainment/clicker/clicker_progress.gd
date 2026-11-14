class_name ClickerProgress
extends RefCounted
## Rebirth and achievements tabs of the clicker.

## Achievement icons (tools/printables/make_clicker_achievements.py): one column per achievement in
## the order of the rules, row 0 received, row 1 grey.
const ICONS: Texture2D = preload("res://assets/ui/clicker_achievements.png")
const ICON_SIZE: int = 32


## Rebirth: the next golden part of the cat, how far this run is, and the button when it is open.
static func build_rebirth(box: VBoxContainer, rules: ClickerRules, state: Dictionary, on_rebirth: Callable) -> void:
	var gold: int = int(state.get("gold", 0))
	var reachable: int = int(state.get("rebirth_gold", gold))
	var levels: int = rules.gold_levels().size()
	box.add_child(_text("Сейчас: %s · уровень золота %d из %d · доход ×%s" % [rules.gold_name(gold), gold, levels, ClickerNumbers.format(rules.gold_mult(gold))], 10))
	if gold >= levels:
		box.add_child(_text("Кот полностью золотой и сияет на весь космос. Дальше — только рекорды рейтинга.", 10, UiStyle.MUTED))
		return
	var target: int = maxi(reachable, gold + 1)
	var preview: ClickerCat = ClickerCat.new(150)
	preview.gold = target
	preview.interactive = false
	box.add_child(preview)
	box.add_child(_text("Следующий рубеж: %s — %s очков за забег, доход ×%s навсегда." % [rules.gold_name(gold + 1), ClickerNumbers.format(rules.gold_at(gold + 1)), ClickerNumbers.format(rules.gold_mult(gold + 1))], 10))
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	bar.max_value = 1000
	var run: float = maxf(1.0, float(state.get("run", 0)))
	bar.value = 1000.0 * clampf(log(run) / log(rules.gold_at(gold + 1)), 0.0, 1.0)
	box.add_child(bar)
	if reachable > gold:
		var skipped: String = " (сразу %d уровня)" % (reachable - gold) if reachable - gold > 1 else ""
		var button: Button = UiStyle.make_button("Переродиться: %s%s" % [rules.gold_name(reachable), skipped], true, 11)
		button.custom_minimum_size.y = 40
		button.pressed.connect(func() -> void:
			if button.has_meta("armed"):
				button.disabled = true
				on_rebirth.call()
				return
			button.set_meta("armed", true)
			button.text = "Точно? Очки и улучшения обнулятся. Нажми ещё раз"
		)
		box.add_child(button)
		box.add_child(_text("Очки и улучшения обнулятся. Рейтинг, достижения и золото кота останутся.", 9, UiStyle.MUTED))
	else:
		box.add_child(_text("Перерождение откроется, когда забег дойдёт до рубежа. Можно копить дальше: следующий рубеж даст сразу несколько уровней золота.", 9, UiStyle.MUTED))


static func build_achievements(box: VBoxContainer, rules: ClickerRules, state: Dictionary) -> void:
	var have: Array = state.get("achievements", [])
	var bonus: float = float(rules.data.get("achievement_bonus", 0.01)) * 100.0
	box.add_child(_text("Получено %d из %d · каждое даёт +%d%% к доходу" % [have.size(), rules.achievements().size(), int(bonus)], 10))
	box.add_child(_text("Касаний: %s · рекорд комбо ×%s · перерождений: %d · пока кот работал сам: %s" % [
		ClickerNumbers.format(float(state.get("taps", 0))), String.num(float(state.get("best_combo", 1)), 1).replace(".", ","),
		int(state.get("rebirths", 0)), ClickerNumbers.format(float(state.get("offline", 0)))], 9, UiStyle.MUTED))
	var achievements: Array = rules.achievements()
	for i: int in achievements.size():
		var achievement: Dictionary = achievements[i]
		box.add_child(_achievement_row(i, achievement, have.has(achievement.get("id", "")), state, int(bonus)))


## One achievement: its icon (grey until received), name, goal and progress.
static func _achievement_row(index: int, achievement: Dictionary, done: bool, state: Dictionary, bonus: int) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(Color("#fff3c4") if done else UiStyle.SHADE, 6, 6))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var icon: TextureRect = TextureRect.new()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = Rect2(index * ICON_SIZE, 0 if done else ICON_SIZE, ICON_SIZE, ICON_SIZE)
	icon.texture = atlas
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var title: Label = UiStyle.make_label(str(achievement.get("name", "")), 10, UiStyle.INK if done else UiStyle.MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(title)
	var detail: String = "Получено · +%d%% к доходу" % bonus if done else "Цель: %s · сейчас %s" % [_goal(achievement), _progress(achievement, state)]
	var line: Label = UiStyle.make_label(detail, 8, UiStyle.RED_DARK if done else UiStyle.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(line)
	return card


## Where the player is now towards an achievement.
static func _progress(achievement: Dictionary, state: Dictionary) -> String:
	var value: float = float(achievement.get("value", 0))
	var target: float = value
	var now: float = 0.0
	match str(achievement.get("kind", "")):
		"taps":
			now = float(state.get("taps", 0))
		"total":
			now = float(state.get("total", 0))
			target = pow(10.0, value)
		"gold":
			now = float(state.get("gold", 0))
		"levels":
			for key: String in ["tap", "idle"]:
				for level: Variant in state.get(key, []):
					now += float(level)
		"combo":
			return "×%s" % String.num(float(state.get("best_combo", 1)), 1).replace(".", ",")
		"offline":
			now = float(state.get("offline", 0))
			target = pow(10.0, value)
	return ClickerNumbers.format(minf(now, target))


static func _goal(achievement: Dictionary) -> String:
	var value: float = float(achievement.get("value", 0))
	match str(achievement.get("kind", "")):
		"taps":
			return "%s касаний" % ClickerNumbers.format(value)
		"total":
			return "%s очков" % ClickerNumbers.format(pow(10.0, value))
		"gold":
			return "золото %d уровня" % int(value)
		"levels":
			return "%d улучшений" % int(value)
		"combo":
			return "комбо ×%d" % int(value)
		"offline":
			return "%s без тебя" % ClickerNumbers.format(pow(10.0, value))
	return ""


static func _text(value: String, font_size: int, color: Color = UiStyle.INK) -> Label:
	var label: Label = UiStyle.make_label(value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
