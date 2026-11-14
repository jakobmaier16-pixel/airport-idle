extends TestCase
## Painting walkways (design doc §7.1b, §7.2) and zones computed from the layout (design doc §8.1).


func _count(data: PackedByteArray) -> int:
	var total := 0
	for value in data:
		total += value
	return total


func test_painting_does_not_pan() -> void:
	await start_game()
	await open_build_view()
	var start := build_camera().position
	await paint("WalkwayButton", at(Vector2i(28, 28)), at(Vector2i(36, 30)))
	check_eq(build_camera().position, start, "one-finger drag paints instead of panning")
	check_eq(_count(Airport.grid.get_walkway_data()), 27, "9 x 3 walkway cells")


func test_second_finger_cancels_paint_drag() -> void:
	await start_game()
	await open_build_view()
	await press(ui("BuildMenu/PaintButtons/WalkwayButton"))
	touch(0, true, screen_of_cell(at(Vector2i(28, 28))))
	move(0, screen_of_cell(at(Vector2i(34, 32))))
	check(build_mode()._paint_preview.visible, "rectangle preview while dragging")
	touch(1, true, screen_of_cell(at(Vector2i(40, 32))))
	touch(0, false, Vector2.ZERO)
	touch(1, false, Vector2.ZERO)
	check_eq(_count(Airport.grid.get_walkway_data()), 0, "nothing painted when the drag turned into a pinch")
	check(not build_mode()._paint_preview.visible, "preview hidden")
	check(build_camera().pan_enabled, "panning enabled again")


func test_remove_walkway() -> void:
	await start_game()
	await open_build_view()
	await paint("WalkwayButton", at(Vector2i(28, 28)), at(Vector2i(31, 28)))
	await paint("RemoveButton", at(Vector2i(28, 28)), at(Vector2i(29, 28)))
	check_eq(_count(Airport.grid.get_walkway_data()), 2, "two of four walkway cells removed")


func test_security_splits_landside_and_airside() -> void:
	await start_game()
	build_basic_terminal()
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 25))), AirportGrid.Zone.LANDSIDE, "the hall is landside")
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 32))), AirportGrid.Zone.AIRSIDE, "behind security is airside")
	check(Airport.brain.zone_map.airside_reached, "airside reached")
	check_eq(Airport.grid.get_zone(at(Vector2i(10, 10))), AirportGrid.Zone.LANDSIDE, "empty ground is landside")


func test_removing_and_readding_security() -> void:
	await start_game()
	build_basic_terminal()
	var security: Building
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.SECURITY:
			security = building
	Airport.demolish(security)
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 32))), AirportGrid.Zone.LANDSIDE, "without security nothing is airside")
	check(not Airport.brain.zone_map.airside_reached, "airside gone")
	Airport.place_building(type_of(&"security"), at(Vector2i(30, 28)), 0)
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 32))), AirportGrid.Zone.AIRSIDE, "airside is back")


func test_airside_building_before_security_is_not_connected() -> void:
	await start_game()
	Airport.paint_walkway(cells(at(Vector2i(18, 21)), Vector2i(28, 7)), true)
	Airport.paint_walkway(cells(at(Vector2i(10, 31)), Vector2i(44, 3)), true)
	Airport.place_building(type_of(&"entrance"), at(Vector2i(30, 19)), 0)
	var gate := type_of(&"gate")
	check_eq(Airport.check_placement(gate, at(Vector2i(14, 34)), 0), "", "a gate can be placed anywhere")
	var placed := Airport.place_building(gate, at(Vector2i(14, 34)), 0)
	check(placed != null, "gate placed before security")
	check(Airport.connection_problem(gate, at(Vector2i(14, 34)), 0).begins_with("Not connected"), "hint: not connected")
	Airport.place_building(type_of(&"security"), at(Vector2i(30, 28)), 0)
	check(not Airport.connection_problem(gate, at(Vector2i(14, 34)), 0).begins_with("Not connected"), "connected once security and the walkway exist")


func test_security_needs_a_free_row_on_both_sides() -> void:
	await start_game()
	var security := type_of(&"security")
	check_eq(Airport.check_placement(security, at(Vector2i(30, 28)), 0), "", "free rows: fine, nothing painted needed")
	check(Airport.place_building(type_of(&"check_in"), at(Vector2i(30, 25)), 0) != null, "something stands in the front row")
	check_eq(Airport.check_placement(security, at(Vector2i(30, 28)), 0), "Needs a free row in front and behind", "no room in front")
