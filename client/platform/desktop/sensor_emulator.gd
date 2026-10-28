class_name SensorEmulator
extends CanvasLayer
## Debug overlay for DesktopPlatform. Visible while a sensor is running; lists the keys and offers
## buttons for input that has no natural key (QR codes, room emblems, recognized speech).
## Keys: arrows tilt, Space jerk, W walk, S squat, P arm pose, F faces, G smile, B wink, O open mouth,
## 1-9 marker, 0 no marker.
## QR codes, room emblems and recognized objects are picked with the buttons on the panel.

const PANEL_COLOR: Color = Color(0.08, 0.07, 0.1, 0.88)
const TEXT_COLOR: Color = Color("#f2efe9")
const ACCENT: Color = Color("#ef3124")
const FONT_SIZE: int = 9
const MAX_FACES: int = 3

var platform: PlatformBackend

var _panel: PanelContainer
var _status: Label
var _button_box: HFlowContainer
var _button_mode: int = -1
var _speech_box: HBoxContainer
var _speech_input: LineEdit


func _ready() -> void:
	layer = 90
	_panel = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.visible = false
	add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)
	_status = Label.new()
	_status.label_settings = LabelSettings.new()
	_status.label_settings.font_size = FONT_SIZE
	_status.label_settings.font_color = TEXT_COLOR
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_button_box = HFlowContainer.new()
	_button_box.add_theme_constant_override("h_separation", 3)
	_button_box.add_theme_constant_override("v_separation", 3)
	column.add_child(_button_box)
	_speech_box = HBoxContainer.new()
	column.add_child(_speech_box)
	_speech_input = LineEdit.new()
	_speech_input.placeholder_text = "say..."
	_speech_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speech_input.add_theme_font_size_override("font_size", FONT_SIZE)
	_speech_input.text_submitted.connect(func(_text: String) -> void: _say())
	_speech_box.add_child(_speech_input)
	_speech_box.add_child(_make_button("say", _say))
	PlatformServices.safe_rect_changed.connect(func(_rect: Rect2) -> void: _fit())


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not _panel.visible or _speech_input.has_focus():
		return
	var desktop: Object = platform
	match key.physical_keycode:
		KEY_SPACE:
			desktop.call("jerk")
		KEY_F:
			desktop.set("face_count", (int(desktop.get("face_count")) + 1) % (MAX_FACES + 1))
		KEY_G:
			desktop.set("smiling", not bool(desktop.get("smiling")))
		KEY_B:
			desktop.set("winking", not bool(desktop.get("winking")))
		KEY_O:
			desktop.set("mouth_open", not bool(desktop.get("mouth_open")))
		KEY_P:
			desktop.set("arm_pose", _next_arm_pose(desktop.get("arm_pose")))
		KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			desktop.set("marker_id", key.physical_keycode - KEY_0)
		_:
			return
	get_viewport().set_input_as_handled()
	refresh()


## Arms down, then every PoseMatcher pose in turn.
static func _next_arm_pose(current: StringName) -> StringName:
	var poses: Array[StringName] = [&""]
	poses.append_array(PoseMatcher.POSES)
	return poses[(poses.find(current) + 1) % poses.size()]


func _process(_delta: float) -> void:
	if _panel.visible:
		_status.text = _describe()


func refresh() -> void:
	var desktop: Object = platform
	var camera_running: bool = bool(desktop.call("is_camera_running"))
	var mode: int = int(desktop.call("get_camera_mode")) if camera_running else -1
	var speech_running: bool = bool(desktop.call("is_speech_running"))
	_panel.visible = camera_running or speech_running or bool(desktop.call("is_steps_running"))
	_speech_box.visible = speech_running
	if mode != _button_mode or (_button_box.visible and _button_box.get_child_count() == 0):
		_rebuild_buttons(mode)
	_status.text = _describe()
	_fit.call_deferred()


func _describe() -> String:
	var desktop: Object = platform
	var lines: PackedStringArray = PackedStringArray(["[SENSOR EMULATOR]  arrows tilt, Space jerk"])
	var tilt: Vector2 = desktop.get("tilt")
	lines.append("tilt %d/%d" % [roundi(tilt.x), roundi(tilt.y)])
	if bool(desktop.call("is_steps_running")):
		lines.append("hold W: walk")
	if bool(desktop.call("is_camera_running")):
		match int(desktop.call("get_camera_mode")):
			PlatformBackend.CameraMode.POSE:
				var arms: String = String(desktop.get("arm_pose"))
				lines.append("hold S: squat (depth %.1f), P arms: %s" % [float(desktop.get("squat_depth")), arms if not arms.is_empty() else "down"])
			PlatformBackend.CameraMode.FACES:
				lines.append("F faces: %d, G smile: %s, B wink: %s, O mouth: %s" % [
					int(desktop.get("face_count")), "yes" if desktop.get("smiling") else "no",
					"yes" if desktop.get("winking") else "no", "yes" if desktop.get("mouth_open") else "no",
				])
			PlatformBackend.CameraMode.MARKERS:
				lines.append("1-9 marker, 0 none: %d" % int(desktop.get("marker_id")))
			PlatformBackend.CameraMode.QR:
				lines.append("QR: pick a code")
			PlatformBackend.CameraMode.CODES:
				lines.append("QR or room emblem: pick one")
			PlatformBackend.CameraMode.LABELS:
				var label: String = str(desktop.get("label_id"))
				lines.append("object: %s" % (label if not label.is_empty() else "none"))
			_:
				lines.append("camera preview")
	if bool(desktop.call("is_speech_running")):
		lines.append("speech: type a phrase")
	return "  |  ".join(lines)


## QR mode lists the codes the camera can "see", codes mode adds the room emblems, object mode lists
## the recognizable labels.
func _rebuild_buttons(mode: int) -> void:
	_button_mode = mode
	for child: Node in _button_box.get_children():
		child.queue_free()
	_button_box.visible = mode in [PlatformBackend.CameraMode.QR, PlatformBackend.CameraMode.CODES, PlatformBackend.CameraMode.LABELS]
	if mode == PlatformBackend.CameraMode.CODES:
		for emblem_id: String in RoomEmblems.ids():
			var label: String = "%s (%s)" % [emblem_id, RoomEmblems.room_of(emblem_id)]
			_button_box.add_child(_make_button(label, func() -> void: platform.call("emit_emblem", emblem_id)))
	if mode in [PlatformBackend.CameraMode.QR, PlatformBackend.CameraMode.CODES]:
		_load_qr_buttons(mode)
	elif mode == PlatformBackend.CameraMode.LABELS:
		_button_box.add_child(_make_button("none", func() -> void: platform.set("label_id", "")))
		for label: String in OfficeObjects.all_labels():
			_button_box.add_child(_make_button(label, func() -> void: platform.set("label_id", label)))


## The list comes from the server (office codes, players), so it is filled in when it arrives.
func _load_qr_buttons(mode: int) -> void:
	await DevQrCodes.refresh()
	if _button_mode != mode:
		return
	var entries: Array[Array] = DevQrCodes.suggestions()
	for index: int in entries.size():
		# Office codes are fetched again on press: they rotate every 30 s.
		var on_press: Callable = func() -> void: platform.call("emit_qr", await DevQrCodes.fresh_text(index))
		_button_box.add_child(_make_button(str(entries[index][0]), on_press))


func _say() -> void:
	var text: String = _speech_input.text.strip_edges()
	if text.is_empty():
		return
	_speech_input.text = ""
	_speech_input.release_focus()
	platform.call("emit_speech", text)


func _make_button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = ACCENT.darkened(0.3)
	normal.set_content_margin_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.pressed.connect(action)
	return button


func _fit() -> void:
	var safe: Rect2 = PlatformServices.get_safe_rect()
	_panel.position = safe.position
	_panel.size = Vector2(safe.size.x, 0)
	_panel.reset_size()
	_panel.size.x = safe.size.x
