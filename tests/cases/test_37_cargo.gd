extends TestCase
## Cargo: terminal, handlers, freighters, cargo airlines (design doc §10.3).


func _terminal() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.CARGO_TERMINAL:
			return building
	return null


func _flights_seen(seconds: float) -> Array[Flight]:
	var seen: Array[Flight] = []
	for i in int(seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if not seen.has(flight):
				seen.append(flight)
	return seen


func test_terminal_rules() -> void:
	var type := type_of(&"cargo_terminal")
	check_eq(Airport.check_placement(type, Vector2i(20, 35), 0), "Unlocked at National airport", "not for regional airports")
	Airport.progression.tier = Progression.Tier.NATIONAL
	var terminal := Airport.place_building(type, Vector2i(20, 35), 0)
	check(terminal != null, "built")
	check_eq(Airport.connection_problem(type, terminal.origin_cell, 0), "Needs an aircraft stand behind", "needs a stand")
	check(Airport.needs_staff(terminal), "needs handlers")
	check_eq(Airport.hire(terminal).salary_per_minute, 9.0, "€9 per minute")


func test_freighters_fly_from_the_cargo_terminal() -> void:
	ShowcaseAirport.build(0.0)
	var terminal := _terminal()
	var freighters := 0
	for flight in _flights_seen(900):
		if flight.gate == terminal:
			check(flight.cargo, "only freighters at the cargo terminal")
		if flight.cargo:
			freighters += 1
			check(flight.gate == terminal, "freighters only at the cargo terminal")
			check_eq(flight.booked, 0, "no passengers")
			check(flight.inbound_types.is_empty(), "nobody on board")
	check(freighters >= 2, "freighters came: %d" % freighters)


func test_cargo_pays_per_tonne() -> void:
	ShowcaseAirport.build(0.0)
	var paid := [0.0]
	for i in 9000:
		Airport.step(Airport.SIM_STEP)
		paid[0] = maxf(paid[0], Airport.economy.source_total(Economy.CARGO))
	# A freighter carries 30-50 t at €20 per tonne, plus the landing fee.
	check(paid[0] >= 30.0 * 20.0 + Economy.FLIGHT_FEE, "cargo income: %s" % Economy.format(paid[0]))


func test_handlers_load_the_freight() -> void:
	ShowcaseAirport.build(0.0)
	var terminal := _terminal()
	var done: Array[Flight] = []
	for i in 9000:
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.cargo and flight.phase == Flight.Phase.DEPARTING and not done.has(flight):
				done.append(flight)
	check(not done.is_empty(), "a freighter left")
	for flight in done:
		check(is_equal_approx(flight.tonnes_handled, flight.tonnes), "all %d t loaded with four handlers" % roundi(flight.tonnes))
		check(flight.airport_delay() < 1.0, "on time")
	var handler: Employee = Airport.staff_at(terminal)[0]
	check(handler.served.get(BuildingType.Role.CARGO_TERMINAL, 0) > 0, "handlers gain experience")


func test_too_few_handlers_delay_the_freighter() -> void:
	ShowcaseAirport.build(0.0)
	var terminal := _terminal()
	while Airport.staff_at(terminal).size() > 1:
		Airport.dismiss(terminal)
	Airport.staff_at(terminal)[0].served.clear()  # a new handler: slow
	var late: Flight = null
	for i in 9000:
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.cargo and flight.phase == Flight.Phase.DEPARTING:
				late = flight
		if late != null:
			break
	check(late != null, "a freighter left")
	if late != null:
		check(late.airport_delay() > 5.0, "it waited for its freight: %.0f s" % late.airport_delay())
		check(late.airport_delay() <= FlightSchedule.CARGO_MAX_HOLD + 0.2, "but not longer than a minute")


func test_cargo_airlines_need_a_terminal() -> void:
	var airlines := Airport.airlines
	for i in 80:
		var offer := airlines.make_offer(5.0, Progression.Tier.HUB, false)
		if offer != null:
			check(not offer.type.cargo, "%s waits for a cargo terminal" % offer.type.display_name)
			airlines.offers.erase(offer)
	var seen_cargo := false
	for i in 80:
		var offer := airlines.make_offer(5.0, Progression.Tier.HUB, true)
		if offer != null:
			seen_cargo = seen_cargo or offer.type.cargo
			airlines.offers.erase(offer)
	check(seen_cargo, "with one, cargo airlines make offers")


func test_no_transfers_onto_freighters() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(1)
	var flow := Airport.passenger_flow
	flow.transfer_share_override = 1.0
	var inbound: Flight = flow.schedule.upcoming()[0]
	for i in 300:
		var connection := flow._connecting_flight(inbound)
		check(connection == null or not connection.cargo, "passengers never connect to a freighter")


func test_panel_shows_handling() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	hud().show_station(_terminal())
	await frames(1)
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("Handling:") and info.contains("handler places"), "panel: '%s'" % info)
