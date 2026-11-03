class_name OfficeTiles
extends RefCounted
## Layout of the 32px tile atlas shared by the art generator and the runtime maps (office and home).
## Rows = surface styles, columns = floor variants, wall face (upper/lower), cap and shadow overlay.

const SIZE: int = 32
const TEXTURE_PATH: String = "res://assets/tiles/office_tiles_32.png"

enum Style { OFFICE, WOOD, KITCHEN, MARBLE, CORRIDOR, LOUNGE, PARTY, DOOR, BEDROOM, BATH, HALL, LIVING, HOME_KITCHEN, CARPET, CONCRETE, GRASS }

const FLOOR_VARIANTS: int = 3
const COL_FACE_UPPER: int = 3
const COL_FACE_LOWER: int = 4
const COL_CAP: int = 5
const COL_SHADOW: int = 6
const COLUMNS: int = 7


static func floor_coords(style: Style, variant: int) -> Vector2i:
	return Vector2i(variant % FLOOR_VARIANTS, style)


static func face_coords(style: Style, upper: bool) -> Vector2i:
	return Vector2i(COL_FACE_UPPER if upper else COL_FACE_LOWER, style)


static func cap_coords() -> Vector2i:
	return Vector2i(COL_CAP, 0)


static func shadow_coords() -> Vector2i:
	return Vector2i(COL_SHADOW, 0)
