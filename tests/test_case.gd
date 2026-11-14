class_name TestCase
extends Node
## Base class for the automated walkthrough tests in tests/cases/. Run them with tools/run_tests.sh.
## Every test_* method starts with an empty airport. The helpers act like a player: they tap,
## drag and pinch on the real UI, and fast-forward the simulation.

## Collected failure messages ("test name: message").
var failures: Array[String] = []
## Set by the runner before each test.
var current_test: String = ""
## Number of buildings in the showcase airport (scripts/dev/showcase_airport.gd).
const SHOWCASE_BUILDINGS: int = 19

## Building types of the 6 m prototype that save format 10 removes (full refund) when it converts an
## older save; the new runway is laid on loading. Prices are what format 9 saved when an entry has none.
const LEGACY_AIRSIDE_PRICES: Dictionary = {"aircraft_stand": 6000.0, "wide_body_stand": 15000.0, "runway": 40000.0}
const LEGACY_TAXIWAY_PRICE: float = 30.0

## A small map that still holds the 2 km runway (the old 64 x 64 reference map no longer does).
const SMALL_MAP: Vector2i = Vector2i(1200, 400)

## The running game (main scene), created by start_game().
var main: Node = null


# --- Checks ---

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


# --- Game ---

func start_game() -> Node:
	main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(2)
	return main


## Called by the runner after every test.
func cleanup() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	if main != null:
		main.queue_free()
		main = null
	await frames(1)


func hud() -> Hud:
	return main.get_node("HUD")


func build_mode() -> BuildMode:
	return main.get_node("BuildMode")


func build_camera() -> BuildCamera:
	return main.get_node("BuildCamera")


func manager_camera() -> ManagerCamera:
	return main.get_node("ManagerCamera")


func manager() -> Manager:
	return main.get_node("Manager")


func ui(path: String) -> Control:
	return hud().get_node("SafeArea/" + path)


## Puts the manager at `cell` and turns the first-person view to `building` (design doc §15).
func stand_and_look(cell: Vector2i, building: Building) -> void:
	manager().global_position = Airport.grid.cell_to_world(cell)
	await physics_frames(2)
	var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
	manager_camera().face(Airport.grid.block_center(building.origin_cell, size) + Vector3.UP * 1.5)
	await frames(1)


func screen_size() -> Vector2:
	return get_tree().root.get_visible_rect().size


func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Fast-forwards the passenger simulation without waiting in real time.
func sim_seconds(seconds: float) -> void:
	for i in int(seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)


## Runs the simulation until the timetable has turned a slot into a flight (every flight starts
## as a slot whose arrivals window opens, so the first one appears within a few game hours at most),
## then returns the next departure. With `gate_number` > 0 it waits for a flight at that gate.
## Returns null if there is none within `max_seconds`.
func first_flight(gate_number: int = 0, max_seconds: float = 1500.0) -> Flight:
	var schedule := Airport.passenger_flow.schedule
	for i in int(max_seconds / Airport.SIM_STEP):
		for flight in schedule.upcoming():
			if gate_number == 0 or Airport.passenger_flow.gate_number(flight.gate) == gate_number:
				return flight
		Airport.step(Airport.SIM_STEP)
	return null


## Runs the simulation until two flights depart at least MIN_CONNECTION apart (so passengers can
## connect from the earlier one to the later one), and returns the earlier one. Null if none within
## `max_seconds`.
func first_flight_with_connection(max_seconds: float = 2400.0) -> Flight:
	var schedule := Airport.passenger_flow.schedule
	for i in int(max_seconds / Airport.SIM_STEP):
		for flight in schedule.upcoming():
			for other in schedule.flights:
				if not other.cargo and other.departure_time >= flight.departure_time + FlightSchedule.MIN_CONNECTION:
					return flight
		Airport.step(Airport.SIM_STEP)
	return null


# --- Touch input, like a player's fingers ---

func touch(index: int, pressed: bool, position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	get_tree().root.push_input(event, true)


func move(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	get_tree().root.push_input(event, true)


func tap(position: Vector2) -> void:
	touch(0, true, position)
	touch(0, false, position)


## Taps a button. Waits a frame first, like a real finger: containers lay out newly shown
## buttons one frame later, and tapping before that would hit the wrong spot.
func press(control: Control) -> void:
	await frames(1)
	tap(control.get_global_rect().get_center())


func drag(from: Vector2, to: Vector2, steps: int = 10) -> void:
	touch(0, true, from)
	for i in range(1, steps + 1):
		move(0, from.lerp(to, float(i) / steps))
	touch(0, false, to)


## Two fingers: start `start_gap` pixels apart around `center`, end `end_gap` apart.
func pinch(center: Vector2, start_gap: float, end_gap: float) -> void:
	var half := Vector2(start_gap * 0.5, 0.0)
	touch(0, true, center - half)
	touch(1, true, center + half)
	for i in range(1, 6):
		var gap := lerpf(start_gap, end_gap, i / 5.0) * 0.5
		move(0, center - Vector2(gap, 0.0))
		move(1, center + Vector2(gap, 0.0))
	touch(0, false, center)
	touch(1, false, center)


func wheel(up: bool, times: int = 1) -> void:
	for i in times:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		get_tree().root.push_input(event, true)


# --- Build view, through the real UI ---

func open_build_view() -> void:
	if not build_camera().current:
		await press(ui("TopButtons/ViewButton"))
		await frames(1)


func close_build_view() -> void:
	if build_camera().current:
		await press(ui("TopButtons/ViewButton"))
		await frames(1)


## Shows the area the tests build in: the 64 x 64 reference area (MapAnchor) around the map centre,
## centered and as big as the camera allows. (The whole map is far too big to tap cells on.)
## `view_height` (meters, 0 = the reference area) and `centre` show another part, e.g. the taller
## real-scale airside.
func show_whole_map(view_height: float = 0.0, centre: Vector3 = Vector3.ZERO) -> void:
	var camera := build_camera()
	var reference := Vector2(MapAnchor.REFERENCE_SIZE) * Airport.grid.cell_size
	camera.view_height = view_height if view_height > 0.0 else minf(100.0, minf(reference.y, reference.x / (screen_size().x / screen_size().y)))
	camera.center_on(centre)
	await frames(1)


## A cell of the 64 x 64 reference map (where the showcase and the tests are drawn) on the real map:
## the same spot relative to the map centre, whatever the map size.
func at(reference_cell: Vector2i) -> Vector2i:
	return MapAnchor.cell(reference_cell, Airport.grid.size)


func screen_of_cell(cell: Vector2i) -> Vector2:
	return build_camera().unproject_position(Airport.grid.cell_to_world(cell))


## Picks a paint tool, drags a rectangle from one cell to another, and presses Done.
func paint(tool_button: String, from_cell: Vector2i, to_cell: Vector2i) -> void:
	await press(ui("BuildMenu/PaintButtons/" + tool_button))
	drag(screen_of_cell(from_cell), screen_of_cell(to_cell))
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	await frames(1)


## Picks a building in the build menu like a player: open its category, tap the building.
## Returns false if there is no such building.
func pick_building(display_name: String) -> bool:
	var type: BuildingType = null
	for candidate in Airport.CATALOG.types:
		if candidate.display_name == display_name:
			type = candidate
	if type == null:
		check(false, "no building type '%s'" % display_name)
		return false
	var row := ui("BuildMenu/BuildingButtons")
	if _menu_button(row, display_name) == null:
		var back := _menu_button(row, "‹")
		if back != null:
			await press(back)
		await press(_menu_button(row, type.category + " ›"))
	var button := _menu_button(row, display_name)
	if button == null:
		check(false, "no build menu button '%s'" % display_name)
		return false
	await press(button)
	return true


func _menu_button(row: Control, text: String) -> Button:
	for child in row.get_children():
		if not child.is_queued_for_deletion() and (child as Button).text == text:
			return child
	return null


## Places a building like a player: pick it, rotate, drag the preview to `origin`, press Place.
## Returns true if the building was placed there.
func place(display_name: String, origin: Vector2i, rotation_steps: int = 0) -> bool:
	if not await pick_building(display_name):
		return false
	for i in rotation_steps:
		await press(ui("ToolPanel/ToolBar/RotateButton"))
	var mode := build_mode()
	var grab := build_camera().unproject_position(mode._preview.position)
	var cell_pixels := screen_of_cell(Vector2i(1, 0)).x - screen_of_cell(Vector2i.ZERO).x
	drag(grab, grab + Vector2(origin - mode._placing_origin) * cell_pixels)
	var count := Airport.buildings.size()
	await press(ui("ToolPanel/ToolBar/PlaceButton"))
	if mode.is_placing():
		await press(ui("ToolPanel/ToolBar/CancelButton"))
	await frames(1)
	if Airport.buildings.size() != count + 1:
		return false
	var placed: Building = Airport.buildings[-1]
	return placed.origin_cell == origin and placed.rotation_steps == rotation_steps


# --- Layout helpers (direct, for tests that aren't about the build UI) ---

func cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			result.append(origin + Vector2i(x, y))
	return result


func type_of(id: StringName) -> BuildingType:
	return Airport.CATALOG.find(id)


## A minimal terminal: landside hall with an entrance, security on the border, and an airside
## walkway behind it (gates and shops can go along that walkway). No money or tier needed.
func build_basic_terminal() -> void:
	Airport.economy.balance = 1.0e9
	Airport.paint_walkway(cells(at(Vector2i(18, 21)), Vector2i(28, 7)), true)
	Airport.paint_walkway(cells(at(Vector2i(10, 31)), Vector2i(44, 3)), true)
	Airport.place_building(type_of(&"entrance"), at(Vector2i(30, 19)), 0)
	Airport.place_building(type_of(&"security"), at(Vector2i(30, 28)), 0)


## The showcase airport (scripts/dev/showcase_airport.gd), without passengers yet.
func build_reference_airport() -> void:
	ShowcaseAirport.build(0.0)


# --- Loading saves from before format 10 (the real-scale airside) ---

## Money an example save gets back for its removed stands, runway and taxiway paint: worked out
## from the file itself, not from SaveGame.
func legacy_refund_of(saved: Dictionary) -> float:
	var total := 0.0
	for entry: Dictionary in saved.get("buildings", []):
		var type := str(entry.get("type", ""))
		if LEGACY_AIRSIDE_PRICES.has(type):
			total += float(entry.get("cost", LEGACY_AIRSIDE_PRICES[type]))
	var taxiways: Variant = saved.get("taxiways")
	var cells := 0
	if taxiways is String:
		for byte in Marshalls.base64_to_raw(taxiways):
			cells += 1 if byte != 0 else 0
	elif taxiways is Array:
		cells = GridSave.cells_of(taxiways).size()
	return total + cells * LEGACY_TAXIWAY_PRICE


## The building counts of an example save as they are after loading it today: its stands and old
## runway are gone and one (new) runway is there; everything else is as saved.
func counts_after_legacy_removal(counts: Dictionary) -> Dictionary:
	var result := counts.duplicate()
	for type in LEGACY_AIRSIDE_PRICES:
		result.erase(type)
	result["runway"] = 1
	return result
