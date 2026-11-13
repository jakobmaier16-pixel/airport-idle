class_name BuildCamera
extends Camera3D
## Build view camera: looks straight down at the map (top-down) without perspective.
## One-finger drag pans (unless a tool uses it), two fingers pan and zoom, scroll wheel zooms,
## WASD pans on the Mac.
## Zoom is limited and the view never leaves the map.

## Height above the ground in meters. With an orthographic camera this doesn't affect the zoom;
## it only has to be above everything we build. Keep it well inside the sun's shadow range
## (directional_shadow_max_distance on the Sun node), or shadows get blurry and unstable.
const HEIGHT_ABOVE_GROUND: float = 40.0

## How many meters of the map are visible vertically when the build view first opens: about 250 m
## around the terminal (the view opens above the manager).
@export var view_height: float = 250.0
## Closest zoom: visible height in meters.
@export var min_view_height: float = 16.0
## Farthest zoom: visible height in meters: the whole map (3.2 km high). The camera shows the whole
## map at once, so the view never needs to be bigger than that.
@export var max_view_height: float = 3200.0
## Zoomed out further than this many meters, the sun's shadows are switched off: one shadow map
## cannot cover a kilometre sharply, and it costs frame time for nothing.
@export var shadows_max_view_height: float = 400.0
## The sun whose shadows are switched off when zoomed far out.
@export var sun: DirectionalLight3D
## Keyboard panning speed (Mac testing), in screen heights per second.
@export var key_pan_speed: float = 0.8

## Turned off while a finger drags something else in the build view (e.g. the building preview).
var pan_enabled: bool = true


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	position.y = HEIGHT_ABOVE_GROUND
	far = HEIGHT_ABOVE_GROUND + 50.0
	# This camera moves every frame from input, not in the physics step, so it must not be
	# smoothed by physics interpolation.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	TouchGestures.dragged.connect(_on_dragged)
	TouchGestures.pinch_moved.connect(_on_pinch_moved)
	TouchGestures.pinched.connect(_on_pinched)
	_apply_limits()


func _process(delta: float) -> void:
	if not current:
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if input != Vector2.ZERO:
		var step := input * view_height * key_pan_speed * delta
		position.x += step.x
		position.z += step.y
		_apply_limits()


## Shadows on in the manager view and when zoomed in, off in the build view when zoomed far out.
## Main calls it after every view switch.
func update_shadows() -> void:
	if sun != null:
		sun.shadow_enabled = not current or view_height <= shadows_max_view_height


## Moves the view so `world_position` is in the center (as far as the map edges allow).
func center_on(world_position: Vector3) -> void:
	position.x = world_position.x
	position.z = world_position.z
	_apply_limits()


func _on_dragged(_touch_position: Vector2, relative: Vector2) -> void:
	if current and pan_enabled:
		_pan(relative)


# Two fingers always pan, even while one-finger drags are used for a tool (e.g. painting walkways).
func _on_pinch_moved(relative: Vector2) -> void:
	if current:
		_pan(relative)


func _pan(screen_relative: Vector2) -> void:
	# Move the camera opposite to the finger, so the map sticks to the finger.
	var meters_per_pixel := view_height / get_viewport().get_visible_rect().size.y
	position.x -= screen_relative.x * meters_per_pixel
	position.z -= screen_relative.y * meters_per_pixel
	_apply_limits()


func _on_pinched(factor: float) -> void:
	if not current:
		return
	# Fingers apart (factor > 1) = zoom in = see fewer meters.
	view_height /= factor
	_apply_limits()


func _apply_limits() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / viewport_size.y
	var map := Airport.grid.get_world_rect()

	# The farthest zoom shows the whole map: its height, or on a wide screen its width.
	var largest := minf(max_view_height, maxf(map.size.y, map.size.x / aspect))
	view_height = clampf(view_height, min_view_height, maxf(largest, min_view_height))
	size = view_height  # Orthographic size = visible height in meters.
	update_shadows()

	var half_view := Vector2(view_height * aspect, view_height) * 0.5
	position.x = _clamp_axis(position.x, map.position.x + half_view.x, map.end.x - half_view.x)
	position.z = _clamp_axis(position.z, map.position.y + half_view.y, map.end.y - half_view.y)


# Clamps `value` between `low` and `high`; centers it if the view is wider than the map.
func _clamp_axis(value: float, low: float, high: float) -> float:
	if low > high:
		return (low + high) * 0.5
	return clampf(value, low, high)
