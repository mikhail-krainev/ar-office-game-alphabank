class_name UnreadDot
extends Panel
## Glowing red dot in the corner of a button: there is something unread behind it (the chat).

const SIDE: float = 10.0
const INSET: float = 3.0
const PULSE_SECONDS: float = 0.6
const DIM_ALPHA: float = 0.45

var _pulse: Tween


## Puts a hidden dot into the top right corner of `button`.
static func attach(button: Control) -> UnreadDot:
	var dot: UnreadDot = UnreadDot.new()
	button.add_child(dot)
	return dot


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = UiStyle.RED
	style.set_corner_radius_all(int(SIDE / 2.0))
	style.border_color = Color.WHITE
	style.set_border_width_all(1)
	style.shadow_color = Color(UiStyle.RED, 0.6)
	style.shadow_size = 4
	add_theme_stylebox_override("panel", style)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -SIDE - INSET
	offset_right = -INSET
	offset_top = INSET
	offset_bottom = SIDE + INSET


func set_lit(lit: bool) -> void:
	if lit == visible:
		return
	visible = lit
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	modulate.a = 1.0
	if lit:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(self, "modulate:a", DIM_ALPHA, PULSE_SECONDS)
		_pulse.tween_property(self, "modulate:a", 1.0, PULSE_SECONDS)
