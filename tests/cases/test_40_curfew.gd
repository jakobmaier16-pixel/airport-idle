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
	var refused_in_curfew := 0
	var seen: Array[Flight] = []
	var refused := func() -> int:
		var total := 0
		for airline in Airport.airlines.signed:
			total += airline.refused
		return total
	for i in int(8.0 * 3600.0 / Clock.GAME_SECONDS_PER_SECOND / Airport.SIM_STEP):  # until 06:00
		var refused_before: int = refused.call()
		Airport.step(Airport.SIM_STEP)
		if Airport.curfew_at() and Airport.curfew_at(FlightSchedule.ARRIVALS_START):
			refused_in_curfew += refused.call() - refused_before
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.phase >= Flight.Phase.ARRIVING and flight.phase <= Flight.Phase.DEPARTING and Airport.curfew_at():
				if not seen.has(flight):
					seen.append(flight)
					during += 1
	check_eq(during, 0, "no plane moves during the curfew")
	check_eq(refused_in_curfew, 0, "no flights are refused during the curfew itself")
	check(Airport.timetable.slots.all(func(s: TimetableSlot) -> bool: return not Airport.timetable.in_curfew(s.departure_time) or s.state != TimetableSlot.State.FILLED), "no slot in the curfew hours became a flight")


func test_hub_flies_all_night() -> void:
	ShowcaseAirport.build(0.0)
	Airport.progression.tier = Progression.Tier.HUB
	Airport.clock.game_seconds = 0.5 * 3600.0
	sim_seconds(1300)  # until about 06:00
	check(not Airport.curfew_at() or Airport.clock.hour() >= 5.0, "no curfew for a hub")
	check(_movements_between(0.0, 5.0) > 0, "runway movements in the quiet hours: %d" % _movements_between(0.0, 5.0))


func test_hud_shows_curfew() -> void:
	Airport.clock.game_seconds = 2.0 * 3600.0
	await start_game()
	await frames(1)
	check((ui("TopButtons/ClockLabel") as Label).text.ends_with("Curfew"), "clock: '%s'" % (ui("TopButtons/ClockLabel") as Label).text)
	check(Airport.passenger_flow.departures_text().begins_with("Night curfew"), "board explains")
