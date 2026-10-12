extends TestCase
## Manager view: walking with keyboard and joystick, zoom, and the touch rules (design doc §15).


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
	check(moved.x > 4.0, "joystick right walks right: %s" % moved)
	check(absf(manager().rotation_degrees.y + 90.0) < 5.0, "manager faces right (yaw -90): %s" % manager().rotation_degrees.y)


func test_pinch_never_moves_joystick_and_zooms() -> void:
	await start_game()
	var camera := manager_camera()
	var start_distance := camera.distance
	pinch(Vector2(300, 400), 100, 300)
	check(camera.distance < start_distance, "spreading fingers zooms in")
	check_eq(hud().joystick.output, Vector2.ZERO, "pinch never moves the joystick")
	pinch(Vector2(300, 400), 300, 20)
	check(camera.distance > start_distance - 0.01, "pinching together zooms out")


func test_zoom_limits() -> void:
	await start_game()
	var camera := manager_camera()
	wheel(false, 40)
	check_eq(camera.distance, camera.max_distance, "zoom out stops at the limit")
	wheel(true, 40)
	check_eq(camera.distance, camera.min_distance, "zoom in stops at the limit")


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
