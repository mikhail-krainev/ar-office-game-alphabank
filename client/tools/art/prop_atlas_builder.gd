class_name PropAtlasBuilder
extends RefCounted
## Paints every prop in PropCatalog and shelf-packs them into one atlas with a JSON manifest.

const ATLAS_WIDTH: int = 512
const PADDING: int = 2

var image: Image
var manifest: Dictionary = {}


func build() -> void:
	var painters: Array[PropPainterBase] = [OfficePropPainter.new(), HospitalityPropPainter.new(), PartyPropPainter.new(), HomePropPainter.new(), AnalyticsPropPainter.new(), HomeDecorPropPainter.new()]
	var ids: Array = PropCatalog.DEFS.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return PropCatalog.sprite_size(a).y > PropCatalog.sprite_size(b).y)

	var placements: Dictionary = {}
	var cursor: Vector2i = Vector2i(PADDING, PADDING)
	var row_height: int = 0
	for id: String in ids:
		var size: Vector2i = PropCatalog.sprite_size(id)
		if cursor.x + size.x + PADDING > ATLAS_WIDTH:
			cursor = Vector2i(PADDING, cursor.y + row_height + PADDING * 2)
			row_height = 0
		placements[id] = Rect2i(cursor, size)
		cursor.x += size.x + PADDING * 2
		row_height = maxi(row_height, size.y)
	var height: int = cursor.y + row_height + PADDING

	var canvas: PixelCanvas = PixelCanvas.create(Vector2i(ATLAS_WIDTH, height))
	image = canvas.image
	for id: String in ids:
		var rect: Rect2i = placements[id]
		var painted: bool = false
		for painter: PropPainterBase in painters:
			painter.c = canvas
			painter.rng.seed = hash(id)
			canvas.set_cell(rect)
			if painter.paint(id, rect.size.x, rect.size.y):
				painted = true
				break
		if not painted:
			push_warning("No painter for prop '%s'" % id)
			canvas.rect(0, 0, rect.size.x, rect.size.y, Color(1, 0, 1, 0.6))
		if PropCatalog.kind(id) != PropCatalog.Kind.DECAL:
			canvas.outline(0.62, 0.9)
		manifest[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
