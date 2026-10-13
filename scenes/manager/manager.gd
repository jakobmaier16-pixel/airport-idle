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
## The first-person view: "forward" is where it looks (design doc §15). Optional.
@export var view: ManagerCamera

## Turned off in the build view, so WASD moves the build camera instead of the manager.
var input_enabled: bool = true


func _physics_process(delta: float) -> void:
	var input := _get_move_input()
	# Walk relative to the view: stick up = forward (where the manager looks), sideways = strafe.
	var yaw := view.yaw if view != null else 0.0
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)

	# Frame-rate independent smoothing: same feel at 60 Hz and 120 Hz (ProMotion).
	var accel_weight := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, direction.x * move_speed, accel_weight)
	velocity.z = lerpf(velocity.z, direction.z * move_speed, accel_weight)
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
	_stay_inside_map()

	# The simulation needs to know where the manager is (managing on the spot, design doc §15.1).
	Airport.manager_position = global_position
	Airport.manager_yaw = yaw

	# The body faces where the manager looks (others see it in the build view and cutscenes).
	if view != null:
		rotation.y = yaw
	elif direction.length_squared() > 0.01:
		# Godot's "forward" is -Z, hence the negated arguments.
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


func _ready() -> void:
	Airport.manager_position = global_position


func _exit_tree() -> void:
	Airport.manager_position = Airport.NOBODY_THERE


# The map has no walls yet, so keep the manager from walking off the edge.
func _stay_inside_map() -> void:
	var rect := Airport.grid.get_world_rect()
	global_position.x = clampf(global_position.x, rect.position.x, rect.end.x)
	global_position.z = clampf(global_position.z, rect.position.y, rect.end.y)


## Combined keyboard + joystick input. Length is 0..1; y is negative when pushing "up".
func _get_move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if joystick:
		input += joystick.output
	return input.limit_length(1.0)
