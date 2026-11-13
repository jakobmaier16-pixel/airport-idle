extends TestCase
## Step 4a: zones computed from the layout are compared with the painted ones (no behaviour change).
## Every difference is listed in the failure message.


func _compare(label: String) -> void:
	var lines := Airport.brain.zone_map.differences(Airport.grid, Airport.buildings)
	check(lines.is_empty(), "%s: computed zones differ from painted in %d places:\n  %s" % [label, lines.size(), "\n  ".join(lines)])


func test_showcase_computed_equals_painted() -> void:
	await start_game()
	build_reference_airport()
	_compare("showcase")
	# Both zones exist: the walk really reached behind security.
	check_eq(Airport.brain.zone_map.zone_at(Vector2i(20, 32)), AirportGrid.Zone.AIRSIDE, "gate walkway is airside")
	check_eq(Airport.brain.zone_map.zone_at(Vector2i(20, 25)), AirportGrid.Zone.LANDSIDE, "hall is landside")


func test_walkthrough_layout_computed_equals_painted() -> void:
	Airport.reset()
	await start_game()
	Airport.paint_zone(cells(Vector2i(8, 31), Vector2i(48, 26)), AirportGrid.Zone.AIRSIDE)
	Airport.paint_walkway(cells(Vector2i(18, 21), Vector2i(28, 7)), true)
	Airport.paint_walkway(cells(Vector2i(10, 31), Vector2i(44, 3)), true)
	for entry: Array in [[&"entrance", Vector2i(30, 19), 0], [&"check_in", Vector2i(20, 22), 2], [&"check_in", Vector2i(39, 22), 2],
			[&"security", Vector2i(30, 28), 0], [&"gate", Vector2i(14, 34), 0], [&"gate", Vector2i(42, 34), 0],
			[&"aircraft_stand", Vector2i(10, 39), 0], [&"aircraft_stand", Vector2i(38, 39), 0], [&"baggage_claim", Vector2i(37, 27), 0]]:
		Airport.place_building(type_of(entry[0]), entry[1], entry[2])
	Airport.paint_taxiway(cells(Vector2i(15, 51), Vector2i(2, 6)), true)
	Airport.paint_taxiway(cells(Vector2i(43, 51), Vector2i(2, 6)), true)
	_compare("walkthrough layout")


func test_security_is_the_border() -> void:
	await start_game()
	build_reference_airport()
	var map := Airport.brain.zone_map
	check_eq(map.zone_at(Vector2i(20, 32)), AirportGrid.Zone.AIRSIDE, "behind security: airside")
	var security: Building
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.SECURITY:
			security = building
	check(Airport.demolish(security), "security demolished")
	check_eq(map.zone_at(Vector2i(20, 32)), AirportGrid.Zone.LANDSIDE, "without security nothing is airside")
