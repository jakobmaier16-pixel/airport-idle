class_name CinematicCamera
extends Camera3D
## A short cutscene camera (design doc §14): follows a plane for a few seconds, e.g. a new
## airline's first landing, then hands back to the previous camera. A tap ends it early.
## Only used for these moments; the manager camera itself never rotates.

signal finished

## How long a cutscene lasts, in seconds.
const DURATION: float = 8.0
## Distance and height from the plane, in meters, and how far the view swings round it.
const DISTANCE: float = 32.0
const HEIGHT: float = 9.0
const SWING_DEGREES: float = 50.0

var _plane: Node3D = null
var _previous: Camera3D = null
var _time: float = 0.0


func _ready() -> void:
	# Moved every frame with the plane, so Godot's physics interpolation stays out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	TouchGestures.tapped.connect(func(_position: Vector2) -> void:
		if is_playing():
			stop())


func is_playing() -> bool:
	return _plane != null


## Follows `plane` for DURATION seconds.
func play(plane: Node3D) -> void:
	_plane = plane
	_previous = get_viewport().get_camera_3d()
	_time = 0.0
	_follow()
	make_current()


func stop() -> void:
	if _plane == null:
		return
	_plane = null
	if is_instance_valid(_previous):
		_previous.make_current()
	finished.emit()


func _process(delta: float) -> void:
	if _plane == null:
		return
	_time += delta
	if _time >= DURATION or not is_instance_valid(_plane):
		stop()
		return
	_follow()


func _follow() -> void:
	# Beside and a little behind the plane, swinging slowly round it.
	var forward := -_plane.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var angle := deg_to_rad(110.0 + SWING_DEGREES * _time / DURATION)
	var offset := forward.rotated(Vector3.UP, angle) * DISTANCE + Vector3.UP * HEIGHT
	global_position = _plane.global_position + offset
	look_at(_plane.global_position + Vector3.UP * 2.0, Vector3.UP)
