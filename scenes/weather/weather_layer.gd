class_name WeatherLayer
extends Node3D
## Shows the weather (design doc §12.2): rain or snow falls in a box around what the camera
## looks at, fog thickens the air. Only reads Airport.weather. Lightning and the darker sky are
## done by DayNight.

## Size of the box around the camera's focus where rain and snow fall, in meters.
const AREA: Vector3 = Vector3(70.0, 25.0, 70.0)
const RAIN_AMOUNT: int = 900
const SNOW_AMOUNT: int = 700
const FOG_DENSITY: float = 0.035

@export var world_environment: WorldEnvironment

var _rain: CPUParticles3D
var _snow: CPUParticles3D


func _ready() -> void:
	# Moved every frame with the camera, so Godot's physics interpolation stays out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain = _make_particles(RAIN_AMOUNT, Vector3(0.03, 0.9, 0.03), Color(0.75, 0.82, 0.95, 0.55), 22.0, 0.05)
	_snow = _make_particles(SNOW_AMOUNT, Vector3(0.12, 0.12, 0.12), Color(1.0, 1.0, 1.0, 0.9), 2.5, 0.5)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var kind := Airport.weather.kind
	_rain.emitting = kind == Weather.Kind.RAIN or kind == Weather.Kind.STORM
	_snow.emitting = kind == Weather.Kind.SNOW
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Centre the box where the camera looks at the ground.
		var forward := -camera.global_transform.basis.z
		var focus := camera.global_position
		if forward.y < -0.01:
			focus += forward * (camera.global_position.y / -forward.y)
		global_position = Vector3(focus.x, AREA.y, focus.z)
	if world_environment != null and world_environment.environment != null:
		var environment := world_environment.environment
		environment.fog_enabled = kind == Weather.Kind.FOG
		environment.fog_density = FOG_DENSITY


func is_raining() -> bool:
	return _rain.emitting


func is_snowing() -> bool:
	return _snow.emitting


func _make_particles(amount: int, size: Vector3, color: Color, speed: float, spread: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = AREA.y / speed
	particles.preprocess = particles.lifetime
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(AREA.x * 0.5, 0.5, AREA.z * 0.5)
	particles.direction = Vector3(0.1, -1.0, 0.0)
	particles.spread = spread * 90.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = speed * 0.9
	particles.initial_velocity_max = speed * 1.1
	# Drops fall in world space, so moving the box doesn't drag the falling ones along.
	particles.local_coords = false
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	particles.mesh = mesh
	particles.emitting = false
	add_child(particles)
	return particles
