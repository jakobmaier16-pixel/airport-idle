class_name TouchJoystick
extends Control
## Floating on-screen joystick for the manager view. Appears where a finger starts dragging on the
## left half of the screen and follows the thumb. The right half is for looking around and tapping.
## Read `output` for the current direction (length 0..1, y is negative when pushed up).
## The joystick ring is kept inside this control's rect, so place it in a SafeAreaContainer.

## Radius of the outer ring in UI pixels. Pushing the knob to the edge means full speed.
@export var base_radius: float = 100.0
@export var knob_radius: float = 40.0
## Small movements below this fraction of the radius are ignored.
@export_range(0.0, 0.5) var dead_zone: float = 0.15
## Fraction of the screen width (from the left) where a drag starts the joystick.
@export_range(0.1, 1.0) var touch_area_width: float = 0.5
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.25)
@export var knob_color: Color = Color(1.0, 1.0, 1.0, 0.6)

## Turned off in the build view, where one-finger drags move the camera instead.
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			_stop()

## Current stick direction, read by the manager every physics step.
var output: Vector2 = Vector2.ZERO

var _active: bool = false
# The finger driving the stick (TouchGestures finger index), or -1.
var _finger: int = -1
# Ring center in viewport coordinates.
var _base_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Never block taps meant for other UI elements.
	mouse_filter = MOUSE_FILTER_IGNORE
	# Each finger drags on its own in the manager view: the stick follows the one finger it claimed.
	TouchGestures.finger_drag_started.connect(_on_drag_started)
	TouchGestures.finger_dragged.connect(_on_dragged)
	TouchGestures.finger_drag_ended.connect(_on_drag_ended)


func _draw() -> void:
	if not _active:
		return
	var center := get_global_transform().affine_inverse() * _base_center
	draw_circle(center, base_radius, base_color, true, -1.0, true)
	draw_arc(center, base_radius, 0.0, TAU, 64, knob_color, 3.0, true)
	draw_circle(center + _knob_offset, knob_radius, knob_color, true, -1.0, true)


func _on_drag_started(index: int, start_position: Vector2, touch_position: Vector2) -> void:
	if not enabled or _active:
		return
	if start_position.x > get_viewport().get_visible_rect().size.x * touch_area_width:
		return
	_active = true
	_finger = index
	# Keep the whole ring inside the safe area, even if the touch is near the screen edge.
	var allowed := get_global_rect().grow(-base_radius)
	_base_center = start_position.clamp(allowed.position, allowed.end)
	_move_knob(touch_position)


func _on_dragged(index: int, touch_position: Vector2, _relative: Vector2) -> void:
	if _active and index == _finger:
		_move_knob(touch_position)


func _on_drag_ended(index: int, _touch_position: Vector2) -> void:
	if index == _finger:
		_stop()


func _move_knob(touch_position: Vector2) -> void:
	_knob_offset = (touch_position - _base_center).limit_length(base_radius)
	var strength := _knob_offset.length() / base_radius
	if strength < dead_zone:
		output = Vector2.ZERO
	else:
		# Rescale so output starts at 0 right outside the dead zone instead of jumping.
		output = _knob_offset.normalized() * inverse_lerp(dead_zone, 1.0, strength)
	queue_redraw()


func _stop() -> void:
	_active = false
	_finger = -1
	_knob_offset = Vector2.ZERO
	output = Vector2.ZERO
	queue_redraw()
