extends TestCase
## Flights (design doc §8.5): schedule, departures, cancelled flights, planes, board.


func _flight_at(gate_number: int) -> Flight:
	# Flights appear when their timetable slot's arrivals window opens.
	return first_flight(gate_number)


func test_flights_come_from_the_timetable() -> void:
	ShowcaseAirport.build(0.0)
	Airport.step(Airport.SIM_STEP)  # the first step plans today
	var slots_before: int = Airport.timetable.slots.size()
	check(slots_before > 0, "today's slots are planned: %d" % slots_before)
	sim_seconds(900.0)
	var flights := Airport.schedule.flights
	check(flights.size() >= 2, "several flights planned within 15 minutes: %d" % flights.size())
	var filled: Array[TimetableSlot] = Airport.timetable.slots.filter(func(s: TimetableSlot) -> bool: return s.state == TimetableSlot.State.FILLED)
	check(filled.size() >= flights.size(), "every flight came from a slot (%d slots, %d flights)" % [filled.size(), flights.size()])
	check(flights.all(func(f: Flight) -> bool: return f.stand != null), "every flight has a stand")
	var numbers := {}
	for flight in flights:
		check(not numbers.has(flight.number), "flight numbers are unique: %s" % flight.number)
		numbers[flight.number] = true
	var gates := {}
	for flight in flights:
		gates[flight.gate] = true
	check(gates.size() >= 2, "flights are spread over several gates: %d" % gates.size())


func test_a_gate_needs_a_turnaround_between_departures() -> void:
	ShowcaseAirport.build(0.0)
	var departures: Dictionary[int, Array] = {}
	var seen: Dictionary[Flight, bool] = {}
	for i in 7000:  # ~12 minutes
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if not seen.has(flight):
				seen[flight] = true
				var gate := Airport.gate_number(flight.gate)
				if not departures.has(gate):
					departures[gate] = []
				departures[gate].append(flight.departure_time)
	check(departures.size() >= 2, "several gates flew: %d" % departures.size())
	for gate in departures:
		var times: Array = departures[gate]
		for i in range(1, times.size()):
			# The planner only gives a slot to a gate that is free for a turnaround before it.
			check(times[i] - times[i - 1] >= FlightSchedule.INTERVAL - 0.001, "gate %d: departures at least a turnaround apart %s" % [gate, times])


func test_a_flight_goes_through_its_phases_and_departs() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at(1)
	sim_seconds(flight.departure_time - Airport.sim_time - FlightSchedule.BOARDING_OPENS - 1.0)
	check_eq(flight.phase, Flight.Phase.AT_STAND, "the plane waits at the stand")
	sim_seconds(FlightSchedule.BOARDING_OPENS - 1.0)
	check_eq(flight.phase, Flight.Phase.BOARDING, "the last stretch before the doors close")
	var departures := Airport.reputation.departures
	sim_seconds(3.0)
	check(flight.phase >= Flight.Phase.DEPARTING, "doors closed at departure time")
	check_eq(Airport.reputation.departures, departures + 1, "the departure is counted")


func test_unusable_gate_cancels_its_flight() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(60)
	var flight := _flight_at(1)
	# Remove the walkway in front of gate 1 (gate at x 14..18, front row y 33).
	Airport.paint_walkway(cells(at(Vector2i(14, 33)), Vector2i(5, 1)), false)
	sim_seconds(1)
	check_eq(flight.phase, Flight.Phase.CANCELLED, "flight at the unusable gate is cancelled")
	check(_flight_at(2) != null, "gate 2 keeps flying")


func test_departures_board() -> void:
	ShowcaseAirport.build(0.0)
	check(first_flight() != null, "a flight is planned")
	sim_seconds(600.0)
	var flights := Airport.schedule.upcoming()
	var text := Airport.schedule.departures_text()
	var lines := text.split("\n")
	check_eq(lines.size(), mini(flights.size(), 4), "one line per upcoming flight (at most four)")
	var columns := lines[0].split("   ")
	var airline_codes := Airlines.CATALOG.types.map(func(t: AirlineType) -> String: return t.code)
	check(airline_codes.has(columns[0].left(2)), "flight number with airline code: '%s'" % columns[0])
	check(columns[1] == "Cargo" or columns[1].begins_with("Gate "), "gate: '%s'" % columns[1])
	check(not columns[2].is_empty(), "route type: '%s'" % columns[2])
	check(columns[3] in ["Scheduled", "Plane arriving", "At stand", "Boarding", "Delayed", "Departed"], "status: '%s'" % columns[3])
	var regex := RegEx.create_from_string("^\\d+:\\d\\d$")
	check(regex.search(columns[4]) != null, "time to departure: '%s'" % columns[4])
	await start_game()
	await frames(2)
	check_eq((ui("InfoPanel/DeparturesLabel") as Label).text.split("\n").size(), lines.size(), "board shown in the HUD")


func test_plane_parks_nose_in_at_the_stand() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at(1)
	sim_seconds(flight.departure_time - Airport.sim_time - FlightSchedule.BOARDING_OPENS + 5.0)
	await start_game()
	await frames(2)
	var layer := main.get_node("Planes") as PlaneLayer
	check(layer.plane_count() >= 1, "a plane is drawn")
	var plane := layer._planes[flight] as Node3D
	var stand := flight.stand
	var stand_center := Airport.grid.block_center(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
	check(plane.global_position.distance_to(stand_center) < 0.5, "parked on the stand center")
	var gate := flight.gate
	var gate_center := Airport.grid.block_center(gate.origin_cell, Building.rotated_size(gate.type.footprint, gate.rotation_steps))
	var nose := -plane.global_basis.z
	check(nose.dot((gate_center - stand_center).normalized()) > 0.99, "nose points at the gate")


func test_plane_is_solid() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at(1)
	sim_seconds(flight.departure_time - Airport.sim_time - FlightSchedule.BOARDING_OPENS + 5.0)  # parked, boarding
	await start_game()
	var stand := flight.stand
	var stand_center := Airport.grid.block_center(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
	# Start south of the plane's tail and walk north, straight into it.
	manager().global_position = stand_center + Vector3(0.0, 0.0, 24.0)
	await physics_frames(10)
	Input.action_press(&"move_up")
	await physics_frames(300)  # 5 s: enough to walk 30 m
	Input.action_release(&"move_up")
	var size := PlaneVisual.size_for(flight)
	var tail_end_z := stand_center.z + PlaneVisual.LENGTH * size * 0.5
	check(manager().global_position.z > tail_end_z - 1.0, "manager stopped at the tail: z=%.1f, tail at %.1f" % [manager().global_position.z, tail_end_z])
	# And from the side, into the wing.
	manager().global_position = stand_center + Vector3(-PlaneVisual.WINGSPAN * size * 0.5 - 4.0, 0.0, 0.5)
	await physics_frames(10)
	Input.action_press(&"move_right")
	await physics_frames(300)
	Input.action_release(&"move_right")
	check(manager().global_position.x < stand_center.x - PlaneVisual.WINGSPAN * size * 0.5 + 1.0, "manager stopped at the wing tip: x=%.1f" % manager().global_position.x)
