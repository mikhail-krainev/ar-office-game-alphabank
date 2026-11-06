extends Control
## Intro sequence for portrait screens, laid out as a column of comic panels. Each IntroScene plays in
## its own integer-scaled panel with a caption; finished panels freeze, dim and slide up.
## Tap skips a shot, holding skips the whole sequence.

enum Sequence { MORNING, COMMUTE, EVENING }

const HOLD_TO_SKIP: float = 0.8
const CUT_GLITCH: float = 0.14
const FADE_TIME: float = 0.3
const GAP: float = 10.0
const BORDER: float = 2.0
const CAPTION_HEIGHT: float = 22.0
const HEADER: float = 26.0
const SLIDE_SPEED: float = 9.0
const BACKGROUND: Color = Color("#140c10")
const DIMMED: Color = Color(0.55, 0.55, 0.6)

@export var sequence: Sequence = Sequence.MORNING
@export_file("*.tscn") var next_scene: String = "res://scenes/home/home.tscn"


class Shot:
	extends RefCounted

	var frame: ColorRect
	var clip: Control
	var stage: Node2D
	var scene: IntroScene
	var view: Rect2i
	var target_y: float = 0.0
	## Unrounded position, so slow slides still converge at high frame rates.
	var pos: Vector2 = Vector2.ZERO


var _context: IntroContext = IntroContext.new()
var _scene_scripts: Array[Script] = []
var _index: int = -1
var _shots: Array[Shot] = []
var _panels: Control
var _skip: Label
var _fade: ColorRect
var _hold: float = 0.0
var _holding: bool = false
var _leaving: bool = false
var _glitch: float = 0.0
var _scale: float = 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scene_scripts = _plan_shots()
	var background: ColorRect = ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_context.audio = IntroAudio.new()
	add_child(_context.audio)
	_panels = Control.new()
	_panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panels)
	_skip = UiStyle.make_label(tr("INTRO_SKIP"), 10, Color(1, 1, 1, 0.7))
	add_child(_skip)
	var overlay: DrawLayer = DrawLayer.new()
	overlay.painter = _draw_glitch
	add_child(overlay)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	# The outfit and car come with the profile, so shots start once it is loaded.
	_context.profile = Backend.profile if Backend.profile != null else await Backend.login()
	_context.car_id = VehicleCatalog.player_car(_context.profile.car_id)
	_context.car_name = _context.profile.car_name
	_context.car_speed_kmh = _context.profile.car_speed_kmh
	_next_scene()


## The morning at home is always the same; the trips vary (CommutePlan).
func _plan_shots() -> Array[Script]:
	if sequence == Sequence.MORNING:
		return [WakeScene, StreakScene, BathroomScene, BreakfastScene]
	var direction: String = "evening" if sequence == Sequence.EVENING else "morning"
	_context.evening = sequence == Sequence.EVENING
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var last_stop: String = CommutePlan.load_last_stop(direction)
	var shots: Array[Script] = CommutePlan.evening(rng, last_stop) if _context.evening else CommutePlan.morning(rng, last_stop)
	CommutePlan.save_last_stop(direction, CommutePlan.stop_of(shots))
	return shots


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_holding = true
		_hold = 0.0
	else:
		if _holding and _hold < HOLD_TO_SKIP * 0.5:
			_next_scene()
		_holding = false


func _process(delta: float) -> void:
	_layout(delta)
	if _holding:
		_hold += delta
		if _hold >= HOLD_TO_SKIP:
			_finish()
	_skip.text = tr("INTRO_SKIP") + (" " + "■".repeat(int(_hold / HOLD_TO_SKIP * 5.0)) if _holding else "")
	_glitch = maxf(0.0, _glitch - delta)
	var current: IntroScene = _current_scene()
	if current != null and current.time >= current.get_duration():
		_next_scene()


func _current_scene() -> IntroScene:
	if _shots.is_empty() or _index >= _scene_scripts.size():
		return null
	return _shots[_shots.size() - 1].scene


func _next_scene() -> void:
	if _leaving or _index >= _scene_scripts.size():
		return
	var current: IntroScene = _current_scene()
	if current != null:
		if not current.is_ready_to_advance():
			return
		current.finish()
		current.process_mode = Node.PROCESS_MODE_DISABLED
		_context.shake = 0.0
		_context.audio.stop_all(0.15)
	_index += 1
	if _index >= _scene_scripts.size():
		_finish()
		return
	var scene: IntroScene = (_scene_scripts[_index] as GDScript).new() as IntroScene
	scene.intro = _context
	_add_shot(scene)
	scene.begin()
	_shots[_shots.size() - 1].frame.get_child(1).set("text", scene.get_caption())
	_glitch = CUT_GLITCH


func _add_shot(scene: IntroScene) -> void:
	_scale = maxf(1.0, floorf((size.x - 16.0) / IntroArt.STAGE.x))
	var shot: Shot = Shot.new()
	shot.scene = scene
	shot.view = scene.get_view()
	var view_size: Vector2 = Vector2(shot.view.size) * _scale
	shot.frame = ColorRect.new()
	shot.frame.color = UiStyle.INK
	shot.frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.frame.size = view_size + Vector2(BORDER * 2.0, BORDER * 2.0 + CAPTION_HEIGHT)
	shot.clip = Control.new()
	shot.clip.clip_contents = true
	shot.clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.clip.position = Vector2(BORDER, BORDER)
	shot.clip.size = view_size
	shot.frame.add_child(shot.clip)
	var caption: Label = UiStyle.make_label("", 11, UiStyle.PAPER)
	caption.label_settings.shadow_color = Color(UiStyle.RED, 0.9)
	caption.label_settings.shadow_offset = Vector2(1, 1)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.position = Vector2(BORDER, BORDER + view_size.y)
	caption.size = Vector2(view_size.x, CAPTION_HEIGHT)
	shot.frame.add_child(caption)
	shot.stage = Node2D.new()
	shot.stage.scale = Vector2(_scale, _scale)
	shot.stage.position = -Vector2(shot.view.position) * _scale
	shot.clip.add_child(shot.stage)
	shot.stage.add_child(scene)
	_panels.add_child(shot.frame)
	_shots.append(shot)
	_update_targets()
	shot.pos = Vector2(size.x, shot.target_y)
	shot.frame.position = shot.pos


func _update_targets() -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var top: float = safe.position.y + HEADER
	var bottom: float = safe.end.y - 10.0
	var total: float = -GAP
	for shot: Shot in _shots:
		total += shot.frame.size.y + GAP
	var cursor: float = top - maxf(0.0, top + total - bottom)
	for shot: Shot in _shots:
		shot.target_y = roundf(cursor)
		cursor += shot.frame.size.y + GAP


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	_context.audio.stop_all(FADE_TIME)
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished
	if _context.profile == null:
		await Backend.login()
	get_tree().change_scene_to_file(next_scene)


func _layout(delta: float) -> void:
	_update_targets()
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var blend: float = 1.0 - exp(-SLIDE_SPEED * delta)
	var last: int = _shots.size() - 1
	for index: int in range(last, -1, -1):
		var shot: Shot = _shots[index]
		var target_x: float = roundf((size.x - shot.frame.size.x) / 2.0)
		shot.pos = shot.pos.lerp(Vector2(target_x, shot.target_y), blend)
		shot.frame.position = shot.pos.round()
		shot.frame.modulate = Color.WHITE if index == last and not _leaving else DIMMED
		if index != last and shot.target_y + shot.frame.size.y < safe.position.y - 40.0:
			shot.frame.queue_free()
			_shots.remove_at(index)
	if last >= 0 and last < _shots.size():
		var active: Shot = _shots[_shots.size() - 1]
		var shake: Vector2 = Vector2.ZERO
		if _context.shake > 0.0:
			shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).round() * _context.shake
		active.stage.position = (-Vector2(active.view.position) + shake) * _scale
	_skip.position = Vector2(safe.position.x + 10.0, safe.position.y + 6.0)


func _draw_glitch(canvas: CanvasItem) -> void:
	if _glitch <= 0.0 or _shots.is_empty():
		return
	var active: Shot = _shots[_shots.size() - 1]
	var rect: Rect2 = Rect2(active.frame.position + active.clip.position, active.clip.size)
	var strength: float = _glitch / CUT_GLITCH
	for i: int in 7:
		var y: float = rect.position.y + randf() * rect.size.y
		var h: float = randf_range(2.0, 10.0) * _scale
		var color: Color = [Color(1, 0.2, 0.3), Color(0.3, 1, 1), Color(1, 1, 1)][i % 3]
		canvas.draw_rect(Rect2(rect.position.x + randf_range(-8, 8) * _scale, y, rect.size.x, h), Color(color, 0.25 * strength))
	canvas.draw_rect(rect, Color(0, 0, 0, 0.35 * strength))
