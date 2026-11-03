class_name HomeDecorator
extends Node
## Decorating the apartment: the catalog (HomePanel), placing a bought item, rearranging placed ones
## and the palette. While placing, the camera leaves the character: a drag pans the apartment, a tap
## moves the item preview, which is green where it fits (HomeDecor) and red where it does not.
## Every change is saved on the server at once (Backend.home.save); a refused save goes back.

## The player moves to another apartment: the home scene reloads with it.
signal move_requested(apartment_id: String)

enum Mode { IDLE, PLACING, ARRANGING }

const FIT: Color = Color(0.55, 1.0, 0.6, 0.8)
const NO_FIT: Color = Color(1.0, 0.35, 0.35, 0.7)
## The cells under the preview, so the spot reads even behind the character.
const CELLS_FIT: Color = Color(0.3, 0.9, 0.45, 0.35)
const CELLS_NO_FIT: Color = Color(0.95, 0.25, 0.25, 0.35)
const TAP_SLOP: float = 10.0
const BAR_MARGIN: float = 10.0

var state: BackendHome.State

var _mode: Mode = Mode.IDLE
var _layout: HomeLayout
var _map: WorldMap
var _entities: Node2D
var _camera: GameCamera
var _player: Player
var _panel: HomePanel
var _focus: Node2D
var _ghost: Sprite2D
var _cells: ColorRect
var _item_id: String = ""
var _cell: Vector2i = Vector2i.ZERO
## The placed prop being moved, taken out of the layout until it is put down again.
var _moving: MapLayout.Prop
var _bar: CanvasLayer
var _bar_panel: PanelContainer
var _hint: Label
var _place_button: Button
var _remove_button: Button
var _cancel_button: Button
var _press_at: Vector2 = Vector2.INF
var _dragged: bool = false
var _saving: bool = false


func setup(p_state: BackendHome.State, layout: HomeLayout, map: WorldMap, entities: Node2D, camera: GameCamera, player: Player) -> void:
	state = p_state
	_layout = layout
	_map = map
	_entities = entities
	_camera = camera
	_player = player
	_panel = HomePanel.new()
	add_child(_panel)
	_panel.place_requested.connect(_start_placing)
	_panel.arrange_requested.connect(_start_arranging)
	_panel.palette_requested.connect(_apply_palette)
	_panel.move_requested.connect(func(id: String) -> void: move_requested.emit(id))
	_panel.state_changed.connect(func(fresh: BackendHome.State) -> void: state = fresh)
	_focus = Node2D.new()
	_map.add_child(_focus)
	_cells = ColorRect.new()
	_cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cells.z_index = 9
	_cells.visible = false
	_map.add_child(_cells)
	_build_bar()


func is_active() -> bool:
	return _mode != Mode.IDLE or _panel.is_open() or _saving


func open_catalog() -> void:
	if state != null:
		_panel.open(state)


func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.IDLE:
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.index == 0:
		if _press_at != Vector2.INF and drag.position.distance_to(_press_at) > TAP_SLOP:
			_dragged = true
		if _dragged:
			_focus.global_position -= drag.relative / _camera.zoom
		get_viewport().set_input_as_handled()
	elif touch != null and touch.index == 0:
		if touch.pressed:
			_press_at = touch.position
			_dragged = false
		else:
			if not _dragged:
				_on_tap(_map.get_canvas_transform().affine_inverse() * touch.position)
			_press_at = Vector2.INF
		get_viewport().set_input_as_handled()


func _on_tap(world: Vector2) -> void:
	if _mode == Mode.ARRANGING:
		var prop: MapLayout.Prop = HomeDecor.prop_at(_layout, _map, world)
		if prop != null:
			_pick_up(prop)
		return
	_cell = HomeDecor.cell_for_tap(_layout, _item_id, _map.world_to_cell(world))
	_update_ghost()


func _start_placing(item_id: String) -> void:
	_item_id = item_id
	_moving = null
	_begin(Mode.PLACING)
	_cell = HomeDecor.cell_for_tap(_layout, item_id, _map.world_to_cell(_player.global_position) + Vector2i.DOWN)
	_show_ghost()


func _start_arranging() -> void:
	_begin(Mode.ARRANGING)
	_hint.text = tr("HOME_ARRANGE_HINT")
	_place_button.visible = false
	_remove_button.visible = false
	_cancel_button.text = tr("HOME_DONE")


## A placed item is lifted to be moved or put away.
func _pick_up(prop: MapLayout.Prop) -> void:
	_moving = prop
	_item_id = prop.id
	_cell = prop.cell
	_layout.props.erase(prop)
	_map.rebuild_props(_entities)
	_mode = Mode.PLACING
	_show_ghost()


func _begin(mode: Mode) -> void:
	_mode = mode
	_player.walk_path(PackedVector2Array())
	_focus.global_position = _player.global_position
	_camera.target = _focus
	# Above the home indicator of the phone.
	var safe: Rect2 = PlatformServices.get_safe_rect()
	var bottom_inset: float = maxf(0.0, _bar_panel.get_viewport_rect().size.y - safe.end.y)
	_bar_panel.offset_bottom = -BAR_MARGIN - bottom_inset
	_bar_panel.offset_top = _bar_panel.offset_bottom
	_bar.visible = true


func _show_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	_ghost = _map.make_prop_sprite(_item_id, _cell)
	if _ghost == null:
		_finish()
		return
	_ghost.z_index = 10
	_map.add_child(_ghost)
	_place_button.visible = true
	_remove_button.visible = _moving != null
	_cancel_button.text = tr("HOME_CANCEL")
	_update_ghost()


func _update_ghost() -> void:
	_map.place_prop_sprite(_ghost, _item_id, _cell)
	var error: String = _placement_error()
	_ghost.modulate = FIT if error.is_empty() else NO_FIT
	_cells.position = Vector2(_cell * MapLayout.TILE_SIZE)
	_cells.size = Vector2(PropCatalog.footprint(_item_id) * MapLayout.TILE_SIZE)
	_cells.color = CELLS_FIT if error.is_empty() else CELLS_NO_FIT
	_cells.visible = true
	_place_button.disabled = not error.is_empty()
	_hint.text = tr("HOME_PLACE_HINT") if error.is_empty() else tr(error)
	_focus.global_position = _map.to_global(Vector2(_cell * MapLayout.TILE_SIZE))


func _placement_error() -> String:
	var occupied: Array[Vector2i] = [_map.world_to_cell(_player.global_position)]
	return HomeDecor.placement_error(_layout, _item_id, _cell, null, occupied)


func _on_place() -> void:
	if not _placement_error().is_empty():
		return
	_layout.add_prop(_item_id, _cell.x, _cell.y)
	_moving = null
	await _save_layout()
	_finish()


## Puts the lifted item back into the inventory.
func _on_remove() -> void:
	_moving = null
	await _save_layout()
	_finish()


func _on_cancel() -> void:
	if _moving != null:
		_layout.props.append(_moving)
		_moving = null
		_map.rebuild_props(_entities)
	_finish()


func _finish() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_cells.visible = false
	_mode = Mode.IDLE
	_bar.visible = false
	_camera.target = _player
	if state != null:
		_panel.open(state)


func _apply_palette(palette_id: String) -> void:
	var previous: String = state.palette
	_map.set_surface_material(HomePalettes.material(palette_id))
	state.palette = palette_id
	if not await _save_layout():
		state.palette = previous
		_map.set_surface_material(HomePalettes.material(previous))
	_panel.set_state(state)


## Saves the layout's interior and the palette; a refused save puts the last saved look back.
func _save_layout() -> bool:
	_saving = true
	var placed: Array[BackendHome.Placed] = []
	for prop: MapLayout.Prop in _layout.decor_props():
		placed.append(BackendHome.Placed.new(prop.id, prop.cell))
	var saved: BackendHome.State = await Backend.home.save(state.apartment, state.palette, placed)
	_saving = false
	if not saved.ok:
		_hint.text = tr("ERROR_" + (saved.error if not saved.error.is_empty() else "server").to_upper())
		_layout.set_decor(state.placed)
		_map.rebuild_props(_entities)
		return false
	state = saved
	_layout.set_decor(state.placed)
	_map.rebuild_props(_entities)
	return true


func _build_bar() -> void:
	_bar = CanvasLayer.new()
	_bar.layer = 21
	_bar.visible = false
	add_child(_bar)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PAPER, 8, 8))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = BAR_MARGIN
	panel.offset_right = -BAR_MARGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.add_child(panel)
	_bar_panel = panel
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_hint = UiStyle.make_label("", 10, UiStyle.INK)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	_place_button = _bar_button(row, tr("HOME_PUT_DOWN"), true, _on_place)
	_remove_button = _bar_button(row, tr("HOME_PUT_AWAY"), false, _on_remove)
	_cancel_button = _bar_button(row, tr("HOME_CANCEL"), false, _on_cancel)


func _bar_button(row: HBoxContainer, text: String, primary: bool, action: Callable) -> Button:
	var button: Button = UiStyle.make_button(text, primary, 12)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 34)
	button.pressed.connect(action)
	row.add_child(button)
	return button
