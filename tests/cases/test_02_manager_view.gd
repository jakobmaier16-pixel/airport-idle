extends TestCase
## Manager view (first person): walking with keyboard and joystick, looking around, and the touch
## rules (design doc §15).


func test_keyboard_walks_up() -> void:
	await start_game()
	await physics_frames(10)
	var start := manager().global_position
	Input.action_press(&"move_up")
	await physics_frames(60)
	Input.action_release(&"move_up")
	var moved := manager().global_position - start
	check(moved.z < -4.0, "W moves the manager up the screen (-Z): %s" % moved)
	check(absf(moved.x) < 0.1, "no sideways drift: %s" % moved)
	check(manager().is_on_floor(), "manager stands on the ground")


func test_joystick_left_half_only() -> void:
	await start_game()
	var joystick := hud().joystick
	var width := screen_size().x
	touch(0, true, Vector2(width * 0.2, 400))
	move(0, Vector2(width * 0.2 + 100, 400))
	check(joystick.output.x > 0.9, "drag on the left half moves the stick right: %s" % joystick.output)
	touch(0, false, Vector2(width * 0.2 + 100, 400))
	check_eq(joystick.output, Vector2.ZERO, "stick resets on release")

	touch(0, true, Vector2(width * 0.8, 400))
	move(0, Vector2(width * 0.8 + 100, 400))
	check_eq(joystick.output, Vector2.ZERO, "drag on the right half does not start the joystick")
	touch(0, false, Vector2(width * 0.8 + 100, 400))


func test_joystick_moves_manager() -> void:
	await start_game()
	var start := manager().global_position
	touch(0, true, Vector2(200, 400))
	move(0, Vector2(320, 400))
	await physics_frames(60)
	touch(0, false, Vector2(320, 400))
	var moved := manager().global_position - start
	check(moved.x > 4.0, "looking north, joystick right steps right: %s" % moved)
	check(absf(manager().rotation.y - manager_camera().yaw) < 0.01, "the body faces where the manager looks")


func test_drag_on_right_half_looks_around() -> void:
	await start_game()
	var camera := manager_camera()
	var width := screen_size().x
	var yaw := camera.yaw
	touch(0, true, Vector2(width * 0.75, 400))
	move(0, Vector2(width * 0.75 - 200, 400))
	touch(0, false, Vector2(width * 0.75 - 200, 400))
	check(camera.yaw > yaw + deg_to_rad(20.0), "dragging left turns the view left: %.0f°" % rad_to_deg(camera.yaw))
	check_eq(hud().joystick.output, Vector2.ZERO, "looking never moves the joystick")
	touch(0, true, Vector2(width * 0.75, 300))
	move(0, Vector2(width * 0.75, 1300))
	touch(0, false, Vector2(width * 0.75, 1300))
	check(is_equal_approx(camera.pitch, deg_to_rad(camera.min_pitch_degrees)), "looking down stops at the limit")
	await frames(1)
	check(camera.global_position.distance_to(manager().global_position + Vector3.UP * camera.eye_height) < 0.3, "the camera is at the manager's eyes")


func test_walk_and_look_at_the_same_time() -> void:
	await start_game()
	var camera := manager_camera()
	var width := screen_size().x
	var start := manager().global_position
	touch(0, true, Vector2(200, 400))
	move(0, Vector2(200, 280))  # walk forward
	touch(1, true, Vector2(width - 300, 400))
	move(1, Vector2(width - 300 - 450, 400))  # turn left by about 90 degrees
	check(hud().joystick.output.y < -0.9, "the left thumb still walks: %s" % hud().joystick.output)
	await physics_frames(60)
	touch(1, false, Vector2(width - 750, 400))
	touch(0, false, Vector2(200, 280))
	var moved := manager().global_position - start
	check(moved.x < -3.0, "after turning left, forward is west: %s" % moved)


func test_turning_changes_what_forward_means() -> void:
	await start_game()
	manager_camera().yaw = -PI * 0.5  # looking east
	var start := manager().global_position
	Input.action_press(&"move_up")
	await physics_frames(60)
	Input.action_release(&"move_up")
	var moved := manager().global_position - start
	check(moved.x > 4.0 and absf(moved.z) < 0.5, "W walks where the manager looks: %s" % moved)


func test_no_zoom_in_manager_view() -> void:
	await start_game()
	var position := manager_camera().global_position
	pinch(Vector2(900, 400), 100, 300)
	wheel(true, 10)
	await frames(1)
	check(manager_camera().global_position.distance_to(position) < 0.01, "the eyes stay where they are")
	check_eq(hud().joystick.output, Vector2.ZERO, "two fingers never move the joystick by themselves")


func test_joystick_keeps_working_while_other_thumb_taps() -> void:
	await start_game()
	var taps: Array[Vector2] = []
	var on_tap := func(p: Vector2) -> void: taps.append(p)
	TouchGestures.tapped.connect(on_tap)
	var width := screen_size().x
	touch(0, true, Vector2(200, 400))
	move(0, Vector2(200, 300))
	touch(1, true, Vector2(width - 200, 300))
	touch(1, false, Vector2(width - 200, 300))
	check_eq(taps.size(), 1, "right-thumb tap registers")
	check(hud().joystick.output.y < -0.9, "joystick still held up: %s" % hud().joystick.output)
	touch(0, false, Vector2(200, 300))
	TouchGestures.tapped.disconnect(on_tap)


func test_manager_stays_on_map() -> void:
	await start_game()
	Input.action_press(&"move_right")
	# Fast-forward physics: the map edge is 64 m away.
	for i in 30:
		await physics_frames(30)
	Input.action_release(&"move_right")
	check(manager().global_position.x <= Airport.grid.get_world_rect().end.x + 0.01, "manager stops at the map edge")


func test_wobbly_finger_still_taps() -> void:
	await start_game()
	var taps := [0]
	var on_tap := func(_p: Vector2) -> void: taps[0] += 1
	TouchGestures.tapped.connect(on_tap)
	var slop := TouchGestures.tap_slop
	check(slop >= TouchGestures.MIN_TAP_SLOP, "tap slop is at least %.0f UI pixels: %.1f" % [TouchGestures.MIN_TAP_SLOP, slop])
	# A real finger wobbles a little during a tap.
	touch(0, true, Vector2(900, 400))
	move(0, Vector2(900 + slop * 0.8, 400 + 2))
	touch(0, false, Vector2(900 + slop * 0.8, 400 + 2))
	check_eq(taps[0], 1, "a tap that wobbles less than the slop counts")
	touch(0, true, Vector2(900, 400))
	move(0, Vector2(900 + slop * 2.0, 400))
	touch(0, false, Vector2(900 + slop * 2.0, 400))
	check_eq(taps[0], 1, "moving further is a drag, not a tap")
	TouchGestures.tapped.disconnect(on_tap)


func test_tap_slop_is_measured_in_screen_points() -> void:
	# On an iPhone (3x screen, 2556 px window for 1560 UI pixels) 12 pt must be about 22 UI pixels.
	var window_pixels_per_ui_pixel := 2556.0 / 1560.0
	var expected := TouchGestures.TAP_SLOP_POINTS * 3.0 / window_pixels_per_ui_pixel
	check(expected > 20.0 and expected < 24.0, "iPhone slop in UI pixels: %.1f" % expected)


func test_start_inside_the_entrance_and_saved_position() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var entrance: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.ENTRANCE)[0]
	var cell := Airport.grid.world_to_cell(manager().global_position)
	check(Airport.grid.is_walkway(cell), "the manager starts on the hall floor: %s" % cell)
	check(cell.y > entrance.origin_cell.y, "just inside the entrance")
	manager().global_position = Airport.grid.cell_to_world(Vector2i(40, 32))
	manager_camera().yaw = 1.0
	await physics_frames(2)
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	await cleanup()
	Airport.load_state(data)
	await start_game()
	check(manager().global_position.distance_to(Airport.grid.cell_to_world(Vector2i(40, 32))) < 0.5, "back where the manager stood")
	check(absf(manager_camera().yaw - 1.0) < 0.01, "looking the same way")
