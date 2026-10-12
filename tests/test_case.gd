class_name TestCase
extends Node
## Base class for the automated walkthrough tests in tests/cases/. Run them with tools/run_tests.sh.
## Every test_* method starts with an empty airport. The helpers act like a player: they tap,
## drag and pinch on the real UI, and fast-forward the simulation.

## Collected failure messages ("test name: message").
var failures: Array[String] = []
## Set by the runner before each test.
var current_test: String = ""
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
		Airport.passenger_flow.tick(Airport.SIM_STEP)


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
		await press(ui("ViewButton"))
		await frames(1)


func close_build_view() -> void:
	if build_camera().current:
		await press(ui("ViewButton"))
		await frames(1)


## Zooms the build camera all the way out and centers it on the map.
func show_whole_map() -> void:
	wheel(false, 30)
	build_camera().center_on(Vector3.ZERO)
	await frames(1)


func screen_of_cell(cell: Vector2i) -> Vector2:
	return build_camera().unproject_position(Airport.grid.cell_to_world(cell))


## Picks a paint tool, drags a rectangle from one cell to another, and presses Done.
func paint(tool_button: String, from_cell: Vector2i, to_cell: Vector2i) -> void:
	await press(ui("BuildMenu/PaintButtons/" + tool_button))
	drag(screen_of_cell(from_cell), screen_of_cell(to_cell))
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	await frames(1)


## Places a building like a player: pick it, rotate, drag the preview to `origin`, press Place.
## Returns true if the building was placed there.
func place(display_name: String, origin: Vector2i, rotation_steps: int = 0) -> bool:
	var button: Button = null
	for child in ui("BuildMenu/BuildingButtons").get_children():
		if (child as Button).text == display_name:
			button = child
	if button == null:
		check(false, "no build menu button '%s'" % display_name)
		return false
	await press(button)
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


## The showcase airport (scripts/dev/showcase_airport.gd), without passengers yet.
func build_reference_airport() -> void:
	ShowcaseAirport.build(0.0)
