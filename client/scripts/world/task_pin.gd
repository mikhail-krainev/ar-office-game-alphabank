class_name TaskPin
extends Node2D
## Floating map marker over the spot where a task starts. Tap it to walk there and play the minigame.

const PIN_SIZE: float = 22.0
const PIN_Y: float = -76.0
const HIT_RECT: Rect2 = Rect2(-16, -94, 32, 40)
const RED: Color = Color("#ef3124")
const INK: Color = Color("#1d1d1f")
const WHITE: Color = Color("#fbfaf8")
const GOLD: Color = Color("#f7c948")
const ICONS: Dictionary[String, int] = {
	"check_in": NpcAction.Kind.PAPERS, "coffee": NpcAction.Kind.COFFEE,
	"bubble_wrap": NpcAction.Kind.DANCE,
}

var task: BackendModels.TaskInfo

var _time: float = 0.0


func _ready() -> void:
	z_index = 20
	_time = randf() * TAU


## Places the pin on the task spot; world_position is the centre of the spot cell.
func setup(p_task: BackendModels.TaskInfo, world_position: Vector2) -> void:
	task = p_task
	position = world_position + Vector2(0, MapLayout.TILE_SIZE / 2.0 - 1.0)
	visible = not task.is_closed()
	queue_redraw()


func is_hit(world_position: Vector2) -> bool:
	return HIT_RECT.has_point(world_position - global_position)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if task == null:
		return
	var floor_center: Vector2 = Vector2(0, -MapLayout.TILE_SIZE / 2.0 + 1.0)
	var pulse: float = fmod(_time * 0.9, 1.0)
	draw_set_transform(floor_center, 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, 8.0 + pulse * 8.0, 0.0, TAU, 24, Color(RED, 0.7 * (1.0 - pulse)), 2.0)
	draw_circle(Vector2.ZERO, 6.0, Color(RED, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var bob: float = roundf(sin(_time * 3.0) * 2.0)
	var center: Vector2 = Vector2(0, PIN_Y + bob)
	var half: float = PIN_SIZE / 2.0
	var body: Rect2 = Rect2(center - Vector2(half, half), Vector2(PIN_SIZE, PIN_SIZE))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, body.end.y - 1), Vector2(5, body.end.y - 1), Vector2(0, body.end.y + 7),
	]), INK)
	draw_rect(body.grow(1.0), INK)
	draw_rect(body, RED)
	draw_rect(Rect2(body.position, Vector2(PIN_SIZE, 2)), Color(1, 1, 1, 0.25))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3, body.end.y), Vector2(3, body.end.y), Vector2(0, body.end.y + 5),
	]), RED)
	draw_set_transform(center - Vector2(7, 7), 0.0, Vector2(2, 2))
	draw_rect(Rect2(-1, -1, 9, 9), WHITE)
	NpcAction.draw_icon(self, ICONS.get(task.minigame, NpcAction.Kind.PAPERS), Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var font: Font = ThemeDB.fallback_font
	var text: String = "+%d" % task.reward
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var label: Rect2 = Rect2(Vector2(roundf(-width / 2.0) - 3, body.position.y - 14), Vector2(roundf(width) + 6, 12))
	draw_rect(label.grow(1.0), INK)
	draw_rect(label, GOLD)
	draw_string(font, label.position + Vector2(3, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)

	if task.difficulty != "normal":
		var tag_text: String = UiStyle.difficulty_text(task.difficulty, task.difficulty_multiplier)
		var tag_width: float = font.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var tag: Rect2 = Rect2(Vector2(roundf(-tag_width / 2.0) - 3, label.position.y - 12), Vector2(roundf(tag_width) + 6, 10))
		draw_rect(tag.grow(1.0), INK)
		draw_rect(tag, UiStyle.difficulty_color(task.difficulty))
		draw_string(font, tag.position + Vector2(3, 8), tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, WHITE)
