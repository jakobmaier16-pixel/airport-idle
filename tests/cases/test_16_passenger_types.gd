extends TestCase
## Passenger types (design doc §8.7).


func _flights() -> Array[Flight]:
	return Airport.passenger_flow.schedule.flights


# Many flights, to compare averages without depending on luck.
func _many_flights(count: int) -> Array[Flight]:
	var schedule := FlightSchedule.new()
	schedule.world = Airport.brain
	var gate := Building.new(type_of(&"gate"), Vector2i(0, 0), 0)
	var result: Array[Flight] = []
	for i in count:
		schedule._schedule(gate, 1000.0 + i * 180.0)
	result.assign(schedule.flights)
	return result


func test_route_sets_the_mix() -> void:
	var by_route := {}
	for flight in _many_flights(300):
		if not by_route.has(flight.route):
			by_route[flight.route] = {"business": 0, "total": 0}
		for type in flight.arrival_types:
			by_route[flight.route]["total"] += 1
			if type.id == &"business":
				by_route[flight.route]["business"] += 1
	var share := func(route: String) -> float: return float(by_route[route]["business"]) / by_route[route]["total"]
	check(share.call("Business") > 0.45, "business routes are mostly business: %.2f" % share.call("Business"))
	check(share.call("Holiday") < 0.2, "holiday routes have few business travellers: %.2f" % share.call("Holiday"))
	check(share.call("Low-cost") < 0.12, "low-cost routes have very few: %.2f" % share.call("Low-cost"))


func test_business_arrives_later_than_families() -> void:
	var family_total := 0.0
	var family_count := 0
	var business_total := 0.0
	var business_count := 0
	for flight in _many_flights(200):
		for i in flight.booked:
			var before := flight.departure_time - flight.arrival_times[i]
			if flight.arrival_types[i].id == &"family":
				family_total += before
				family_count += 1
			elif flight.arrival_types[i].id == &"business":
				business_total += before
				business_count += 1
	check(family_total / family_count > business_total / business_count + 40.0, "families arrive about a minute earlier on average")


func test_some_low_cost_skip_check_in() -> void:
	ShowcaseAirport.build(0.0)
	var skipped := 0
	var business_skipped := 0
	var seen: Dictionary[Passenger, bool] = {}
	for i in 3000:
		Airport.step(Airport.SIM_STEP)
		for passenger in Airport.passenger_flow.passengers:
			if seen.has(passenger):
				continue
			seen[passenger] = true
			if passenger.goal == BuildingType.Role.SECURITY and passenger.state == Passenger.State.WALKING and passenger.position.distance_to(passenger.previous_position) < 0.5:
				if passenger.type.id == &"low_cost":
					skipped += 1
				elif passenger.type.id == &"business":
					business_skipped += 1
	check(skipped > 0, "some low-cost passengers went straight to security: %d" % skipped)
	check_eq(business_skipped, 0, "business travellers use the counters")


func test_types_move_and_are_processed_differently() -> void:
	var family: PassengerType = load("res://data/passengers/family.tres")
	var business: PassengerType = load("res://data/passengers/business.tres")
	check(family.walk_speed < business.walk_speed, "families walk slower than business travellers")
	check(family.check_in_time_factor > business.check_in_time_factor, "families need longer at check-in")
	check(business.spend_factor > family.spend_factor, "business travellers spend more")
	var flow := PassengerFlow.new()
	flow.world = Airport.brain
	var passenger := Passenger.new()
	passenger.type = family
	check_eq(flow._speed(passenger), family.walk_speed, "speed comes from the type")


func test_figures_use_type_colors() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(120)
	for passenger in Airport.passenger_flow.passengers:
		check(passenger.type.colors.has(PassengerLayer.color_of(passenger)), "figure color belongs to the type")


func test_stats_show_types() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(150)
	await start_game()
	hud().show_stats()
	await frames(2)
	var text := (ui("StatsPanel/Content/TypesLabel") as Label).text
	check(text.begins_with("In the airport: ") and text.contains("Families") and text.contains("Business"), "types line: '%s'" % text)
	var counts := Airport.passenger_flow.count_by_type()
	var total := 0
	for value in counts.values():
		total += value
	check_eq(total, Airport.passenger_flow.passengers.size(), "every passenger is counted once")


func test_showcase_still_handles_all_types() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(720)
	check_eq(Airport.passenger_flow.missed_count, 0, "no missed flights with all three passenger types")
	check(Airport.passenger_flow.departed_count > 60, "passengers departed: %d" % Airport.passenger_flow.departed_count)
