extends WorldScene
## The player's apartment after breakfast. The character lives by itself: walks between objects and
## comments on them. The player changes the outfit (wardrobe), picks a car (garage) and leaves with
## "Go to the office": the character then walks out through the front door.

const COMMUTE_SCENE: String = "res://scenes/intro/commute_intro.tscn"
const REMARKS_PATH: String = "res://data/home_remarks.json"
const REMARK_COOLDOWN: float = 9.0
const FADE_TIME: float = 0.4
## The player fades out over this time while stepping through the front door.
const EXIT_FADE: float = 0.35
## The walk to the door after the "Go to the office" button: the player hurries.
const EXIT_SPEED_FACTOR: float = 1.6

var _remarks: Dictionary = {}
var _cooldowns: Dictionary[String, float] = {}
var _near_id: String = ""
var _busy: bool = false
var _leaving: bool = false
var _corner: PlayerCorner
var _office_button: Button

@onready var _wardrobe: WardrobePanel = $WardrobePanel
@onready var _shop_panel: ShopPanel = $ShopPanel
@onready var _fade: ColorRect = $Fade/Rect


func _ready() -> void:
	var layout: HomeLayout = HomeLayout.new()
	_setup_world(layout)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REMARKS_PATH))
	_remarks = parsed if parsed is Dictionary else {}
	for use: HomeLayout.Interactable in layout.interactables:
		_cooldowns[use.id] = 0.0
		if not _remarks.has(use.id):
			push_warning("No home remarks for '%s'" % use.id)
	# The player starts next to the breakfast table.
	_cooldowns["table"] = REMARK_COOLDOWN
	_hud.set_title(tr("HUD_HOME_TITLE"))
	_hud.set_hint(tr("HUD_HOME_HINT"))
	_corner = PlayerCorner.attach(self, _hud)
	_hud.add_action(tr("HUD_WARDROBE"), false).pressed.connect(_open_wardrobe)
	_hud.add_action(tr("HUD_GARAGE"), false).pressed.connect(_open_garage)
	_office_button = _hud.add_wide_action(tr("HUD_GO_OFFICE"))
	_office_button.pressed.connect(_go_to_office)
	_player.face(Vector2.UP)
	_fade.color.a = 1.0
	if Backend.profile == null:
		await Backend.login()
	_update_room()
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	await tween.finished
	_player.say(_pick("greeting"))


func _process(delta: float) -> void:
	super(delta)
	for id: String in _cooldowns:
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	_check_proximity()


func _is_modal_open() -> bool:
	return (
		_busy or _leaving or _wardrobe.is_open() or _shop_panel.is_open()
		or (_corner != null and _corner.is_open())
	)


## The character visits an object of the flat; the remark comes on arrival (_check_proximity).
func _run_activity() -> void:
	var uses: Array[HomeLayout.Interactable] = (_map.layout as HomeLayout).interactables
	if uses.is_empty() or randf() < 0.2:
		await _wander()
		return
	var use: HomeLayout.Interactable = uses.pick_random()
	if use.kind == HomeLayout.Kind.DOOR:
		# The door is for the trip to the office only.
		return
	if await _auto_walk(use.stand_cell):
		var target: Vector2 = _map.cell_to_world(use.prop_cell)
		_player.face(target - _player.global_position if target.distance_to(_player.global_position) > 1.0 else Vector2.UP)
		await _auto_wait(randf_range(2.0, 4.0))


func _open_wardrobe() -> void:
	if _is_modal_open():
		return
	_stop_player()
	_busy = true
	_wardrobe.open()
	await _wardrobe.closed
	_busy = false
	_player.say(_pick("mirror"))


func _open_garage() -> void:
	if _is_modal_open():
		return
	_stop_player()
	_player.say(_pick("keys"))
	_shop_panel.open(ShopPanel.Tab.GARAGE)


## Remarks when the player steps onto an object's spot, at most once per cooldown.
func _check_proximity() -> void:
	if _is_modal_open():
		return
	var cell: Vector2i = _player_cell()
	var near: HomeLayout.Interactable = null
	for use: HomeLayout.Interactable in (_map.layout as HomeLayout).interactables:
		if use.stand_cell == cell:
			near = use
			break
	var near_id: String = near.id if near != null else ""
	if near != null and near_id != _near_id and _cooldowns.get(near_id, 0.0) <= 0.0 and not _player.is_talking():
		_player.say(_pick(near_id))
		_cooldowns[near_id] = REMARK_COOLDOWN
	_near_id = near_id


## The "Go to the office" button: the character walks out through the front door, then the commute.
func _go_to_office() -> void:
	if _is_modal_open():
		return
	_leaving = true
	_marker.hide_marker()
	_office_button.visible = false
	_hud.hide_hint()
	_player.say(_pick("door"))
	var path: PackedVector2Array = _door_path()
	if not path.is_empty():
		_player.move_speed *= EXIT_SPEED_FACTOR
		_player.walk_path(path)
		var length: float = _player.global_position.distance_to(path[0])
		for i: int in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		var fade_out: Tween = create_tween()
		fade_out.tween_interval(maxf(0.0, length / _player.move_speed - EXIT_FADE))
		fade_out.tween_property(_player, "modulate:a", 0.0, EXIT_FADE)
		await _player.arrived
	_leaving = false
	_leave()


## Path to the doormat and on through the front door.
func _door_path() -> PackedVector2Array:
	for use: HomeLayout.Interactable in (_map.layout as HomeLayout).interactables:
		if use.kind != HomeLayout.Kind.DOOR:
			continue
		var path: PackedVector2Array = _map.find_path(_player.global_position, use.stand_cell)
		if path.is_empty() and _player_cell() != use.stand_cell:
			return path
		path.append(_map.cell_to_world(use.prop_cell))
		return path
	return PackedVector2Array()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_stop_player()
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished
	get_tree().change_scene_to_file(COMMUTE_SCENE)


func _pick(id: String) -> String:
	var lines: Array = _remarks.get(id, [])
	return str(lines.pick_random()) if not lines.is_empty() else ""
