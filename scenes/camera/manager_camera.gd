class_name ManagerCamera
extends Camera3D
## Manager view camera: first person (design doc §15). It sits at the manager's eye height and
## looks where the player drags on the right half of the screen; the manager walks relative to it.

## The node to follow, usually the manager.
@export var target: Node3D
## Eye height above the manager's feet, in meters.
@export var eye_height: float = 1.7
## Degrees turned per UI pixel dragged.
@export var look_sensitivity: float = 0.2
## How far the view can tilt down (to watch queues) and up, in degrees.
@export var min_pitch_degrees: float = -70.0
@export var max_pitch_degrees: float = 35.0
## Drags starting right of this share of the screen width look around (the left part is the joystick).
@export_range(0.1, 1.0) var look_area_start: float = 0.5

## Where the view points: yaw 0 looks north (-Z), positive turns left; pitch < 0 looks down.
var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)

# The finger turning the view (TouchGestures finger index), or -1.
var _look_finger: int = -1


func _ready() -> void:
	# Moved every frame from the manager's smoothed position, so physics interpolation stays out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Don't see the inside of your own head: the manager's body is on layer 2.
	set_cull_mask_value(2, false)
	TouchGestures.finger_drag_started.connect(_on_finger_drag_started)
	TouchGestures.finger_dragged.connect(_on_finger_dragged)
	TouchGestures.finger_drag_ended.connect(_on_finger_drag_ended)
	_follow(false)


func _process(_delta: float) -> void:
	_follow(true)


## Moves the camera to the manager's eyes right away (e.g. after teleporting the manager).
func snap_to_target() -> void:
	_follow(false)


## Turns the view by a drag of `relative` UI pixels.
func turn(relative: Vector2) -> void:
	var step := deg_to_rad(look_sensitivity)
	yaw = wrapf(yaw - relative.x * step, -PI, PI)
	pitch = clampf(pitch - relative.y * step, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	_follow(true)


## Looks straight at `point` (tests, and later e.g. "show me that station").
func face(point: Vector3) -> void:
	_follow(false)
	var direction := (point - global_position).normalized()
	yaw = atan2(-direction.x, -direction.z)
	pitch = clampf(asin(direction.y), deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	_follow(false)


func _follow(smoothed: bool) -> void:
	if target == null:
		return
	# The manager moves in physics steps; its interpolated position is smooth on 120 Hz screens.
	var feet := target.get_global_transform_interpolated().origin if smoothed else target.global_position
	global_position = feet + Vector3.UP * eye_height
	rotation = Vector3(pitch, yaw, 0.0)


func _on_finger_drag_started(index: int, start_position: Vector2, _position: Vector2) -> void:
	if not current or _look_finger >= 0:
		return
	if start_position.x >= get_viewport().get_visible_rect().size.x * look_area_start:
		_look_finger = index


func _on_finger_dragged(index: int, _position: Vector2, relative: Vector2) -> void:
	if index == _look_finger and current:
		turn(relative)


func _on_finger_drag_ended(index: int, _position: Vector2) -> void:
	if index == _look_finger:
		_look_finger = -1
