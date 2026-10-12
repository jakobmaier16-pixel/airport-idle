class_name TouchJoystick
extends Control
## Floating on-screen joystick: appears wherever the player touches the screen and follows the thumb.
## Read `output` for the current direction (length 0..1, y is negative when pushed up).
## The joystick ring is kept inside this control's rect, so place it in a SafeAreaContainer.

## Radius of the outer ring in UI pixels. Pushing the knob to the edge means full speed.
@export var base_radius: float = 110.0
@export var knob_radius: float = 45.0
## Small movements below this fraction of the radius are ignored.
@export_range(0.0, 0.5) var dead_zone: float = 0.15
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.25)
@export var knob_color: Color = Color(1.0, 1.0, 1.0, 0.6)

## Current stick direction, read by the player every physics step.
var output: Vector2 = Vector2.ZERO

# Which finger controls the joystick (-1 = none). Lets a second finger be used for other things.
var _touch_index: int = -1
# Ring center in viewport coordinates.
var _base_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Never block clicks/taps meant for other UI elements.
	mouse_filter = MOUSE_FILTER_IGNORE


# _unhandled_input only receives touches that no other UI element has consumed,
# so later buttons on top of the screen keep working.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_start(touch.index, touch.position)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			_stop()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_move_knob(drag.position)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Release the stick if the app is sent to the background mid-drag (e.g. a phone call).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop()


func _draw() -> void:
	if _touch_index == -1:
		return
	var center := get_global_transform().affine_inverse() * _base_center
	draw_circle(center, base_radius, base_color, true, -1.0, true)
	draw_arc(center, base_radius, 0.0, TAU, 64, knob_color, 3.0, true)
	draw_circle(center + _knob_offset, knob_radius, knob_color, true, -1.0, true)


func _start(index: int, touch_position: Vector2) -> void:
	_touch_index = index
	# Keep the whole ring inside the safe area, even if the touch is near the screen edge.
	var allowed := get_global_rect().grow(-base_radius)
	_base_center = touch_position.clamp(allowed.position, allowed.end)
	_move_knob(touch_position)


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
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	output = Vector2.ZERO
	queue_redraw()
