class_name FollowCamera
extends Camera3D
## Follows a target from a fixed, tilted angle (like League of Legends). The camera never rotates.

## The node to follow, usually the player.
@export var target: Node3D
## How steeply the camera looks down at the ground, in degrees (90 = straight down).
@export_range(10.0, 90.0) var pitch_degrees: float = 55.0
## Distance from the target in meters.
@export var distance: float = 18.0
## How quickly the camera catches up with the target (higher = tighter follow).
@export var follow_speed: float = 6.0


func _ready() -> void:
	rotation = Vector3(-deg_to_rad(pitch_degrees), 0.0, 0.0)
	if target:
		global_position = _desired_position()
		# Start at the target instead of smoothly sliding in from the scene origin.
		reset_physics_interpolation()


# Runs in the physics step, in sync with the player. Physics interpolation (enabled in
# Project Settings) smooths the motion between steps on 120 Hz screens.
func _physics_process(delta: float) -> void:
	if not target:
		return
	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(_desired_position(), weight)


func _desired_position() -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	return target.global_position + Vector3(0.0, sin(pitch), cos(pitch)) * distance
