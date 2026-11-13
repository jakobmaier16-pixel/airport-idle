extends TestCase
## Build view: switching views, top-down camera, pan and zoom limits (design doc §15).


func test_view_button_switches_views() -> void:
	await start_game()
	var taps := [0]
	var on_tap := func(_p: Vector2) -> void: taps[0] += 1
	TouchGestures.tapped.connect(on_tap)
	await open_build_view()
	check(build_camera().current, "build camera active after pressing the button")
	check_eq(taps[0], 0, "pressing a button is not a tap on the map")
	check(ui("BuildMenu").visible, "build menu visible")
	check(not hud().joystick.enabled, "joystick off in build view")
	await close_build_view()
	check(manager_camera().current, "back in manager view")
	check(hud().joystick.enabled, "joystick on again")
	TouchGestures.tapped.disconnect(on_tap)


func test_drag_pans_map_with_finger() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	var start := camera.position
	drag(Vector2(600, 600), Vector2(400, 600))
	var meters_per_pixel := camera.size / screen_size().y
	check(is_equal_approx(camera.position.x - start.x, 200 * meters_per_pixel), "map follows the finger: %s" % (camera.position - start))


func test_two_finger_pan() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	var start := camera.position
	var center := screen_size() * 0.5
	touch(0, true, center)
	touch(1, true, center + Vector2(200, 0))
	move(0, center + Vector2(0, -100))
	move(1, center + Vector2(200, -100))
	touch(0, false, center)
	touch(1, false, center)
	check(camera.position.z - start.z > 1.0, "two fingers moving up move the view: %s" % (camera.position - start))


func test_zoom_and_map_limits() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	wheel(true, 40)
	check_eq(camera.size, camera.min_view_height, "zoom in limit")
	wheel(false, 40)
	check(camera.size <= camera.max_view_height + 0.01, "zoom out limit")
	drag(Vector2(600, 600), Vector2(600 + 5000, 600 - 5000), 50)
	var map := Airport.grid.get_world_rect()
	check(camera.position.x >= map.position.x and camera.position.z <= map.end.y, "camera stays over the map: %s" % camera.position)


func test_build_view_opens_above_manager() -> void:
	await start_game()
	manager().global_position = Vector3(10, 0, -6)
	await open_build_view()
	check(build_camera().position.distance_to(Vector3(10, build_camera().position.y, -6)) < 0.01, "build view centers on the manager")


func test_tap_highlights_cell() -> void:
	await start_game()
	await open_build_view()
	tap(screen_of_cell(at(Vector2i(33, 31))))
	check_eq(build_mode().selected_cell, at(Vector2i(33, 31)), "tapped cell is selected")
