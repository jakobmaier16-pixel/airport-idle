class_name DayNight
extends Node
## Lights the airport by the time of day (design doc §12.1): the sun climbs and sets, evenings
## are warm, nights are dim and blue but still readable. Only reads Airport.clock.
## The sun keeps its compass direction (the camera never rotates, so shadows stay familiar).

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment

const DAY_SUN_ENERGY: float = 1.0
const NIGHT_SUN_ENERGY: float = 0.4
const DAY_AMBIENT: float = 1.0
const NIGHT_AMBIENT: float = 0.6
const NOON_COLOR: Color = Color(1.0, 0.98, 0.94)
const LOW_SUN_COLOR: Color = Color(1.0, 0.72, 0.5)
const MOON_COLOR: Color = Color(0.55, 0.65, 1.0)
## Sun height above the horizon at noon and when it is low, in degrees.
const NOON_ELEVATION: float = 55.0
const LOW_ELEVATION: float = 18.0

## How much darker the sky gets in each kind of weather (design doc §12.2).
const WEATHER_LIGHT: Array[float] = [1.0, 0.75, 0.5, 0.8, 0.85]
## Lightning: how often (per second) and how long a flash lasts.
const LIGHTNING_CHANCE: float = 0.25
const FLASH_SECONDS: float = 0.12

var _yaw: float = 0.0
var _flash_left: float = 0.0


func _ready() -> void:
	if sun != null:
		_yaw = sun.rotation.y
	_update()


func _process(delta: float) -> void:
	_flash_left -= delta
	if Airport.weather.kind == Weather.Kind.STORM and _flash_left < -0.5 and randf() < LIGHTNING_CHANCE * delta:
		_flash_left = FLASH_SECONDS
	_update()


func _update() -> void:
	if sun == null:
		return
	var hour := Airport.clock.hour()
	var light := Clock.daylight(hour) * WEATHER_LIGHT[Airport.weather.kind]
	# How high the sun is: low in the morning and evening, highest at noon.
	var height := clampf(1.0 - absf(hour - 13.0) / 7.0, 0.0, 1.0)
	sun.rotation = Vector3(-deg_to_rad(lerpf(LOW_ELEVATION, NOON_ELEVATION, height)), _yaw, 0.0)
	sun.light_energy = lerpf(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, light)
	var day_color := LOW_SUN_COLOR.lerp(NOON_COLOR, height)
	sun.light_color = MOON_COLOR.lerp(day_color, light)
	if _flash_left > 0.0:
		sun.light_energy = 3.0
		sun.light_color = Color(0.9, 0.92, 1.0)
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.ambient_light_energy = lerpf(NIGHT_AMBIENT, DAY_AMBIENT, light)
		world_environment.environment.background_energy_multiplier = lerpf(0.35, 1.0, light)
