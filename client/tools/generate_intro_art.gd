extends SceneTree
## Generates intro backgrounds, layers and the vehicle atlas with its manifest.
## Run: godot --headless --path client --script res://tools/generate_intro_art.gd

const ATLAS_WIDTH: int = 512
const PADDING: int = 2


func _init() -> void:
	var painter: IntroScenePainter = ErrandScenePainter.new()
	for id: String in IntroArt.IMAGES:
		_save(painter.paint(id), IntroArt.path(id))
	_build_vehicles()
	quit()


func _build_vehicles() -> void:
	var entries: Array = []
	for id: String in VehicleCatalog.BODIES:
		entries.append([id, VehicleCatalog.body_size(id), false])
	for id: String in VehicleCatalog.WHEELS:
		var diameter: int = VehicleCatalog.WHEELS[id]
		entries.append([id, Vector2i(diameter * VehicleCatalog.WHEEL_FRAMES, diameter), true])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector2i).y > (b[1] as Vector2i).y)

	var rects: Dictionary = {}
	var cursor: Vector2i = Vector2i(PADDING, PADDING)
	var row_height: int = 0
	for entry: Array in entries:
		var size: Vector2i = entry[1]
		if cursor.x + size.x + PADDING > ATLAS_WIDTH:
			cursor = Vector2i(PADDING, cursor.y + row_height + PADDING * 2)
			row_height = 0
		rects[entry[0]] = Rect2i(cursor, size)
		cursor.x += size.x + PADDING * 2
		row_height = maxi(row_height, size.y)

	var canvas: PixelCanvas = PixelCanvas.create(Vector2i(ATLAS_WIDTH, cursor.y + row_height + PADDING))
	var painter: VehiclePainter = VehiclePainter.new()
	painter.c = canvas
	var manifest: Dictionary = {}
	for entry: Array in entries:
		var rect: Rect2i = rects[entry[0]]
		canvas.set_cell(rect)
		painter.paint(entry[0])
		if not entry[2]:
			canvas.outline(0.6, 0.9)
		manifest[entry[0]] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	_save(canvas.image, VehicleCatalog.TEXTURE_PATH)
	var file: FileAccess = FileAccess.open(VehicleCatalog.MANIFEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("Saved ", VehicleCatalog.MANIFEST_PATH)


func _save(image: Image, path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save %s: %s" % [path, error_string(error)])
	else:
		print("Saved ", path)
