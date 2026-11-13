extends TestCase
## Demolishing (design doc §7.6): 50 % refund, any time, also during operation.


func _building(role: BuildingType.Role, index: int = 0) -> Building:
	var found := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == role)
	return found[index] if index < found.size() else null


func test_refund_and_removal() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), at(Vector2i(10, 10)), 0)
	Airport.staff_fully(check_in)
	var balance := Airport.economy.balance
	check_eq(Airport.demolish_refund(check_in), 1500.0, "half of €3,000")
	check(Airport.demolish(check_in), "demolished")
	check_eq(Airport.economy.balance, balance + 1500.0, "€1,500 refunded")
	check(not Airport.buildings.has(check_in), "gone from the list")
	check(Airport.grid.is_empty(at(Vector2i(11, 11))), "its cells are free")
	check_eq(Airport.staff.size(), 0, "its staff were dismissed")
	check_eq(Airport.running_cost_per_minute(), 0.0, "no running costs or salaries left")
	check(Airport.can_place(type_of(&"check_in"), at(Vector2i(10, 10)), 0), "the spot can be built on again")


func test_upgrades_are_not_refunded() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), at(Vector2i(10, 10)), 0)
	Airport.start_upgrade(check_in)
	check_eq(Airport.demolish_refund(check_in), 1500.0, "only half the build price, not the upgrade")


func test_passengers_go_to_another_station() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(150)
	var check_in := _building(BuildingType.Role.CHECK_IN, 0)
	Airport.demolish(check_in)
	sim_seconds(60)
	var flow := Airport.passenger_flow
	var stuck := flow.passengers.filter(func(p: Passenger) -> bool: return p.state == Passenger.State.STUCK)
	check_eq(stuck.size(), 0, "nobody is stuck after a check-in was demolished")
	check(flow.passengers.all(func(p: Passenger) -> bool: return p.target != check_in), "nobody heads for the demolished check-in")
	check(flow.station_for(check_in) == null, "its station is gone")


func test_demolished_gate_cancels_flights() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(200)
	var gate := _building(BuildingType.Role.GATE, 0)
	var flights := Airport.passenger_flow.schedule.flights.filter(func(f: Flight) -> bool: return f.gate == gate)
	check(not flights.is_empty(), "the gate had flights")
	Airport.demolish(gate)
	sim_seconds(1)
	check(flights.all(func(f: Flight) -> bool: return f.phase == Flight.Phase.CANCELLED), "its flights are cancelled")
	check_eq(Airport.passenger_flow.missed_count, 0, "cancelled is not missed")
	sim_seconds(300)
	check(Airport.passenger_flow.schedule.flights.all(func(f: Flight) -> bool: return f.gate != gate), "no new flights at the demolished gate")
	check(Airport.passenger_flow.departed_count > 0, "the other gate keeps flying")


func test_demolished_stand_stops_its_gate() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(1)
	var stand := _building(BuildingType.Role.AIRCRAFT_STAND, 0)
	Airport.demolish(stand)
	sim_seconds(1)
	var gate := _building(BuildingType.Role.GATE, 0)
	check_eq(Airport.connection_problem(gate.type, gate.origin_cell, gate.rotation_steps), "Needs an aircraft stand behind", "gate lost its stand")
	check(Airport.passenger_flow.schedule.flights.all(func(f: Flight) -> bool: return f.gate != gate), "no flights at that gate")


func test_demolishing_security_makes_the_airside_landside() -> void:
	build_basic_terminal()
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 32))), AirportGrid.Zone.AIRSIDE, "airside behind security")
	Airport.demolish(_building(BuildingType.Role.SECURITY))
	check_eq(Airport.grid.get_zone(at(Vector2i(20, 32))), AirportGrid.Zone.LANDSIDE, "landside without it")


func test_demolish_by_touch() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	await open_build_view()
	await show_whole_map()
	var shop := _building(BuildingType.Role.SHOP, 0)
	var balance := Airport.economy.balance
	var drawn := (main.get_node("Buildings") as BuildingLayer).visual_count()
	await press(ui("BuildMenu/PaintButtons/DemolishToolButton"))
	var demolish := ui("ToolPanel/ToolBar/DemolishButton") as Button
	check(demolish.visible and demolish.disabled, "Demolish waits for a selection")
	tap(screen_of_cell(shop.origin_cell + Vector2i(1, 1)))
	await frames(1)
	var hint := (ui("ToolPanel/HintLabel") as Label).text
	check_eq(hint, "Demolish Shop · refund €1,750", "hint names building and refund")
	check(build_mode()._paint_preview.visible, "the building is marked in red")
	await press(demolish)
	await frames(1)
	check(not Airport.buildings.has(shop), "shop demolished")
	check_eq(Airport.economy.balance, balance + 1750.0, "refund paid")
	check_eq((main.get_node("Buildings") as BuildingLayer).visual_count(), drawn - 1, "its 3D box is gone")
	check(build_mode()._tool == BuildMode.Tool.DEMOLISH, "tool stays open for the next building")
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	check(ui("BuildMenu").visible, "Done closes the tool")


func test_save_after_demolish() -> void:
	ShowcaseAirport.build(0.0)
	Airport.demolish(_building(BuildingType.Role.SHOP, 0))
	var count := Airport.buildings.size()
	var staff := Airport.staff.size()
	var state := Airport.save_state()
	Airport.load_state(state)
	check_eq(Airport.buildings.size(), count, "buildings after demolishing are saved")
	check_eq(Airport.staff.size(), staff, "staff still match their workplaces")
