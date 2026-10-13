extends TestCase
## Transfer passengers and transfer security (design doc §8.9).


func _transfer_security() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.TRANSFER_SECURITY:
			return building
	return null


func test_no_transfer_security_no_transfers() -> void:
	ShowcaseAirport.build(0.0)
	Airport.demolish(_transfer_security())
	check(not Airport.passenger_flow.transfers_possible, "no connections without transfer security")
	Airport.passenger_flow.transfer_share_override = 0.6  # would be many, if it were possible
	sim_seconds(400)
	check_eq(Airport.passenger_flow.transferred_count, 0, "nobody transferred")
	check(Airport.passenger_flow.passengers.all(func(p: Passenger) -> bool: return not p.is_transfer), "nobody is transferring")


func test_transfers_connect() -> void:
	ShowcaseAirport.build(0.0)
	check(Airport.passenger_flow.transfers_possible, "showcase sells connections")
	var flow := Airport.passenger_flow
	flow.transfer_share_override = 0.6  # more transfers: independent of luck
	var landside := 0
	var at_claim := 0
	var screened := 0
	var too_short := 0
	var seen: Dictionary[Passenger, bool] = {}
	for i in 6000:  # 10 minutes
		Airport.step(Airport.SIM_STEP)
		for passenger in flow.passengers:
			if not passenger.is_transfer:
				continue
			if not seen.has(passenger):
				seen[passenger] = true
				if passenger.flight.departure_time < flow.time + FlightSchedule.MIN_CONNECTION - 1.0:
					too_short += 1
			var cell := Airport.grid.world_to_cell(passenger.position)
			if passenger.state == Passenger.State.WALKING and Airport.grid.get_zone(cell) != AirportGrid.Zone.AIRSIDE:
				landside += 1
			if passenger.state == Passenger.State.AT_BELT:
				at_claim += 1
			if passenger.state == Passenger.State.IN_SERVICE and passenger.target == _transfer_security():
				screened += 1
	check(seen.size() > 5, "transfer passengers came off the planes: %d" % seen.size())
	check(flow.transferred_count > 3, "transfers boarded their connecting flight: %d" % flow.transferred_count)
	check(screened > 0, "they were screened at transfer security")
	check_eq(landside, 0, "transfers never go landside")
	check_eq(at_claim, 0, "transfers skip baggage claim")
	check_eq(too_short, 0, "connections leave at least 2½ minutes later")


func test_unstaffed_transfer_security_sells_no_connections() -> void:
	ShowcaseAirport.build(0.0)
	var transfer_security := _transfer_security()
	while Airport.dismiss(transfer_security):
		pass
	check(not Airport.passenger_flow.transfers_possible, "no staff, no connections")
	Airport.hire(transfer_security)
	check(Airport.passenger_flow.transfers_possible, "hiring someone opens it again")


func test_missed_connections_count() -> void:
	ShowcaseAirport.build(0.0)
	var transfer_security := _transfer_security()
	var normal_time := transfer_security.type.service_time
	transfer_security.type.service_time = 400.0  # practically closed after the first passengers
	Airport.passenger_flow.transfer_share_override = 0.6
	sim_seconds(600)
	transfer_security.type.service_time = normal_time
	check(Airport.passenger_flow.missed_count > 0, "stuck transfers miss their connection")


func test_transfer_security_rules() -> void:
	var type := type_of(&"transfer_security")
	check_eq(Airport.check_placement(type, Vector2i(10, 10), 0), "Unlocked at National airport", "not for regional airports")
	Airport.progression.tier = Progression.Tier.NATIONAL
	check_eq(Airport.check_placement(type, Vector2i(10, 10), 0), "Must be built on airside", "airside only")
	Airport.paint_zone(cells(Vector2i(0, 32), Vector2i(64, 32)), AirportGrid.Zone.AIRSIDE)
	check_eq(Airport.connection_problem(type, Vector2i(10, 40), 0), "Needs a walkway in front", "needs walkway in front")
	Airport.paint_walkway(cells(Vector2i(10, 39), Vector2i(4, 1)), true)
	check_eq(Airport.connection_problem(type, Vector2i(10, 40), 0), "Needs a walkway behind", "and behind")
	var building := Airport.place_building(type, Vector2i(10, 40), 0)
	check(Airport.needs_staff(building), "staffed like security")
	check_eq(Airport.hire(building).salary_per_minute, 10.0, "security officer salary")


func test_stats_show_transfers() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(100)
	await start_game()
	hud().show_stats()
	await frames(2)
	var text := (ui("StatsPanel/Content/TypesLabel") as Label).text
	check(text.contains("Transfers:") and text.contains("connected"), "stats line: '%s'" % text)
