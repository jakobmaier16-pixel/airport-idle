class_name Hud
extends CanvasLayer
## On-screen UI for both views. Everything sits inside the SafeArea container.
## The HUD only shows state and reports button presses; main.gd connects it to the game.

signal view_toggle_pressed
signal building_type_selected(type: BuildingType)
signal paint_tool_selected(kind: BuildMode.PaintKind)
signal rotate_pressed
signal place_pressed
signal cancel_pressed
signal done_pressed
## The player confirmed resetting the map (test builds only).
signal reset_confirmed
## The player confirmed loading the showcase airport (test builds only).
signal showcase_confirmed

## Smallest size for touch buttons, in UI pixels (Apple recommends at least 44 pt).
const BUTTON_MIN_SIZE: Vector2 = Vector2(120, 72)
## How long Reset / Demo wait for the confirming second tap.
const CONFIRM_TIME: float = 3.0

var _build_view_open: bool = false
var _tool: BuildMode.Tool = BuildMode.Tool.NONE

@onready var joystick: TouchJoystick = $SafeArea/TouchJoystick
@onready var _view_button: Button = $SafeArea/ViewButton
@onready var _build_menu: Control = $SafeArea/BuildMenu
@onready var _building_buttons: HBoxContainer = $SafeArea/BuildMenu/BuildingButtons
@onready var _tool_panel: Control = $SafeArea/ToolPanel
@onready var _hint_label: Label = $SafeArea/ToolPanel/HintLabel
@onready var _rotate_button: Button = $SafeArea/ToolPanel/ToolBar/RotateButton
@onready var _cancel_button: Button = $SafeArea/ToolPanel/ToolBar/CancelButton
@onready var _place_button: Button = $SafeArea/ToolPanel/ToolBar/PlaceButton
@onready var _done_button: Button = $SafeArea/ToolPanel/ToolBar/DoneButton
@onready var _build_label: Label = $SafeArea/BuildLabel
@onready var _status_label: Label = $SafeArea/StatusLabel
@onready var _reset_button: Button = $SafeArea/BuildMenu/PaintButtons/ResetButton
@onready var _demo_button: Button = $SafeArea/BuildMenu/PaintButtons/DemoButton


func _ready() -> void:
	_view_button.pressed.connect(view_toggle_pressed.emit)
	var paint_buttons := {
		^"SafeArea/BuildMenu/PaintButtons/AirsideButton": BuildMode.PaintKind.AIRSIDE,
		^"SafeArea/BuildMenu/PaintButtons/LandsideButton": BuildMode.PaintKind.LANDSIDE,
		^"SafeArea/BuildMenu/PaintButtons/WalkwayButton": BuildMode.PaintKind.WALKWAY,
		^"SafeArea/BuildMenu/PaintButtons/RemoveButton": BuildMode.PaintKind.REMOVE_WALKWAY,
	}
	for path: NodePath in paint_buttons:
		(get_node(path) as Button).pressed.connect(paint_tool_selected.emit.bind(paint_buttons[path]))
	_rotate_button.pressed.connect(rotate_pressed.emit)
	_cancel_button.pressed.connect(cancel_pressed.emit)
	_place_button.pressed.connect(place_pressed.emit)
	_done_button.pressed.connect(done_pressed.emit)
	# Reset and Demo are testing aids, so they only exist in debug builds (including device test builds).
	_reset_button.visible = OS.is_debug_build()
	_demo_button.visible = OS.is_debug_build()
	_reset_button.pressed.connect(_on_confirm_button_pressed.bind(_reset_button, "Reset", reset_confirmed))
	_demo_button.pressed.connect(_on_confirm_button_pressed.bind(_demo_button, "Demo", showcase_confirmed))
	_update_visibility()
	_show_build_info()


## Creates one build menu button per building type.
func setup_build_menu(types: Array[BuildingType]) -> void:
	for child in _building_buttons.get_children():
		child.queue_free()
	for type in types:
		var button := Button.new()
		button.text = type.display_name
		button.custom_minimum_size = BUTTON_MIN_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(building_type_selected.emit.bind(type))
		_building_buttons.add_child(button)


## Passenger status line in the top left (both views).
func set_status(text: String) -> void:
	_status_label.text = text


func set_view_button_text(text: String) -> void:
	_view_button.text = text


func set_build_view_open(open: bool) -> void:
	_build_view_open = open
	_update_visibility()


func set_tool_state(tool: BuildMode.Tool, can_confirm: bool, hint: String) -> void:
	_tool = tool
	_place_button.disabled = not can_confirm
	_hint_label.text = hint
	_update_visibility()


func _update_visibility() -> void:
	var placing := _tool == BuildMode.Tool.PLACE
	var painting := _tool == BuildMode.Tool.PAINT
	_build_menu.visible = _build_view_open and _tool == BuildMode.Tool.NONE
	_tool_panel.visible = _build_view_open and _tool != BuildMode.Tool.NONE
	_rotate_button.visible = placing
	_cancel_button.visible = placing
	_place_button.visible = placing
	_done_button.visible = painting


# For buttons that replace the map: the first tap arms the button, a second tap within a few
# seconds confirms. No dialog needed.
func _on_confirm_button_pressed(button: Button, label: String, confirmed: Signal) -> void:
	if button.text == label:
		button.text = "Tap again"
		# A connection to a method (unlike await) is dropped automatically if the HUD is freed meanwhile.
		get_tree().create_timer(CONFIRM_TIME).timeout.connect(_disarm.bind(button, label))
	else:
		confirmed.emit()


func _disarm(button: Button, label: String) -> void:
	button.text = label


# Shows which export is running, so a stale build on the device is easy to spot.
func _show_build_info() -> void:
	_build_label.text = "build " + BuildStamp.text()
