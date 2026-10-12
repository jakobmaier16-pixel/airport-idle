class_name Hud
extends CanvasLayer
## On-screen UI for both views. Everything sits inside the SafeArea container.
## The HUD only shows state and reports button presses; main.gd connects it to the game.

signal view_toggle_pressed
signal building_type_selected(type: BuildingType)
signal rotate_pressed
signal place_pressed
signal cancel_pressed

## Smallest size for touch buttons, in UI pixels (Apple recommends at least 44 pt).
const BUTTON_MIN_SIZE: Vector2 = Vector2(160, 72)
## Written by tools/export_ios.sh; missing when running from the editor.
const BUILD_INFO_PATH: String = "res://build_info.gd"

var _build_view_open: bool = false
var _is_placing: bool = false

@onready var joystick: TouchJoystick = $SafeArea/TouchJoystick
@onready var _view_button: Button = $SafeArea/ViewButton
@onready var _build_menu: HBoxContainer = $SafeArea/BuildMenu
@onready var _placement_bar: HBoxContainer = $SafeArea/PlacementBar
@onready var _place_button: Button = $SafeArea/PlacementBar/PlaceButton
@onready var _build_label: Label = $SafeArea/BuildLabel


func _ready() -> void:
	_view_button.pressed.connect(view_toggle_pressed.emit)
	$SafeArea/PlacementBar/RotateButton.pressed.connect(rotate_pressed.emit)
	_place_button.pressed.connect(place_pressed.emit)
	$SafeArea/PlacementBar/CancelButton.pressed.connect(cancel_pressed.emit)
	_update_visibility()
	_show_build_info()


## Creates one build menu button per building type.
func setup_build_menu(types: Array[BuildingType]) -> void:
	for child in _build_menu.get_children():
		child.queue_free()
	for type in types:
		var button := Button.new()
		button.text = type.display_name
		button.custom_minimum_size = BUTTON_MIN_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(building_type_selected.emit.bind(type))
		_build_menu.add_child(button)


func set_view_button_text(text: String) -> void:
	_view_button.text = text


func set_build_view_open(open: bool) -> void:
	_build_view_open = open
	_update_visibility()


func set_placement_state(is_placing: bool, can_place: bool) -> void:
	_is_placing = is_placing
	_place_button.disabled = not can_place
	_update_visibility()


func _update_visibility() -> void:
	_build_menu.visible = _build_view_open and not _is_placing
	_placement_bar.visible = _build_view_open and _is_placing


# Shows which export is running, so a stale build on the device is easy to spot.
func _show_build_info() -> void:
	var text := "dev"
	if ResourceLoader.exists(BUILD_INFO_PATH):
		var info := load(BUILD_INFO_PATH) as GDScript
		text = info.get_script_constant_map().get("TEXT", text)
	_build_label.text = "build " + text
