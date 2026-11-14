extends TestCase
## Access sides and connection hints (design doc §7.1b).


func test_check_in_needs_walkway_in_front() -> void:
	var check_in := type_of(&"check_in")
	check_eq(Airport.connection_problem(check_in, at(Vector2i(10, 10)), 0), "No walkway in front", "alone")
	Airport.paint_walkway(cells(at(Vector2i(10, 9)), Vector2i(2, 1)), true)
	check_eq(Airport.connection_problem(check_in, at(Vector2i(10, 10)), 0), "", "walkway in front")
	check_eq(Airport.connection_problem(check_in, at(Vector2i(10, 10)), 2), "No walkway in front", "turned around")


func test_security_needs_both_sides() -> void:
	var security := type_of(&"security")
	Airport.paint_walkway(cells(at(Vector2i(20, 28)), Vector2i(5, 1)), true)
	check_eq(Airport.connection_problem(security, at(Vector2i(20, 29)), 0), "No walkway behind", "front only")
	Airport.paint_walkway(cells(at(Vector2i(20, 32)), Vector2i(5, 1)), true)
	check_eq(Airport.connection_problem(security, at(Vector2i(20, 29)), 0), "", "both sides")


func test_gate_needs_stand_behind() -> void:
	build_basic_terminal()  # the gate's walkway must be reached through security
	Airport.place_building(type_of(&"gate"), at(Vector2i(40, 34)), 0)
	check_eq(Airport.connection_problem(type_of(&"gate"), at(Vector2i(40, 34)), 0), "No stand", "no stand")
	Airport.place_building(type_of(&"aircraft_stand"), at(Vector2i(32, 39)), 0)
	check_eq(Airport.connection_problem(type_of(&"gate"), at(Vector2i(40, 34)), 0), "Stand has no taxiway", "stand behind, but no way to a runway")
	# The runway south of the stands and a taxiway from the stand down to it (design doc §7.5a).
	Airport.add_starting_runway()  # already there, like in a new game
	check_eq(Airport.connection_problem(type_of(&"aircraft_stand"), at(Vector2i(32, 39)), 0), "No taxiway", "runway, but no taxiway")
	Airport.paint_taxiway(cells(at(Vector2i(36, 62)), Vector2i(12, 19)), true)
	check_eq(Airport.connection_problem(type_of(&"aircraft_stand"), at(Vector2i(32, 39)), 0), "", "taxiway to the runway")
	check_eq(Airport.connection_problem(type_of(&"gate"), at(Vector2i(40, 34)), 0), "", "the gate works")


func test_building_on_walkway_blocks_it() -> void:
	Airport.paint_walkway(cells(at(Vector2i(10, 9)), Vector2i(5, 1)), true)
	check(Airport.grid.is_walkable(at(Vector2i(12, 9))), "walkway is walkable")
	Airport.place_building(type_of(&"entrance"), at(Vector2i(10, 8)), 0)
	check(not Airport.grid.is_walkable(at(Vector2i(12, 9))), "a building on walkway isn't walkable")
	check(Airport.grid.is_walkable(at(Vector2i(14, 9))), "the rest still is")


func test_hint_label_follows_connection() -> void:
	await start_game()
	Airport.place_building(type_of(&"check_in"), at(Vector2i(28, 20)), 0)
	await frames(1)
	var layer := main.get_node("Buildings")
	var label := layer._hints.values()[0] as Label3D
	check(label.visible, "unconnected check-in shows a hint")
	check_eq(label.text, "No walkway in front", "hint text")
	Airport.paint_walkway(cells(at(Vector2i(28, 19)), Vector2i(5, 1)), true)
	await frames(1)
	check(not label.visible, "hint disappears once connected")
