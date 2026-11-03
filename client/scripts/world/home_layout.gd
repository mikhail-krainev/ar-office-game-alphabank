class_name HomeLayout
extends MapLayout
## One of the player's apartments (ApartmentLayouts builds them by the server's apartment id): rooms,
## the built-in furniture, the objects the player can walk up to, and the interior the player placed
## (decor, after `decor_start` in `props`). Remark texts live in res://data/home_remarks.json.

enum Kind { REMARK, WARDROBE, LAPTOP, DOOR, GARAGE }


class Interactable:
	extends RefCounted

	## Key in home_remarks.json.
	var id: String
	var kind: Kind
	var prop_id: String
	var prop_cell: Vector2i
	## Walkable cell where the player stands to use the object.
	var stand_cell: Vector2i

	func _init(p_id: String, p_kind: Kind, p_prop_id: String, p_prop_cell: Vector2i, p_stand_cell: Vector2i) -> void:
		id = p_id
		kind = p_kind
		prop_id = p_prop_id
		prop_cell = p_prop_cell
		stand_cell = p_stand_cell


var apartment_id: String = ""
var interactables: Array[Interactable] = []
## Index in `props` where the placed interior starts; props before it are built in.
var decor_start: int = 0
## Garage: the cells the parked car takes (blocked) and the ground point under its rear bumper.
## Empty when the apartment has no garage.
var car_rect: Rect2i = Rect2i()
var car_origin: Vector2 = Vector2.ZERO


## Call after the built-in props: everything added later is the placed interior.
func finish_built_in() -> void:
	if car_rect.has_area():
		solid_rects.append(car_rect)
	decor_start = props.size()
	finalize()


func set_decor(placed: Array[BackendHome.Placed]) -> void:
	props.resize(decor_start)
	for placement: BackendHome.Placed in placed:
		if PropCatalog.DEFS.has(placement.item):
			add_prop(placement.item, placement.cell.x, placement.cell.y)


func decor_props() -> Array[Prop]:
	return props.slice(decor_start)


func built_in_props() -> Array[Prop]:
	return props.slice(0, decor_start)


func use(id: String, kind: Kind, prop_id: String, prop_x: int, prop_y: int, stand_x: int, stand_y: int) -> void:
	interactables.append(Interactable.new(id, kind, prop_id, Vector2i(prop_x, prop_y), Vector2i(stand_x, stand_y)))


func add_props(list: Array) -> void:
	for entry: Array in list:
		add_prop(entry[0], entry[1], entry[2])


func validate() -> PackedStringArray:
	var errors: PackedStringArray = super.validate()
	for use_spot: Interactable in interactables:
		if find_prop(use_spot.prop_id, use_spot.prop_cell) == null:
			errors.append("Interactable '%s' points to a missing prop %s at %s" % [use_spot.id, use_spot.prop_id, use_spot.prop_cell])
		if not is_walkable_cell(use_spot.stand_cell):
			errors.append("Interactable '%s' stand cell %s is not walkable" % [use_spot.id, use_spot.stand_cell])
	return errors
