extends TestCase
## Placing buildings: preview, dragging, rotating, rules and hints (design doc §7.1a, §7.2).


func test_all_mvp_buildings_in_menu() -> void:
	await start_game()
	await open_build_view()
	var row := ui("BuildMenu/BuildingButtons")
	var texts := func() -> Array:
		return row.get_children().filter(func(b: Node) -> bool: return not b.is_queued_for_deletion()).map(func(b: Node) -> String: return (b as Button).text)
	check_eq(texts.call(), ["Terminal ›", "Airside ›", "Shops ›", "Landside ›"], "categories")
	await press(_menu_button(row, "Terminal ›"))
	check_eq(texts.call(), ["‹", "Entrance", "Check-in", "Security", "Gate", "Baggage claim", "Transfer security (National)"], "terminal buildings (transfer security unlocks later)")
	await press(_menu_button(row, "‹"))
	await press(_menu_button(row, "Shops ›"))
	check_eq(texts.call(), ["‹", "Shop", "Café", "Lounge"], "shops")
	await press(_menu_button(row, "‹"))
	await press(_menu_button(row, "Airside ›"))
	check_eq(texts.call(), ["‹", "Stand", "Wide-body stand (International)", "Runway", "Cargo terminal (National)"], "airside")
	await close_build_view()
	await open_build_view()
	check_eq(texts.call(), ["Terminal ›", "Airside ›", "Shops ›", "Landside ›"], "menu starts at the categories again")


func test_place_with_buttons() -> void:
	await start_game()
	await open_build_view()
	check(await place("Check-in", at(Vector2i(30, 20))), "check-in placed where it was dragged")
	check_eq(main.get_node("Buildings").get_child_count(), 1, "one building visual")
	check(not build_mode().is_placing(), "placing ends after Place")
	check(ui("BuildMenu").visible, "build menu back")


func test_drag_preview_cell_by_cell() -> void:
	await start_game()
	await open_build_view()
	await pick_building("Check-in")
	var mode := build_mode()
	var camera := build_camera()
	var start_origin := mode._placing_origin
	var cell_pixels := screen_of_cell(Vector2i(1, 0)).x - screen_of_cell(Vector2i.ZERO).x
	var camera_start := camera.position
	var grab := camera.unproject_position(mode._preview.position)
	drag(grab, grab + Vector2(cell_pixels, 0))
	check_eq(mode._placing_origin, start_origin + Vector2i(1, 0), "one cell right")
	check_eq(camera.position, camera_start, "camera stays still while dragging the building")
	grab = camera.unproject_position(mode._preview.position)
	drag(grab, grab + Vector2(cell_pixels * 0.4, 0))
	check_eq(mode._placing_origin, start_origin + Vector2i(1, 0), "less than half a cell doesn't move it")
	drag(grab + Vector2(0, -cell_pixels * 9), grab + Vector2(cell_pixels * 4, -cell_pixels * 9))
	check(camera.position != camera_start, "a drag away from the building pans the camera")
	check_eq(mode._placing_origin, start_origin + Vector2i(1, 0), "...and leaves the building where it is")


func test_rotate_keeps_position() -> void:
	await start_game()
	await open_build_view()
	await pick_building("Check-in")
	var mode := build_mode()
	var origin := mode._placing_origin
	await press(ui("ToolPanel/ToolBar/RotateButton"))
	check_eq(mode._placing_rotation, 1, "rotated once")
	await press(ui("ToolPanel/ToolBar/RotateButton"))
	check_eq(mode._placing_origin, origin, "two turns: same spot as before")


func test_overlap_is_red_and_place_disabled() -> void:
	await start_game()
	await open_build_view()
	check(await place("Check-in", at(Vector2i(30, 30))), "first check-in")
	await pick_building("Check-in")
	build_mode()._set_preview_origin(at(Vector2i(31, 31)))
	var place_button := ui("ToolPanel/ToolBar/PlaceButton") as Button
	check(place_button.disabled, "Place disabled on an occupied spot")
	check_eq((ui("ToolPanel/HintLabel") as Label).text, "Space is taken", "hint")
	await press(place_button)
	check_eq(Airport.buildings.size(), 1, "pressing a disabled Place does nothing")


func test_zone_rules_and_hints() -> void:
	await start_game()
	await open_build_view()
	var hint := ui("ToolPanel/HintLabel") as Label
	await pick_building("Gate")  # Gate
	build_mode()._set_preview_origin(at(Vector2i(10, 10)))
	check(hint.text.begins_with("Needs a walkway"), "a gate can go anywhere, hint names what's missing: '%s'" % hint.text)
	await press(ui("ToolPanel/ToolBar/CancelButton"))
	check_eq(Airport.check_placement(type_of(&"security"), at(Vector2i(20, 29)), 0), "", "security on the border, front landside")


func test_leaving_build_view_cancels() -> void:
	await start_game()
	await open_build_view()
	await pick_building("Entrance")
	await close_build_view()
	check(not build_mode().is_placing(), "placement cancelled")
	check(build_mode()._preview == null, "preview removed")


func test_buildings_are_solid_but_stand_is_flat() -> void:
	await start_game()
	var cell := Airport.grid.world_to_cell(manager().global_position)
	Airport.place_building(type_of(&"check_in"), cell + Vector2i(-2, -4), 0)
	await frames(1)
	Input.action_press(&"move_up")
	await physics_frames(120)
	Input.action_release(&"move_up")
	var wall_z := Airport.grid.block_center(cell + Vector2i(-2, -4), Vector2i(5, 3)).z + 3.0
	check(manager().global_position.z > wall_z - 0.01, "manager is blocked by the check-in")
