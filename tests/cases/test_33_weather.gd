extends TestCase
## Seasons and weather (design doc §12.2).


func _flight_at_gate(number: int) -> Flight:
	if Airport.passenger_flow.schedule.flights.is_empty():
		Airport.step(Airport.SIM_STEP)
	for flight in Airport.passenger_flow.schedule.upcoming():
		if Airport.passenger_flow.gate_number(flight.gate) == number:
			return flight
	return null


func test_seasons() -> void:
	check_eq(Weather.season_of(1), Weather.Season.SPRING, "a new airport starts in spring")
	check_eq(Weather.season_of(3), Weather.Season.SUMMER, "two days per season")
	check_eq(Weather.season_of(7), Weather.Season.WINTER, "winter on day 7")
	check_eq(Weather.season_of(9), Weather.Season.SPRING, "and round again")
	check(Weather.demand_factor("Holiday", Weather.Season.SUMMER) > 1.3, "summer holidays")
	check(Weather.demand_factor("Holiday", Weather.Season.WINTER) < 0.8, "quiet winter holidays")


func test_events_come_and_go() -> void:
	var weather := Airport.weather
	weather.automatic = true
	weather.rng.seed = 3
	sim_seconds(Weather.EVENT_EVERY_MIN + 1.0)
	check(weather.kind != Weather.Kind.CLEAR, "an event started")
	check(weather.kind != Weather.Kind.SNOW, "no snow in spring")
	sim_seconds(weather.time_left + 1.0)
	check_eq(weather.kind, Weather.Kind.CLEAR, "and passed")
	check(weather.next_event_in >= Weather.EVENT_EVERY_MIN - 2.0, "the next one is minutes away")


func test_storm_stops_ground_work() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at_gate(1)
	sim_seconds(flight.departure_time - Airport.passenger_flow.time - 30.0)
	check_eq(flight.phase, Flight.Phase.BOARDING, "boarding")
	var boarded := flight.boarded
	var late_before := Airport.reputation.late_departures
	Airport.weather.start(Weather.Kind.STORM)
	sim_seconds(60)
	check_eq(flight.boarded, boarded, "nobody boards in a thunderstorm")
	check_eq(flight.phase, Flight.Phase.BOARDING, "the plane stays")
	check(flight.weather_delay > 55.0, "a weather delay: %.0f s" % flight.weather_delay)
	sim_seconds(Weather.DURATIONS[Weather.Kind.STORM])
	check(flight.phase >= Flight.Phase.DEPARTING, "it leaves after the storm")
	check_eq(Airport.reputation.late_departures, late_before, "weather delays don't count against the airport")


func test_fog_holds_landings_and_stands_are_never_shared() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at_gate(2)
	sim_seconds(flight.departure_time - Airport.passenger_flow.time - FlightSchedule.PLANE_ARRIVES - 5.0)
	Airport.weather.start(Weather.Kind.FOG)
	sim_seconds(30)
	check_eq(flight.phase, Flight.Phase.SCHEDULED, "the plane can't land in fog")
	check(flight.weather_delay > 20.0, "held: %.0f s" % flight.weather_delay)
	# Knock-on: whatever the weather does, one plane per stand.
	var shared := 0
	for i in 6000:
		Airport.step(Airport.SIM_STEP)
		if i % 1500 == 0:
			Airport.weather.start(Weather.Kind.STORM)
		var at_gate: Dictionary[Building, int] = {}
		for other in Airport.passenger_flow.schedule.flights:
			if other.phase >= Flight.Phase.ARRIVING and other.phase <= Flight.Phase.DEPARTING:
				at_gate[other.gate] = at_gate.get(other.gate, 0) + 1
		for gate in at_gate:
			if at_gate[gate] > 1:
				shared += 1
	check_eq(shared, 0, "never two planes at one gate")


func test_snow_needs_de_icing() -> void:
	var departure_delay := func(with_pad: bool) -> float:
		ShowcaseAirport.build(0.0)
		if not with_pad:
			for building in Airport.buildings.duplicate():
				if building.type.id == &"deicing_pad":
					Airport.demolish(building)
		var flight := _flight_at_gate(1)
		sim_seconds(flight.departure_time - Airport.passenger_flow.time - 10.0)
		Airport.weather.start(Weather.Kind.SNOW)
		sim_seconds(40)
		return flight.weather_delay
	var without_pad: float = departure_delay.call(false)
	var with_pad: float = departure_delay.call(true)
	check(absf(without_pad - Weather.DEICING_SECONDS) < 0.5, "20 s of de-icing: %.1f" % without_pad)
	check(absf(with_pad - Weather.DEICING_SECONDS_WITH_PAD) < 0.5, "5 s with a pad: %.1f" % with_pad)


func test_weather_is_saved() -> void:
	Airport.weather.start(Weather.Kind.FOG)
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check_eq(Airport.weather.kind, Weather.Kind.FOG, "still foggy")


func test_weather_shows() -> void:
	await start_game()
	var layer := main.get_node("Weather") as WeatherLayer
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	Airport.weather.start(Weather.Kind.RAIN)
	await frames(1)
	check(layer.is_raining(), "rain falls")
	check((ui("TopButtons/ClockLabel") as Label).text.ends_with("Spring · Rain"), "named in the HUD")
	Airport.weather.start(Weather.Kind.FOG)
	await frames(1)
	check(environment.fog_enabled and not layer.is_raining(), "fog")
	Airport.weather.start(Weather.Kind.SNOW)
	await frames(1)
	check(layer.is_snowing() and not environment.fog_enabled, "snow")
	check(hud().notice_text().begins_with("Snow"), "explained: '%s'" % hud().notice_text())
