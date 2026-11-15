extends Node
## Screenshots of the 21 and roulette tables with made-up room states, without a server:
## godot --path client res://tools/casino_preview.tscn -- --out=/tmp/casino
## Nothing here talks to Nakama; the views only draw the states they receive.

const PANEL_WIDTH: float = 340.0

var _out: String = "user://casino_preview"
var _layer: CanvasLayer
var _view: LoungeCasinoView


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	# Without a session the backend opens the login scene: this node must outlive that switch.
	get_tree().current_scene = null
	Backend.apply_balance(480)
	await _blackjack_solo()
	await _blackjack_multi()
	await _roulette()
	get_tree().quit()


func _me() -> String:
	return Backend.get_user_id()


func _player(id: String, player_name: String, extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {"id": id, "name": player_name, "avatar": "me", "outfit": {}, "ready": false, "done": false, "eliminated": false, "departed": false}
	p.merge(extra, true)
	return p


func _mount(view: LoungeCasinoView) -> void:
	if _layer != null:
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("#3a3533")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 10))
	panel.position = Vector2(10, 40)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_layer.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	column.add_child(UiStyle.make_label("21" if view is LoungeBlackjackView else "Рулетка", 16))
	column.add_child(view)
	_view = view


func _shot(file_name: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_out.path_join(file_name + ".png"))
	print("shot ", file_name)


func _blackjack_solo() -> void:
	var room: Dictionary = {"id": "BJ1", "game": "blackjack", "host": _me(), "phase": "waiting", "stake": 20, "round": 0, "players": [_player(_me(), "Миша")]}
	_mount(LoungeBlackjackView.new(room))
	await _shot("bj_1_waiting", 0.5)
	room = room.duplicate(true)
	room["phase"] = "playing"
	room["round"] = 1
	room["left"] = 55
	room["players"] = [_player(_me(), "Миша", {"cards": [19, 51], "ready": true})]
	room["dealer"] = [31]
	_view.update_room(room)
	await _shot("bj_2_dealing", 0.35)
	await _shot("bj_3_playing", 1.2)
	room = room.duplicate(true)
	room["players"] = [_player(_me(), "Миша", {"cards": [19, 51, 2], "done": true})]
	room["phase"] = "finished"
	room["dealer"] = [31, 22, 46]
	room["awards"] = {_me(): 40}
	room["outcomes"] = {_me(): "win"}
	room["message"] = "Твоя победа! Ещё партию?"
	_view.update_room(room)
	await _shot("bj_4_reveal", 0.45)
	await _shot("bj_5_finished", 1.6)


func _blackjack_multi() -> void:
	var others: Array = [_player("a", "Аня", {"card_count": 2}), _player("b", "Пётр Иванов", {"card_count": 3, "done": true}), _player("c", "Оля", {"card_count": 2, "done": true})]
	var room: Dictionary = {"id": "BJ2", "game": "blackjack", "host": "a", "phase": "playing", "stake": 50, "round": 1, "left": 8, "players": [_player(_me(), "Миша", {"cards": [0, 10]})] + others}
	_mount(LoungeBlackjackView.new(room))
	await _shot("bj_6_multi", 1.8)


func _roulette() -> void:
	var players: Array = [_player(_me(), "Миша"), _player("a", "Аня"), _player("b", "Пётр")]
	var bets: Array = [
		{"player": 0, "field": "red", "amount": 20}, {"player": 0, "field": "red", "amount": 40},
		{"player": 0, "field": "n17", "amount": 10}, {"player": 1, "field": "black", "amount": 50},
		{"player": 2, "field": "n17", "amount": 5}, {"player": 0, "field": "green", "amount": 5},
		{"player": 1, "field": "n17", "amount": 5}, {"player": 2, "field": "black", "amount": 20},
		{"player": 2, "field": "n8", "amount": 20}, {"player": 1, "field": "green", "amount": 10},
	]
	var room: Dictionary = {"id": "RL1", "game": "roulette", "host": _me(), "phase": "betting", "round": 3, "left": 14, "players": players, "bets": bets, "history": [8, 32, 0, 15, 21, 4, 11, 30]}
	_mount(LoungeRouletteView.new(room))
	await _shot("rl_1_betting", 0.8)
	room = room.duplicate(true)
	room["phase"] = "spinning"
	room["left"] = 8
	_view.update_room(room)
	await _shot("rl_2_spinning", 2.0)
	room = room.duplicate(true)
	room["phase"] = "result"
	room["left"] = 7
	room["result"] = 17
	room["history"] = [17, 8, 32, 0, 15, 21, 4, 11, 30]
	room["gains"] = {_me(): 300, "a": -50, "b": 175}
	_view.update_room(room)
	await _shot("rl_3_landing", 2.2)
	await _shot("rl_4_result", 2.0)
