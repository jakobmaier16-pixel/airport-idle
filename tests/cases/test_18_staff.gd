extends TestCase
## Staff (design doc §9.1).


func _building(role: BuildingType.Role) -> Building:
	for building in Airport.buildings:
		if building.type.role == role:
			return building
	return null


func test_no_staff_no_service() -> void:
	ShowcaseAirport.build(0.0)
	var security := _building(BuildingType.Role.SECURITY)
	while Airport.dismiss(security):
		pass
	var station := Airport.passenger_flow.station_for(security)
	sim_seconds(240)
	check_eq(station.busyness() - station.queue.size(), 0, "nobody is served at an unstaffed security")
	check(station.queue.size() > 0, "the queue grows instead")


func test_open_counters_follow_staff() -> void:
	ShowcaseAirport.build(0.0)
	var check_in := Airport.passenger_flow.stations()[1].building  # check-in 2 (3 counters)
	while Airport.dismiss(check_in):
		pass
	Airport.hire(check_in)
	var station := Airport.passenger_flow.station_for(check_in)
	var most_serving := 0
	for i in 2400:
		Airport.step(Airport.SIM_STEP)
		most_serving = maxi(most_serving, station.serving.size() - station.serving.count(null))
	check_eq(most_serving, 1, "one employee runs one counter")


func test_hiring_limit_and_salary() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), at(Vector2i(10, 10)), 0)
	var cost := Airport.running_cost_per_minute()
	check(Airport.hire(check_in) != null, "hired one")
	check_eq(Airport.running_cost_per_minute(), cost + 8.0, "€8/min salary")
	Airport.staff_fully(check_in)
	check_eq(Airport.staff_at(check_in).size(), 3, "one per counter")
	check_eq(Airport.hire_problem(check_in), "Every counter is staffed", "no fourth agent for 3 counters")
	check(Airport.hire(check_in) == null, "hire refused")
	Airport.start_upgrade(check_in)
	check_eq(Airport.hire_problem(check_in), "", "an upgrade adds a counter that needs staff")
	check(Airport.dismiss(check_in), "dismissed one")
	check_eq(Airport.staff_at(check_in).size(), 2, "two left")


func test_gates_need_no_staff() -> void:
	var gate := Airport.place_building(type_of(&"gate"), at(Vector2i(10, 40)), 0)
	check(not Airport.needs_staff(gate), "gates run without staff for now")
	check_eq(Airport.hire_problem(gate), "No staff needed here", "hint")


func test_experience_makes_staff_faster() -> void:
	var employee := Employee.new()
	employee.workplace = Building.new(type_of(&"check_in"), Vector2i.ZERO, 0)
	check_eq(employee.level_name(), "New", "starts new")
	check_eq(employee.time_factor(), Employee.NEW_TIME_FACTOR, "25 %% slower when new")
	employee.served[BuildingType.Role.CHECK_IN] = 90
	check_eq(employee.level_name(), "Experienced", "after 90 passengers")
	employee.served[BuildingType.Role.CHECK_IN] = 500
	check_eq(employee.level_name(), "Expert", "expert")
	check_eq(employee.time_factor(), Employee.EXPERT_TIME_FACTOR, "15 %% faster as an expert")
	employee.workplace = Building.new(type_of(&"security"), Vector2i.ZERO, 0)
	check_eq(employee.level_name(), "New", "experience is per station type: new at security")


func test_experience_grows_while_working() -> void:
	ShowcaseAirport.build(0.0)
	var before := 0
	for employee in Airport.staff:
		before += employee.experience()
	sim_seconds(300)
	var after := 0
	for employee in Airport.staff:
		after += employee.experience()
	check(after > before + 20, "staff gained experience: %d -> %d" % [before, after])


func test_staff_saved_and_loaded() -> void:
	ShowcaseAirport.build(0.0)
	var names := Airport.staff.map(func(e: Employee) -> String: return e.name)
	var experience := Airport.staff.map(func(e: Employee) -> int: return e.experience())
	var state := Airport.save_state()
	Airport.load_state(state)
	check_eq(Airport.staff.map(func(e: Employee) -> String: return e.name), names, "names restored")
	check_eq(Airport.staff.map(func(e: Employee) -> int: return e.experience()), experience, "experience restored")
	check(Airport.staff.all(func(e: Employee) -> bool: return Airport.buildings.has(e.workplace)), "workplaces restored")


func test_old_save_gets_staff() -> void:
	ShowcaseAirport.build(0.0)
	var state := Airport.save_state()
	state.erase("staff")
	Airport.load_state(state)
	for building in Airport.buildings:
		if Airport.needs_staff(building):
			check_eq(Airport.staff_at(building).size(), building.service_slots(), "%s staffed after loading an old save" % building.type.display_name)


func test_panel_hire_and_dismiss() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), at(Vector2i(28, 20)), 0)
	await start_game()
	await frames(1)
	var label: Label3D = main.get_node("Buildings")._hints[check_in]
	Airport.paint_walkway(cells(at(Vector2i(28, 19)), Vector2i(5, 1)), true)
	await frames(1)
	check(label.visible and label.text == "Needs staff", "unstaffed station says so")
	# Managing happens on the spot: walk over first (design doc §15.1).
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(30, 17)))
	await physics_frames(2)
	hud().show_station(check_in)
	await frames(1)
	check(ui("StationPanel/Content/StaffButtons").visible, "staff buttons shown")
	var hire := ui("StationPanel/Content/StaffButtons/HireButton") as Button
	check_eq(hire.text, "Hire · €8/min", "hire button names the salary")
	await press(hire)
	await frames(1)
	check_eq(Airport.staff_at(check_in).size(), 1, "hired through the panel")
	check(label.text != "Needs staff", "staff hint gone once staffed")
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("Staff: 1 / 3 counters"), "panel shows staffing: '%s'" % info)
	check(info.contains("· New"), "panel lists the employee's level")
	await press(ui("StationPanel/Content/StaffButtons/DismissButton"))
	check_eq(Airport.staff_at(check_in).size(), 0, "dismissed through the panel")


func test_showcase_is_staffed() -> void:
	ShowcaseAirport.build()
	for building in Airport.buildings:
		if Airport.needs_staff(building):
			check(Airport.staff_at(building).size() >= building.service_slots() - 1, "%s staffed" % building.type.display_name)
	check(Airport.passenger_flow.departed_count >= 0 and Airport.passenger_flow.missed_count == 0, "no missed flights")
