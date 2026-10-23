extends Node
## Opens the mini profile of a colleague from anywhere (autoload "ColleagueProfiles"): a tap on a
## colleague's name or avatar in a task card or the inbox, or on their character on the office map.
## One panel for the whole game, drawn above minigames.

## A press that moves further than this is a drag, not a tap.
const TAP_SLOP: float = 8.0

var _panel: ColleagueProfilePanel


func _ready() -> void:
	_panel = ColleagueProfilePanel.new()
	add_child(_panel)


## A colleague whose card is already loaded (the office map).
func open(player: BackendModels.OfficePlayer) -> void:
	_panel.open(player)


## A colleague known only by id: the panel loads the card from the server.
func open_user(user_id: String) -> void:
	if user_id.is_empty() or user_id == Backend.get_user_id():
		return
	_panel.open_user(user_id)


func is_open() -> bool:
	return _panel.is_open()


func close() -> void:
	_panel.close_panel()


## Makes `control` (a name or an avatar) open the colleague's mini profile on tap. A drag (scrolling
## the inbox) is not a tap.
func make_tappable(control: Control, user_id: String) -> void:
	if user_id.is_empty():
		return
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	var pressed_at: Array[Vector2] = []
	control.gui_input.connect(
		func(event: InputEvent) -> void:
			var press: Variant = Minigame.press_position(event)
			if press != null:
				pressed_at.assign([press as Vector2])
			elif Minigame.is_release(event) and not pressed_at.is_empty():
				var mouse: InputEventMouseButton = event as InputEventMouseButton
				if mouse.position.distance_to(pressed_at[0]) <= TAP_SLOP:
					open_user(user_id)
				pressed_at.clear()
	)
