extends TestCase
## Managing on the spot (design doc §15.1).


func _building(role: BuildingType.Role) -> Building:
	for building in Airport.buildings:
		if building.type.role == role:
			return building
	return null


func _stand_near(building: Building, extra_meters: float) -> void:
	var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
	var center := Airport.grid.block_center(building.origin_cell, size)
	# South of the building, `extra_meters` beyond its edge.
	manager().global_position = center + Vector3(0.0, 0.0, size.y * Airport.CELL_SIZE * 0.5 + extra_meters)
	manager_camera().snap_to_target()
	await physics_frames(2)


func test_distance_rules() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), Vector2i(20, 20), 0)
	check_eq(Airport.manage_problem(check_in), "Walk here to manage", "nobody there")
	var center := Airport.grid.block_center(check_in.origin_cell, Vector2i(5, 3))
	Airport.manager_position = center
	check_eq(Airport.distance_to_building(check_in, center), 0.0, "inside counts as 0 m")
	check(Airport.is_manager_near(check_in), "standing in the hall at the counters")
	Airport.manager_position = center + Vector3(5.0 + 20.0, 0.0, 0.0)  # 20 m east of its edge
	check_eq(Airport.manage_problem(check_in), "Walk closer to manage (20 m away)", "too far")
	check(not Airport.is_manager_near(check_in), "no presence effect from there")


func test_panel_needs_the_manager_nearby() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var security := _building(BuildingType.Role.SECURITY)
	security.level = 2  # so there is an upgrade left to buy
	await _stand_near(security, 30.0)
	hud().show_station(security)
	await frames(1)
	var upgrade := ui("StationPanel/Content/UpgradeButton") as Button
	var dismiss := ui("StationPanel/Content/StaffButtons/DismissButton") as Button
	check(upgrade.disabled and upgrade.text.begins_with("Walk closer"), "upgrade needs the manager: '%s'" % upgrade.text)
	check(dismiss.disabled, "dismissing too")
	var staff_before := Airport.staff_at(security).size()
	await press(dismiss)
	check_eq(Airport.staff_at(security).size(), staff_before, "nothing happens from far away")

	await _stand_near(security, 3.0)
	await frames(1)
	check(not upgrade.disabled, "close by, the upgrade works")
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("You're here"), "the panel says the manager helps: '%s'" % info)
	await press(upgrade)
	check(security.is_upgrading(), "upgrade started on the spot")


func test_presence_speeds_up_staff() -> void:
	# The same passenger served twice with the same random numbers: once alone, once with the
	# manager there. The service time must be exactly 10 % shorter (no luck involved).
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	var security := _building(BuildingType.Role.SECURITY)
	var station := flow.station_for(security)
	var service_time := func(manager_near: bool) -> float:
		Airport.manager_position = Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) if manager_near else Airport.NOBODY_THERE
		var passenger := Passenger.new()
		passenger.position = Airport.grid.cell_to_world(Vector2i(32, 27))
		station.queue.append(passenger)
		flow._rng.seed = 42
		flow._tick_station(station, Airport.SIM_STEP)
		var slot := station.serving.find(passenger)
		var seconds: float = station.service_left[slot]
		station.serving[slot] = null
		return seconds
	var alone: float = service_time.call(false)
	var with_manager: float = service_time.call(true)
	check(alone > 0.0, "the passenger was served")
	check(is_equal_approx(with_manager, alone * PassengerFlow.PRESENCE_TIME_FACTOR), "10 %% faster: %.3f vs %.3f s" % [with_manager, alone])


func test_hint_shows_presence() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var security := _building(BuildingType.Role.SECURITY)
	await _stand_near(security, 2.0)
	await frames(1)
	var hint: Label3D = main.get_node("Buildings")._hints[security]
	check(hint.visible and hint.text.begins_with("Manager here"), "hint above the station: '%s'" % hint.text)


func test_manager_position_follows_the_manager() -> void:
	await start_game()
	await physics_frames(2)
	check(Airport.manager_position.distance_to(manager().global_position) < 0.01, "the simulation knows where the manager is")
