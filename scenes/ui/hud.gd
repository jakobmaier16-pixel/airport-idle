class_name Hud
extends CanvasLayer
## On-screen UI for both views. Everything sits inside the SafeArea container.
## The HUD only shows state and reports button presses; main.gd connects it to the game.

signal view_toggle_pressed
## The build menu's Zones toggle: show the zone colours over the ground (build view only).
signal zone_overlay_toggled(enabled: bool)
signal building_type_selected(type: BuildingType)
signal paint_tool_selected(kind: BuildMode.PaintKind)
signal rotate_pressed
signal place_pressed
signal cancel_pressed
signal done_pressed
signal demolish_tool_selected
signal demolish_pressed
## The player confirmed resetting the map (test builds only).
signal reset_confirmed
## The player confirmed loading the showcase airport (test builds only).
signal showcase_confirmed
## The player confirmed starting the device benchmark (test builds only, scripts/dev/benchmark.gd).
signal benchmark_confirmed

## How long a notice stays on screen, in seconds.
const NOTICE_SECONDS: float = 10.0

## Smallest size for touch buttons, in UI pixels (Apple recommends at least 44 pt).
const BUTTON_MIN_SIZE: Vector2 = Vector2(120, 72)
## How long Reset / Demo wait for the confirming second tap.
const CONFIRM_TIME: float = 3.0
## Colours of the hint line while placing: info (allowed, something is missing) and error.
const HINT_INFO_COLOR: Color = Color(0.6, 0.82, 1.0)
const HINT_ERROR_COLOR: Color = Color(1.0, 0.6, 0.55)

var _build_view_open: bool = false
# Build menu: every building type, and the category whose buildings are shown ("" = categories).
var _building_types: Array[BuildingType] = []
var _open_category: String = ""
## The building shown in the station panel, or null.
var shown_station: Building = null
# Area name of the shown station: looked up on opening and when the layout changes, not per frame.
var _station_area: String = ""
var _tool: BuildMode.Tool = BuildMode.Tool.NONE
var _notice_left: float = 0.0

@onready var joystick: TouchJoystick = $SafeArea/TouchJoystick
@onready var _view_button: Button = $SafeArea/TopButtons/ViewButton
@onready var _clock_label: Label = $SafeArea/TopButtons/ClockLabel
@onready var _build_menu: Control = $SafeArea/BuildMenu
@onready var _building_buttons: HBoxContainer = $SafeArea/BuildMenu/BuildingButtons
@onready var _tool_panel: Control = $SafeArea/ToolPanel
@onready var _hint_label: Label = $SafeArea/ToolPanel/HintLabel
@onready var _rotate_button: Button = $SafeArea/ToolPanel/ToolBar/RotateButton
@onready var _cancel_button: Button = $SafeArea/ToolPanel/ToolBar/CancelButton
@onready var _place_button: Button = $SafeArea/ToolPanel/ToolBar/PlaceButton
@onready var _done_button: Button = $SafeArea/ToolPanel/ToolBar/DoneButton
@onready var _demolish_button: Button = $SafeArea/ToolPanel/ToolBar/DemolishButton
@onready var _build_label: Label = $SafeArea/BuildLabel
@onready var _notice_panel: Control = $SafeArea/NoticeBox/NoticePanel
@onready var _notice_label: Label = $SafeArea/NoticeBox/NoticePanel/NoticeLabel
@onready var _status_label: Label = $SafeArea/InfoPanel/StatusLabel
@onready var _departures_label: Label = $SafeArea/InfoPanel/DeparturesLabel
@onready var _reset_button: Button = $SafeArea/BuildMenu/PaintButtons/ResetButton
@onready var _demo_button: Button = $SafeArea/BuildMenu/PaintButtons/DemoButton
@onready var _bench_button: Button = $SafeArea/BuildMenu/PaintButtons/BenchButton
@onready var _station_panel: Control = $SafeArea/StationPanel
@onready var _station_title: Label = $SafeArea/StationPanel/Content/TitleLabel
@onready var _station_info: Label = $SafeArea/StationPanel/Content/InfoLabel


func _ready() -> void:
	Airport.zones_changed.connect(_refresh_station_area)
	_view_button.pressed.connect(view_toggle_pressed.emit)
	var paint_buttons := {
		^"SafeArea/BuildMenu/PaintButtons/WalkwayButton": BuildMode.PaintKind.WALKWAY,
		^"SafeArea/BuildMenu/PaintButtons/RemoveButton": BuildMode.PaintKind.REMOVE_WALKWAY,
		^"SafeArea/BuildMenu/PaintButtons/TaxiwayButton": BuildMode.PaintKind.TAXIWAY,
	}
	for path: NodePath in paint_buttons:
		(get_node(path) as Button).pressed.connect(paint_tool_selected.emit.bind(paint_buttons[path]))
	$SafeArea/BuildMenu/PaintButtons/ZonesButton.toggled.connect(zone_overlay_toggled.emit)
	_rotate_button.pressed.connect(rotate_pressed.emit)
	_cancel_button.pressed.connect(cancel_pressed.emit)
	_place_button.pressed.connect(place_pressed.emit)
	_done_button.pressed.connect(done_pressed.emit)
	_demolish_button.pressed.connect(demolish_pressed.emit)
	$SafeArea/BuildMenu/PaintButtons/DemolishToolButton.pressed.connect(demolish_tool_selected.emit)
	# Reset and Demo are testing aids, so they only exist in debug builds (including device test builds).
	_reset_button.visible = OS.is_debug_build()
	_demo_button.visible = OS.is_debug_build()
	_bench_button.visible = OS.is_debug_build()
	_reset_button.pressed.connect(_on_confirm_button_pressed.bind(_reset_button, "Reset", reset_confirmed))
	_demo_button.pressed.connect(_on_confirm_button_pressed.bind(_demo_button, "Demo", showcase_confirmed))
	_bench_button.pressed.connect(_on_confirm_button_pressed.bind(_bench_button, "Bench", benchmark_confirmed))
	$SafeArea/StationPanel/Content/CloseButton.pressed.connect(hide_station)
	_update_visibility()
	_show_build_info()


func _process(delta: float) -> void:
	_clock_label.text = Airport.clock.text()
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice_panel.visible = false
	if shown_station != null:
		_update_station_panel()


## Test builds: shows what a tap did at the bottom of the screen (see TapFeedback).
func report_tap(text: String) -> void:
	var feedback := get_node_or_null(^"TapFeedback") as TapFeedback
	if feedback != null and not feedback.is_queued_for_deletion():
		feedback.report(text)


## Opens the panel for `building` (manager view): its name, its area and a close button.
func show_station(building: Building) -> void:
	shown_station = building
	_refresh_station_area()
	_station_panel.visible = true
	_update_station_panel()


func hide_station() -> void:
	shown_station = null
	_station_panel.visible = false


## Fills the build menu: a row of categories; tapping one shows its buildings.
func setup_build_menu(types: Array[BuildingType]) -> void:
	_building_types = types
	show_build_category("")


## Shows the buildings of `category`, or the category buttons for "". A category with sub-categories
## (landside pieces: Roads, Curb, ...) shows them first; `sub_category` then lists one of them.
func show_build_category(category: String, sub_category: String = "") -> void:
	_open_category = category
	for child in _building_buttons.get_children():
		_building_buttons.remove_child(child)
		child.queue_free()
	if category.is_empty():
		var categories: PackedStringArray = []
		for type in _building_types:
			if not categories.has(type.category):
				categories.append(type.category)
		for category_name in categories:
			_add_menu_button(category_name + " ›", show_build_category.bind(category_name))
		return
	# One step back: from a sub-category to its category, from a category to the list of categories.
	_add_menu_button("‹", show_build_category.bind(category if not sub_category.is_empty() else ""))
	var subs: PackedStringArray = []
	for type in _building_types:
		if type.category == category and not type.sub_category.is_empty() and not subs.has(type.sub_category):
			subs.append(type.sub_category)
	if sub_category.is_empty():
		for sub_name in subs:
			_add_menu_button(sub_name + " ›", show_build_category.bind(category, sub_name))
	for type in _building_types:
		if type.category == category and type.sub_category == sub_category:
			_add_menu_button(type.display_name, building_type_selected.emit.bind(type))


func _add_menu_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_MIN_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	_building_buttons.add_child(button)


## Shows a message at the top of the screen for a few seconds.
func notify(text: String) -> void:
	_notice_label.text = text
	_notice_panel.visible = true
	_notice_left = NOTICE_SECONDS


func notice_text() -> String:
	return _notice_label.text if _notice_panel.visible else ""


## Status line in the top left (both views).
func set_status(text: String) -> void:
	_status_label.text = text


## Departures board below the status line, one flight per line.
func set_departures(text: String) -> void:
	_departures_label.text = text


func set_view_button_text(text: String) -> void:
	_view_button.text = text


func set_build_view_open(open: bool) -> void:
	_build_view_open = open
	if not open and not _open_category.is_empty():
		show_build_category("")
	_update_visibility()


func set_tool_state(tool: BuildMode.Tool, can_confirm: bool, hint: String) -> void:
	_tool = tool
	_place_button.disabled = not can_confirm
	_demolish_button.disabled = not can_confirm
	_hint_label.text = hint
	# Red-ish: not allowed. Blue-ish: allowed, but the building still needs something (info).
	if tool == BuildMode.Tool.PLACE and can_confirm and hint != BuildMode.DRAG_HINT:
		_hint_label.add_theme_color_override(&"font_color", HINT_INFO_COLOR)
	elif tool == BuildMode.Tool.PLACE and not can_confirm:
		_hint_label.add_theme_color_override(&"font_color", HINT_ERROR_COLOR)
	else:
		_hint_label.remove_theme_color_override(&"font_color")
	_update_visibility()


func _update_visibility() -> void:
	var placing := _tool == BuildMode.Tool.PLACE
	var demolishing := _tool == BuildMode.Tool.DEMOLISH
	var painting := _tool == BuildMode.Tool.PAINT or demolishing
	_build_menu.visible = _build_view_open and _tool == BuildMode.Tool.NONE
	_tool_panel.visible = _build_view_open and _tool != BuildMode.Tool.NONE
	_rotate_button.visible = placing
	_cancel_button.visible = placing
	_place_button.visible = placing
	_done_button.visible = painting
	_demolish_button.visible = demolishing


func _refresh_station_area() -> void:
	_station_area = "" if shown_station == null else _area_of_building(shown_station)


# A building stands next to the area its walkway belongs to: the first side that has one.
func _area_of_building(building: Building) -> String:
	for front: bool in [true, false]:
		for cell in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, front):
			var name := Airport.area_name(cell)
			if not name.is_empty():
				return name
	return ""


func _update_station_panel() -> void:
	var building := shown_station
	_station_title.text = building.type.display_name
	var lines: PackedStringArray = ["Zone: %s" % _zone_text(building)]
	if not _station_area.is_empty():
		lines.append("Area: %s" % _station_area)
	_station_info.text = "\n".join(lines)


# Landside or airside, or both for security (the border between them).
func _zone_text(building: Building) -> String:
	if building.type.zone_rule == BuildingType.ZoneRule.BORDER:
		return "Border (landside to airside)"
	return "Airside" if Airport.grid.get_zone(building.origin_cell) == AirportGrid.Zone.AIRSIDE else "Landside"


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
