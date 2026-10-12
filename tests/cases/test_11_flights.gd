extends TestCase
## Flights (design doc §8.5): schedule, boarding, missed and cancelled flights, planes, board.


func _flight_at(gate_number: int) -> Flight:
	# Flights are planned on the schedule's first step.
	if Airport.passenger_flow.schedule.flights.is_empty():
		Airport.step(Airport.SIM_STEP)
	for flight in Airport.passenger_flow.schedule.upcoming():
		if Airport.passenger_flow.gate_number(flight.gate) == gate_number:
			return flight
	return null


func test_one_flight_per_usable_gate() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(1)
	var flights := Airport.passenger_flow.schedule.flights
	check_eq(flights.size(), 2, "one flight planned per gate")
	check(flights[0].gate != flights[1].gate, "different gates")
	check(flights.all(func(f: Flight) -> bool: return f.stand != null), "every flight has a stand")
	check(is_equal_approx(_flight_at(2).departure_time - _flight_at(1).departure_time, FlightSchedule.GATE_STAGGER), "gates are staggered")


func test_three_minutes_between_departures() -> void:
	ShowcaseAirport.build(0.0)
	var departures: Dictionary[int, Array] = {}
	var seen: Dictionary[Flight, bool] = {}
	for i in 7000:  # ~12 minutes
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if not seen.has(flight):
				seen[flight] = true
				var gate := Airport.passenger_flow.gate_number(flight.gate)
				if not departures.has(gate):
					departures[gate] = []
				departures[gate].append(flight.departure_time)
	for gate in departures:
		var times: Array = departures[gate]
		check(times.size() >= 3, "gate %d had several flights: %s" % [gate, times])
		for i in range(1, times.size()):
			check(is_equal_approx(times[i] - times[i - 1], FlightSchedule.INTERVAL), "gate %d: 3 minutes between departures %s" % [gate, times])


func test_passengers_go_to_their_flights_gate() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(170)
	var flow := Airport.passenger_flow
	var at_gates := 0
	for station: Station in flow._stations.values():
		for passenger in station.waiting:
			at_gates += 1
			check(passenger.flight.gate == station.building, "waiting at the gate of their own flight")
	for passenger in flow.passengers:
		if passenger.goal == BuildingType.Role.GATE and passenger.state == Passenger.State.WALKING:
			check(passenger.target == passenger.flight.gate, "walking to the gate of their own flight")
	check(at_gates > 0, "someone is already waiting at a gate")


func test_boarding_only_while_boarding() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at(1)
	sim_seconds(flight.departure_time - FlightSchedule.BOARDING_OPENS - 1.0)
	check_eq(flight.boarded, 0, "nobody boards before boarding opens")
	check_eq(flight.phase, Flight.Phase.AT_STAND, "plane waits at the stand")
	sim_seconds(FlightSchedule.BOARDING_OPENS + 2.0)
	check(flight.boarded > 0, "passengers boarded: %d" % flight.boarded)
	check(flight.phase >= Flight.Phase.DEPARTING, "doors closed at departure time")
	check_eq(flight.boarded + flight.missed, flight.booked, "every booked passenger either flew or missed it")
	check_eq(Airport.passenger_flow.passengers.filter(func(p: Passenger) -> bool: return p.flight == flight).size(), 0, "no passenger of a departed flight is left")


func test_slow_security_makes_passengers_miss_flights() -> void:
	var security := type_of(&"security")
	var normal_time := security.service_time
	security.service_time = 60.0  # a very slow checkpoint
	ShowcaseAirport.build(0.0)
	sim_seconds(270)
	security.service_time = normal_time
	var flow := Airport.passenger_flow
	check(flow.missed_count > 0, "passengers missed their flight: %d" % flow.missed_count)
	check(flow.status_text().contains("Missed: %d" % flow.missed_count), "status shows missed passengers")


func test_unusable_gate_cancels_its_flight() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(60)
	var flight := _flight_at(1)
	var flow := Airport.passenger_flow
	var missed_before := flow.missed_count
	# Remove the walkway in front of gate 1 (gate at x 14..18, front row y 33).
	Airport.paint_walkway(cells(Vector2i(14, 33), Vector2i(5, 1)), false)
	sim_seconds(1)
	check_eq(flight.phase, Flight.Phase.CANCELLED, "flight at the unusable gate is cancelled")
	check_eq(flow.passengers.filter(func(p: Passenger) -> bool: return p.flight == flight).size(), 0, "its passengers left")
	check_eq(flow.missed_count, missed_before, "cancelled is not counted as missed")
	check(_flight_at(2) != null, "gate 2 keeps flying")


func test_departures_board() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(1)
	var text := Airport.passenger_flow.departures_text()
	var lines := text.split("\n")
	check_eq(lines.size(), 2, "one line per upcoming flight")
	check(lines[0].begins_with("AX 101   Gate 1   Scheduled   3:"), "first line: '%s'" % lines[0])
	await start_game()
	await frames(2)
	check_eq((ui("InfoPanel/DeparturesLabel") as Label).text.split("\n").size(), 2, "board shown in the HUD")


func test_plane_parks_nose_in_at_the_stand() -> void:
	ShowcaseAirport.build(0.0)
	var flight := _flight_at(1)
	sim_seconds(flight.departure_time - FlightSchedule.BOARDING_OPENS + 5.0)
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
	sim_seconds(flight.departure_time - FlightSchedule.BOARDING_OPENS + 5.0)  # parked, boarding
	await start_game()
	var stand := flight.stand
	var stand_center := Airport.grid.block_center(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
	# Start south of the plane's tail and walk north, straight into it.
	manager().global_position = stand_center + Vector3(0.0, 0.0, 16.0)
	await physics_frames(10)
	Input.action_press(&"move_up")
	await physics_frames(300)  # 5 s: enough to walk 30 m
	Input.action_release(&"move_up")
	var tail_end_z := stand_center.z + PlaneVisual.LENGTH * 0.5
	check(manager().global_position.z > tail_end_z - 1.0, "manager stopped at the tail: z=%.1f, tail at %.1f" % [manager().global_position.z, tail_end_z])
	# And from the side, into the wing.
	manager().global_position = stand_center + Vector3(-PlaneVisual.WINGSPAN * 0.5 - 4.0, 0.0, 0.5)
	await physics_frames(10)
	Input.action_press(&"move_right")
	await physics_frames(300)
	Input.action_release(&"move_right")
	check(manager().global_position.x < stand_center.x - PlaneVisual.WINGSPAN * 0.5 + 1.0, "manager stopped at the wing tip: x=%.1f" % manager().global_position.x)
