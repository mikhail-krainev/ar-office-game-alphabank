class_name CameraView
extends Control
## Shows the camera, cropped to fill the control. Where the platform can (the web), the camera is the
## browser's own full-quality video under the game: this control leaves a transparent hole for it.
## Elsewhere it draws PlatformServices camera frames. Overlays (face boxes, pose points, the probe
## square) are drawn by the owner through `overlay`, on top of the camera either way.

const HOLE_SHADER: Shader = preload("res://shaders/camera_hole.gdshader")
const FRAME_COLOR: Color = Color("#1d1d1f")
const WAITING_COLOR: Color = Color("#2b2730")

## Called with (view, image_rect) after the frame is drawn; image_rect maps normalized frame coordinates.
var overlay: Callable

var _texture: ImageTexture
var _frame_size: Vector2 = Vector2.ZERO
## Full-quality platform view: the window rectangle last sent, empty when not shown.
var _native_rect: Rect2 = Rect2()
var _native: bool = false
var _hole: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	PlatformServices.camera_frame.connect(_on_frame)
	_hole = Control.new()
	_hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole.show_behind_parent = true
	_hole.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hole.material = ShaderMaterial.new()
	(_hole.material as ShaderMaterial).shader = HOLE_SHADER
	_hole.draw.connect(func() -> void: _hole.draw_rect(Rect2(Vector2.ZERO, _hole.size), Color.BLACK))
	_hole.visible = false
	add_child(_hole)


func _exit_tree() -> void:
	if PlatformServices.camera_frame.is_connected(_on_frame):
		PlatformServices.camera_frame.disconnect(_on_frame)
	if _native:
		PlatformServices.show_camera_view(Rect2())
		_native = false


func _process(_delta: float) -> void:
	var rect: Rect2 = _window_rect() if is_visible_in_tree() else Rect2()
	if rect == _native_rect:
		return
	_native_rect = rect
	_native = PlatformServices.show_camera_view(rect) and rect.has_area()
	_hole.visible = _native
	queue_redraw()


func has_frame() -> bool:
	return _texture != null


## Rectangle the whole frame occupies inside the control (it overflows to fill the control).
func get_image_rect() -> Rect2:
	if _frame_size == Vector2.ZERO:
		return Rect2(Vector2.ZERO, size)
	var scale_factor: float = maxf(size.x / _frame_size.x, size.y / _frame_size.y)
	var image_size: Vector2 = _frame_size * scale_factor
	return Rect2((size - image_size) / 2.0, image_size)


## This control in window pixels: the viewport is drawn integer-scaled and centred in the window.
func _window_rect() -> Rect2:
	var window: Vector2 = Vector2(DisplayServer.window_get_size())
	var visible: Vector2 = get_viewport().get_visible_rect().size
	if visible.x <= 0.0 or visible.y <= 0.0:
		return Rect2()
	var fit: float = minf(window.x / visible.x, window.y / visible.y)
	var scale_factor: float = floorf(fit) if fit >= 1.0 else fit
	var offset: Vector2 = ((window - visible * scale_factor) / 2.0).floor()
	var transform: Transform2D = get_global_transform_with_canvas()
	var top_left: Vector2 = transform * Vector2.ZERO
	var bottom_right: Vector2 = transform * size
	return Rect2(offset + top_left * scale_factor, (bottom_right - top_left) * scale_factor)


func _on_frame(frame: Image) -> void:
	if _texture == null or Vector2(frame.get_size()) != _frame_size:
		_texture = ImageTexture.create_from_image(frame)
		_frame_size = Vector2(frame.get_size())
	else:
		_texture.update(frame)
	queue_redraw()


func _draw() -> void:
	if not _native:
		if _texture == null:
			draw_rect(Rect2(Vector2.ZERO, size), WAITING_COLOR)
		else:
			draw_texture_rect(_texture, get_image_rect(), false)
	if overlay.is_valid():
		overlay.call(self, get_image_rect())
	draw_rect(Rect2(Vector2.ZERO, size), FRAME_COLOR, false, 3.0)
