extends TestCase
## Cargo: terminal, freighters, cargo airlines (design doc §10.3).


func _terminal() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.CARGO_TERMINAL:
			return building
	return null


func _flights_seen(seconds: float) -> Array[Flight]:
	var seen: Array[Flight] = []
	for i in int(seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if not seen.has(flight):
				seen.append(flight)
	return seen


func test_terminal_rules() -> void:
	var type := type_of(&"cargo_terminal")
	check_eq(Airport.check_placement(type, at(Vector2i(20, 35)), 0), "Unlocked at National airport", "not for regional airports")
	Airport.progression.tier = Progression.Tier.NATIONAL
	var terminal := Airport.place_building(type, at(Vector2i(20, 35)), 0)
	check(terminal != null, "built")
	check_eq(Airport.connection_problem(type, terminal.origin_cell, 0), "Needs an aircraft stand behind", "needs a stand")


func test_freighters_fly_from_the_cargo_terminal() -> void:
	ShowcaseAirport.build(0.0)
	var terminal := _terminal()
	var freighters := 0
	# Freighter slots are rare (about one every two game hours): look at ten game hours.
	for flight in _flights_seen(2400):
		if flight.gate == terminal:
			check(flight.cargo, "only freighters at the cargo terminal")
		if flight.cargo:
			freighters += 1
			check(flight.gate == terminal, "freighters only at the cargo terminal")
	check(freighters >= 2, "freighters came: %d" % freighters)


func test_cargo_pays_per_tonne() -> void:
	ShowcaseAirport.build(0.0)
	var paid := [0.0]
	for i in 40000:  # up to a game day: until the first freighter has been paid
		Airport.step(Airport.SIM_STEP)
		paid[0] = maxf(paid[0], Airport.economy.source_total(Economy.CARGO))
		if paid[0] > 0.0:
			break
	# A freighter carries 30-50 t at €20 per tonne, plus the landing fee.
	check(paid[0] >= 30.0 * 20.0 + Economy.FLIGHT_FEE, "cargo income: %s" % Economy.format(paid[0]))


func test_handlers_load_the_freight() -> void:
	ShowcaseAirport.build(0.0)
	var done: Array[Flight] = []
	for i in 40000:  # up to a game day: until a freighter has left
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if flight.cargo and flight.phase == Flight.Phase.DEPARTING and not done.has(flight):
				done.append(flight)
		if not done.is_empty():
			break
	check(not done.is_empty(), "a freighter left")
	for flight in done:
		check(is_equal_approx(flight.tonnes_handled, flight.tonnes), "all %d t loaded" % roundi(flight.tonnes))
		check(flight.airport_delay() < 1.0, "on time")


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
