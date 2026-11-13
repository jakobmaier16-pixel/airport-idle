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
signal demolish_tool_selected
signal demolish_pressed
## The player confirmed resetting the map (test builds only).
signal reset_confirmed
## The player confirmed loading the showcase airport (test builds only).
signal showcase_confirmed
## The player confirmed starting the device benchmark (test builds only, scripts/dev/benchmark.gd).
signal benchmark_confirmed
signal upgrade_pressed(building: Building)
signal hire_pressed(building: Building)
signal dismiss_pressed(building: Building)
signal train_pressed(building: Building)
signal promote_pressed(building: Building)
signal fast_track_pressed(building: Building)

const MONEY_COLOR: Color = Color(1.0, 1.0, 1.0)
const DEBT_COLOR: Color = Color(1.0, 0.4, 0.35)

const STATS_FONT_SIZE: int = 20
const BOTTLENECK_COLOR: Color = Color(1.0, 0.7, 0.3)
## How often the statistics panel refreshes, in seconds.
const STATS_REFRESH: float = 0.5

## How long a notice stays on screen, in seconds.
const NOTICE_SECONDS: float = 10.0

## Smallest size for touch buttons, in UI pixels (Apple recommends at least 44 pt).
const BUTTON_MIN_SIZE: Vector2 = Vector2(120, 72)
## How long Reset / Demo wait for the confirming second tap.
const CONFIRM_TIME: float = 3.0

var _build_view_open: bool = false
# Build menu: every building type, and the category whose buildings are shown ("" = categories).
var _building_types: Array[BuildingType] = []
var _open_category: String = ""
var _stats_refresh_in: float = 0.0
## Statistics tabs (design doc §13.2).
enum StatsTab { STATIONS, MONEY, AIRLINES, MESSAGES }
## The last notices, newest first: [clock text, message] (design doc §13.2).
const MESSAGE_LOG_SIZE: int = 30
var messages: Array = []
var stats_tab: StatsTab = StatsTab.STATIONS
## The building shown in the station panel, or null.
var shown_station: Building = null
# Area name of the shown station: looked up on opening and when the layout changes, not per frame.
var _station_area: String = ""
var _tool: BuildMode.Tool = BuildMode.Tool.NONE
var _notice_left: float = 0.0
var _goal_refresh_in: float = 0.0

@onready var joystick: TouchJoystick = $SafeArea/TouchJoystick
@onready var _view_button: Button = $SafeArea/TopButtons/ViewButton
@onready var _stats_button: Button = $SafeArea/TopButtons/StatsButton
@onready var _airlines_button: Button = $SafeArea/TopButtons/AirlinesButton
@onready var _clock_label: Label = $SafeArea/TopButtons/ClockLabel
@onready var airlines_panel: AirlinesPanel = $SafeArea/AirlinesPanel
@onready var _stats_panel: Control = $SafeArea/StatsPanel
@onready var _stats_table: GridContainer = $SafeArea/StatsPanel/Content/TableScroll/Table
@onready var _bottleneck_label: Label = $SafeArea/StatsPanel/Content/BottleneckLabel
@onready var _types_label: Label = $SafeArea/StatsPanel/Content/TypesLabel
@onready var _satisfaction_label: Label = $SafeArea/StatsPanel/Content/SatisfactionLabel
@onready var _progress_label: Label = $SafeArea/StatsPanel/Content/ProgressLabel
@onready var _milestone_panel: Control = $SafeArea/MilestonePanel
@onready var _goal_panel: Control = $SafeArea/GoalPanel
@onready var _goal_label: Label = $SafeArea/GoalPanel/Row/GoalLabel
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
@onready var _money_label: Label = $SafeArea/InfoPanel/MoneyLabel
@onready var _loan_label: Label = $SafeArea/InfoPanel/LoanLabel
@onready var _notice_panel: Control = $SafeArea/NoticeBox/NoticePanel
@onready var _notice_label: Label = $SafeArea/NoticeBox/NoticePanel/NoticeLabel
@onready var _status_label: Label = $SafeArea/InfoPanel/StatusLabel
@onready var _stars: StarRating = $SafeArea/InfoPanel/RatingRow/Stars
@onready var _rating_label: Label = $SafeArea/InfoPanel/RatingRow/RatingLabel
@onready var _departures_label: Label = $SafeArea/InfoPanel/DeparturesLabel
@onready var _reset_button: Button = $SafeArea/BuildMenu/PaintButtons/ResetButton
@onready var _demo_button: Button = $SafeArea/BuildMenu/PaintButtons/DemoButton
@onready var _bench_button: Button = $SafeArea/BuildMenu/PaintButtons/BenchButton
@onready var _station_panel: Control = $SafeArea/StationPanel
@onready var _station_title: Label = $SafeArea/StationPanel/Content/TitleLabel
@onready var _station_info: Label = $SafeArea/StationPanel/Content/InfoLabel
@onready var _upgrade_button: Button = $SafeArea/StationPanel/Content/UpgradeButton
@onready var _staff_buttons: Control = $SafeArea/StationPanel/Content/StaffButtons
@onready var _hire_button: Button = $SafeArea/StationPanel/Content/StaffButtons/HireButton
@onready var _dismiss_button: Button = $SafeArea/StationPanel/Content/StaffButtons/DismissButton
@onready var _team_buttons: Control = $SafeArea/StationPanel/Content/TeamButtons
@onready var _train_button: Button = $SafeArea/StationPanel/Content/TeamButtons/TrainButton
@onready var _promote_button: Button = $SafeArea/StationPanel/Content/TeamButtons/PromoteButton
@onready var _fast_track_button: Button = $SafeArea/StationPanel/Content/FastTrackButton


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
	_upgrade_button.pressed.connect(func() -> void: upgrade_pressed.emit(shown_station))
	_hire_button.pressed.connect(func() -> void: hire_pressed.emit(shown_station))
	_dismiss_button.pressed.connect(func() -> void: dismiss_pressed.emit(shown_station))
	_train_button.pressed.connect(func() -> void: train_pressed.emit(shown_station))
	_promote_button.pressed.connect(func() -> void: promote_pressed.emit(shown_station))
	_fast_track_button.pressed.connect(func() -> void: fast_track_pressed.emit(shown_station))
	$SafeArea/StationPanel/Content/CloseButton.pressed.connect(hide_station)
	_stats_button.pressed.connect(func() -> void: hide_stats() if _stats_panel.visible else show_stats())
	$SafeArea/StatsPanel/Content/CloseButton.pressed.connect(hide_stats)
	for tab: StatsTab in [StatsTab.STATIONS, StatsTab.MONEY, StatsTab.AIRLINES, StatsTab.MESSAGES]:
		_tab_button(tab).pressed.connect(show_stats_tab.bind(tab))
	$SafeArea/MilestonePanel/Content/OkButton.pressed.connect(func() -> void: _milestone_panel.visible = false)
	$SafeArea/GoalPanel/Row/HideButton.pressed.connect(func() -> void: Airport.goals.hidden = true)
	_airlines_button.pressed.connect(func() -> void: hide_airlines() if airlines_panel.visible else show_airlines())
	_update_visibility()
	_show_build_info()


func _process(delta: float) -> void:
	_goal_refresh_in -= delta
	if _goal_refresh_in <= 0.0:
		_goal_refresh_in = STATS_REFRESH
		_goal_label.text = Airport.goals.text()
	_goal_panel.visible = not _goal_label.text.is_empty() and not Airport.goals.hidden and not _station_panel.visible \
		and not airlines_panel.visible and not _stats_panel.visible and not _milestone_panel.visible
	_clock_label.text = "%s · %s" % [Airport.clock.text(), Seasons.text(Airport.season())]
	if Airport.curfew_at():
		_clock_label.text += " · Curfew"
	var offer_count := Airport.airlines.offers.size()
	_airlines_button.text = "Airlines (%d)" % offer_count if offer_count > 0 else "Airlines"
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice_panel.visible = false
	if shown_station != null:
		_update_station_panel()
	if _stats_panel.visible:
		_stats_refresh_in -= delta
		if _stats_refresh_in <= 0.0:
			_stats_refresh_in = STATS_REFRESH
			_update_stats_panel()


## The next "getting started" goal (design doc §6.1) shown under the top buttons; hidden while
## a panel on the right is open, so they never overlap.
func goal_text() -> String:
	return _goal_label.text if _goal_panel.visible else ""


## Opens the airlines panel (design doc §10.1).
func show_airlines() -> void:
	hide_station()
	hide_stats()
	airlines_panel.open()


func hide_airlines() -> void:
	airlines_panel.close()


## Opens the statistics panel (manager view, design doc §13.1).
func show_stats() -> void:
	hide_station()
	hide_airlines()
	_stats_panel.visible = true
	_update_stats_panel()


## Switches the statistics panel to `tab`.
func show_stats_tab(tab: StatsTab) -> void:
	stats_tab = tab
	for other: StatsTab in [StatsTab.STATIONS, StatsTab.MONEY, StatsTab.AIRLINES, StatsTab.MESSAGES]:
		_tab_button(other).button_pressed = other == tab
	_update_stats_panel()


func _tab_button(tab: StatsTab) -> Button:
	return get_node("SafeArea/StatsPanel/Content/Tabs/" + ["StationsTab", "MoneyTab", "AirlinesTab", "MessagesTab"][tab]) as Button


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
	hide_airlines()
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
			var label := type.display_name
			if type.unlocked_at > Airport.progression.tier:
				# Still pickable: the preview explains when it unlocks.
				label += " (%s)" % Airport.progression.name_of(type.unlocked_at as Progression.Tier)
			_add_menu_button(label, building_type_selected.emit.bind(type))


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


## Bank loan line under the money (design doc §11.6); hidden while there is no debt.
## `restructure_in` is the countdown while over the credit limit, or -1.
func set_loan(debt: float, interest_per_minute: float, limit: float, restructure_in: float) -> void:
	_loan_label.visible = debt > 0.0
	if debt <= 0.0:
		return
	var text := "Bank loan %s of %s · interest %s/min" % [Economy.format(debt), Economy.format(limit), Economy.format(interest_per_minute)]
	if restructure_in >= 0.0:
		var seconds := ceili(restructure_in)
		text = "Over the credit limit! The bank restructures in %d:%02d" % [seconds / 60, seconds % 60]
	_loan_label.text = text


## Shows a message at the top of the screen for a few seconds, and keeps it in the log.
func notify(text: String) -> void:
	messages.push_front([Airport.clock.text(), text])
	if messages.size() > MESSAGE_LOG_SIZE:
		messages.pop_back()
	_notice_label.text = text
	_notice_panel.visible = true
	_notice_left = NOTICE_SECONDS


func notice_text() -> String:
	return _notice_label.text if _notice_panel.visible else ""


## The milestone moment (design doc §14.1): a big panel naming the new tier and its rewards.
func show_milestone(title: String, rewards: String) -> void:
	hide_station()
	hide_stats()
	hide_airlines()
	$SafeArea/MilestonePanel/Content/TitleLabel.text = title
	$SafeArea/MilestonePanel/Content/RewardsLabel.text = rewards
	_milestone_panel.visible = true


func is_milestone_open() -> bool:
	return _milestone_panel.visible


## Star rating and what it is made of, under the money (design doc §11.7).
## Short, so it never runs under the top buttons on an iPad; satisfaction and punctuality are in
## the statistics panel.
func set_rating(stars: float, tier_name: String) -> void:
	_stars.value = stars
	_rating_label.text = "%.1f   ·   %s airport" % [Reputation.shown_stars(stars), tier_name]


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
		hide_airlines()
	elif not _open_category.is_empty():
		show_build_category("")
	_update_visibility()


func set_tool_state(tool: BuildMode.Tool, can_confirm: bool, hint: String) -> void:
	_tool = tool
	_place_button.disabled = not can_confirm
	_demolish_button.disabled = not can_confirm
	_hint_label.text = hint
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
	_stats_button.visible = not _build_view_open
	_airlines_button.visible = not _build_view_open


func _update_stats_panel() -> void:
	var flow := Airport.passenger_flow
	var bottleneck := flow.bottleneck()
	for child in _stats_table.get_children():
		_stats_table.remove_child(child)
		child.queue_free()
	match stats_tab:
		StatsTab.MONEY:
			_fill_money_table()
		StatsTab.AIRLINES:
			_fill_airlines_table()
		StatsTab.MESSAGES:
			_fill_messages_table()
		_:
			_fill_stations_table(bottleneck)
	var counts := flow.count_by_type()
	var parts: PackedStringArray = []
	for type_name in ["Families", "Low-cost", "Business"]:
		parts.append("%d %s" % [counts.get(type_name, 0), type_name])
	_types_label.text = "In the airport: " + "  ·  ".join(parts) \
		+ "     Transfers: %d now  ·  %d connected" % [flow.transferring_count(), flow.transferred_count]
	_satisfaction_label.text = satisfaction_text(flow.satisfaction) \
		+ "     On time: %d %%" % roundi(Airport.reputation.on_time_rate * 100.0) \
		+ "     " + demand_text(Airport.demand, Airport.stars())
	_progress_label.text = Airport.progression.progress_text(Airport.stars())
	_bottleneck_label.visible = stats_tab == StatsTab.STATIONS
	if bottleneck != null:
		_bottleneck_label.text = "Bottleneck: %s · avg wait %d s" % [
			flow.station_label(bottleneck.building), roundi(bottleneck.average_wait(flow.time))]
	else:
		_bottleneck_label.text = "No bottleneck: every queue moves quickly."


# Income and costs by source over the last five minutes (design doc §13.2).
func _fill_money_table() -> void:
	_stats_table.columns = 3
	var heading := Color(0.75, 0.78, 0.82)
	var economy := Airport.economy
	for text in ["Income", "Last 5 min", "Per minute"]:
		_add_stats_cell(text, heading)
	var income := 0.0
	for source in Economy.INCOME_SOURCES:
		var amount := economy.source_total(source)
		income += amount
		_add_money_row(source, amount, Color.WHITE)
	_add_money_row("Total income", income, Color(0.6, 1.0, 0.65))
	for text in ["Costs", "", ""]:
		_add_stats_cell(text, heading)
	var costs := 0.0
	for source in Economy.COST_SOURCES:
		var amount := economy.source_total(source)
		costs += amount
		_add_money_row(source, -amount, Color.WHITE)
	_add_money_row("Total costs", -costs, DEBT_COLOR)
	_add_money_row("Profit", income - costs, BOTTLENECK_COLOR)


func _add_money_row(label: String, amount: float, color: Color) -> void:
	_add_stats_cell(label, color)
	_add_stats_cell(Economy.format(amount), color)
	_add_stats_cell(Economy.format(amount / (Economy.SOURCE_WINDOW_SECONDS / 60.0)), color)


# The last notices, newest first.
func _fill_messages_table() -> void:
	_stats_table.columns = 2
	if messages.is_empty():
		_add_stats_cell("No messages yet.", Color(0.75, 0.78, 0.82))
		_add_stats_cell("", Color.WHITE)
	for entry: Array in messages:
		_add_stats_cell(entry[0], Color(0.75, 0.78, 0.82))
		var cell := Label.new()
		cell.text = entry[1]
		cell.custom_minimum_size = Vector2(620, 0)
		cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_theme_font_size_override(&"font_size", STATS_FONT_SIZE)
		_stats_table.add_child(cell)


# On-time performance and happiness per airline (design doc §13.2).
func _fill_airlines_table() -> void:
	_stats_table.columns = 6
	for heading in ["Airline", "Flights/h", "Flown", "On time", "Happy", "Fee"]:
		_add_stats_cell(heading, Color(0.75, 0.78, 0.82))
	for airline in Airport.airlines.signed:
		var color := DEBT_COLOR if airline.happiness < Airlines.COMPLAIN_BELOW else Color.WHITE
		_add_stats_cell(airline.type.display_name, color)
		_add_stats_cell(str(airline.flights_per_hour), color)
		_add_stats_cell(str(airline.flown), color)
		var on_time := "–" if airline.flown == 0 else "%d %%" % roundi(100.0 * (airline.flown - airline.late) / airline.flown)
		_add_stats_cell(on_time, color)
		_add_stats_cell("%d %%" % roundi(airline.happiness), color)
		_add_stats_cell(Economy.format(airline.fee), color)


func _fill_stations_table(bottleneck: Station) -> void:
	var flow := Airport.passenger_flow
	_stats_table.columns = 5
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
		if station.role() == BuildingType.Role.CAR_PARK:
			for i in 3:
				_add_stats_cell("", color)
			_add_stats_cell(Economy.format(station.income_in_window(flow.time)), color)
			continue
		if station.role() == BuildingType.Role.SHOP or station.role() == BuildingType.Role.LOUNGE:
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


## "Demand: 54 flights/day, 78 % full, rising" (words, not arrows: the font has no arrow glyphs).
static func demand_text(demand: Demand, stars: float) -> String:
	var trend := {"up": "rising", "down": "falling", "steady": "steady"}[demand.trend()] as String
	return "Demand: %d flights/day, %d %% full, %s" % [roundi(demand.flights_per_day()), roundi(Demand.load_factor(stars) * 100.0), trend]


## "Satisfaction: 78 %  ·  Families 82 % …" plus the main complaint (design doc §8.10).
static func satisfaction_text(satisfaction: Satisfaction) -> String:
	var parts: PackedStringArray = []
	for type_name in ["Families", "Low-cost", "Business"]:
		if satisfaction.by_type.has(type_name):
			parts.append("%s %d %%" % [type_name, roundi(satisfaction.by_type[type_name])])
	var text := "Satisfaction: %d %%" % roundi(satisfaction.average)
	if not parts.is_empty():
		text += "   (" + "  ·  ".join(parts) + ")"
	var complaint := satisfaction.main_complaint()
	text += "\nMain complaint: " + (complaint if not complaint.is_empty() else "none")
	return text


func _add_stats_cell(text: String, color: Color) -> void:
	var cell := Label.new()
	cell.text = text
	cell.add_theme_font_size_override(&"font_size", STATS_FONT_SIZE)
	cell.add_theme_color_override(&"font_color", color)
	_stats_table.add_child(cell)


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
	_station_title.text = "%s · Level %d" % [building.type.display_name, building.level]
	var lines: PackedStringArray = []
	var role := building.type.role
	var station := Airport.passenger_flow.station_for(building)
	if not _station_area.is_empty():
		lines.append("Area: %s" % _station_area)
	if role in [BuildingType.Role.CHECK_IN, BuildingType.Role.SECURITY, BuildingType.Role.TRANSFER_SECURITY]:
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
	elif role == BuildingType.Role.CARGO_TERMINAL:
		# Cargo (design doc §10.3): handling speed and the freighter at the stand.
		lines.append("Handling: %.1f t per second" % Airport.passenger_flow.schedule._handling_rate(building))
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.gate == building and flight.phase >= Flight.Phase.AT_STAND:
				lines.append("%s: %d / %d t handled" % [flight.number, roundi(flight.tonnes_handled), roundi(flight.tonnes)])
	elif role == BuildingType.Role.CAR_PARK and station != null:
		lines.append("Returning travellers pay %s each" % Economy.format(PassengerFlow.PARKING_FEE))
		lines.append("Parking income (5 min): %s" % Economy.format(station.income_in_window(Airport.passenger_flow.time)))
	elif (role == BuildingType.Role.SHOP or role == BuildingType.Role.LOUNGE) and station != null:
		lines.append("%s inside: %d / %d" % ["Guests" if role == BuildingType.Role.LOUNGE else "Customers", station.waiting.size(), building.type.customer_capacity])
		lines.append("Airport income (5 min): %s" % Economy.format(station.income_in_window(Airport.passenger_flow.time)))
	var staffed := Airport.needs_staff(building)
	if staffed:
		var working := Airport.staff_at(building)
		var salaries := 0.0
		for employee in working:
			salaries += employee.salary_per_minute
		lines.append("Running cost: %s/min + staff %s/min" % [Economy.format(building.running_cost_per_minute()), Economy.format(salaries)])
		var unit := "counters" if role == BuildingType.Role.CHECK_IN else ("handler places" if role == BuildingType.Role.CARGO_TERMINAL else "lanes")
		lines.append("Staff: %d / %d %s" % [working.size(), building.service_slots(), unit])
		for employee in working.slice(0, 4):
			lines.append("   %s · %s" % [employee.name, employee.level_name()])
		if working.size() > 4:
			lines.append("   … and %d more" % (working.size() - 4))
	else:
		lines.append("Running cost: %s/min" % Economy.format(building.running_cost_per_minute()))
	if building.is_upgrading():
		var seconds := ceili(building.upgrade_seconds_left)
		lines.append("Upgrading: %s · %d:%02d left" % [building.next_upgrade().title, seconds / 60, seconds % 60])
	_station_info.text = "\n".join(lines)

	# Managing happens on the spot (design doc §15.1): far away, the panel only shows information.
	var manage_problem := Airport.manage_problem(building)
	if staffed and Airport.is_manager_near(building):
		lines.append("You're here: staff work 10 % faster, queues stay calmer.")
		_station_info.text = "\n".join(lines)
	_staff_buttons.visible = staffed
	if staffed:
		var hire_problem := Airport.hire_problem(building)
		if hire_problem.is_empty():
			hire_problem = manage_problem
		_hire_button.disabled = not hire_problem.is_empty()
		_hire_button.text = "Hire · %s/min" % Economy.format(Airport.SALARIES[role]) if hire_problem.is_empty() else hire_problem
		_dismiss_button.disabled = Airport.staff_at(building).is_empty() or not manage_problem.is_empty()
	# Training and promotion (design doc §9.2).
	_team_buttons.visible = staffed
	if staffed:
		var train_problem := Airport.train_problem(building)
		_train_button.text = "Train · %s" % Economy.format(Employee.TRAINING_COST) if train_problem.is_empty() else train_problem
		_train_button.disabled = not train_problem.is_empty() or not manage_problem.is_empty()
		var promote_problem := Airport.promote_problem(building)
		_promote_button.text = "Promote to supervisor" if promote_problem.is_empty() else promote_problem
		_promote_button.disabled = not promote_problem.is_empty() or not manage_problem.is_empty()

	# Fast track (design doc §11.8): security only, bought once.
	_fast_track_button.visible = role == BuildingType.Role.SECURITY
	if _fast_track_button.visible:
		var fast_problem := Airport.fast_track_problem(building)
		if building.fast_track:
			_fast_track_button.text = "Fast track: business travellers first · %s each" % Economy.format(PassengerFlow.FAST_TRACK_FEE)
		elif fast_problem.is_empty():
			_fast_track_button.text = "Add fast track · %s" % Economy.format(Airport.FAST_TRACK_COST)
		else:
			_fast_track_button.text = fast_problem
		_fast_track_button.disabled = not fast_problem.is_empty() or not manage_problem.is_empty()

	var upgrade := building.next_upgrade()
	var problem := Airport.upgrade_problem(building)
	if problem.is_empty():
		problem = manage_problem
	if upgrade != null and not building.is_upgrading():
		var duration := "" if upgrade.build_seconds <= 0.0 else " · %d min" % ceili(upgrade.build_seconds / 60.0)
		_upgrade_button.text = "Upgrade: %s · %s%s" % [upgrade.title, Economy.format(upgrade.cost), duration]
		if not manage_problem.is_empty():
			_upgrade_button.text = manage_problem
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
