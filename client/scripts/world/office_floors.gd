class_name OfficeFloors
extends RefCounted
## Floors of the office building reachable by the lift. The office scene builds the current floor;
## a floor change reloads the scene. Room ids are unique across floors, so a room QR code also tells
## which floor the player is on.

const HQ: StringName = &"hq"
const ANALYTICS: StringName = &"analytics"
const ORDER: Array[StringName] = [HQ, ANALYTICS]
const NAME_KEYS: Dictionary[StringName, String] = {HQ: "FLOOR_HQ", ANALYTICS: "FLOOR_ANALYTICS"}
const NUMBERS: Dictionary[StringName, int] = {HQ: 3, ANALYTICS: 5}

## Floor the office scene shows next time it loads.
static var current: StringName = HQ
## The player came by lift: start in front of its doors instead of the main entrance.
static var arrived_by_lift: bool = false
## Room to walk to right after arriving (a room QR code from the other floor was scanned).
static var pending_room: StringName = &""

static var _layouts: Dictionary[StringName, MapLayout] = {}


static func create_layout(floor_id: StringName) -> MapLayout:
	return AnalyticsLayout.new() if floor_id == ANALYTICS else OfficeLayout.new()


## Cached layouts for lookups (room names, floors of rooms); the scene builds its own copy.
static func layout(floor_id: StringName) -> MapLayout:
	if not _layouts.has(floor_id):
		_layouts[floor_id] = create_layout(floor_id)
	return _layouts[floor_id]


static func floor_of_room(room_id: StringName) -> StringName:
	for floor_id: StringName in ORDER:
		if layout(floor_id).find_room(room_id) != null:
			return floor_id
	return &""


static func find_room(room_id: StringName) -> MapLayout.Room:
	var floor_id: StringName = floor_of_room(room_id)
	return layout(floor_id).find_room(room_id) if floor_id != &"" else null


## "5 этаж · Продуктовая аналитика".
static func title(floor_id: StringName) -> String:
	return TranslationServer.translate("FLOOR_TITLE") % [NUMBERS.get(floor_id, 0), TranslationServer.translate(NAME_KEYS.get(floor_id, ""))]


## The other floor for a two-floor lift; with more floors the next one in ORDER.
static func next_floor(floor_id: StringName) -> StringName:
	var index: int = ORDER.find(floor_id)
	return ORDER[(index + 1) % ORDER.size()]


## Back to the main floor, e.g. when a new day starts.
static func reset() -> void:
	current = HQ
	arrived_by_lift = false
	pending_room = &""
