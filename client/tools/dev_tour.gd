extends Node
## Dev check: walks through home, commute intro and office, driving the scenes directly and saving
## screenshots. Plays as the account signed in on this computer (sign in through the game once) on
## a server with DEV_MODE=true; the tour changes that account's progress, so use a test account.
## Run (GUI): godot --path client res://tools/dev_tour.tscn -- --device=pixel_8 --out=<dir> [--shot-scale=2]
## --shot-scale below 1 shrinks screenshots smoothly, 1 and above enlarges them with crisp pixels.
## --only=play runs only the play-time limit screens. The tour turns the task limits (hours and the
## pause between tasks) off for the account, so it can close a whole day at any hour.

var _out: String = ""
var _shot_scale: float = 0.5
var _only: String = ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--shot-scale="):
			_shot_scale = maxf(0.1, argument.trim_prefix("--shot-scale=").to_float())
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
	# The emulator's key help would end up in the screenshots.
	var emulator: Node = get_node_or_null("/root/DeviceEmulator")
	if emulator != null and emulator.get("_help") is Label:
		(emulator.get("_help") as Label).visible = false
	# So would the desktop sensor emulator panel; the tour drives the emulated sensors itself.
	var sensor_emulator: CanvasLayer = PlatformServices.get_node("Backend").get("_emulator") as CanvasLayer
	if sensor_emulator != null:
		sensor_emulator.layer = -100
		sensor_emulator.visible = false
	_start.call_deferred()


func _start() -> void:
	# Survive scene changes: move to the root and leave an empty placeholder as the current scene.
	var tree: SceneTree = get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	var placeholder: Node = Node.new()
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	if not Backend.server.restore() or not (await Backend.load_account()).is_empty():
		printerr("dev tour: sign in through the game once, then run the tour again")
		tree.quit(1)
		return
	await _wait(0.5)
	await Backend.dev_call("dev_task_limits", {"off": true})
	if _only == "play":
		await _play_limit_tour()
		tree.quit()
		return
	await _morning_tour()
	await _home_tour()
	await _commute_tour()
	await _office_tour()
	await _evening_tour()
	await _social_tour()
	await _analytics_tour()
	await _play_limit_tour()
	await _office_screen_tour()
	tree.quit()


func _morning_tour() -> void:
	get_tree().change_scene_to_file("res://scenes/intro/morning_intro.tscn")
	await _wait(2.6)
	await _shot("m1_wake")
	await _wait(8.2)
	await _shot("m2_bath")


func _home_tour() -> void:
	get_tree().change_scene_to_file("res://scenes/home/home.tscn")
	await _wait(2.5)
	await _shot("h1_start")
	var home: Node = get_tree().current_scene
	var layout: HomeLayout = (home.get("_map") as WorldMap).layout
	await _teleport(home, _find(layout, "wardrobe").stand_cell)
	await _wait(1.2)
	await _shot("h2_bedroom")
	home.call("_open_wardrobe")
	await _wait(1.5)
	await _shot("h3_wardrobe")
	var wardrobe: WardrobePanel = home.get("_wardrobe")
	wardrobe.call("_select_slot", "hat")
	await _wait(0.6)
	await _shot("h4_wardrobe_hats")
	var state: BackendModels.WardrobeState = wardrobe.get("_state")
	var wanted: Array[String] = ["hat:cowboy", "back:angel_wings", "hand:balloon", "top:hawaiian"]
	for item: BackendModels.WardrobeItem in state.items:
		if wanted.has(item.slot + ":" + item.id):
			wardrobe.call("_on_item_pressed", item)
	wardrobe.call("_select_slot", "back")
	await _wait(0.8)
	await _shot("h5_wardrobe_back")
	wardrobe.call("_save_and_close")
	await _wait(1.2)
	await _shot("h6_new_look")
	await _teleport(home, _find(layout, "keys").stand_cell)
	home.call("_open_garage")
	await _wait(1.5)
	await _shot("h9_garage")
	(home.get("_shop_panel") as ShopPanel).visible = false
	await _teleport(home, _find(layout, "sink").stand_cell)
	await _wait(1.0)
	await _shot("h10_bathroom_remark")


func _commute_tour() -> void:
	get_tree().change_scene_to_file("res://scenes/intro/commute_intro.tscn")
	await _wait(4.0)
	await _shot("c1_parking_retry")
	await _wait(5.0)
	await _shot("c2_autobahn")
	await _wait(4.4)
	await _shot("c3_traffic")
	await _wait(4.5)
	await _shot("c4_arrival")
	await Backend.dev_call("dev_grant_coins", {"amount": 6000})
	var result: BackendModels.PurchaseResult = await Backend.buy_car("audi_rs6")
	if result.status == BackendModels.PurchaseResult.Status.GRANTED:
		await Backend.select_car("audi_rs6")
	get_tree().change_scene_to_file("res://scenes/intro/commute_intro.tscn")
	await _wait(4.2)
	await _shot("c5_rs6_parking")
	await _wait(5.6)
	await _shot("c6_rs6_autobahn")


func _office_tour() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.5)
	await _shot("o1_start")
	var office: Node = get_tree().current_scene
	await _teleport(office, Vector2i(24, 23))
	await _wait(1.0)
	await _shot("o2_reception_pins")
	for child: Node in (office.get("_entities") as Node).get_children():
		var npc: Npc = child as Npc
		if npc != null and npc.definition.id == "reception":
			office.call("_chat_with", npc)
	await _wait(4.0)
	await _shot("o3_reception_talk")
	await _wait(6.0)
	office.call("_open_tasks")
	await _wait(1.0)
	await _shot("o4_tasks")
	(office.get("_task_panel") as TaskPanel).close_panel()
	await _minigame_tour(office)
	office.call("_open_shop")
	await _wait(1.2)
	await _shot("o6_shop")
	(office.get("_shop_panel") as ShopPanel).visible = false
	office.call("_open_tasks")
	await _wait(1.0)
	await _shot("o8_tasks_difficulty")
	(office.get("_task_panel") as TaskPanel).close_panel()
	# Close every task so the "Go home" button appears. Check-in goes first: the server accepts other
	# tasks only inside the office. Tasks with a colleague stay open when nobody else is in the office.
	await _check_in()
	for task: BackendModels.TaskInfo in office.get("_tasks"):
		if task.skippable:
			await Backend.skip_task(task.id)
		elif task.assignment.is_empty():
			await _take(task)
			await Backend.complete_task(task.id, true, {"colleague_ids": []})
	office.call("_refresh_tasks")
	await _wait(1.0)
	await _teleport(office, Vector2i(24, 23))
	await _shot("o9_go_home_button")
	office.call("_go_home")
	await _wait(1.5)
	await _shot("o10_walking_out")


## Opens every task minigame, feeds the emulated sensors and takes a screenshot of each.
func _minigame_tour(office: Node) -> void:
	var desktop: Node = PlatformServices.get_node("Backend")
	var panel: MinigamePanel = office.get("_minigame_panel")
	var setups: Dictionary[String, Callable] = {
		"carry_coffee": func() -> void: desktop.set("tilt", Vector2(14, -8)),
		"find_object": func() -> void: desktop.set("label_id", OfficeObjects.all_labels()[0]),
		"squats": func() -> void: desktop.set("squat_depth", 0.8),
		"selfie": func() -> void:
			desktop.set("face_count", 2)
			desktop.set("smiling", false),
		"scavenger_hunt": func() -> void: desktop.set("marker_id", 2),
		"stairs": func() -> void: desktop.call("add_steps", 47),
	}
	var index: int = 0
	for task: BackendModels.TaskInfo in office.get("_tasks"):
		if task.floor_id != OfficeFloors.current or not task.assignment.is_empty():
			continue
		index += 1
		await _teleport(office, task.spot)
		await _take(task)
		office.call("_go_to_task", task)
		await _wait(0.8)
		if setups.has(task.minigame):
			setups[task.minigame].call()
		await _wait(0.9)
		await _shot("g%d_%s" % [index, task.minigame])
		if task.minigame == "tongue_twister":
			var game: Minigame = panel.get("_game")
			game.call("_listen")
			await _wait(0.3)
			desktop.call("emit_speech", "Шла Саша по шоссе")
			await _wait(0.1)
			await _shot("g%d_%s_listening" % [index, task.minigame])
		if panel.is_open():
			panel.emit_signal("_resolved", MinigamePanel.Outcome.CANCELLED)
		desktop.set("tilt", Vector2.ZERO)
		await _wait(0.5)
	office.call("_scan_code")
	await _wait(1.0)
	await _shot("g_scan_qr")
	var scanner: Minigame = panel.get("_game")
	scanner.call("_toggle_profile")
	await _wait(0.4)
	await _shot("g_profile_qr")
	panel.emit_signal("_resolved", MinigamePanel.Outcome.CANCELLED)
	await _wait(0.5)


## Photo with a colleague, inbox, profile and the parking draw on a fresh office day.
func _social_tour() -> void:
	OfficeFloors.reset()
	await Backend.dev_call("dev_reset_day")
	await _check_in()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.5)
	var office: Node = get_tree().current_scene
	var desktop: Node = PlatformServices.get_node("Backend")
	var panel: MinigamePanel = office.get("_minigame_panel")
	await _teleport(office, (office.get("_map") as WorldMap).layout.elevator_cell)
	await _wait(0.6)
	await _shot("s1_lift")
	for task: BackendModels.TaskInfo in office.get("_tasks"):
		if task.id != "selfie":
			continue
		await _teleport(office, task.spot)
		await _take(task)
		office.call("_go_to_task", task)
		await _wait(1.2)
		await _shot("s2_photo_partner")
		desktop.set("face_count", 2)
		desktop.set("smiling", true)
		(panel.get("_game") as Minigame).call("_start_camera")
		await _wait(0.6)
		await _shot("s3_photo_camera")
		await _wait(2.6)
		await _shot("s4_photo_sent")
	desktop.set("face_count", 0)
	Notifications.poll()
	await _wait(1.2)
	var corner: PlayerCorner = office.get("_corner")
	corner.open_inbox()
	await _wait(1.2)
	await _shot("s6_inbox")
	(office.get_node("InboxPanel") as ModalPanel).close_panel()
	corner.open_profile()
	await _wait(1.2)
	await _shot("s7_profile")
	var profile: ProfilePanel = office.get_node("ProfilePanel")
	(profile.get("_scroll") as ScrollContainer).scroll_vertical = 330
	await _wait(0.4)
	await _shot("s8_profile_streak")
	profile.set("_show_calendar", true)
	await profile.call("_reload")
	(profile.get("_scroll") as ScrollContainer).scroll_vertical = 330
	await _wait(0.6)
	await _shot("s9_profile_calendar")
	(profile.get("_scroll") as ScrollContainer).scroll_vertical = 700
	await _wait(0.4)
	await _shot("s10_profile_history")
	profile.close_panel()
	await _raffle_tour(office)


## Scans the task's room code and takes the task, as the player does at the room door. Before the
## check-in the server refuses both; the task is still marked taken, so its minigame opens for a shot.
func _take(task: BackendModels.TaskInfo) -> void:
	if not task.is_check_in():
		await Backend.enter_room(String(task.room))
		await Backend.take_task(task.id)
	task.taken = true


## Entry code from the dev server, then the check-in task (or a plain entry if it is done today).
func _check_in() -> void:
	var codes: ServerSession.RpcResult = await Backend.dev_call("dev_presence_codes")
	var token: String = str(codes.data.get("entry", ""))
	var result: BackendModels.TaskResult = await Backend.complete_task("check_in", true, {"presence_token": token})
	if not result.ok:
		await Backend.check_in(token)


func _raffle_tour(office: Node) -> void:
	await Backend.dev_call("dev_set_office_days", {"days": 10})
	await Backend.dev_call("dev_grant_coins", {"amount": 3000})
	await Backend.dev_call("dev_schedule_raffle", {"seconds": 2 * 86400 + 5 * 3600 + 17 * 60})
	office.call("_open_shop")
	var shop: ShopPanel = office.get("_shop_panel")
	await _wait(0.5)
	await shop.call("_select_tab", ShopPanel.Tab.RAFFLE)
	await _wait(0.6)
	await _shot("r1_raffle")
	await shop.call("_on_buy_ticket")
	await _wait(0.6)
	await _shot("r2_raffle_ticket")
	await Backend.dev_call("dev_draw_now")
	await shop.call("_reload")
	await _wait(0.6)
	await _shot("r3_raffle_results")
	var state: BackendModels.RaffleState = await Backend.raffle.get_raffle()
	shop.call("_watch_draw", state)
	await _wait(2.0)
	await _shot("r4_roulette_spin")
	await _wait(6.0)
	await _shot("r5_roulette_winner")
	for child: Node in shop.get_children():
		if child is RaffleRoulette:
			child.emit_signal("finished")
			child.queue_free()
	await _wait(0.8)
	shop.visible = false
	await Backend.dev_call("dev_clear_raffle")


## The product analytics floor: rooms, NPCs and the meet-a-colleague tasks.
func _analytics_tour() -> void:
	get_tree().current_scene.call("_travel", OfficeFloors.ANALYTICS)
	await _wait(2.8)
	var office: Node = get_tree().current_scene
	await _shot("a1_lift_hall")
	for entry: Array in [[Vector2i(12, 9), "a2_open_space"], [Vector2i(36, 9), "a3_data_lab"], [Vector2i(22, 22), "a4_coffee"], [Vector2i(37, 21), "a5_workshop"]]:
		await _teleport(office, entry[0])
		await _wait(0.8)
		await _shot(str(entry[1]))
	office.call("_open_tasks")
	await _wait(1.0)
	await _shot("a6_tasks")
	(office.get("_task_panel") as TaskPanel).close_panel()
	var panel: MinigamePanel = office.get("_minigame_panel")
	for task: BackendModels.TaskInfo in office.get("_tasks"):
		if task.floor_id != OfficeFloors.ANALYTICS or task.minigame == "meet_colleague" and task.assignment.is_empty():
			continue
		await _teleport(office, task.spot)
		await _take(task)
		office.call("_go_to_task", task)
		await _wait(1.4)
		await _shot("a7_%s" % task.id)
		if panel.is_open():
			panel.emit_signal("_resolved", MinigamePanel.Outcome.CANCELLED)
		await _wait(0.5)
	for child: Node in (office.get("_entities") as Node).get_children():
		var npc: Npc = child as Npc
		if npc != null and npc.definition.id == "masha":
			await _teleport(office, (office.get("_map") as WorldMap).world_to_cell(npc.global_position) + Vector2i(0, 1))
			office.call("_chat_with", npc)
	await _wait(2.0)
	await _shot("a8_talk_masha")
	OfficeFloors.reset()


func _evening_tour() -> void:
	await _wait(3.0)
	await _shot("e1_leave_office")
	await _wait(3.4)
	await _shot("e2_night_city")
	await _wait(4.4)
	await _shot("e3_home_arrival")
	await _wait(5.6)
	await _shot("e4_sleep")
	await _wait(3.0)
	await _shot("e5_lights_out")


## The task list under the limits, then the play-time limit: the warning, its countdown pill, the
## rest screen, the end of the rest and the day lock. The dev RPC sets the state; PlayTime shows it as after a real heartbeat.
func _play_limit_tour() -> void:
	OfficeFloors.reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.5)
	# The task list with the limits on: today's pack and the pause after the last task.
	await Backend.dev_call("dev_task_limits", {"off": false})
	var office: Node = get_tree().current_scene
	office.call("_open_tasks")
	await _wait(1.0)
	await _shot("p0_tasks_limits")
	(office.get("_task_panel") as TaskPanel).close_panel()
	await Backend.dev_call("dev_task_limits", {"off": true})
	var overlay: PlayOverlay = PlayTime.get("_overlay")
	for step: Array in [["warning", "p1_play_warning"], ["resting", "p3_play_rest"], ["blocked", "p5_play_blocked"]]:
		await Backend.dev_call("dev_play_state", {"state": step[0]})
		PlayTime.check_now()
		await _wait(1.5)
		await _shot(step[1])
		if step[0] == "warning":
			overlay.collapse_warning()
			await _wait(0.4)
			await _shot("p2_play_pill")
		elif step[0] == "resting":
			overlay.show_rest_done()
			await _wait(0.4)
			await _shot("p4_play_rest_done")
	await Backend.dev_call("dev_play_state", {"state": "ok"})
	PlayTime.check_now()
	await _wait(1.0)
	await _deferred_rest_tour()
	# Outside the office network every game call is refused and this screen covers the game.
	overlay.show_network()
	await _wait(0.6)
	await _shot("p7_office_network")
	overlay.hide_screen()


## The limit comes during a minigame: a quiet notice, no warning; the rest starts when it closes.
func _deferred_rest_tour() -> void:
	var office: Node = get_tree().current_scene
	var panel: MinigamePanel = office.get("_minigame_panel")
	for task: BackendModels.TaskInfo in office.get("_tasks"):
		if task.is_closed() or task.is_check_in() or not task.assignment.is_empty():
			continue
		if task.floor_id != OfficeFloors.current:
			continue
		await _teleport(office, task.spot)
		await _take(task)
		office.call("_go_to_task", task)
		await _wait(1.0)
		await Backend.dev_call("dev_play_state", {"state": "deferred"})
		PlayTime.check_now()
		await _wait(1.5)
		await _shot("p6_play_deferred")
		panel.emit_signal("_resolved", MinigamePanel.Outcome.CANCELLED)
		await _wait(2.0)
		await _shot("p6b_play_rest_after_minigame")
		break
	await Backend.dev_call("dev_play_state", {"state": "ok"})
	PlayTime.check_now()
	await _wait(1.0)


## The reception screen with the rotating presence code, normally shown on a TV in the office.
func _office_screen_tour() -> void:
	get_tree().change_scene_to_file("res://scenes/kiosk/office_screen.tscn")
	await _wait(1.2)
	await _shot("k1_office_screen")


func _find(layout: HomeLayout, id: String) -> HomeLayout.Interactable:
	for use: HomeLayout.Interactable in layout.interactables:
		if use.id == id:
			return use
	return null


func _teleport(scene: Node, cell: Vector2i) -> void:
	var map: WorldMap = scene.get("_map")
	var player: Player = scene.get("_player")
	player.walk_path(PackedVector2Array())
	player.global_position = map.cell_to_world(cell)
	(scene.get("_camera") as GameCamera).snap_to_target()
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var image: Image = get_tree().root.get_texture().get_image()
	var interpolation: Image.Interpolation = Image.INTERPOLATE_NEAREST if _shot_scale >= 1.0 else Image.INTERPOLATE_BILINEAR
	image.resize(roundi(image.get_width() * _shot_scale), roundi(image.get_height() * _shot_scale), interpolation)
	image.save_png("%s/t-%s.png" % [_out, shot_name])
	print("shot ", shot_name)
