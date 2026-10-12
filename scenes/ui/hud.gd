class_name Hud
extends CanvasLayer
## On-screen UI for both views. Everything sits inside the SafeArea container.
## The HUD only shows state and reports button presses; main.gd connects it to the game.

signal view_toggle_pressed
signal building_type_selected(type: BuildingType)
signal zone_tool_selected(zone: AirportGrid.Zone)
signal rotate_pressed
signal place_pressed
signal cancel_pressed
signal done_pressed
## The player confirmed resetting the map (test builds only).
signal reset_confirmed

## Smallest size for touch buttons, in UI pixels (Apple recommends at least 44 pt).
const BUTTON_MIN_SIZE: Vector2 = Vector2(120, 72)
## Written by tools/export_ios.sh; missing when running from the editor.
const BUILD_INFO_PATH: String = "res://build_info.gd"
## How long the Reset button waits for the confirming second tap.
const RESET_CONFIRM_TIME: float = 3.0

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
@onready var _reset_button: Button = $SafeArea/BuildMenu/ZoneButtons/ResetButton


func _ready() -> void:
	_view_button.pressed.connect(view_toggle_pressed.emit)
	$SafeArea/BuildMenu/ZoneButtons/AirsideButton.pressed.connect(
		zone_tool_selected.emit.bind(AirportGrid.Zone.AIRSIDE))
	$SafeArea/BuildMenu/ZoneButtons/LandsideButton.pressed.connect(
		zone_tool_selected.emit.bind(AirportGrid.Zone.LANDSIDE))
	_rotate_button.pressed.connect(rotate_pressed.emit)
	_cancel_button.pressed.connect(cancel_pressed.emit)
	_place_button.pressed.connect(place_pressed.emit)
	_done_button.pressed.connect(done_pressed.emit)
	# Resetting is a testing aid, so it only exists in debug builds (including device test builds).
	_reset_button.visible = OS.is_debug_build()
	_reset_button.pressed.connect(_on_reset_pressed)
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


# First tap arms the button, a second tap within a few seconds resets. No dialog needed.
func _on_reset_pressed() -> void:
	if _reset_button.text == "Reset":
		_reset_button.text = "Tap again"
		# A signal connection (unlike await) is dropped automatically if the HUD is freed meanwhile.
		get_tree().create_timer(RESET_CONFIRM_TIME).timeout.connect(_disarm_reset)
	else:
		reset_confirmed.emit()


func _disarm_reset() -> void:
	_reset_button.text = "Reset"


# Shows which export is running, so a stale build on the device is easy to spot.
func _show_build_info() -> void:
	var text := "dev"
	if ResourceLoader.exists(BUILD_INFO_PATH):
		var info := load(BUILD_INFO_PATH) as GDScript
		text = info.get_script_constant_map().get("TEXT", text)
	_build_label.text = "build " + text
