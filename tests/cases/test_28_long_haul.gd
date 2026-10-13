extends TestCase
## Long-haul flights: wide-body stands, planes and airlines (design doc §10.2).


func _gate_3() -> Building:
	var gates := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)
	return gates[2]


func _flights_planned(seconds: float) -> Array[Flight]:
	var seen: Array[Flight] = []
	for i in int(seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if not seen.has(flight):
				seen.append(flight)
	return seen


func test_wide_body_stand_unlocks_at_international() -> void:
	var type := type_of(&"wide_body_stand")
	Airport.paint_zone(cells(Vector2i(8, 30), Vector2i(48, 26)), AirportGrid.Zone.AIRSIDE)
	check_eq(Airport.check_placement(type, Vector2i(20, 36), 0), "Unlocked at International airport", "not before International")
	Airport.progression.tier = Progression.Tier.INTERNATIONAL
	check_eq(Airport.check_placement(type, Vector2i(20, 36), 0), "", "then it can be built")


func test_long_haul_flies_from_the_wide_body_gate() -> void:
	ShowcaseAirport.build(0.0)
	var wide := 0
	var wide_booked := 0
	var narrow_booked := 0
	var narrow := 0
	for flight in _flights_planned(900):
		if flight.airline.type.wide_body:
			wide += 1
			wide_booked += flight.booked
			check(flight.wide_body, "long-haul airlines fly wide-body planes")
			check(flight.gate == _gate_3(), "only from the gate with the wide-body stand")
			check_eq(flight.route, "Long-haul", "long-haul route")
		else:
			narrow += 1
			narrow_booked += flight.booked
	check(wide >= 2, "long-haul flights: %d" % wide)
	check(float(wide_booked) / wide > 1.6 * float(narrow_booked) / narrow, "big planes carry far more passengers")


func test_wide_stand_prefers_wide_airlines() -> void:
	var airlines := Airport.airlines
	var long_haul := airlines.sign_deal(Airlines.CATALOG.find(&"orynth"), 6, 32.0)
	long_haul.credit = 0.6
	airlines.signed[0].credit = 1.5  # the starter is owed more
	check(airlines.next_airline(true) == long_haul, "the wide-body stand goes to the long-haul airline")
	check(airlines.next_airline(false) == airlines.signed[0], "a narrow stand never takes a wide-body plane")
	long_haul.credit = 5.0
	check(airlines.next_airline(false) != long_haul, "however much it is owed")


func test_no_wide_stand_means_refused_flights() -> void:
	ShowcaseAirport.build(0.0)
	var wide_stand: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.wide_body)[0]
	Airport.demolish(wide_stand)
	sim_seconds(1200)
	var orynth := Airport.airlines.find_signed(Airlines.CATALOG.find(&"orynth"))
	check(orynth == null or orynth.refused > 0, "long-haul flights are refused without a wide-body stand")


func test_long_haul_offers_need_international() -> void:
	var airlines := Airport.airlines
	for i in 60:
		var offer := airlines.make_offer(5.0, Progression.Tier.NATIONAL)
		if offer != null:
			check(not offer.type.wide_body, "%s needs an international airport" % offer.type.display_name)
			airlines.offers.erase(offer)
	var seen_long_haul := false
	for i in 60:
		var offer := airlines.make_offer(5.0, Progression.Tier.INTERNATIONAL)
		if offer != null:
			seen_long_haul = seen_long_haul or offer.type.wide_body
			airlines.offers.erase(offer)
	check(seen_long_haul, "international airports hear from long-haul airlines")


func test_reaching_international_brings_an_offer() -> void:
	for i in Satisfaction.MEMORY:
		Airport.passenger_flow.satisfaction.record("Business", 100.0)
	Airport.reputation.on_time_rate = 1.0
	Airport.progression.tier = Progression.Tier.NATIONAL
	Airport.progression.passengers = Progression.PASSENGERS_NEEDED[Progression.Tier.INTERNATIONAL]
	sim_seconds(0.2)
	check_eq(Airport.progression.tier, Progression.Tier.INTERNATIONAL, "international")
	check(Airport.airlines.offers.any(func(o: AirlineOffer) -> bool: return o.type.id == &"orynth"), "Orynth Pacific makes an offer")


func test_wide_body_plane_is_bigger() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var wide_flight: Flight = null
	for i in 9000:
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.wide_body and flight.phase == Flight.Phase.AT_STAND:
				wide_flight = flight
		if wide_flight != null:
			break
	check(wide_flight != null, "a wide-body plane parked")
	if wide_flight == null:
		return
	await frames(2)
	var planes := main.get_node("Planes") as PlaneLayer
	check(planes._planes.has(wide_flight) and planes._planes[wide_flight].size_factor > 1.0, "drawn bigger")
