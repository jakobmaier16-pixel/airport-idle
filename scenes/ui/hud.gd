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
signal upgrade_pressed(building: Building)

const MONEY_COLOR: Color = Color(1.0, 1.0, 1.0)
const DEBT_COLOR: Color = Color(1.0, 0.4, 0.35)

const STATS_FONT_SIZE: int = 22
const BOTTLENECK_COLOR: Color = Color(1.0, 0.7, 0.3)
## How often the statistics panel refreshes, in seconds.
const STATS_REFRESH: float = 0.5

## Smallest size for touch buttons, in UI pixels (Apple recommends at least 44 pt).
const BUTTON_MIN_SIZE: Vector2 = Vector2(120, 72)
## How long Reset / Demo wait for the confirming second tap.
const CONFIRM_TIME: float = 3.0

var _build_view_open: bool = false
# Build menu: every building type, and the category whose buildings are shown ("" = categories).
var _building_types: Array[BuildingType] = []
var _open_category: String = ""
var _stats_refresh_in: float = 0.0
## The building shown in the station panel, or null.
var shown_station: Building = null
var _tool: BuildMode.Tool = BuildMode.Tool.NONE

@onready var joystick: TouchJoystick = $SafeArea/TouchJoystick
@onready var _view_button: Button = $SafeArea/TopButtons/ViewButton
@onready var _stats_button: Button = $SafeArea/TopButtons/StatsButton
@onready var _stats_panel: Control = $SafeArea/StatsPanel
@onready var _stats_table: GridContainer = $SafeArea/StatsPanel/Content/Table
@onready var _bottleneck_label: Label = $SafeArea/StatsPanel/Content/BottleneckLabel
@onready var _types_label: Label = $SafeArea/StatsPanel/Content/TypesLabel
@onready var _build_menu: Control = $SafeArea/BuildMenu
@onready var _building_buttons: HBoxContainer = $SafeArea/BuildMenu/BuildingButtons
@onready var _tool_panel: Control = $SafeArea/ToolPanel
@onready var _hint_label: Label = $SafeArea/ToolPanel/HintLabel
@onready var _rotate_button: Button = $SafeArea/ToolPanel/ToolBar/RotateButton
@onready var _cancel_button: Button = $SafeArea/ToolPanel/ToolBar/CancelButton
@onready var _place_button: Button = $SafeArea/ToolPanel/ToolBar/PlaceButton
@onready var _done_button: Button = $SafeArea/ToolPanel/ToolBar/DoneButton
@onready var _build_label: Label = $SafeArea/BuildLabel
@onready var _money_label: Label = $SafeArea/InfoPanel/MoneyLabel
@onready var _status_label: Label = $SafeArea/InfoPanel/StatusLabel
@onready var _departures_label: Label = $SafeArea/InfoPanel/DeparturesLabel
@onready var _reset_button: Button = $SafeArea/BuildMenu/PaintButtons/ResetButton
@onready var _demo_button: Button = $SafeArea/BuildMenu/PaintButtons/DemoButton
@onready var _station_panel: Control = $SafeArea/StationPanel
@onready var _station_title: Label = $SafeArea/StationPanel/Content/TitleLabel
@onready var _station_info: Label = $SafeArea/StationPanel/Content/InfoLabel
@onready var _upgrade_button: Button = $SafeArea/StationPanel/Content/UpgradeButton


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
	_upgrade_button.pressed.connect(func() -> void: upgrade_pressed.emit(shown_station))
	$SafeArea/StationPanel/Content/CloseButton.pressed.connect(hide_station)
	_stats_button.pressed.connect(func() -> void: hide_stats() if _stats_panel.visible else show_stats())
	$SafeArea/StatsPanel/Content/CloseButton.pressed.connect(hide_stats)
	_update_visibility()
	_show_build_info()


func _process(delta: float) -> void:
	if shown_station != null:
		_update_station_panel()
	if _stats_panel.visible:
		_stats_refresh_in -= delta
		if _stats_refresh_in <= 0.0:
			_stats_refresh_in = STATS_REFRESH
			_update_stats_panel()


## Opens the statistics panel (manager view, design doc §13.1).
func show_stats() -> void:
	hide_station()
	_stats_panel.visible = true
	_update_stats_panel()


func hide_stats() -> void:
	_stats_panel.visible = false


func is_stats_open() -> bool:
	return _stats_panel.visible


## Test builds: shows what a tap did at the bottom of the screen (see TapFeedback).
func report_tap(text: String) -> void:
	var feedback := get_node_or_null(^"TapFeedback") as TapFeedback
	if feedback != null and not feedback.is_queued_for_deletion():
		feedback.report(text)


## Opens the station panel for `building` (manager view, design doc §7.8).
func show_station(building: Building) -> void:
	hide_stats()
	shown_station = building
	_station_panel.visible = true
	_update_station_panel()


func hide_station() -> void:
	shown_station = null
	_station_panel.visible = false


## Fills the build menu: a row of categories; tapping one shows its buildings.
func setup_build_menu(types: Array[BuildingType]) -> void:
	_building_types = types
	show_build_category("")


## Shows the buildings of `category`, or the category buttons for "".
func show_build_category(category: String) -> void:
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
	_add_menu_button("‹", show_build_category.bind(""))
	for type in _building_types:
		if type.category == category:
			_add_menu_button(type.display_name, building_type_selected.emit.bind(type))


func _add_menu_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_MIN_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	_building_buttons.add_child(button)


## Balance and profit over the last minute, top left. Red while the balance is negative.
func set_money(balance: float, profit_per_minute: float) -> void:
	var plus := "+" if roundi(profit_per_minute) >= 0 else ""
	_money_label.text = "%s   %s%s/min" % [Economy.format(balance), plus, Economy.format(profit_per_minute)]
	_money_label.modulate = DEBT_COLOR if balance < 0.0 else MONEY_COLOR


## Passenger status line in the top left (both views).
func set_status(text: String) -> void:
	_status_label.text = text


## Departures board below the status line, one flight per line.
func set_departures(text: String) -> void:
	_departures_label.text = text


func set_view_button_text(text: String) -> void:
	_view_button.text = text


func set_build_view_open(open: bool) -> void:
	_build_view_open = open
	if open:
		hide_stats()
	elif not _open_category.is_empty():
		show_build_category("")
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
	_stats_button.visible = not _build_view_open


func _update_stats_panel() -> void:
	var flow := Airport.passenger_flow
	var bottleneck := flow.bottleneck()
	for child in _stats_table.get_children():
		child.queue_free()
	for heading in ["Station", "Queue now", "Longest", "Avg. wait", "Busy"]:
		_add_stats_cell(heading, Color(0.75, 0.78, 0.82))
	for station in flow.stations():
		var color := BOTTLENECK_COLOR if station == bottleneck else Color.WHITE
		_add_stats_cell(flow.station_label(station.building), color)
		if station.role() == BuildingType.Role.GATE:
			_add_stats_cell("%d waiting" % station.queue_length(), color)
			for i in 3:
				_add_stats_cell("", color)
			continue
		if station.role() == BuildingType.Role.BAGGAGE_CLAIM:
			var claim_wait := station.average_wait(flow.time)
			_add_stats_cell("%d waiting" % station.queue_length(), color)
			_add_stats_cell(str(station.longest_queue()), color)
			_add_stats_cell("–" if claim_wait < 0.0 else "%d s" % roundi(claim_wait), color)
			_add_stats_cell("", color)
			continue
		if station.role() == BuildingType.Role.SHOP:
			_add_stats_cell("%d inside" % station.queue_length(), color)
			_add_stats_cell(str(station.longest_queue()), color)
			_add_stats_cell("", color)
			_add_stats_cell(Economy.format(station.income_in_window(flow.time)), color)
			continue
		var wait := station.average_wait(flow.time)
		_add_stats_cell(str(station.queue_length()), color)
		_add_stats_cell(str(station.longest_queue()), color)
		_add_stats_cell("–" if wait < 0.0 else "%d s" % roundi(wait), color)
		_add_stats_cell("%d %%" % roundi(station.busy_share() * 100.0), color)
	var counts := flow.count_by_type()
	var parts: PackedStringArray = []
	for type_name in ["Families", "Low-cost", "Business"]:
		parts.append("%d %s" % [counts.get(type_name, 0), type_name])
	_types_label.text = "In the airport: " + "  ·  ".join(parts)
	if bottleneck != null:
		_bottleneck_label.text = "Bottleneck: %s · avg wait %d s" % [
			flow.station_label(bottleneck.building), roundi(bottleneck.average_wait(flow.time))]
	else:
		_bottleneck_label.text = "No bottleneck: every queue moves quickly."


func _add_stats_cell(text: String, color: Color) -> void:
	var cell := Label.new()
	cell.text = text
	cell.add_theme_font_size_override(&"font_size", STATS_FONT_SIZE)
	cell.add_theme_color_override(&"font_color", color)
	_stats_table.add_child(cell)


func _update_station_panel() -> void:
	var building := shown_station
	_station_title.text = "%s · Level %d" % [building.type.display_name, building.level]
	var lines: PackedStringArray = []
	var role := building.type.role
	var station := Airport.passenger_flow.station_for(building)
	if role == BuildingType.Role.CHECK_IN or role == BuildingType.Role.SECURITY:
		var unit := "counters" if role == BuildingType.Role.CHECK_IN else "lanes"
		lines.append("%d %s · %.1f s per passenger" % [building.service_slots(), unit, building.service_time()])
		if station != null:
			lines.append("Queue: %d waiting · %d being served" % [station.queue.size(), station.busyness() - station.queue.size()])
	elif role == BuildingType.Role.GATE and station != null:
		lines.append("Waiting at the gate: %d" % station.waiting.size())
	elif role == BuildingType.Role.BAGGAGE_CLAIM and station != null:
		lines.append("Waiting for bags: %d" % station.waiting.size())
		var wait := station.average_wait(Airport.passenger_flow.time)
		lines.append("Average time here (5 min): %s" % ("–" if wait < 0.0 else "%d s" % roundi(wait)))
	elif role == BuildingType.Role.SHOP and station != null:
		lines.append("Customers inside: %d / %d" % [station.waiting.size(), building.type.customer_capacity])
		lines.append("Airport income (5 min): %s" % Economy.format(station.income_in_window(Airport.passenger_flow.time)))
	lines.append("Running cost: %s/min" % Economy.format(building.running_cost_per_minute()))
	if building.is_upgrading():
		var seconds := ceili(building.upgrade_seconds_left)
		lines.append("Upgrading: %s · %d:%02d left" % [building.next_upgrade().title, seconds / 60, seconds % 60])
	_station_info.text = "\n".join(lines)

	var upgrade := building.next_upgrade()
	var problem := Airport.upgrade_problem(building)
	if upgrade != null and not building.is_upgrading():
		var duration := "" if upgrade.build_seconds <= 0.0 else " · %d min" % ceili(upgrade.build_seconds / 60.0)
		_upgrade_button.text = "Upgrade: %s · %s%s" % [upgrade.title, Economy.format(upgrade.cost), duration]
	else:
		_upgrade_button.text = problem
	_upgrade_button.disabled = not problem.is_empty()


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
