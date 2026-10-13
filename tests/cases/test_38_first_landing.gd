extends TestCase
## A new airline's first landing (design doc §14).


func _sign_new_airline_and_wait_for_landing() -> Flight:
	var airlines := Airport.airlines
	airlines.signed.clear()
	var newcomer := airlines.sign_deal(Airlines.CATALOG.find(&"norvane"), 20, 20.0)
	for i in 4000:
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if flight.airline == newcomer and flight.phase == Flight.Phase.ARRIVING:
				return flight
	return null


func test_cutscene_follows_the_first_landing() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var flight := _sign_new_airline_and_wait_for_landing()
	check(flight != null, "the new airline's plane arrives")
	await frames(3)
	var cinematic := main.get_node("CinematicCamera") as CinematicCamera
	check(cinematic.is_playing() and cinematic.current, "the cutscene camera follows it")
	check(hud().notice_text().contains("First landing"), "notice: '%s'" % hud().notice_text())
	check(not manager().input_enabled, "the manager waits")
	tap(screen_size() * 0.5)
	await frames(1)
	check(not cinematic.is_playing(), "a tap ends it")
	check(manager_camera().current, "back to the manager view")
	check(manager().input_enabled, "and walking again")


func test_only_once_and_not_for_the_starter() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var airline: Airline = Airport.airlines.signed[0]
	check(airline.first_landing_seen, "showcase airlines are old friends")
	var flight := _sign_new_airline_and_wait_for_landing()
	await frames(3)
	var cinematic := main.get_node("CinematicCamera") as CinematicCamera
	cinematic.stop()
	check(flight.airline.first_landing_seen, "remembered")
	# The next arrival of the same airline: no second cutscene.
	var next: Flight = null
	for i in 4000:
		Airport.step(Airport.SIM_STEP)
		for other in Airport.passenger_flow.schedule.flights:
			if other.airline == flight.airline and other != flight and other.phase == Flight.Phase.ARRIVING:
				next = other
		if next != null:
			break
	await frames(3)
	check(next != null and not cinematic.is_playing(), "only the first landing")
