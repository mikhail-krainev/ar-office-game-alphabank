class_name UiStyle
extends RefCounted
## Shared Alfa-styled colours, panels, buttons and label settings for code-built UI.

const RED: Color = Color("#ef3124")
const RED_DARK: Color = Color("#c4251b")
const INK: Color = Color("#1d1d1f")
const MUTED: Color = Color("#6e6a64")
const PAPER: Color = Color("#fbfaf8")
const PAPER_EDGE: Color = Color("#d8d1c6")
const SHADE: Color = Color("#efebe5")
const GOLD: Color = Color("#f7c948")
const DIM: Color = Color(0.1, 0.08, 0.07, 0.55)
const HARD: Color = Color("#e0701f")
const VERY_HARD: Color = Color("#9b3fd1")

const RARITY_COLORS: Dictionary[String, Color] = {
	"common": Color("#8a857d"),
	"rare": Color("#3a7bd5"),
	"epic": Color("#9b3fd1"),
	"legendary": Color("#e89a10"),
}


static func panel(bg: Color = PAPER, radius: int = 6, margin: int = 8) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_width_bottom = 2
	box.border_color = PAPER_EDGE if bg != RED else RED_DARK
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.anti_aliasing = false
	return box


static func label(size: int, color: Color = INK) -> LabelSettings:
	var settings: LabelSettings = LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	return settings


static func make_label(text: String, size: int, color: Color = INK) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.label_settings = label(size, color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func make_button(text: String, primary: bool = true, font_size: int = 11) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	var bg: Color = RED if primary else PAPER
	var fg: Color = Color.WHITE if primary else INK
	var normal: StyleBoxFlat = panel(bg, 5, 4)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.12)
	pressed.border_width_bottom = 0
	pressed.content_margin_top = 6
	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = SHADE
	disabled.border_color = PAPER_EDGE
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_font_size_override("font_size", font_size)
	return button


static func difficulty_color(difficulty: String) -> Color:
	return VERY_HARD if difficulty == "very_hard" else HARD


## "2" for 2.0, "1.5" for 1.5.
static func format_multiplier(multiplier: float) -> String:
	return String.num(multiplier, 1).trim_suffix(".0")


## Short difficulty tag, e.g. "СЛОЖНО ×2".
static func difficulty_text(difficulty: String, multiplier: float) -> String:
	var name: String = String(TranslationServer.translate("TASK_DIFFICULTY_" + difficulty.to_upper()))
	return "%s ×%s" % [name.to_upper(), format_multiplier(multiplier)]


## Coloured difficulty tag with the reward multiplier, for task lists and the minigame header.
static func make_difficulty_badge(difficulty: String, multiplier: float) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = panel(difficulty_color(difficulty), 4, 2)
	style.border_width_bottom = 0
	style.content_margin_left = 6
	style.content_margin_right = 6
	badge.add_theme_stylebox_override("panel", style)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text: String = "%s · %s" % [
		String(TranslationServer.translate("TASK_DIFFICULTY_" + difficulty.to_upper())).to_upper(),
		String(TranslationServer.translate("TASK_BONUS")) % format_multiplier(multiplier),
	]
	badge.add_child(make_label(text, 9, Color.WHITE))
	return badge


## Full-screen dimmer that blocks input to the world below.
static func make_dimmer() -> ColorRect:
	var dimmer: ColorRect = ColorRect.new()
	dimmer.color = DIM
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	return dimmer


## Draw symbols directly so missing font glyphs never become Unicode codepoint boxes.
static func make_symbol_button(symbol: String, hint: String) -> Button:
	var button: Button = make_button("", false)
	button.tooltip_text = hint
	var icon: Control = Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(icon)
	icon.draw.connect(func() -> void:
		var center: Vector2 = (icon.size / 2.0).round()
		if symbol == "close":
			icon.draw_line(center + Vector2(-5, -5), center + Vector2(5, 5), INK, 2)
			icon.draw_line(center + Vector2(5, -5), center + Vector2(-5, 5), INK, 2)
		else:
			icon.draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), INK, 2)
			icon.draw_line(center + Vector2(1, -5), center + Vector2(6, 0), INK, 2)
			icon.draw_line(center + Vector2(6, 0), center + Vector2(1, 5), INK, 2)
	)
	icon.resized.connect(icon.queue_redraw)
	return button
