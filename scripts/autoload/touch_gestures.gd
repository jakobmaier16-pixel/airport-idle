extends Node
## Turns raw touches (and mouse / trackpad input on the Mac) into simple gestures:
## one-finger drags, taps and pinch zoom. Registered as the autoload "TouchGestures",
## so any script can connect to its signals.
##
## Touches on UI controls (buttons etc.) never reach this script, because Godot's GUI
## consumes them first and we only read *unhandled* input.

## A one-finger drag began. `start_position` is where the finger first touched down.
signal drag_started(start_position: Vector2, position: Vector2)
signal dragged(position: Vector2, relative: Vector2)
## The finger was lifted at the end of a drag.
signal drag_ended(position: Vector2)
## A drag was interrupted (a second finger turned it into a pinch, or the app lost focus).
## Unlike drag_ended, whatever the drag was doing should be undone, not completed.
signal drag_cancelled
## A short touch without movement (any finger that is not part of a pinch).
signal tapped(position: Vector2)
## Zoom gesture. factor > 1 means "zoom in" (fingers moved apart, wheel up, trackpad spread).
signal pinched(factor: float)
## The midpoint between the two pinching fingers moved (two-finger pan).
signal pinch_moved(relative: Vector2)
## Manager view (`independent_drags`): every finger drags on its own, identified by `index`, so
## one thumb can walk (joystick) while the other looks around.
signal finger_drag_started(index: int, start_position: Vector2, position: Vector2)
signal finger_dragged(index: int, position: Vector2, relative: Vector2)
signal finger_drag_ended(index: int, position: Vector2)

enum State {
	IDLE, ## No finger down.
	PENDING, ## One finger down, not moved yet: could still become a drag, a tap or a pinch.
	DRAGGING, ## One finger is dragging.
	PINCHING, ## Two fingers are pinching.
	WAITING, ## A pinch ended; ignore everything until all fingers are lifted.
}

## How far a finger may wobble during a tap, in screen points (Apple's controls allow ~10-15 pt).
## Moving further turns the touch into a drag. Measured in points, not UI pixels, so it is the
## same physical size on every device (on an iPhone, 10 UI pixels are only ~5 pt: too strict).
const TAP_SLOP_POINTS: float = 12.0
## Limits for the slop in UI pixels. Platforms report window sizes in pixels or in points, so the
## conversion can be off by the screen scale; the limits keep it sensible either way.
const MIN_TAP_SLOP: float = 10.0
const MAX_TAP_SLOP: float = 30.0
## Longest press that still counts as a tap, in seconds (iOS uses 0.5 s for long presses).
const TAP_MAX_DURATION: float = 0.5
const WHEEL_ZOOM_STEP: float = 1.1
const TRACKPAD_SCROLL_ZOOM_SPEED: float = 0.05

## If true, a second finger during a drag cancels the drag and starts a pinch (build view).
## If false, an active drag is never interrupted (manager view: the joystick keeps working
## while the other thumb taps the right half of the screen).
var pinch_cancels_drag: bool = false

## If true (manager view), every finger is its own gesture: a finger that moves sends the finger_*
## drag signals, a short touch is a tap, and there is no pinch. If false (build view), the usual
## one-finger drag / two-finger pinch rules apply.
var independent_drags: bool = false:
	set(value):
		if value != independent_drags:
			_end_all_gestures()
		independent_drags = value

## Current tap slop in UI pixels (see TAP_SLOP_POINTS); updated when the window size changes.
var tap_slop: float = MIN_TAP_SLOP

var _state: State = State.IDLE
var _primary_index: int = -1
var _pinch_indices: Array[int] = []
var _pinch_distance: float = 0.0
var _pinch_center: Vector2 = Vector2.ZERO
# Per finger (keyed by touch index): current position, start position, start time, moved too far for a tap.
var _positions: Dictionary[int, Vector2] = {}
var _start_positions: Dictionary[int, Vector2] = {}
var _start_times: Dictionary[int, float] = {}
var _moved: Dictionary[int, bool] = {}
# independent_drags: the fingers that are dragging.
var _finger_dragging: Dictionary[int, bool] = {}


func _ready() -> void:
	get_viewport().size_changed.connect(_update_tap_slop)
	_update_tap_slop()


# Converts the slop from screen points to UI pixels for this device.
func _update_tap_slop() -> void:
	var window_pixels_per_ui_pixel := get_viewport().get_screen_transform().get_scale().x
	# No real window (headless tests): use the minimum, so tests behave the same everywhere.
	if DisplayServer.window_get_size() == Vector2i.ZERO or window_pixels_per_ui_pixel <= 0.0:
		tap_slop = MIN_TAP_SLOP
		return
	var window_pixels := TAP_SLOP_POINTS * DisplayServer.screen_get_scale()
	tap_slop = clampf(window_pixels / window_pixels_per_ui_pixel, MIN_TAP_SLOP, MAX_TAP_SLOP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_finger_down(touch.index, touch.position)
		else:
			_on_finger_up(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_finger_moved(drag.index, drag.position)
	elif event is InputEventMouseButton and event.is_pressed():
		# Mac only: mouse wheel zooms.
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			pinched.emit(WHEEL_ZOOM_STEP)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			pinched.emit(1.0 / WHEEL_ZOOM_STEP)
	elif event is InputEventMagnifyGesture:
		# Mac only: trackpad pinch.
		pinched.emit((event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		# Mac only: two-finger trackpad scroll behaves like the mouse wheel.
		pinched.emit(exp(-(event as InputEventPanGesture).delta.y * TRACKPAD_SCROLL_ZOOM_SPEED))


func _notification(what: int) -> void:
	# Forget all fingers if the app goes to the background mid-gesture (e.g. a phone call).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_all_gestures()


# Ends whatever is going on (app in the background, or the view changed mid-gesture).
func _end_all_gestures() -> void:
	if _state == State.DRAGGING:
		drag_cancelled.emit()
	for index in _finger_dragging.keys():
		finger_drag_ended.emit(index, _positions.get(index, Vector2.ZERO))
	_reset()


func _on_finger_down(index: int, position: Vector2) -> void:
	_positions[index] = position
	_start_positions[index] = position
	_start_times[index] = _now()
	_moved[index] = false
	if independent_drags:
		return

	match _state:
		State.IDLE:
			_state = State.PENDING
			_primary_index = index
		State.PENDING:
			# Two fingers landed before the first one moved: that's a pinch.
			_start_pinch(_primary_index, index)
		State.DRAGGING:
			if pinch_cancels_drag:
				drag_cancelled.emit()
				_start_pinch(_primary_index, index)


func _on_finger_moved(index: int, position: Vector2) -> void:
	if not _positions.has(index):
		return
	var relative := position - _positions[index]
	_positions[index] = position
	if position.distance_to(_start_positions[index]) > tap_slop:
		_moved[index] = true
	if independent_drags:
		if _finger_dragging.has(index):
			finger_dragged.emit(index, position, relative)
		elif _moved[index]:
			_finger_dragging[index] = true
			finger_drag_started.emit(index, _start_positions[index], position)
			finger_dragged.emit(index, position, position - _start_positions[index])
		return

	match _state:
		State.PENDING:
			if index == _primary_index and _moved[index]:
				_state = State.DRAGGING
				drag_started.emit(_start_positions[index], position)
				dragged.emit(position, position - _start_positions[index])
		State.DRAGGING:
			if index == _primary_index:
				dragged.emit(position, relative)
		State.PINCHING:
			if index in _pinch_indices:
				var first := _positions[_pinch_indices[0]]
				var second := _positions[_pinch_indices[1]]
				var distance := first.distance_to(second)
				if _pinch_distance > 0.0 and distance > 0.0:
					pinched.emit(distance / _pinch_distance)
				_pinch_distance = distance
				var center := (first + second) * 0.5
				pinch_moved.emit(center - _pinch_center)
				_pinch_center = center


func _on_finger_up(index: int, position: Vector2) -> void:
	if not _positions.has(index):
		return
	var was_tap: bool = (
		not _moved[index]
		and not index in _pinch_indices
		and _now() - _start_times[index] <= TAP_MAX_DURATION
	)
	if independent_drags:
		if _finger_dragging.has(index):
			_finger_dragging.erase(index)
			finger_drag_ended.emit(index, position)
		_positions.erase(index)
		_start_positions.erase(index)
		_start_times.erase(index)
		_moved.erase(index)
		if was_tap:
			tapped.emit(position)
		return

	match _state:
		State.DRAGGING:
			if index == _primary_index:
				drag_ended.emit(position)
				_state = State.WAITING
		State.PINCHING:
			if index in _pinch_indices:
				_state = State.WAITING

	_positions.erase(index)
	_start_positions.erase(index)
	_start_times.erase(index)
	_moved.erase(index)
	if was_tap:
		tapped.emit(position)
	if _positions.is_empty():
		_reset()
	elif _state == State.PENDING and index == _primary_index:
		_state = State.WAITING


func _start_pinch(first: int, second: int) -> void:
	_state = State.PINCHING
	_pinch_indices = [first, second]
	_pinch_distance = _positions[first].distance_to(_positions[second])
	_pinch_center = (_positions[first] + _positions[second]) * 0.5


func _reset() -> void:
	_state = State.IDLE
	_primary_index = -1
	_pinch_indices.clear()
	_pinch_distance = 0.0
	_positions.clear()
	_start_positions.clear()
	_start_times.clear()
	_moved.clear()
	_finger_dragging.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
