extends TestCase
## Painting zones and walkways (design doc §7.1b, §7.2).


func _count(data: PackedByteArray) -> int:
	var total := 0
	for value in data:
		total += value
	return total


func test_paint_airside_rectangle_and_tap() -> void:
	await start_game()
	await open_build_view()
	await show_whole_map()
	await paint("AirsideButton", Vector2i(20, 30), Vector2i(24, 32))
	check_eq(_count(Airport.grid.get_zone_data()), 15, "5 x 3 cells painted airside")
	await press(ui("BuildMenu/PaintButtons/AirsideButton"))
	tap(screen_of_cell(Vector2i(10, 10)))
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	check_eq(_count(Airport.grid.get_zone_data()), 16, "a tap paints one cell")


func test_painting_does_not_pan() -> void:
	await start_game()
	await open_build_view()
	var start := build_camera().position
	await paint("WalkwayButton", Vector2i(28, 28), Vector2i(36, 30))
	check_eq(build_camera().position, start, "one-finger drag paints instead of panning")
	check_eq(_count(Airport.grid.get_walkway_data()), 27, "9 x 3 walkway cells")


func test_second_finger_cancels_paint_drag() -> void:
	await start_game()
	await open_build_view()
	await press(ui("BuildMenu/PaintButtons/WalkwayButton"))
	touch(0, true, screen_of_cell(Vector2i(28, 28)))
	move(0, screen_of_cell(Vector2i(34, 32)))
	check(build_mode()._paint_preview.visible, "rectangle preview while dragging")
	touch(1, true, screen_of_cell(Vector2i(40, 32)))
	touch(0, false, Vector2.ZERO)
	touch(1, false, Vector2.ZERO)
	check_eq(_count(Airport.grid.get_walkway_data()), 0, "nothing painted when the drag turned into a pinch")
	check(not build_mode()._paint_preview.visible, "preview hidden")
	check(build_camera().pan_enabled, "panning enabled again")


func test_remove_walkway() -> void:
	await start_game()
	await open_build_view()
	await paint("WalkwayButton", Vector2i(28, 28), Vector2i(31, 28))
	await paint("RemoveButton", Vector2i(28, 28), Vector2i(29, 28))
	check_eq(_count(Airport.grid.get_walkway_data()), 2, "two of four walkway cells removed")


func test_cells_needed_by_buildings_keep_their_zone() -> void:
	await start_game()
	Airport.paint_zone(cells(Vector2i(0, 32), Vector2i(64, 32)), AirportGrid.Zone.AIRSIDE)
	Airport.place_building(type_of(&"security"), Vector2i(20, 29), 0)
	var blocked := Airport.paint_zone(cells(Vector2i(18, 32), Vector2i(9, 1)), AirportGrid.Zone.LANDSIDE)
	check_eq(blocked, 5, "the 5 cells behind security stay airside")
	check_eq(Airport.grid.get_zone(Vector2i(20, 32)), AirportGrid.Zone.AIRSIDE, "cell behind security")
	check_eq(Airport.grid.get_zone(Vector2i(18, 32)), AirportGrid.Zone.LANDSIDE, "free cell was repainted")
