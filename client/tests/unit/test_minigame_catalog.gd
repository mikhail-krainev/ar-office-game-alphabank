extends GdUnitTestSuite
## Every task of the server content (server/content/tasks.json) points at an existing minigame and
## a free cell of its room on the client's map, and fallbacks need no sensors.

const TASKS_PATH: String = "../server/content/tasks.json"
const SCREEN_ONLY: Array[String] = ["check_in", "coffee", "bubble_wrap"]


func _tasks() -> Array:
	var path: String = ProjectSettings.globalize_path("res://").path_join(TASKS_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary)["tasks"]


func test_tasks_use_known_minigames() -> void:
	for entry: Variant in _tasks():
		var task: Dictionary = entry
		var kind: String = task["minigame"]
		assert_bool(Minigame.REQUIRED_FEATURES.has(kind) or SCREEN_ONLY.has(kind)).override_failure_message(kind).is_true()
		var fallback: String = str(task.get("fallback", ""))
		if not fallback.is_empty():
			assert_bool(SCREEN_ONLY.has(fallback)).override_failure_message(fallback).is_true()
			assert_array(Minigame.required_features(fallback)).is_empty()


func test_physical_minigames_are_created() -> void:
	for kind: String in Minigame.REQUIRED_FEATURES:
		var game: Minigame = auto_free(Minigame.create(kind))
		assert_bool(game is CheckInMinigame).override_failure_message(kind).is_false()


func test_task_spots_are_on_the_floor() -> void:
	for entry: Variant in _tasks():
		var task: Dictionary = entry
		var layout: MapLayout = OfficeFloors.layout(StringName(str(task.get("floor", OfficeFloors.HQ))))
		var spot: Array = task["spot"]
		var cell: Vector2i = Vector2i(int(spot[0]), int(spot[1]))
		assert_bool(layout.is_walkable_cell(cell) and not _blocked(layout).has(cell)).override_failure_message("%s %s" % [task["id"], cell]).is_true()
		var room: MapLayout.Room = layout.get_room_at(cell)
		assert_str(String(room.id) if room != null else "").override_failure_message(task["id"]).is_equal(task["room"])


func test_floors_are_valid_and_have_a_lift() -> void:
	for floor_id: StringName in OfficeFloors.ORDER:
		var layout: MapLayout = OfficeFloors.create_layout(floor_id)
		assert_array(Array(layout.validate())).override_failure_message(str(layout.validate())).is_empty()
		assert_bool(layout.has_elevator()).is_true()
		assert_bool(_blocked(layout).has(layout.elevator_cell)).is_false()


func test_room_ids_are_unique_across_floors() -> void:
	var seen: Array[StringName] = []
	for floor_id: StringName in OfficeFloors.ORDER:
		for room: MapLayout.Room in OfficeFloors.layout(floor_id).rooms:
			assert_bool(seen.has(room.id)).override_failure_message(String(room.id)).is_false()
			seen.append(room.id)
			assert_str(String(OfficeFloors.floor_of_room(room.id))).is_equal(String(floor_id))


func test_npc_spots_are_free() -> void:
	for floor_id: StringName in OfficeFloors.ORDER:
		var layout: MapLayout = OfficeFloors.layout(floor_id)
		for definition: NpcRoster.Definition in NpcRoster.for_floor(floor_id):
			for activity: NpcRoster.Activity in definition.activities:
				var free: bool = layout.is_walkable_cell(activity.cell) and not _blocked(layout).has(activity.cell)
				assert_bool(free).override_failure_message("%s %s" % [definition.id, activity.cell]).is_true()


## Cells covered by blocking furniture.
func _blocked(layout: MapLayout) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for prop: MapLayout.Prop in layout.props:
		if not PropCatalog.is_blocking(prop.id):
			continue
		var footprint: Rect2i = Rect2i(prop.cell, PropCatalog.footprint(prop.id))
		for y: int in range(footprint.position.y, footprint.end.y):
			for x: int in range(footprint.position.x, footprint.end.x):
				cells.append(Vector2i(x, y))
	return cells
