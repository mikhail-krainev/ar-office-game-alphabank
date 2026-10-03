extends Node
## DEV-ONLY keys on a desktop debug build (added by Backend). They call dev RPCs, so the server must
## run with DEV_MODE=true:
##   F9   the play-time warning now; Shift+F9 brings the play time back to normal
##   F8   a parking draw for everyone starts in one minute
##   F10  one day passes for this player (absence fines, lost streak); the scene reloads


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.keycode in [KEY_F8, KEY_F9, KEY_F10]:
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_F9:
		var state: String = "ok" if key.shift_pressed else "warning"
		await Backend.dev_call("dev_play_state", {"state": state})
		PlayTime.check_now()
		print("[dev] play time: ", state)
	elif key.keycode == KEY_F8:
		await Backend.dev_call("dev_schedule_raffle", {"seconds": 60})
		print("[dev] parking draw in 60 s")
	else:
		await Backend.dev_call("dev_skip_day")
		print("[dev] skipped a day")
		Backend.profile = null
		get_tree().reload_current_scene()
