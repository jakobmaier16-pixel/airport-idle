class_name ViewerCamera
extends Camera3D
## Asset viewer camera (scenes/viewer/): a perspective camera that orbits one item.
## One-finger drag turns and tilts, pinch (or the mouse wheel) zooms; all input comes through
## TouchGestures. The limits follow the item's size: it never goes below the ground, never closer than
## a few centimetres to a small prop and never farther than about 6 times the item's diagonal.

## The camera never looks from lower than this above the ground, or higher than this (degrees).
const MIN_PITCH_DEG: float = 3.0
const MAX_PITCH_DEG: float = 85.0
## Eye height of the first-person game, in metres.
const EYE_HEIGHT: float = 1.7
## How much of the screen the item fills at the start (the larger of width and height). About half, so it stays clear of the buttons at the right and the bottom.
const START_FILL: float = 0.5
## Start view: from the front right, a bit from above (three-quarter view).
const START_YAW_DEG: float = 35.0
const START_PITCH_DEG: float = 28.0
## Closest and farthest distance, as shares of the item's diagonal (and a floor for tiny props).
const MIN_DISTANCE_PER_DIAGONAL: float = 0.05
const MIN_DISTANCE_FLOOR: float = 0.3
const MAX_DISTANCE_PER_DIAGONAL: float = 6.0
## At eye level the camera stands at most this far from the item's middle ("a natural distance").
const EYE_DISTANCE_MAX: float = 80.0
## Degrees turned / tilted per UI pixel dragged.
@export var turn_sensitivity: float = 0.35
## The sun, whose shadows are switched off when the camera is far away (one shadow map cannot
## cover hundreds of metres sharply).
@export var sun: DirectionalLight3D
@export var shadows_max_distance: float = 300.0

## What the camera frames: the item's bounds in world space.
var bounds: AABB = AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2))
## The point the camera orbits: the middle of the bounds.
var target: Vector3 = Vector3.ZERO
var yaw: float = deg_to_rad(START_YAW_DEG)
var pitch: float = deg_to_rad(START_PITCH_DEG)
var distance: float = 10.0
## True after "Eye level": the camera stands at 1.7 m and only walks around the item.
var eye_level: bool = false

var _min_distance: float = 0.3
var _max_distance: float = 100.0


func _ready() -> void:
	# Moved from input, not in the physics step.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	fov = 50.0
	# Like the manager: the full-detail landside models, not the build view's stand-ins.
	set_cull_mask_value(2, false)
	set_cull_mask_value(LandsideLayer.FAR_LAYER, false)
	TouchGestures.dragged.connect(_on_dragged)
	TouchGestures.pinched.connect(_on_pinched)
	_apply()


## Frames `item_bounds` (world space): three-quarter view, the item filling about 60 % of the screen.
func frame(item_bounds: AABB) -> void:
	bounds = item_bounds
	target = bounds.get_center()
	var diagonal := bounds.size.length()
	_min_distance = maxf(MIN_DISTANCE_FLOOR, diagonal * MIN_DISTANCE_PER_DIAGONAL)
	_max_distance = maxf(diagonal * MAX_DISTANCE_PER_DIAGONAL, _min_distance * 4.0)
	reset_view()


## Back to the three-quarter start view.
func reset_view() -> void:
	eye_level = false
	yaw = deg_to_rad(START_YAW_DEG)
	pitch = deg_to_rad(START_PITCH_DEG)
	distance = clampf(_fitting_distance(), _min_distance, _max_distance)
	_apply()


## Stands at eye height (1.7 m) at a natural distance and looks at the item.
func go_eye_level() -> void:
	eye_level = true
	var horizontal := Vector2(bounds.size.x, bounds.size.z).length()
	# A player stands back far enough to see the whole item (about its own width), but never farther than 80 m: not limited by the orbit's closest distance.
	distance = clampf(minf(horizontal + 3.0, EYE_DISTANCE_MAX), MIN_DISTANCE_FLOOR, _max_distance)
	_apply()


## Turns (x) and tilts (y) the view by a drag of `relative` UI pixels.
func turn(relative: Vector2) -> void:
	var step := deg_to_rad(turn_sensitivity)
	yaw = wrapf(yaw - relative.x * step, -PI, PI)
	if not eye_level:
		pitch = clampf(pitch + relative.y * step, deg_to_rad(MIN_PITCH_DEG), deg_to_rad(MAX_PITCH_DEG))
	_apply()


## Zooms: factor > 1 comes closer (fingers apart, wheel up).
func zoom(factor: float) -> void:
	distance = clampf(distance / factor, MIN_DISTANCE_FLOOR if eye_level else _min_distance, _max_distance)
	_apply()


func min_distance() -> float:
	return _min_distance


func max_distance() -> float:
	return _max_distance


func _on_dragged(_position: Vector2, relative: Vector2) -> void:
	if current:
		turn(relative)


func _on_pinched(factor: float) -> void:
	if current:
		zoom(factor)


func _apply() -> void:
	if eye_level:
		var flat := Vector3(sin(yaw), 0.0, cos(yaw)) * distance
		global_position = Vector3(target.x + flat.x, EYE_HEIGHT, target.z + flat.z)
		look_at(Vector3(target.x, clampf(target.y, 0.0, 2.0), target.z))
	else:
		var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var place := target + direction * distance
		# Never below the ground, even for an item whose middle is low.
		place.y = maxf(place.y, 0.05)
		global_position = place
		look_at(target)
	near = clampf(distance * 0.01, 0.02, 20.0)
	far = distance + bounds.size.length() * 3.0 + 200.0
	if sun != null and current:
		sun.shadow_enabled = distance <= shadows_max_distance


# The distance at which the item's corners fill START_FILL of the screen (width or height, whichever
# is larger), found by halving: the camera looks at the middle from the start yaw and pitch.
func _fitting_distance() -> float:
	var screen := get_viewport().get_visible_rect().size
	var aspect := screen.x / maxf(screen.y, 1.0)
	var half_tan := tan(deg_to_rad(fov) * 0.5)
	var basis := Basis.looking_at(-_direction(yaw, pitch), Vector3.UP)
	var low := 0.01
	var high := bounds.size.length() * 40.0 + 10.0
	for i in 40:
		var middle := (low + high) * 0.5
		var eye := target + _direction(yaw, pitch) * middle
		var fill := 0.0
		for corner in 8:
			var point := bounds.position + bounds.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
			var local := basis.inverse() * (point - eye)
			if local.z >= -0.001:
				fill = INF
				break
			var ndc := Vector2(absf(local.x) / (-local.z * half_tan * aspect), absf(local.y) / (-local.z * half_tan))
			fill = maxf(fill, maxf(ndc.x, ndc.y))
		# ndc runs from the middle to the edge of the screen (1.0): the item spans 2 * fill / 2 of it.
		if fill > START_FILL:
			low = middle
		else:
			high = middle
	return high


static func _direction(yaw_radians: float, pitch_radians: float) -> Vector3:
	return Vector3(sin(yaw_radians) * cos(pitch_radians), sin(pitch_radians), cos(yaw_radians) * cos(pitch_radians))
