extends TestCase
## Runways and taxiways (design doc §7.5a).


func _stand() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.AIRCRAFT_STAND:
			return building
	return null


func test_new_game_has_a_runway() -> void:
	Airport.reset()
	var runways := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY)
	check_eq(runways.size(), 1, "one runway")
	var runway: Building = runways[0]
	var size := Building.rotated_size(runway.type.footprint, runway.rotation_steps)
	for corner in [runway.origin_cell, runway.origin_cell + size - Vector2i.ONE]:
		check(Airport.owns_cell(corner), "the whole runway lies on the airport's own land (%s)" % corner)
	check_eq(Airport.economy.balance, Economy.STARTING_MONEY, "and it was free")


func test_taxiway_rules() -> void:
	Airport.reset()
	Airport.paint_walkway(cells(at(Vector2i(20, 40)), Vector2i(2, 1)), true)
	var money := Airport.economy.balance
	Airport.paint_taxiway(cells(at(Vector2i(20, 40)), Vector2i(4, 1)), true)
	check(not Airport.grid.is_taxiway(at(Vector2i(20, 40))), "never on a walkway")
	check(Airport.grid.is_taxiway(at(Vector2i(23, 40))), "on airside")
	check_eq(Airport.economy.balance, money - 2 * Economy.TAXIWAY_COST_PER_CELL, "€30 per cell")
	check_eq(Airport.grid.get_zone(at(Vector2i(23, 40))), AirportGrid.Zone.AIRSIDE, "taxiways are airside")
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check(Airport.grid.is_taxiway(at(Vector2i(23, 40))), "saved")


func test_showcase_stands_reach_the_runway() -> void:
	ShowcaseAirport.build(0.0)
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.AIRCRAFT_STAND:
			check_eq(Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps), "", "%s connected" % building.type.display_name)
			check(not Airport.plane_network.path_to_stand(building).is_empty(), "planes find a way")
	# Cut the parallel taxiway: the stands lose their way to the runway.
	Airport.paint_taxiway(cells(at(Vector2i(6, 79)), Vector2i(100, 2)), false)
	var stand := _stand()
	check_eq(Airport.connection_problem(stand.type, stand.origin_cell, stand.rotation_steps), "Needs a taxiway to a runway", "cut off")
	check(Airport.passenger_flow.usable_gates().is_empty(), "no gate gets flights")


func test_one_movement_at_a_time() -> void:
	ShowcaseAirport.build(0.0)
	var schedule := Airport.passenger_flow.schedule
	schedule.runway_margin = 60.0  # a slow runway: it becomes the bottleneck
	sim_seconds(900)
	var bookings: Array = schedule.runway_bookings
	check(bookings.size() >= 8, "landings and take-offs: %d" % bookings.size())
	var overlaps := 0
	for i in range(1, bookings.size()):
		# [runway, start, end]: the next movement starts after the one before it has ended.
		if bookings[i][1] < bookings[i - 1][2] - 0.01:
			overlaps += 1
	check_eq(overlaps, 0, "never two planes on the runway")
	check(Airport.passenger_flow.schedule.flights.any(func(f: Flight) -> bool: return f.airport_delay() > 0.0) \
		or Airport.reputation.late_departures > 0, "landings wait for the runway: a delay")


func test_plane_follows_the_taxiway() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var layer := main.get_node("Planes") as PlaneLayer
	var flight: Flight = null
	for i in 4000:
		Airport.step(Airport.SIM_STEP)
		for candidate in Airport.passenger_flow.schedule.flights:
			var left := candidate.departs_at() - Airport.passenger_flow.time
			var route := Airport.passenger_flow.schedule.route_of(candidate)
			if candidate.phase == Flight.Phase.ARRIVING and route != null \
					and left < FlightSchedule.lead_of(route) - route.roll_in_time - 8.0:
				flight = candidate
		if flight != null:
			break
	check(flight != null, "a plane is taxiing in")
	if flight == null:
		return
	await frames(1)
	var cell := Airport.grid.world_to_cell(layer._planes[flight].global_position)
	check(Airport.plane_network.is_paved(cell), "on a taxiway, stand or runway: %s" % cell)
