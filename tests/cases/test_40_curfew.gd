extends TestCase
## Night curfew (design doc §12.4).


func _movements_between(from_hour: float, to_hour: float) -> int:
	var count := 0
	for booking: Array in Airport.passenger_flow.schedule.runway_bookings:
		var hour := Airport.clock.hour_at(booking[1] - Airport.passenger_flow.time)
		if hour >= from_hour and hour < to_hour:
			count += 1
	return count


func test_no_flights_at_night() -> void:
	ShowcaseAirport.build(0.0)
	Airport.progression.tier = Progression.Tier.NATIONAL
	Airport.clock.game_seconds = 22.0 * 3600.0
	var during := 0
	var seen: Array[Flight] = []
	for i in int(8.0 * 3600.0 / Clock.GAME_SECONDS_PER_SECOND / Airport.SIM_STEP):  # until 06:00
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.phase >= Flight.Phase.ARRIVING and flight.phase <= Flight.Phase.DEPARTING and Airport.curfew_at():
				if not seen.has(flight):
					seen.append(flight)
					during += 1
	check_eq(during, 0, "no plane moves during the curfew")
	check(Airport.airlines.signed.all(func(a: Airline) -> bool: return a.refused == 0), "no refused flights because of it")


func test_hub_flies_all_night() -> void:
	ShowcaseAirport.build(0.0)
	Airport.progression.tier = Progression.Tier.HUB
	Airport.clock.game_seconds = 0.5 * 3600.0
	sim_seconds(600)
	check(not Airport.curfew_at(), "no curfew for a hub")
	check(Airport.passenger_flow.departed_count > 0, "flights at night: %d passengers" % Airport.passenger_flow.departed_count)


func test_hud_shows_curfew() -> void:
	Airport.clock.game_seconds = 2.0 * 3600.0
	await start_game()
	await frames(1)
	check((ui("TopButtons/ClockLabel") as Label).text.ends_with("Curfew"), "clock: '%s'" % (ui("TopButtons/ClockLabel") as Label).text)
	check(Airport.passenger_flow.departures_text().begins_with("Night curfew"), "board explains")
