class_name ManagerCamera
extends Camera3D
## Manager view camera. Follows a target from a fixed, tilted angle (like League of Legends).
## The camera never rotates; pinch / scroll wheel only changes the distance, within tight limits.

## The node to follow, usually the manager.
@export var target: Node3D
## How steeply the camera looks down at the ground, in degrees (90 = straight down).
@export_range(10.0, 90.0) var pitch_degrees: float = 55.0
## Distance from the target in meters when the game starts.
@export var distance: float = 18.0
## Closest zoom, in meters. Kept tight so the view always stays playable.
@export var min_distance: float = 12.0
## Farthest zoom, in meters.
@export var max_distance: float = 26.0
## How quickly the camera catches up with the target (higher = tighter follow).
@export var follow_speed: float = 6.0


func _ready() -> void:
	rotation = Vector3(-deg_to_rad(pitch_degrees), 0.0, 0.0)
	distance = clampf(distance, min_distance, max_distance)
	TouchGestures.pinched.connect(_on_pinched)
	if target:
		global_position = _desired_position()
		# Start at the target instead of smoothly sliding in from the scene origin.
		reset_physics_interpolation()


# Runs in the physics step, in sync with the manager. Physics interpolation (enabled in
# Project Settings) smooths the motion between steps on 120 Hz screens.
func _physics_process(delta: float) -> void:
	if not target:
		return
	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(_desired_position(), weight)


## Moves the camera to the target immediately, without smoothing (e.g. when switching views).
func snap_to_target() -> void:
	if target:
		global_position = _desired_position()
		reset_physics_interpolation()


func _on_pinched(factor: float) -> void:
	# Only the active camera reacts, so zooming in the build view doesn't change this one.
	if not current:
		return
	# Fingers apart (factor > 1) = zoom in = move closer.
	distance = clampf(distance / factor, min_distance, max_distance)


func _desired_position() -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	return target.global_position + Vector3(0.0, sin(pitch), cos(pitch)) * distance
