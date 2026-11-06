class_name PaperTossPainter
extends RefCounted
## The AR paper basketball drawn over the camera view as if it stood in the room: a graphite office
## bin with the Alfa red band on the floor in perspective, lit from the ceiling, with a soft contact
## shadow, and crumpled paper balls that cast shadows on the floor. Points are room metres of
## PaperToss, projected by the ArCamera of the phone as it turns, so everything stays where it is in
## the room. Each function draws on the given canvas item (a CameraView overlay). The bin is drawn in
## two passes, so a ball that falls in shows between them; `base` is the point under its middle.

const SEGMENTS: int = 32
const BODY: Color = Color("#3a3d43")
const BAND: Color = UiStyle.RED
const INSIDE: Color = Color("#0e0f11")
const RIM: Color = Color("#5a5e65")
const PAPER: Color = Color("#f4f1ea")
const CREASE: Color = Color("#a9a196")
## Ceiling light: from above, a little to the left and from behind the player.
const LIGHT: Vector3 = Vector3(-0.45, 0.8, -0.4)
## The same light on the screen, for the paper balls: from the upper left.
const LIGHT_ON_SCREEN: Vector2 = Vector2(-0.6, -0.8)
const AMBIENT: float = 0.42
const DIFFUSE: float = 0.58
const SHINE: float = 0.3
const SHININESS: float = 24.0
## The wall near the floor gets less light: its brightness at the very bottom.
const FLOOR_OCCLUSION: float = 0.6
## Plastic thickness and how far the rim lip sticks out, metres.
const WALL: float = 0.008
const LIP: float = 0.007
const LIP_WIDTH: float = 0.014
## The red band, in shares of the bin height, and the logo size on it, metres.
const BAND_BOTTOM: float = 0.58
const BAND_TOP: float = 0.74
const LOGO_SIZE: float = 0.075
const SHADOW_LAYERS: int = 9
const SHADOW_SPREAD: float = 0.9
const BIN_SHADOW: float = 0.55
const BALL_SHADOW: float = 0.45
const BALL_FACETS: int = 9
## The found floor: a grid of dots this far apart (metres) up to this far around the aimed point.
const SCAN_STEP: float = 0.25
const SCAN_REACH: float = 1.2
const SCAN_DOT: float = 2.0
## The placing reticle breathes this many times a second.
const RETICLE_PULSE: float = 0.8
## Polygons smaller than this many square pixels are skipped: they are seen edge-on.
const MIN_AREA: float = 0.25


## The shadow of the bin while it hangs `base.y` metres above the floor and once it stands.
static func bin_shadow(canvas: CanvasItem, camera: ArCamera, base: Vector3) -> void:
	var strength: float = BIN_SHADOW / (1.0 + base.y * 6.0)
	floor_shadow(canvas, camera, base * Vector3(1, 0, 1), PaperToss.BIN_BOTTOM_RADIUS * (1.0 + base.y), strength)


## The inside of the bin: the dark opening, the far inner wall and the bottom.
static func bin_back(canvas: CanvasItem, camera: ArCamera, base: Vector3) -> void:
	var height: float = PaperToss.BIN_HEIGHT
	var top_radius: float = PaperToss.BIN_TOP_RADIUS - WALL
	var bottom_radius: float = PaperToss.BIN_BOTTOM_RADIUS - WALL
	_fill(canvas, _ring(base, top_radius, height, camera), INSIDE)
	for segment: int in SEGMENTS:
		var from: float = TAU * segment / SEGMENTS
		var to: float = TAU * (segment + 1) / SEGMENTS
		if _faces_camera(base, (from + to) / 2.0, camera):
			continue
		var corners: Array[Vector3] = [
			_ring_point(base, bottom_radius, WALL, from),
			_ring_point(base, bottom_radius, WALL, to),
			_ring_point(base, top_radius, height, to),
			_ring_point(base, top_radius, height, from),
		]
		var colors: PackedColorArray = PackedColorArray()
		for corner: int in corners.size():
			var angle: float = to if corner == 1 or corner == 2 else from
			var depth: float = (corners[corner].y - base.y) / height
			var lit: Color = _shade(BODY, -_outer_normal(angle), corners[corner], camera.eye)
			colors.append(INSIDE.lerp(lit, 0.15 + 0.45 * depth))
		_quad(canvas, corners, colors, camera)
	_fill(canvas, _ring(base, bottom_radius, WALL, camera), INSIDE)


## The outer wall that faces the camera, the band with the logo and the rim lip.
static func bin_front(canvas: CanvasItem, camera: ArCamera, base: Vector3) -> void:
	_wall(canvas, camera, base, 0.0, BAND_BOTTOM, BODY)
	_wall(canvas, camera, base, BAND_BOTTOM, BAND_TOP, BAND)
	_wall(canvas, camera, base, BAND_TOP, 1.0, BODY)
	_logo(canvas, camera, base)
	_rim(canvas, camera, base)


## A soft shadow on the floor around `centre`, darker in the middle and leaning away from the light.
static func floor_shadow(
	canvas: CanvasItem, camera: ArCamera, centre: Vector3, radius: float, strength: float
) -> void:
	var away: Vector3 = Vector3(-LIGHT.x, 0.0, -LIGHT.z).normalized()
	for layer: int in range(SHADOW_LAYERS - 1, -1, -1):
		var share: float = float(layer) / float(SHADOW_LAYERS - 1)
		var layer_centre: Vector3 = centre + away * radius * 0.25 * share
		var points: PackedVector2Array = _ring(layer_centre, radius * (1.0 + share * SHADOW_SPREAD), 0.0, camera)
		_fill(canvas, points, Color(0, 0, 0, strength / SHADOW_LAYERS))


static func ball_shadow(canvas: CanvasItem, camera: ArCamera, point: Vector3) -> void:
	var height: float = maxf(point.y - PaperToss.BALL_RADIUS, 0.0)
	var radius: float = PaperToss.BALL_RADIUS * (1.0 + height * 1.2)
	floor_shadow(canvas, camera, Vector3(point.x, 0.0, point.z), radius, BALL_SHADOW / (1.0 + height * 4.0))


## A crumpled paper ball: a lumpy outline lit from the upper left with a few creases, turned by
## `spin` radians; `shape_seed` gives every ball its own shape.
static func ball(canvas: CanvasItem, camera: ArCamera, point: Vector3, spin: float, shape_seed: int) -> void:
	var projected: Vector3 = camera.project(point)
	if projected.z <= 0.0:
		return
	var centre: Vector2 = Vector2(projected.x, projected.y)
	var radius: float = PaperToss.BALL_RADIUS * projected.z
	var outline: PackedVector2Array = PackedVector2Array()
	var shades: PackedColorArray = PackedColorArray()
	for facet: int in BALL_FACETS:
		var direction: Vector2 = Vector2.from_angle(spin + TAU * facet / BALL_FACETS)
		outline.append(centre + direction * radius * (0.8 + 0.2 * _noise(shape_seed, facet)))
		shades.append(PAPER * (0.7 + 0.3 * maxf(direction.dot(LIGHT_ON_SCREEN), -0.4)))
	var middle: Color = PAPER * 0.97
	for facet: int in BALL_FACETS:
		var next: int = (facet + 1) % BALL_FACETS
		canvas.draw_primitive(
			PackedVector2Array([centre, outline[facet], outline[next]]),
			PackedColorArray([_opaque(middle), _opaque(shades[facet]), _opaque(shades[next])]),
			PackedVector2Array()
		)
	if radius < 3.0:
		return
	for crease: int in 3:
		var tip: Vector2 = outline[crease * 3 + 1]
		var start: Vector2 = centre + (outline[crease * 3] - centre) * 0.2 * _noise(shape_seed, crease + 20)
		canvas.draw_line(start, centre.lerp(tip, 0.85), Color(CREASE, 0.8), 1.0)
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, Color(CREASE, 0.6), 1.0)


## The floor the AR found around the aimed point `centre`: a grid of dots that stays on the floor as
## the phone moves, and a breathing ring where the bin will stand, cyan when it may stand there.
static func floor_reticle(canvas: CanvasItem, camera: ArCamera, centre: Vector3, can_place: bool, time: float) -> void:
	var steps: int = ceili(SCAN_REACH / SCAN_STEP)
	var origin: Vector2 = (Vector2(centre.x, centre.z) / SCAN_STEP).round()
	for column: int in range(-steps, steps + 1):
		for row: int in range(-steps, steps + 1):
			var cell: Vector2 = (origin + Vector2(column, row)) * SCAN_STEP
			var off: float = cell.distance_to(Vector2(centre.x, centre.z))
			if off > SCAN_REACH:
				continue
			var projected: Vector3 = camera.project(Vector3(cell.x, 0.0, cell.y))
			if projected.z <= 0.0:
				continue
			var at: Vector2 = Vector2(projected.x, projected.y)
			var alpha: float = 0.7 * (1.0 - off / SCAN_REACH)
			canvas.draw_rect(Rect2(at - Vector2.ONE * SCAN_DOT / 2.0, Vector2.ONE * SCAN_DOT), Color(ArPainter.NEON_CYAN, alpha))
	var color: Color = ArPainter.NEON_CYAN if can_place else ArPainter.NEON_PINK
	var pulse: float = 1.0 + 0.08 * sin(time * TAU * RETICLE_PULSE)
	for ring: int in 2:
		var points: PackedVector2Array = _ring(centre, PaperToss.BIN_TOP_RADIUS * (1.3 - ring * 0.5) * pulse, 0.0, camera)
		points.append(points[0])
		canvas.draw_polyline(points, Color(color, 0.9 - ring * 0.4), 1.5)


## Whether a ball here is hidden by the bin: farther from the eye than the bin and lower than the rim.
static func is_behind_bin(point: Vector3, base: Vector3, eye: Vector3) -> bool:
	var from: Vector2 = Vector2(eye.x, eye.z)
	var farther: bool = Vector2(point.x, point.z).distance_to(from) > Vector2(base.x, base.z).distance_to(from) + 0.05
	return farther and point.y < base.y + PaperToss.BIN_HEIGHT + PaperToss.BALL_RADIUS


static func _radius(share: float) -> float:
	return lerpf(PaperToss.BIN_BOTTOM_RADIUS, PaperToss.BIN_TOP_RADIUS, share)


## A point on the bin at `height` metres above its base; angle 0 is to the right, PI / 2 the far side.
static func _ring_point(base: Vector3, radius: float, height: float, angle: float) -> Vector3:
	return base + Vector3(cos(angle) * radius, height, sin(angle) * radius)


static func _ring(base: Vector3, radius: float, height: float, camera: ArCamera) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for segment: int in SEGMENTS:
		points.append(_at(_ring_point(base, radius, height, TAU * segment / SEGMENTS), camera))
	return points


## The outward normal of the cone wall, tipped a little down because the bin widens to the top.
static func _outer_normal(angle: float) -> Vector3:
	var flare: float = PaperToss.BIN_TOP_RADIUS - PaperToss.BIN_BOTTOM_RADIUS
	return Vector3(cos(angle) * PaperToss.BIN_HEIGHT, -flare, sin(angle) * PaperToss.BIN_HEIGHT).normalized()


static func _faces_camera(base: Vector3, angle: float, camera: ArCamera) -> bool:
	var point: Vector3 = _ring_point(base, _radius(0.5), PaperToss.BIN_HEIGHT / 2.0, angle)
	return _outer_normal(angle).dot(camera.eye - point) > 0.0


## The angle on the bin of the side that faces the camera.
static func _facing(base: Vector3, camera: ArCamera) -> float:
	return atan2(camera.eye.z - base.z, camera.eye.x - base.x)


## Ambient, diffuse and a plastic highlight from the ceiling light.
static func _shade(color: Color, normal: Vector3, point: Vector3, eye: Vector3) -> Color:
	var light: Vector3 = LIGHT.normalized()
	var to_eye: Vector3 = (eye - point).normalized()
	var diffuse: float = maxf(normal.dot(light), 0.0)
	var shine: float = pow(maxf(normal.dot((light + to_eye).normalized()), 0.0), SHININESS) * SHINE
	var lit: float = AMBIENT + DIFFUSE * diffuse
	return Color(color.r * lit + shine, color.g * lit + shine, color.b * lit + shine)


## The outer wall between two heights (shares of the bin height), only the side facing the camera.
static func _wall(
	canvas: CanvasItem, camera: ArCamera, base: Vector3, from_share: float, to_share: float, color: Color
) -> void:
	var height: float = PaperToss.BIN_HEIGHT
	for segment: int in SEGMENTS:
		var from: float = TAU * segment / SEGMENTS
		var to: float = TAU * (segment + 1) / SEGMENTS
		if not _faces_camera(base, (from + to) / 2.0, camera):
			continue
		var corners: Array[Vector3] = [
			_ring_point(base, _radius(from_share), height * from_share, from),
			_ring_point(base, _radius(from_share), height * from_share, to),
			_ring_point(base, _radius(to_share), height * to_share, to),
			_ring_point(base, _radius(to_share), height * to_share, from),
		]
		var colors: PackedColorArray = PackedColorArray()
		for corner: int in corners.size():
			var angle: float = to if corner == 1 or corner == 2 else from
			var share: float = from_share if corner < 2 else to_share
			var occlusion: float = lerpf(FLOOR_OCCLUSION, 1.0, sqrt(share))
			colors.append(_shade(color, _outer_normal(angle), corners[corner], camera.eye) * occlusion)
		_quad(canvas, corners, colors, camera)


## The white Alfa letter in the middle of the band, facing the player.
static func _logo(canvas: CanvasItem, camera: ArCamera, base: Vector3) -> void:
	var share: float = (BAND_BOTTOM + BAND_TOP) / 2.0
	var front: Vector3 = _ring_point(base, _radius(share), PaperToss.BIN_HEIGHT * share, _facing(base, camera))
	var projected: Vector3 = camera.project(front)
	var font_size: int = roundi(LOGO_SIZE * projected.z)
	if font_size < 6:
		return
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size("А", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var at: Vector2 = Vector2(projected.x - text_size.x / 2.0, projected.y + font.get_ascent(font_size) / 2.0 - 1.0)
	canvas.draw_string(font, at, "А", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.92))


## The rolled lip around the opening, each piece lit by where it faces.
static func _rim(canvas: CanvasItem, camera: ArCamera, base: Vector3) -> void:
	var radius: float = PaperToss.BIN_TOP_RADIUS + LIP - WALL
	var scale: float = camera.project(_ring_point(base, radius, PaperToss.BIN_HEIGHT, _facing(base, camera))).z
	var width: float = maxf(LIP_WIDTH * scale, 1.5)
	for segment: int in SEGMENTS:
		var from: float = TAU * segment / SEGMENTS
		var to: float = TAU * (segment + 1) / SEGMENTS
		var middle: float = (from + to) / 2.0
		var normal: Vector3 = Vector3(cos(middle), 0.7, sin(middle)).normalized()
		var point: Vector3 = _ring_point(base, radius, PaperToss.BIN_HEIGHT, middle)
		canvas.draw_line(
			_at(_ring_point(base, radius, PaperToss.BIN_HEIGHT, from), camera),
			_at(_ring_point(base, radius, PaperToss.BIN_HEIGHT, to), camera),
			_shade(RIM, normal, point, camera.eye),
			width
		)


static func _quad(canvas: CanvasItem, corners: Array[Vector3], colors: PackedColorArray, camera: ArCamera) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for corner: Vector3 in corners:
		points.append(_at(corner, camera))
	if absf((points[2] - points[0]).cross(points[3] - points[1])) / 2.0 < MIN_AREA:
		return
	canvas.draw_primitive(points, colors, PackedVector2Array())


static func _fill(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	var area: float = 0.0
	for index: int in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	if absf(area) / 2.0 >= MIN_AREA:
		canvas.draw_colored_polygon(points, color)


static func _at(point: Vector3, camera: ArCamera) -> Vector2:
	var projected: Vector3 = camera.project(point)
	return Vector2(projected.x, projected.y)


static func _opaque(color: Color) -> Color:
	return Color(color, 1.0)


## A steady pseudo-random number from 0 to 1 for a ball shape.
static func _noise(shape_seed: int, index: int) -> float:
	return fposmod(sin(shape_seed * 12.9898 + index * 78.233) * 43758.5453, 1.0)
