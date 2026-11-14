extends TestCase
## The zone map's own rules (tech_architecture.md §4): where the walk from the entrance stops.


func test_showcase_zones() -> void:
	await start_game()
	build_reference_airport()
	check_eq(Airport.brain.zone_map.zone_at(at(Vector2i(20, 32))), AirportGrid.Zone.AIRSIDE, "gate walkway is airside")
	check_eq(Airport.brain.zone_map.zone_at(at(Vector2i(20, 25))), AirportGrid.Zone.LANDSIDE, "hall is landside")
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 32))), AirportGrid.Zone.AIRSIDE, "the grid holds the computed zones")


func test_zones_after_load() -> void:
	await start_game()
	build_reference_airport()
	var zones := Airport.grid.get_zone_data().duplicate()
	var state := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	check(not state.has("zones"), "zones are not saved any more")
	Airport.load_state(state)
	check_eq(Airport.grid.get_zone_data(), zones, "recomputed identically after loading")
