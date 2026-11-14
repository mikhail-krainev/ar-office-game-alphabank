class_name ClickerUpgradeList
extends VBoxContainer
## All upgrades in one list, cheapest first: tap upgrades (more points per tap) and helpers (passive
## points per second). Locked upgrades are grey, show a padlock and the points of this run that
## open them. Rows are rebuilt when levels or unlocks change; prices follow the points.

signal buy_requested(kind: String, tier: int, count: int)

const TAP_COLOR: Color = Color("#ef3124")
const IDLE_COLOR: Color = Color("#6b3fa0")
const LOCKED_BG: Color = Color("#e4e1dc")
const LOCKED_TEXT: Color = Color("#9a958e")

## Levels to buy per press: 1, 10 or 0 (as many as the points allow).
var amount: int = 1

var _rules: ClickerRules
var _signature: String = ""
var _rows: Array[Dictionary] = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


## Every upgrade as {kind, tier, unlock}, in the order they open.
func _entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for tier: int in _rules.tiers().size():
		for kind: String in ["tap", "idle"]:
			entries.append({"kind": kind, "tier": tier, "unlock": _rules.unlock_at(kind, tier)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["unlock"]) < float(b["unlock"]))
	return entries


func show_state(rules: ClickerRules, state: Dictionary, points: float) -> void:
	_rules = rules
	var run: float = float(state.get("run", 0))
	var entries: Array[Dictionary] = _entries()
	var opened: Array[String] = []
	for entry: Dictionary in entries:
		var level: int = _level(state, entry)
		entry["level"] = level
		entry["open"] = level > 0 or run >= float(entry["unlock"])
		opened.append("%s%d:%d:%s" % [entry["kind"], entry["tier"], level, entry["open"]])
	var signature: String = "%d|%s" % [amount, ",".join(opened)]
	if signature != _signature:
		_signature = signature
		_rebuild(entries)
	refresh(points)


func _level(state: Dictionary, entry: Dictionary) -> int:
	var levels: Array = state.get(str(entry["kind"]), [])
	var tier: int = int(entry["tier"])
	return int(levels[tier]) if tier < levels.size() else 0


func _rebuild(entries: Array[Dictionary]) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	for entry: Dictionary in entries:
		_add_row(entry)


func _add_row(entry: Dictionary) -> void:
	var kind: String = entry["kind"]
	var tier: int = entry["tier"]
	var level: int = entry["level"]
	var is_open: bool = entry["open"]
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.SHADE if is_open else LOCKED_BG, 6, 6))
	add_child(card)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)
	row.add_child(_badge(kind, is_open))
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", -1)
	row.add_child(texts)
	var tier_name: String = str(_rules.tiers()[tier].get(kind, ""))
	var title: Label = UiStyle.make_label(tier_name + (" · ур. %d" % level if level > 0 else ""), 10, UiStyle.INK if is_open else LOCKED_TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(title)
	var unit: String = "за тап" if kind == "tap" else "в секунду"
	var effect_text: String = "+%s %s за уровень" % [ClickerNumbers.format(_rules.gain(kind, tier)), unit]
	if not is_open:
		effect_text = "Откроется на %s очков · %s" % [ClickerNumbers.format(float(entry["unlock"])), "клик" if kind == "tap" else "пассивный доход"]
	var effect: Label = UiStyle.make_label(effect_text, 8, UiStyle.MUTED if is_open else LOCKED_TEXT)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(effect)
	if not is_open:
		var lock: LockIcon = LockIcon.new()
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lock)
		return
	var button: Button = UiStyle.make_button("", true, 9)
	button.custom_minimum_size = Vector2(92, 34)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(button)
	button.pressed.connect(func() -> void: buy_requested.emit(kind, tier, amount))
	_rows.append({"kind": kind, "tier": tier, "level": level, "button": button})


## Round badge: a paw for tap upgrades, a clock for helpers; grey while locked.
func _badge(kind: String, is_open: bool) -> PanelContainer:
	var box: PanelContainer = PanelContainer.new()
	var color: Color = (TAP_COLOR if kind == "tap" else IDLE_COLOR) if is_open else LOCKED_TEXT
	box.add_theme_stylebox_override("panel", UiStyle.panel(color, 13, 0))
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label: Label = UiStyle.make_label("ТАП" if kind == "tap" else "АВТО", 7, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(30, 26)
	box.add_child(label)
	return box


## Prices and buttons for the current points.
func refresh(points: float) -> void:
	if _rules == null:
		return
	for row: Dictionary in _rows:
		var kind: String = row["kind"]
		var tier: int = int(row["tier"])
		var level: int = int(row["level"])
		var count: int = amount
		if amount == 0:
			count = maxi(1, _rules.affordable(kind, tier, level, points, 1000))
		var price: float = _rules.price(kind, tier, level, count)
		var button: Button = row["button"]
		button.text = ClickerNumbers.format(price) + (" · ×%d" % count if count > 1 else "")
		button.disabled = price > points


## Grey padlock where a locked upgrade would have its buy button.
class LockIcon:
	extends Control

	const BODY: Color = Color("#8e8982")
	const DARK: Color = Color("#6e6a64")

	func _init() -> void:
		custom_minimum_size = Vector2(92, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = (size / 2.0).round()
		draw_style_box(UiStyle.panel(Color("#d3cfc8"), 6, 0), Rect2(Vector2.ZERO, size))
		draw_arc(c + Vector2(0, -3), 5.0, PI, TAU, 12, DARK, 2.0)
		draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 11)), BODY)
		draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 11)), DARK, false, 1.0)
		draw_rect(Rect2(c + Vector2(-1, 0), Vector2(2, 4)), Color("#4a4642"))
