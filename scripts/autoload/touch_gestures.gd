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
## Also emitted when a drag is cancelled because it turned into a pinch.
signal drag_ended(position: Vector2)
## A short touch without movement (any finger that is not part of a pinch).
signal tapped(position: Vector2)
## Zoom gesture. factor > 1 means "zoom in" (fingers moved apart, wheel up, trackpad spread).
signal pinched(factor: float)

enum State {
	IDLE, ## No finger down.
	PENDING, ## One finger down, not moved yet: could still become a drag, a tap or a pinch.
	DRAGGING, ## One finger is dragging.
	PINCHING, ## Two fingers are pinching.
	WAITING, ## A pinch ended; ignore everything until all fingers are lifted.
}

## How far (in UI pixels) a finger must move before it counts as a drag instead of a tap.
const DRAG_THRESHOLD: float = 10.0
## Longest press that still counts as a tap, in seconds.
const TAP_MAX_DURATION: float = 0.4
const WHEEL_ZOOM_STEP: float = 1.1
const TRACKPAD_SCROLL_ZOOM_SPEED: float = 0.05

## If true, a second finger during a drag cancels the drag and starts a pinch (build view).
## If false, an active drag is never interrupted (manager view: the joystick keeps working
## while the other thumb taps the right half of the screen).
var pinch_cancels_drag: bool = false

var _state: State = State.IDLE
var _primary_index: int = -1
var _pinch_indices: Array[int] = []
var _pinch_distance: float = 0.0
# Per finger (keyed by touch index): current position, start position, start time, moved too far for a tap.
var _positions: Dictionary[int, Vector2] = {}
var _start_positions: Dictionary[int, Vector2] = {}
var _start_times: Dictionary[int, float] = {}
var _moved: Dictionary[int, bool] = {}


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
		if _state == State.DRAGGING:
			drag_ended.emit(_positions.get(_primary_index, Vector2.ZERO))
		_reset()


func _on_finger_down(index: int, position: Vector2) -> void:
	_positions[index] = position
	_start_positions[index] = position
	_start_times[index] = _now()
	_moved[index] = false

	match _state:
		State.IDLE:
			_state = State.PENDING
			_primary_index = index
		State.PENDING:
			# Two fingers landed before the first one moved: that's a pinch.
			_start_pinch(_primary_index, index)
		State.DRAGGING:
			if pinch_cancels_drag:
				drag_ended.emit(_positions[_primary_index])
				_start_pinch(_primary_index, index)


func _on_finger_moved(index: int, position: Vector2) -> void:
	if not _positions.has(index):
		return
	var relative := position - _positions[index]
	_positions[index] = position
	if position.distance_to(_start_positions[index]) > DRAG_THRESHOLD:
		_moved[index] = true

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
				var distance := _positions[_pinch_indices[0]].distance_to(_positions[_pinch_indices[1]])
				if _pinch_distance > 0.0 and distance > 0.0:
					pinched.emit(distance / _pinch_distance)
				_pinch_distance = distance


func _on_finger_up(index: int, position: Vector2) -> void:
	if not _positions.has(index):
		return
	var was_tap: bool = (
		not _moved[index]
		and not index in _pinch_indices
		and _now() - _start_times[index] <= TAP_MAX_DURATION
	)

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


func _reset() -> void:
	_state = State.IDLE
	_primary_index = -1
	_pinch_indices.clear()
	_pinch_distance = 0.0
	_positions.clear()
	_start_positions.clear()
	_start_times.clear()
	_moved.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
