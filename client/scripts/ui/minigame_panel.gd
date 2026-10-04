class_name MinigamePanel
extends CanvasLayer
## Modal host for a task minigame. run() resolves with the outcome once the player finishes, closes
## or skips it. Hard tasks show their difficulty tag; skippable ones get a "Skip" button.
## Physical minigames ask for sensor permissions first; without the sensors the task's screen-only
## fallback runs instead, and without a fallback the task is unavailable on this device.

signal _resolved(outcome: Outcome)

enum Outcome { SUCCESS, FAILED, CANCELLED, SKIPPED, UNAVAILABLE }

const RESULT_DELAY: float = 0.9

## Evidence collected by the last finished minigame, for Backend.complete_task().
var last_proof: Dictionary = {}

var _panel: PanelContainer
var _title: Label
var _host: Control
var _result: Label
var _close: Button
var _footer: HBoxContainer
var _badge_slot: HBoxContainer
var _skip: Button
var _game: Minigame
var _notice: Label


func _ready() -> void:
	layer = 30
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(UiStyle.make_dimmer())

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 10))
	center.add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	_title = UiStyle.make_label("", 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close = UiStyle.make_button("✕", false, 12)
	_close.pressed.connect(func() -> void: _resolved.emit(Outcome.CANCELLED))
	header.add_child(_close)

	_notice = UiStyle.make_label("", 10, UiStyle.HARD)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size = Vector2(Minigame.AREA_SIZE.x, 0)
	_notice.visible = false
	column.add_child(_notice)

	_host = Control.new()
	_host.custom_minimum_size = Minigame.AREA_SIZE
	column.add_child(_host)
	_result = UiStyle.make_label("", 22, UiStyle.RED)
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.label_settings.outline_size = 6
	_result.label_settings.outline_color = Color.WHITE
	_host.add_child(_result)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	column.add_child(_footer)
	_badge_slot = HBoxContainer.new()
	_badge_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_child(_badge_slot)
	_skip = UiStyle.make_button(tr("TASK_SKIP"), false, 11)
	_skip.custom_minimum_size = Vector2(0, 28)
	_skip.pressed.connect(func() -> void: _resolved.emit(Outcome.SKIPPED))
	_footer.add_child(_skip)


func is_open() -> bool:
	return visible


## `context` carries what the server prepared for the run, e.g. the assigned colleague.
func run(task: BackendModels.TaskInfo, context: Dictionary = {}) -> Outcome:
	last_proof = {}
	var kind: String = await _pick_minigame(task)
	if kind.is_empty():
		return Outcome.UNAVAILABLE
	var game: Minigame = Minigame.create(kind)
	game.task = task
	game.context = context
	return await _play(game, task.title, task.difficulty, task.difficulty_multiplier, task.skippable)


## Opens the camera to read any game QR code. Resolves to null when cancelled or unavailable.
func scan_code() -> QrPayload:
	last_proof = {}
	_notice.visible = false
	var features: Array[PlatformBackend.Feature] = [PlatformBackend.Feature.QR_SCAN]
	if not PlatformServices.has_features(features) or not await PlatformServices.request_access(features):
		return null
	var outcome: Outcome = await _play(QrScanMinigame.new(), tr("QR_SCAN_TITLE"), "normal", 1.0, false)
	if outcome != Outcome.SUCCESS:
		return null
	return QrPayload.parse(str(last_proof.get(QrScanMinigame.PROOF_KEY, "")))


func _play(game: Minigame, title: String, difficulty: String, multiplier: float, skippable: bool) -> Outcome:
	_title.text = title
	_result.visible = false
	_close.disabled = false
	_skip.disabled = false
	for child: Node in _badge_slot.get_children():
		child.queue_free()
	if difficulty != "normal":
		var badge: PanelContainer = UiStyle.make_difficulty_badge(difficulty, multiplier)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_badge_slot.add_child(badge)
	_skip.visible = skippable
	_footer.visible = difficulty != "normal" or skippable
	_game = game
	_game.finished.connect(_on_game_finished)
	_host.add_child(_game)
	_host.move_child(_game, 0)
	visible = true
	var outcome: Outcome = await _resolved
	last_proof = _game.proof.duplicate(true)
	_game.queue_free()
	_game = null
	visible = false
	return outcome


## The task's own minigame when the device has its sensors and the player allows them, else the fallback.
func _pick_minigame(task: BackendModels.TaskInfo) -> String:
	_notice.text = ""
	_notice.visible = false
	var features: Array[PlatformBackend.Feature] = Minigame.required_features(task.minigame)
	var reason: String = ""
	if not PlatformServices.has_features(features):
		reason = tr("MG_NO_SENSORS")
	elif not await PlatformServices.request_access(features):
		reason = _permission_text(features)
	if reason.is_empty():
		return task.minigame
	if task.fallback_minigame.is_empty():
		return ""
	_notice.text = reason + " " + tr("MG_FALLBACK")
	_notice.visible = true
	return task.fallback_minigame


## What to ask the player to allow. For the microphone the platform may know where it is blocked.
static func _permission_text(features: Array[PlatformBackend.Feature]) -> String:
	var key: String = _permission_key(features)
	if key != "MG_NO_MIC_PERMISSION":
		return TranslationServer.translate(key)
	var problem: PackedStringArray = PlatformServices.access_problem().split(":")
	if problem[0] == "microphone_system":
		key = "MG_NO_MIC_SYSTEM"
	var text: String = TranslationServer.translate(key)
	return text + (" (%s)" % problem[1] if problem.size() > 1 else "")


## What to ask the player to allow, by the sensors the minigame needs.
static func _permission_key(features: Array[PlatformBackend.Feature]) -> String:
	if features.has(PlatformBackend.Feature.MICROPHONE) or features.has(PlatformBackend.Feature.SPEECH_RECOGNITION):
		return "MG_NO_MIC_PERMISSION"
	for feature: PlatformBackend.Feature in features:
		if feature not in [PlatformBackend.Feature.ACCELEROMETER, PlatformBackend.Feature.PEDOMETER]:
			return "MG_NO_CAMERA_PERMISSION"
	return "MG_NO_PERMISSION"


func show_reward(amount: int) -> void:
	_result.text = tr("MG_SUCCESS") % amount


func _on_game_finished(success: bool) -> void:
	_close.disabled = true
	_skip.disabled = true
	if not _game.shows_result:
		_resolved.emit(Outcome.SUCCESS if success else Outcome.FAILED)
		return
	_result.visible = true
	_result.text = tr("MG_DONE") if success else tr("MG_FAIL")
	await get_tree().create_timer(RESULT_DELAY).timeout
	_resolved.emit(Outcome.SUCCESS if success else Outcome.FAILED)
