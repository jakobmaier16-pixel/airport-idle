extends TestCase
## Reputation: star rating, on-time rate and delays (design doc §11.7).


func _first_flight() -> Flight:
	return first_flight()


func test_star_rating() -> void:
	var reputation := Reputation.new()
	var new_airport := reputation.stars(Satisfaction.START)
	check(new_airport > 3.0 and new_airport < 4.0, "a new airport has 3–4 stars: %.2f" % new_airport)
	reputation.on_time_rate = 1.0
	check_eq(reputation.stars(100.0), 5.0, "happy and punctual: 5 stars")
	reputation.on_time_rate = 0.0
	check_eq(reputation.stars(20.0), 1.0, "unhappy and late: 1 star")
	check_eq(Reputation.shown_stars(3.74), 3.5, "shown in half stars")


func test_on_time_rate() -> void:
	var reputation := Reputation.new()
	for i in 30:
		reputation.record_departure(0.0)
	check(reputation.on_time_rate > 0.97, "punctual flights: %.2f" % reputation.on_time_rate)
	for i in 30:
		reputation.record_departure(Reputation.ON_TIME_LIMIT + 5.0)
	check(reputation.on_time_rate < 0.1, "late flights: %.2f" % reputation.on_time_rate)
	check_eq(reputation.late_departures, 30, "late departures counted")


func test_reputation_sets_demand() -> void:
	var gate := Building.new(type_of(&"gate"), Vector2i(0, 0), 0)
	var average_booked := func(satisfaction: float, on_time: float) -> float:
		Airport.passenger_flow.satisfaction.average = satisfaction
		Airport.reputation.on_time_rate = on_time
		var schedule := FlightSchedule.new()
		schedule.world = Airport.brain
		var total := 0
		for i in 200:
			schedule._schedule(gate, 1000.0 + i * 180.0)
		for flight in schedule.flights:
			total += flight.booked
		return float(total) / schedule.flights.size()
	var bad: float = average_booked.call(10.0, 0.0)
	var good: float = average_booked.call(100.0, 1.0)
	check(good > bad * 2.0, "a 5-star airport gets far more passengers: %.1f vs %.1f" % [good, bad])


func test_flight_holds_for_late_passenger() -> void:
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	var flight := _first_flight()
	sim_seconds(flight.departure_time - flow.time - 2.0)
	check_eq(flight.phase, Flight.Phase.BOARDING, "boarding")
	# A passenger far away on the airside walkway, on the way to this gate.
	var late := Passenger.new()
	late.flight = flight
	late.recipe = PassengerFlow.DEPARTURE
	late.step = 2
	late.goal = BuildingType.Role.GATE
	late.position = Airport.grid.cell_to_world(Vector2i(53, 37))
	late.previous_position = late.position
	flow.passengers.append(late)
	flow._plan(late)
	sim_seconds(10.0)
	check_eq(flight.phase, Flight.Phase.BOARDING, "doors held after the scheduled time")
	check(flight.delay > 5.0, "delayed: %.1f s" % flight.delay)
	check(flow.departures_text().contains("Delayed"), "the board says delayed")
	sim_seconds(FlightSchedule.MAX_HOLD)
	check(flight.phase >= Flight.Phase.DEPARTING, "it leaves after the longest hold")
	check(flight.delay <= FlightSchedule.MAX_HOLD + 0.01, "never holds longer than %d s" % FlightSchedule.MAX_HOLD)
	check_eq(Airport.reputation.late_departures, 1, "counted as late")


func test_showcase_is_punctual_and_well_rated() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(900)
	check(Airport.reputation.departures >= 8, "flights departed: %d" % Airport.reputation.departures)
	check(Airport.reputation.on_time_rate > 0.8, "mostly on time: %.2f" % Airport.reputation.on_time_rate)
	check(Airport.stars() >= 4.0, "a good airport earns at least 4 stars: %.2f" % Airport.stars())


func test_reputation_is_saved() -> void:
	Airport.reputation.on_time_rate = 0.42
	Airport.reputation.departures = 7
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check(is_equal_approx(Airport.reputation.on_time_rate, 0.42), "on-time rate restored")
	check_eq(Airport.reputation.departures, 7, "departures restored")


func test_hud_shows_stars() -> void:
	await start_game()
	await frames(2)
	var stars := ui("InfoPanel/RatingRow/Stars") as StarRating
	check_eq(stars.value, Reputation.shown_stars(Airport.stars()), "stars drawn")
	var text := (ui("InfoPanel/RatingRow/RatingLabel") as Label).text
	check(text.ends_with("Regional airport"), "rating line with the tier: '%s'" % text)
	hud().show_stats()
	await frames(1)
	var stats := (ui("StatsPanel/Content/SatisfactionLabel") as Label).text
	check(stats.contains("Satisfaction") and stats.contains("On time"), "details in the statistics: '%s'" % stats)
