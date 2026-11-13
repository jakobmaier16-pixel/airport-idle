extends TestCase
## Arriving passengers and baggage claim (design doc §8.8).


func _first_flight() -> Flight:
	if Airport.passenger_flow.schedule.flights.is_empty():
		Airport.step(Airport.SIM_STEP)
	return Airport.passenger_flow.schedule.upcoming()[0]


func _claim() -> Station:
	for station in Airport.passenger_flow.stations():
		if station.role() == BuildingType.Role.BAGGAGE_CLAIM:
			return station
	return null


func test_everyone_deplanes_before_boarding() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _first_flight()
	var parked_at := flight.departure_time - (FlightSchedule.PLANE_ARRIVES - FlightSchedule.TAXI_TIME)
	sim_seconds(parked_at - Airport.passenger_flow.time - 1.0)
	check_eq(flight.deplaned, 0, "nobody gets off before the plane is parked")
	sim_seconds(flight.departure_time - FlightSchedule.BOARDING_OPENS - Airport.passenger_flow.time + 0.5)
	check_eq(flight.deplaned, flight.inbound_types.size(), "all %d arriving passengers are off before boarding" % flight.inbound_types.size())


func test_arrivals_leave_through_claim_and_pay() -> void:
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	var saw_at_belt := false
	var wrong_station := 0
	for i in 4000:
		Airport.step(Airport.SIM_STEP)
		for passenger in flow.passengers:
			if not passenger.is_arriving:
				continue
			if passenger.state == Passenger.State.AT_BELT:
				saw_at_belt = true
			if passenger.state in [Passenger.State.QUEUING, Passenger.State.IN_SERVICE, Passenger.State.IN_SHOP, Passenger.State.AT_GATE]:
				wrong_station += 1
	check(saw_at_belt, "arrivals waited at the baggage claim")
	check(flow.arrived_count > 20, "arriving passengers left the airport: %d" % flow.arrived_count)
	check_eq(wrong_station, 0, "arrivals never queue at check-in, security, shops or gates")
	check(flow.status_text().contains("Arrived: %d" % flow.arrived_count), "status shows arrivals")


func test_arrival_fee() -> void:
	# An arriving passenger reaching the exit pays exactly the terminal fee and counts as arrived.
	var flow := Airport.passenger_flow
	var passenger := Passenger.new()
	passenger.is_arriving = true
	passenger.recipe = PassengerFlow.ARRIVAL
	passenger.step = 1
	passenger.goal = BuildingType.Role.ENTRANCE
	flow.passengers.append(passenger)
	var before := Airport.economy.balance
	flow._arrive(passenger)
	check_eq(Airport.economy.balance, before + Economy.ARRIVAL_FEE, "€5 terminal fee")
	check_eq(flow.arrived_count, 1, "counted as arrived")
	check_eq(passenger.state, Passenger.State.GONE, "left the airport")
	Airport.step(Airport.SIM_STEP)
	check(not flow.passengers.has(passenger), "removed at the end of the step")


func test_bags_take_time_hand_luggage_does_not() -> void:
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	var claim := _claim()
	var early_leave_with_bag := 0
	var left_without_bag := 0
	var inside_before: Dictionary[Passenger, bool] = {}
	for i in 4000:
		for passenger in claim.waiting:
			inside_before[passenger] = true
		Airport.step(Airport.SIM_STEP)
		for passenger in inside_before.keys():
			if not claim.waiting.has(passenger):
				inside_before.erase(passenger)
				if passenger.has_bag and flow.time < passenger.bag_ready_at:
					early_leave_with_bag += 1
				if not passenger.has_bag:
					left_without_bag += 1
	check_eq(early_leave_with_bag, 0, "nobody leaves before their bag is on the belt")
	check(left_without_bag > 0, "passengers with hand luggage only walked through")


func test_arrivals_are_never_missed() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(720)
	check_eq(Airport.passenger_flow.missed_count, 0, "arriving passengers don't count as missed when doors close")


func test_baggage_claim_is_required() -> void:
	ShowcaseAirport.build(0.0)
	check(Airport.passenger_flow.route_problem.is_empty(), "showcase is complete")
	# Cut the claim off from the landside hall (its front row y = 26, x 37..42).
	Airport.paint_walkway(cells(Vector2i(37, 26), Vector2i(6, 1)), false)
	check(Airport.passenger_flow.route_problem.contains("baggage claim"), "missing exit is reported: '%s'" % Airport.passenger_flow.route_problem)


func test_claim_sits_on_the_border() -> void:
	var claim := type_of(&"baggage_claim")
	check_eq(Airport.check_placement(claim, Vector2i(20, 28), 0), "", "front landside, back airside")


func test_claim_in_panel_and_stats() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(200)
	await start_game()
	hud().show_station(_claim().building)
	await frames(1)
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("Waiting for bags:"), "panel: '%s'" % info)
	hud().show_stats()
	await frames(2)
	var texts: Array = ui("StatsPanel/Content/TableScroll/Table").get_children().map(func(c: Node) -> String: return (c as Label).text)
	check(texts.has("Baggage claim"), "statistics list the baggage claim")
