class_name IntroContext
extends RefCounted
## Shared state between the intro controller and its scenes.

var profile: BackendModels.Profile
var audio: IntroAudio
## Stage shake amplitude in stage pixels, set by scenes.
var shake: float = 0.0
var car_id: String = VehicleCatalog.DEFAULT_CAR
var car_name: String = ""
var car_speed_kmh: int = 110
## The evening sequence (home from the office): stops look like late evening.
var evening: bool = false
