extends Node
## Access to the game (autoload "PlayTime"): the continuous-play limit and the office network.
## While a player is signed in and the game is on screen, it sends a heartbeat to the server
## (server/modules/play.go), which adds up the play time. The answer says what to show: after the
## limit a warning with a countdown to leave the game; leaving in time (closing the game or "Rest
## now") means the rest screen until the rest ends; playing past the countdown locks the game until
## tomorrow. A task minigame is never interrupted: when the limit comes during one, a small notice
## says the rest starts after it, and it does as soon as the minigame ends.
## Outside the office network the server refuses the game; then a screen asks to connect to the
## office Wi-Fi and checks again by itself. The same screen waits before the sign-in while the server
## cannot be reached at all. The server decides everything; this only shows it.

## Emitted when the player may play (again): after the rest or when nothing stops them.
signal released
## A heartbeat answer was applied (or the heartbeat failed).
signal checked

## Fallback heartbeat interval until the server names one.
const DEFAULT_BEAT_SECONDS: float = 30.0
## While locked for the day, ask now and then whether the new day has come.
const BLOCKED_POLL_SECONDS: float = 60.0
## Outside the office network, check this often whether the player is back on its Wi-Fi.
const NETWORK_POLL_SECONDS: float = 10.0
const OFFICE_NETWORK_ERROR: String = "office_network_required"

var _state: BackendModels.PlayStatus.State = BackendModels.PlayStatus.State.OK
var _overlay: PlayOverlay
var _beat_interval: float = DEFAULT_BEAT_SECONDS
var _beat_left: float = 0.0
var _focused: bool = true
var _beating: bool = false
## Countdown of the grace (WARNING) or of the rest (RESTING), in seconds.
var _countdown: float = 0.0
## The warning was already shown for the current grace, so it does not pop up on every heartbeat.
var _warning_shown: bool = false
## A minigame (or the QR scanner) is on screen; `_minigame_task` is its task, "" for the scanner.
var _in_minigame: bool = false
var _minigame_task: String = ""
## The last request came from outside the office network.
var _off_network: bool = false
## A heartbeat was asked for while one was running; send another right after it.
var _beat_again: bool = false
## wait_for_server() shows the office network screen before the sign-in.
var _waiting_server: bool = false
var _retry_requested: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = PlayOverlay.new()
	add_child(_overlay)
	_overlay.rest_now_pressed.connect(_on_rest_now)
	_overlay.resume_pressed.connect(_on_resume)
	_overlay.retry_pressed.connect(_on_retry)
	Backend.office_network_required.connect(_on_network_lost)


## Before entering the game: one heartbeat, then waits while the player has to rest or is outside
## the office network. A game locked for the day keeps the lock screen up until the next day.
func wait_until_allowed() -> void:
	if _beating:
		await checked
	else:
		await _beat()
	if (
		_off_network
		or _state == BackendModels.PlayStatus.State.RESTING
		or _state == BackendModels.PlayStatus.State.BLOCKED
	):
		await released


## No answer from the server: it is reachable only from the office network. Shows the office network
## screen until the server answers ("Check again" or a check every NETWORK_POLL_SECONDS).
func wait_for_server() -> void:
	_waiting_server = true
	_overlay.hide_warning()
	_overlay.show_network()
	while not await Backend.server.is_reachable():
		_retry_requested = false
		var waited: float = 0.0
		while waited < NETWORK_POLL_SECONDS and not _retry_requested:
			await get_tree().process_frame
			waited += get_process_delta_time()
	_waiting_server = false
	_overlay.hide_screen()


## Asks the server right away, e.g. after a dev RPC changed the play-time state.
func check_now() -> void:
	_beat()


## A task minigame (or the QR scanner, with "") opens. Call end_minigame() once its result is
## handled, so the server never starts the rest before the task is counted.
func begin_minigame(task_id: String = "") -> void:
	_in_minigame = true
	_minigame_task = task_id
	_beat_left = 0.0


func end_minigame() -> void:
	_in_minigame = false
	_minigame_task = ""
	_overlay.hide_deferred_notice()
	match _state:
		BackendModels.PlayStatus.State.DEFERRED:
			# The time ran out during the minigame: the rest starts now.
			_beat_left = 0.0
			_beat()
		BackendModels.PlayStatus.State.WARNING:
			if not _warning_shown:
				_warning_shown = true
				_overlay.show_warning_again()


## Why a new task cannot start now because of the play-time limit, "" when it can.
func task_lock_text() -> String:
	match _state:
		BackendModels.PlayStatus.State.WARNING, BackendModels.PlayStatus.State.DEFERRED:
			return tr("PLAY_TASKS_AFTER_REST")
	return ""


func _process(delta: float) -> void:
	if _waiting_server:
		return
	if not Backend.is_account_loaded():
		_reset()
		return
	match _state:
		BackendModels.PlayStatus.State.WARNING:
			_countdown = maxf(0.0, _countdown - delta)
			_overlay.set_grace_left(ceili(_countdown))
			if _countdown <= 0.0:
				# The grace is over: the server locks the game unless the player has left.
				_beat_left = 0.0
		BackendModels.PlayStatus.State.RESTING:
			if _countdown > 0.0 and not _off_network:
				_countdown = maxf(0.0, _countdown - delta)
				_overlay.set_rest_left(ceili(_countdown))
				if _countdown <= 0.0:
					_beat()
			if not _off_network:
				return
	var polling: bool = _off_network or _state == BackendModels.PlayStatus.State.BLOCKED
	if not polling and (not _focused or _overlay.is_screen_open()):
		# In the background, or the rest is over and the player has not come back yet.
		return
	_beat_left -= delta
	if _beat_left <= 0.0:
		_beat()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if not _focused:
				_focused = true
				# Back from the background: the server may have started the rest meanwhile.
				_beat_left = 0.0


func _beat() -> void:
	if _beating:
		_beat_again = true
		return
	_beating = true
	var status: BackendModels.PlayStatus = await Backend.play_heartbeat(_minigame_task)
	_beating = false
	_beat_left = _beat_interval
	if status.error == OFFICE_NETWORK_ERROR:
		_on_network_lost()
	elif status.ok:
		if _off_network:
			_off_network = false
			_overlay.hide_screen()
		_apply(status)
	checked.emit()
	if _beat_again:
		_beat_again = false
		_beat()


func _apply(status: BackendModels.PlayStatus) -> void:
	_beat_interval = float(status.beat_seconds)
	var previous: BackendModels.PlayStatus.State = _state
	_state = status.state
	if _state != BackendModels.PlayStatus.State.DEFERRED:
		_overlay.hide_deferred_notice()
	match _state:
		BackendModels.PlayStatus.State.OK:
			_warning_shown = false
			_overlay.hide_warning()
			if previous == BackendModels.PlayStatus.State.RESTING:
				# The player comes back with a tap, not by itself.
				_overlay.show_rest_done()
			else:
				_overlay.hide_screen()
				released.emit()
		BackendModels.PlayStatus.State.WARNING:
			_countdown = float(status.seconds_left)
			_overlay.set_grace_left(status.seconds_left)
			if _warning_shown:
				pass
			elif _in_minigame:
				# Never over a minigame: only the countdown pill; the warning follows when it closes.
				_overlay.prepare_warning(status)
				_overlay.collapse_warning()
			else:
				_warning_shown = true
				_overlay.prepare_warning(status)
				_overlay.show_warning_again()
		BackendModels.PlayStatus.State.DEFERRED:
			_warning_shown = false
			_overlay.hide_warning()
			_overlay.show_deferred_notice()
		BackendModels.PlayStatus.State.RESTING:
			_warning_shown = false
			_countdown = float(status.seconds_left)
			_overlay.show_rest(status.seconds_left)
		BackendModels.PlayStatus.State.BLOCKED:
			_warning_shown = false
			_beat_interval = BLOCKED_POLL_SECONDS
			_beat_left = BLOCKED_POLL_SECONDS
			_overlay.show_blocked()


## A request was refused outside the office network: cover the game until the player is back.
func _on_network_lost() -> void:
	if not Backend.is_account_loaded():
		return
	if not _off_network:
		_off_network = true
		_overlay.hide_warning()
		_overlay.hide_deferred_notice()
		_overlay.show_network()
	_beat_left = NETWORK_POLL_SECONDS


func _on_retry() -> void:
	if _waiting_server:
		_retry_requested = true
	elif Backend.is_account_loaded():
		check_now()


func _on_rest_now() -> void:
	var status: BackendModels.PlayStatus = await Backend.play_rest()
	if status.ok:
		_apply(status)


## The rest is over and the player taps "Back to the game".
func _on_resume() -> void:
	_overlay.hide_screen()
	_beat_left = 0.0
	released.emit()


## Signed out: nothing to count and nothing to show.
func _reset() -> void:
	if _state != BackendModels.PlayStatus.State.OK or _off_network or _overlay.is_screen_open():
		_state = BackendModels.PlayStatus.State.OK
		_off_network = false
		_warning_shown = false
		_overlay.hide_warning()
		_overlay.hide_deferred_notice()
		_overlay.hide_screen()
	_in_minigame = false
	_minigame_task = ""
	_beat_left = 0.0
