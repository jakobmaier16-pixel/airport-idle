extends TestCase
## Security incidents (design doc §12.3).


func _security() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.SECURITY:
			return building
	return null


func test_unattended_bag_closes_the_station() -> void:
	ShowcaseAirport.build(0.0)
	var security := _security()
	var station := Airport.passenger_flow.station_for(security)
	sim_seconds(150)  # passengers are coming
	var served_before := 0
	for employee in Airport.staff_at(security):
		served_before += employee.served.get(BuildingType.Role.SECURITY, 0)
	Airport.start_incident(security)
	sim_seconds(20)  # those already in the lanes finish
	var served_after_lanes := 0
	for employee in Airport.staff_at(security):
		served_after_lanes += employee.served.get(BuildingType.Role.SECURITY, 0)
	sim_seconds(40)
	var served_later := 0
	for employee in Airport.staff_at(security):
		served_later += employee.served.get(BuildingType.Role.SECURITY, 0)
	check_eq(served_later, served_after_lanes, "nobody new is served while it's closed")
	check(station.queue.size() > 3, "the queue grows: %d" % station.queue.size())
	sim_seconds(Airport.INCIDENT_SECONDS)
	check(not security.is_closed(), "cleared after 90 seconds")
	var served_end := 0
	for employee in Airport.staff_at(security):
		served_end += employee.served.get(BuildingType.Role.SECURITY, 0)
	check(served_end > served_later, "and serving again")


func test_manager_speeds_up_clearing() -> void:
	ShowcaseAirport.build(0.0)
	var security := _security()
	Airport.start_incident(security)
	Airport.manager_position = Airport.grid.block_center(security.origin_cell, Vector2i(5, 3))
	sim_seconds(Airport.INCIDENT_SECONDS / Airport.INCIDENT_MANAGER_SPEEDUP + 0.5)
	check(not security.is_closed(), "three times as fast with the manager there")


func test_incidents_happen_now_and_then() -> void:
	ShowcaseAirport.build(0.0)
	Airport.incidents_automatic = true
	var started: Array[Building] = []
	Airport.incident_started.connect(func(b: Building) -> void: started.append(b))
	sim_seconds(Airport.INCIDENT_EVERY_MIN + 1.0)
	check_eq(started.size(), 1, "one incident after 12 minutes")
	check(started.size() == 1 and Airport.needs_staff(started[0]), "at a staffed checkpoint")


func test_hint_and_notice() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var security := _security()
	Airport.start_incident(security)
	await frames(1)
	var hint: Label3D = main.get_node("Buildings")._hints[security]
	check(hint.visible and hint.text.begins_with("Unattended bag!"), "hint: '%s'" % hint.text)
	check(hud().notice_text().begins_with("Unattended bag at Security"), "notice: '%s'" % hud().notice_text())


func test_closure_is_saved() -> void:
	ShowcaseAirport.build(0.0)
	Airport.start_incident(_security())
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check(_security().is_closed(), "still closed after loading")
