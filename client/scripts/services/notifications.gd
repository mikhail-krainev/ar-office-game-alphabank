extends Node
## Notifications (autoload "Notifications").
## Scheduled: the server plans reminders (streak, check-in, parking draw) and light-hearted nudges;
## this service hands the plan to the OS through PlatformServices and replaces it whenever the game
## goes to the background or something changes.
## Events: new inbox messages (a fine, a lost streak, a photo to confirm, a draw result) show as an
## in-game banner while the game is open. When it is closed the real server delivers them as push
## notifications (FCM / APNs / Web Push); the mock server cannot, so they wait in the inbox.

signal unread_changed(count: int)
## The player tapped a banner.
signal banner_pressed(kind: String)

const SETTINGS_PATH: String = "user://notifications.cfg"
const POLL_INTERVAL: float = 10.0
## Changes during play replan at most this often; going to the background always replans.
const RESYNC_INTERVAL: float = 30.0
const BANNER_TIME: float = 4.5
const BANNER_SLIDE: float = 0.25

var unread: int = 0

var _last_seen_id: int = 0
## The first poll after launch only sets the baseline; old news is in the inbox.
var _has_baseline: bool = false
var _poll_left: float = 0.0
var _resync_left: float = 0.0
var _resync_wanted: bool = false
var _polling: bool = false
## A poll was asked for while one was running; run another right after it.
var _poll_again: bool = false
var _syncing: bool = false
var _enabled: bool = false
var _queue: Array[Array] = []
var _banner_left: float = 0.0
var _banner_kind: String = ""

var _layer: CanvasLayer
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label


func _ready() -> void:
	_build_banner()
	_enabled = _load_setting("enabled", false)
	Backend.inbox_may_have_changed.connect(_on_state_changed)
	PlatformServices.notification_shown.connect(func(title: String, body: String) -> void: _show_banner(title, body, ""))
	# The desktop asks right away; browsers need a tap, so the web asks from the profile.
	if not _load_setting("asked", false) and not OS.has_feature("web") and is_supported():
		_ask_on_first_login.call_deferred()


func is_supported() -> bool:
	return PlatformServices.has_feature(PlatformBackend.Feature.NOTIFICATIONS)


func is_enabled() -> bool:
	return _enabled and is_supported()


## Asks the OS for permission (call from a button handler on the web) and schedules the plan.
func enable() -> bool:
	_save_setting("asked", true)
	var features: Array[PlatformBackend.Feature] = [PlatformBackend.Feature.NOTIFICATIONS]
	_enabled = is_supported() and await PlatformServices.request_access(features)
	_save_setting("enabled", _enabled)
	await sync_schedule()
	return _enabled


func disable() -> void:
	_enabled = false
	_save_setting("enabled", false)
	PlatformServices.replace_notifications([])


## Replaces the OS schedule with the server's current plan.
func sync_schedule() -> void:
	if _syncing or Backend.profile == null:
		return
	_syncing = true
	_resync_wanted = false
	_resync_left = RESYNC_INTERVAL
	var items: Array[Dictionary] = []
	if is_enabled():
		for item: BackendModels.PlannedNotification in await Backend.get_notification_plan():
			var body: String = NotificationTexts.planned_text(item.kind, item.params)
			items.append({"id": item.id, "title": NotificationTexts.title(), "body": body, "delay": item.delay_seconds})
	PlatformServices.replace_notifications(items)
	_syncing = false


## Reads the inbox, updates the unread badge and announces messages that arrived since the last poll.
func poll() -> void:
	if Backend.profile == null:
		return
	if _polling:
		_poll_again = true
		return
	_polling = true
	_poll_left = POLL_INTERVAL
	var items: Array[BackendModels.InboxItem] = await Backend.social.get_inbox()
	_polling = false
	if _poll_again:
		_poll_again = false
		_poll_left = 0.0
	var count: int = items.filter(func(item: BackendModels.InboxItem) -> bool: return not item.read or item.needs_answer()).size()
	if count != unread:
		unread = count
		unread_changed.emit(unread)
	var newest: int = _last_seen_id
	for index: int in range(items.size() - 1, -1, -1):
		var item: BackendModels.InboxItem = items[index]
		newest = maxi(newest, item.id)
		if _has_baseline and item.id > _last_seen_id:
			_show_banner(NotificationTexts.title(), NotificationTexts.inbox_text(item), item.kind)
	_last_seen_id = newest
	_has_baseline = true


func _on_state_changed() -> void:
	_poll_left = minf(_poll_left, 0.3)
	_resync_wanted = true


func _ask_on_first_login() -> void:
	while Backend.profile == null:
		await get_tree().create_timer(1.0).timeout
	await enable()


func _process(delta: float) -> void:
	if Backend.profile != null:
		_poll_left -= delta
		if _poll_left <= 0.0:
			poll()
		_resync_left -= delta
		if _resync_wanted and _resync_left <= 0.0:
			sync_schedule()
	_update_banner(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		sync_schedule()


# --- Banner ----------------------------------------------------------------------


func _build_banner() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 80
	add_child(_layer)
	_banner = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.panel(UiStyle.PAPER, 6, 8)
	style.border_width_left = 4
	style.border_color = UiStyle.RED
	_banner.add_theme_stylebox_override("panel", style)
	_banner.visible = false
	_banner.gui_input.connect(_on_banner_input)
	_layer.add_child(_banner)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(column)
	_banner_title = UiStyle.make_label("", 9, UiStyle.RED)
	column.add_child(_banner_title)
	_banner_text = UiStyle.make_label("", 11)
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_banner_text)


func _show_banner(title: String, text: String, kind: String) -> void:
	if text.is_empty():
		return
	_queue.append([title, text, kind])
	if _banner_left <= 0.0:
		_next_banner()


func _next_banner() -> void:
	if _queue.is_empty():
		_banner.visible = false
		return
	var entry: Array = _queue.pop_front()
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var width: float = safe.size.x - 16.0
	_banner_title.text = str(entry[0]).to_upper()
	_banner_text.text = str(entry[1])
	_banner_kind = str(entry[2])
	_banner_text.custom_minimum_size = Vector2(width - 20.0, 0)
	_banner.custom_minimum_size = Vector2(width, 0)
	_banner.position = Vector2(safe.position.x + 8.0, safe.position.y - 120.0)
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner_left = BANNER_TIME
	# An autowrapped label knows its height only after a layout pass.
	await get_tree().process_frame
	_banner.size = Vector2(width, 0)
	_banner.reset_size()
	_banner.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_property(_banner, "position:y", safe.position.y + 78.0, BANNER_SLIDE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_banner(delta: float) -> void:
	if _banner_left <= 0.0:
		return
	_banner_left -= delta
	if _banner_left <= 0.0:
		_next_banner()


func _on_banner_input(event: InputEvent) -> void:
	if Minigame.press_position(event) == null:
		return
	_banner.get_viewport().set_input_as_handled()
	var kind: String = _banner_kind
	_banner_left = 0.0
	_next_banner()
	banner_pressed.emit(kind)


# --- Settings --------------------------------------------------------------------


func _load_setting(key: String, default: bool) -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return default
	return bool(config.get_value("notifications", key, default))


func _save_setting(key: String, value: bool) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("notifications", key, value)
	config.save(SETTINGS_PATH)
