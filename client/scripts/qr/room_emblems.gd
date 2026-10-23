class_name RoomEmblems
extends RefCounted
## Room door codes are Alfa-Bank identity emblems, not QR codes: logo versions and the cat stickers,
## one per room, printed, painted on the wall or shown on a screen. The phone recognizes them itself
## (PlatformServices.emblem_detected in CameraMode.CODES); the emblem only names the room, and the
## server checks the visit like any door code (presence.go: rpcEnterRoom).
## The catalog is shared with tools/printables and tools/office-screen.

const CATALOG_PATH: String = "res://assets/brand/emblems/emblems.json"
const IMAGE_DIR: String = "res://assets/brand/emblems/"
## Long side of the pictures sent to the recognizer: the embedder works at 224 px.
const REFERENCE_SIDE: int = 224

## Emblem id -> room id, in catalog order.
static var _rooms: Dictionary[String, StringName] = {}
static var _is_registered: bool = false


## Room of an emblem; &"" for an unknown emblem.
static func room_of(emblem_id: String) -> StringName:
	return _catalog().get(emblem_id, &"") as StringName


## Emblem at the room's door; "" when the room has none.
static func emblem_of(room_id: StringName) -> String:
	for emblem_id: String in _catalog():
		if _rooms[emblem_id] == room_id:
			return emblem_id
	return ""


static func ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_catalog().keys())
	return result


static func image_path(emblem_id: String) -> String:
	return IMAGE_DIR + emblem_id + ".png"


## Hands the reference pictures to the platform once, before the first scan.
static func register() -> void:
	if _is_registered:
		return
	_is_registered = true
	var references: Dictionary[String, Image] = {}
	for emblem_id: String in ids():
		var picture: Image = reference_image(emblem_id)
		if picture == null:
			push_error("Room emblem picture missing: %s" % image_path(emblem_id))
			continue
		references[emblem_id] = picture
	PlatformServices.set_emblems(references)


## The emblem picture, REFERENCE_SIDE on the long side; null when missing.
static func reference_image(emblem_id: String) -> Image:
	var texture: Texture2D = load(image_path(emblem_id)) as Texture2D
	if texture == null:
		return null
	var picture: Image = texture.get_image()
	if picture.is_compressed():
		picture.decompress()
	var scale_factor: float = float(REFERENCE_SIDE) / maxi(picture.get_width(), picture.get_height())
	picture.resize(
		maxi(1, roundi(picture.get_width() * scale_factor)), maxi(1, roundi(picture.get_height() * scale_factor)),
		Image.INTERPOLATE_BILINEAR
	)
	return picture


static func _catalog() -> Dictionary[String, StringName]:
	if _rooms.is_empty():
		_rooms = parse_catalog(FileAccess.get_file_as_string(CATALOG_PATH))
	return _rooms


## {"emblems": [{"id", "room", "title"}]} -> emblem id -> room id. Entries without a valid id or room
## are skipped with an error.
static func parse_catalog(text: String) -> Dictionary[String, StringName]:
	var result: Dictionary[String, StringName] = {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not (parsed as Dictionary).get("emblems") is Array:
		push_error("Room emblem catalog unreadable: %s" % CATALOG_PATH)
		return result
	for entry: Variant in (parsed as Dictionary)["emblems"]:
		var emblem: Dictionary = entry if entry is Dictionary else {}
		var emblem_id: String = str(emblem.get("id", ""))
		var room_id: String = str(emblem.get("room", ""))
		if not emblem_id.is_valid_identifier() or not room_id.is_valid_identifier():
			push_error("Room emblem catalog: bad entry %s" % str(entry))
			continue
		result[emblem_id] = StringName(room_id)
	return result
