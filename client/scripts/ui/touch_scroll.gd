class_name TouchScroll
extends ScrollContainer
## Vertical list scrolled by dragging a finger anywhere over it, also over cards and buttons: the
## built-in drag of ScrollContainer never sees the presses its children take, so on a phone the list
## moved only with the thin scroll bar. A press that turns into a drag cancels the button under the
## finger, so scrolling never starts a task; after the release the list glides on and slows down.

## Finger travel after which a press becomes a scroll, in base-resolution pixels.
const DRAG_THRESHOLD: float = 8.0
## Glide slowdown: the speed falls by e times every 1 / FRICTION seconds.
const FRICTION: float = 5.0
const MIN_GLIDE_SPEED: float = 30.0
const MAX_GLIDE_SPEED: float = 3000.0
## Weight of the newest finger speed sample, for a smooth release speed.
const SPEED_SMOOTHING: float = 0.4

var _pressed: bool = false
var _dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _velocity: float = 0.0
## Scroll position with the fraction that scroll_vertical (an int) drops.
var _scroll_y: float = 0.0
var _last_motion_usec: int = 0


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _process(delta: float) -> void:
	if _pressed or _velocity == 0.0:
		return
	if absf(_velocity) < MIN_GLIDE_SPEED or not is_visible_in_tree():
		_velocity = 0.0
		return
	if not _scroll_to(_scroll_y + _velocity * delta):
		_velocity = 0.0
		return
	_velocity *= exp(-FRICTION * delta)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_pressed = false
		_dragging = false
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_pressed = get_global_rect().has_point(button.position)
			_dragging = false
			if _pressed:
				_press_position = button.position
				_velocity = 0.0
				_scroll_y = scroll_vertical
				_last_motion_usec = Time.get_ticks_usec()
		elif _pressed:
			# The release is not consumed: the GUI must see it to drop the press it started.
			_pressed = false
			_dragging = false
		return
	if not _pressed:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if not _dragging and absf(motion.position.y - _press_position.y) >= DRAG_THRESHOLD:
			_dragging = true
			_cancel_button_press(_press_position)
		if _dragging:
			_drag(-motion.relative.y)
			get_viewport().set_input_as_handled()
	elif _dragging and event is InputEventScreenDrag:
		# The finger events behind the emulated mouse must not scroll the list a second time.
		get_viewport().set_input_as_handled()


func _drag(distance: float) -> void:
	var now: int = Time.get_ticks_usec()
	var seconds: float = maxf((now - _last_motion_usec) / 1_000_000.0, 0.001)
	_last_motion_usec = now
	var speed: float = clampf(distance / seconds, -MAX_GLIDE_SPEED, MAX_GLIDE_SPEED)
	_velocity = lerpf(_velocity, speed, SPEED_SMOOTHING)
	_scroll_to(_scroll_y + distance)


## Returns false when the list is already at its end.
func _scroll_to(target: float) -> bool:
	var limit: float = maxf(0.0, get_v_scroll_bar().max_value - size.y)
	var clamped: float = clampf(target, 0.0, limit)
	var moved: bool = not is_equal_approx(clamped, _scroll_y)
	_scroll_y = clamped
	scroll_vertical = roundi(clamped)
	return moved


## Disabling a button drops its press, so the release under the finger does not press it.
func _cancel_button_press(at: Vector2) -> void:
	var target: BaseButton = _button_at(self, at)
	if target != null and not target.disabled:
		target.disabled = true
		target.disabled = false


func _button_at(node: Node, at: Vector2) -> BaseButton:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var inner: BaseButton = _button_at(control, at)
		if inner != null:
			return inner
		if control is BaseButton and control.get_global_rect().has_point(at):
			return control as BaseButton
	return null
