extends TestCase
## Passenger flow (design doc §8.4).


func test_route_messages_guide_the_player() -> void:
	var flow := Airport.passenger_flow
	check(flow.status_text().contains("build an entrance"), "empty map")
	Airport.paint_zone(cells(Vector2i(8, 31), Vector2i(49, 25)), AirportGrid.Zone.AIRSIDE)
	Airport.paint_walkway(cells(Vector2i(18, 21), Vector2i(28, 7)), true)
	Airport.place_building(type_of(&"entrance"), Vector2i(30, 19), 0)
	check(flow.status_text().contains("check-in"), "after entrance: %s" % flow.status_text())
	Airport.place_building(type_of(&"check_in"), Vector2i(20, 22), 2)
	check(flow.status_text().contains("security"), "after check-in: %s" % flow.status_text())
	Airport.place_building(type_of(&"security"), Vector2i(30, 28), 0)
	check(flow.status_text().contains("gate"), "after security: %s" % flow.status_text())


func test_passengers_flow_and_depart() -> void:
	build_reference_airport()
	var flow := Airport.passenger_flow
	check(flow.route_problem.is_empty(), "reference airport has a complete route: %s" % flow.route_problem)
	var off_walkway := 0
	var landside_after_security := 0
	for step in 2400:  # 4 minutes
		flow.tick(Airport.SIM_STEP)
		for passenger in flow.passengers:
			var cell := Airport.grid.world_to_cell(passenger.position)
			if passenger.state == Passenger.State.WALKING:
				if not Airport.grid.is_walkway(cell):
					off_walkway += 1
				if passenger.goal == BuildingType.Role.GATE and Airport.grid.get_zone(cell) != AirportGrid.Zone.AIRSIDE:
					landside_after_security += 1
	check(flow.departed_count > 30, "passengers departed in 4 minutes: %d" % flow.departed_count)
	check_eq(off_walkway, 0, "walking passengers stay on walkways")
	check_eq(landside_after_security, 0, "airside only through security")


func test_queues_form_at_busy_security() -> void:
	build_reference_airport()
	sim_seconds(240)
	var longest := 0
	for station: Station in Airport.passenger_flow._stations.values():
		if station.role() == BuildingType.Role.SECURITY:
			longest = maxi(longest, station.queue.size() + station.serving.size() - station.serving.count(null))
	check(longest > 0, "someone is at security after 4 minutes")


func test_recovers_after_walkway_cut() -> void:
	build_reference_airport()
	sim_seconds(120)
	Airport.paint_walkway(cells(Vector2i(10, 31), Vector2i(44, 3)), false)
	check(not Airport.passenger_flow.route_problem.is_empty(), "route broken without the airside walkway")
	sim_seconds(10)
	Airport.paint_walkway(cells(Vector2i(10, 31), Vector2i(44, 3)), true)
	sim_seconds(30)
	var stuck := Airport.passenger_flow.passengers.filter(func(p: Passenger) -> bool: return p.state == Passenger.State.STUCK)
	check_eq(stuck.size(), 0, "nobody stuck once the walkway is back")


func test_figures_drawn_near_camera_only() -> void:
	build_reference_airport()
	sim_seconds(90)
	await start_game()
	await frames(2)
	var multimesh := (main.get_node("Passengers").get_child(0) as MultiMeshInstance3D).multimesh
	var walking := Airport.passenger_flow.passengers.filter(func(p: Passenger) -> bool: return p.state != Passenger.State.AT_GATE).size()
	check(multimesh.visible_instance_count > 0, "some figures are drawn")
	check(multimesh.visible_instance_count <= walking, "never more figures than passengers outside gates")


func test_simulation_step_is_cheap() -> void:
	build_reference_airport()
	sim_seconds(180)
	var started := Time.get_ticks_usec()
	sim_seconds(10)
	var per_step_ms := (Time.get_ticks_usec() - started) / 1000.0 / 100.0
	print("INFO simulation step with %d passengers: %.3f ms" % [Airport.passenger_flow.passengers.size(), per_step_ms])
	check(per_step_ms < 2.0, "one simulation step under 2 ms on the Mac: %.3f ms" % per_step_ms)
