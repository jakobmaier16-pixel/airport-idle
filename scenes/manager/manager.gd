class_name Manager
extends CharacterBody3D
## The manager (the player character). Walks on the ground using keyboard (WASD / arrows) or the on-screen joystick.

## Top walking speed in meters per second.
@export var move_speed: float = 6.0
## How quickly the character speeds up and slows down (higher = snappier).
@export var acceleration: float = 12.0
## How quickly the character turns to face its walking direction.
@export var turn_speed: float = 12.0
## On-screen joystick to read touch input from. Optional: the keyboard works without it.
@export var joystick: TouchJoystick


func _physics_process(delta: float) -> void:
	var input := _get_move_input()
	# The camera never rotates and always looks along -Z, so "up" on screen is world -Z.
	# If the camera ever gets a yaw angle, rotate this vector by it.
	var direction := Vector3(input.x, 0.0, input.y)

	# Frame-rate independent smoothing: same feel at 60 Hz and 120 Hz (ProMotion).
	var accel_weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, direction.x * move_speed, accel_weight)
	velocity.z = lerpf(velocity.z, direction.z * move_speed, accel_weight)
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	if direction.length_squared() > 0.01:
		# Godot's "forward" is -Z, hence the negated arguments.
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


## Combined keyboard + joystick input. Length is 0..1; y is negative when pushing "up".
func _get_move_input() -> Vector2:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if joystick:
		input += joystick.output
	return input.limit_length(1.0)
