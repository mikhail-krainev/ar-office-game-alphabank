class_name HomePalettes
extends RefCounted
## Colours of the home palettes of server/content/home.json (ids there, names and prices on the
## server). A palette recolours the floors and walls of the apartment through
## res://shaders/home_palette.gdshader; "original" keeps the tiles as they are drawn.

const ORIGINAL: String = "original"
const SHADER: Shader = preload("res://shaders/home_palette.gdshader")

## id: [wall dark, wall light, floor dark, floor light]
const COLORS: Dictionary[String, Array] = {
	"scandi": [Color("#b3ab9e"), Color("#f7f4ee"), Color("#9c7f5c"), Color("#ead9bc")],
	"japandi": [Color("#857a68"), Color("#e8e0d1"), Color("#5a4632"), Color("#c9a982")],
	"loft": [Color("#3b2622"), Color("#b0604f"), Color("#3c3b39"), Color("#aaa59d")],
	"minimal": [Color("#9ea1a4"), Color("#f8f8f6"), Color("#44474b"), Color("#a6a9ad")],
	"memphis": [Color("#2fb8bd"), Color("#ffd6e2"), Color("#e86a96"), Color("#fff2a8")],
	"miami": [Color("#1a0b2e"), Color("#ff4fa3"), Color("#120a24"), Color("#4a33a8")],
	"deco": [Color("#0f2b26"), Color("#3d8a78"), Color("#6a4a1c"), Color("#e6c47e")],
}


## The material for `id`, or null for the original tiles and unknown ids.
static func material(id: String) -> ShaderMaterial:
	if not COLORS.has(id):
		return null
	var colors: Array = COLORS[id]
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("wall_dark", colors[0])
	result.set_shader_parameter("wall_light", colors[1])
	result.set_shader_parameter("floor_dark", colors[2])
	result.set_shader_parameter("floor_light", colors[3])
	result.set_shader_parameter("atlas_rows", float(OfficeTiles.Style.size()))
	result.set_shader_parameter("atlas_columns", float(OfficeTiles.COLUMNS))
	result.set_shader_parameter("kept_row", float(OfficeTiles.Style.GRASS))
	return result


## Swatch colours for the palette picker: wall light, wall dark, floor light, floor dark.
static func swatch(id: String) -> Array[Color]:
	if not COLORS.has(id):
		return [Color("#efdfc6"), Color("#b9c9b0"), Color("#c99a66"), Color("#c9785a")]
	var colors: Array = COLORS[id]
	return [colors[1], colors[0], colors[3], colors[2]]
