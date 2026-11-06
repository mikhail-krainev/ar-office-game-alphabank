class_name IntroArt
extends RefCounted
## Paths and stage layout shared by the intro art generator and the intro scenes.

const STAGE: Vector2i = Vector2i(320, 180)
const BAR_TOP: int = 16
const BAR_BOTTOM: int = 22
const DIR: String = "res://assets/intro/"

## id: image size. Tiles are 320 px wide and repeat horizontally.
const IMAGES: Dictionary[String, Vector2i] = {
	"bedroom": Vector2i(320, 180),
	"bedroom_blanket": Vector2i(320, 360),
	"bathroom": Vector2i(320, 180),
	"home_kitchen": Vector2i(320, 180),
	"kitchen_table": Vector2i(320, 180),
	"parking": Vector2i(320, 180),
	"autobahn_sky": Vector2i(320, 180),
	"autobahn_far": Vector2i(320, 44),
	"autobahn_mid": Vector2i(320, 76),
	"autobahn_road": Vector2i(320, 50),
	"autobahn_rail": Vector2i(320, 14),
	"city_sky": Vector2i(320, 180),
	"city_far": Vector2i(320, 90),
	"city_near": Vector2i(320, 92),
	"city_road": Vector2i(320, 36),
	"office_exterior": Vector2i(320, 180),
	"coffee_shop": Vector2i(320, 180),
	"grocery": Vector2i(320, 180),
	"restaurant": Vector2i(320, 180),
	"gas_station": Vector2i(320, 180),
}

## Top edge of each repeating layer on the stage.
const AUTOBAHN_FAR_Y: int = 72
const AUTOBAHN_MID_Y: int = 38
const AUTOBAHN_ROAD_Y: int = 108
const AUTOBAHN_RAIL_Y: int = 146
const CITY_FAR_Y: int = 16
const CITY_NEAR_Y: int = 34
const CITY_ROAD_Y: int = 124


static func path(id: String) -> String:
	return DIR + id + ".png"
