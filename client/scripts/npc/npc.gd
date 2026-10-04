class_name Npc
extends Node2D
## Office NPC that walks between activity spots, performs actions and pauses to talk.

enum State { WORKING, WALKING, TALKING }

const HIT_RECT: Rect2 = Rect2(-12, -46, 24, 50)
const WORK_TIME_MIN: float = 6.0
const WORK_TIME_MAX: float = 14.0
const BUBBLE_COLOR: Color = Color("#fbfaf8")
const BUBBLE_BORDER: Color = Color("#2b2b30")
const BUBBLE_Y: float = -62.0

@export var move_speed: float = 48.0

var definition: NpcRoster.Definition

var _map: WorldMap
var _body: CharacterSprite
var _state: State = State.WORKING
var _activity_index: int = 0
var _work_left: float = 0.0
var _path: PackedVector2Array = PackedVector2Array()
var _bubble: SpeechBubble


func setup(p_definition: NpcRoster.Definition, map: WorldMap) -> void:
	definition = p_definition
	_map = map
	name = "Npc_" + definition.id
	_body = CharacterSprite.new()
	add_child(_body)
	_body.setup(definition.id)
	var first: NpcRoster.Activity = definition.activities[0]
	global_position = _map.cell_to_world(first.cell)
	_start_working(first, randf_range(1.0, WORK_TIME_MAX))


func is_hit(world_position: Vector2) -> bool:
	return HIT_RECT.has_point(world_position - global_position)


## A line of a chat in a speech bubble above the head.
func say(text: String, duration: float = 3.2) -> void:
	if text.is_empty():
		return
	if _bubble == null:
		_bubble = SpeechBubble.new()
		add_child(_bubble)
	_bubble.say(text, duration)


func begin_talk(listener_position: Vector2) -> void:
	_state = State.TALKING
	_path.clear()
	_body.bounce = 0.0
	_body.face(listener_position - global_position)
	queue_redraw()


func end_talk() -> void:
	if _state != State.TALKING:
		return
	_start_working(definition.activities[_activity_index], randf_range(2.0, 4.0))


func _process(delta: float) -> void:
	match _state:
		State.WORKING:
			_process_working(delta)
		State.WALKING:
			_process_walking(delta)


func _process_working(delta: float) -> void:
	_work_left -= delta
	if _work_left > 0.0 or definition.activities.size() < 2:
		return
	var current: NpcRoster.Activity = definition.activities[_activity_index]
	_activity_index = (_activity_index + 1) % definition.activities.size()
	_path = _map.find_path(global_position, definition.activities[_activity_index].cell)
	if _path.is_empty():
		_activity_index = definition.activities.find(current)
		_start_working(current, WORK_TIME_MIN)
		return
	_state = State.WALKING
	_body.bounce = 0.0
	queue_redraw()


func _process_walking(delta: float) -> void:
	if _path.is_empty():
		_start_working(definition.activities[_activity_index], randf_range(WORK_TIME_MIN, WORK_TIME_MAX))
		return
	var to_target: Vector2 = _path[0] - global_position
	var step: float = move_speed * delta
	if to_target.length() <= step:
		global_position = _path[0]
		_path.remove_at(0)
	else:
		global_position += to_target.normalized() * step
	_body.set_walking(true, to_target)


func _start_working(activity: NpcRoster.Activity, duration: float) -> void:
	_state = State.WORKING
	_work_left = duration
	_body.face(activity.facing)
	_body.bounce = 3.0 if NpcAction.is_bouncy(activity.action) else 0.0
	queue_redraw()


func _draw() -> void:
	if _state != State.WORKING:
		return
	var activity: NpcRoster.Activity = definition.activities[_activity_index]
	var bubble: Rect2 = Rect2(-6, BUBBLE_Y, 11, 11)
	draw_rect(bubble.grow(1), BUBBLE_BORDER)
	draw_rect(bubble, BUBBLE_COLOR)
	draw_rect(Rect2(-1, bubble.end.y + 1, 2, 2), BUBBLE_BORDER)
	NpcAction.draw_icon(self, activity.action, bubble.position + Vector2(2, 2))
