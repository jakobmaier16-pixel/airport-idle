extends TestCase
## Shops and cafés (design doc §8.6).


func _shops() -> Array[Station]:
	var result: Array[Station] = []
	for station in Airport.passenger_flow.stations():
		if station.role() == BuildingType.Role.SHOP:
			result.append(station)
	return result


func test_passengers_visit_shops_and_earn_money() -> void:
	ShowcaseAirport.build(0.0)
	var most_inside := 0
	var over_capacity := false
	for i in 4000:  # ~6.5 minutes
		Airport.step(Airport.SIM_STEP)
		for shop in _shops():
			most_inside = maxi(most_inside, shop.waiting.size())
			if shop.waiting.size() > shop.building.type.customer_capacity:
				over_capacity = true
	check(most_inside > 0, "customers went into the shops")
	check(not over_capacity, "never more customers than the capacity")
	for shop in _shops():
		var income := shop.income_in_window(Airport.passenger_flow.time)
		check(income > 5.0, "%s earned money: %s" % [shop.building.type.display_name, Economy.format(income)])


func test_shopping_does_not_cause_missed_flights() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(600)
	check_eq(Airport.passenger_flow.missed_count, 0, "final call: nobody misses a flight because of shopping")


func test_customers_leave_by_final_call() -> void:
	ShowcaseAirport.build(0.0)
	var late := 0
	for i in 4000:
		Airport.step(Airport.SIM_STEP)
		for shop in _shops():
			for customer in shop.waiting:
				if Airport.passenger_flow.time > customer.leave_shop_by + Airport.SIM_STEP:
					late += 1
	check_eq(late, 0, "no customer stays past their leave-by time")


func test_landside_cafe_gets_customers_before_security() -> void:
	# Only early passengers have time for a café before security, and only some of them go.
	# To test without luck, everyone who has the time goes (shop chance x landside factor = 1).
	var types: Array[PassengerType] = [FlightSchedule.FAMILY, FlightSchedule.LOW_COST, FlightSchedule.BUSINESS]
	var chances := types.map(func(t: PassengerType) -> float: return t.shop_chance)
	for type in types:
		type.shop_chance = 1.0 / PassengerFlow.DEPARTURE.step_at(1).detour_chance_factor
	ShowcaseAirport.build(0.0)
	# A café in the landside hall (rows 21..27), front facing the hall.
	var cafe := Airport.place_building(type_of(&"cafe"), Vector2i(26, 24), 2)
	check(cafe != null, "café placed landside")
	var station := Airport.passenger_flow.station_for(cafe)
	var visited := false
	for i in 9000:  # 15 minutes
		Airport.step(Airport.SIM_STEP)
		if not station.waiting.is_empty():
			visited = true
			for customer in station.waiting:
				check_eq(customer.recipe.role_at(customer.step), BuildingType.Role.SECURITY, "landside customers go on to security")
			break
	for i in types.size():
		types[i].shop_chance = chances[i]
	check(visited, "passengers sat in the landside café before security")


func test_zone_rules_for_shops() -> void:
	check_eq(Airport.check_placement(type_of(&"shop"), Vector2i(10, 10), 0), "", "a shop can be placed anywhere")
	check_eq(Airport.check_placement(type_of(&"cafe"), Vector2i(10, 10), 0), "", "café allowed landside")
	check_eq(Airport.check_placement(type_of(&"cafe"), Vector2i(10, 40), 0), "", "café allowed airside")
	check_eq(Airport.connection_problem(type_of(&"shop"), Vector2i(10, 40), 0), "Needs a walkway in front", "shops need a walkway in front")


func test_shop_panel_and_stats() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(240)
	await start_game()
	var shop := _shops()[0].building
	hud().show_station(shop)
	await frames(1)
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("Customers inside:"), "panel shows customers: '%s'" % info)
	check(info.contains("Airport income (5 min):"), "panel shows income")
	check_eq((ui("StationPanel/Content/UpgradeButton") as Button).text, "No upgrades for this building yet", "no shop upgrades yet")
	hud().show_stats()
	await frames(2)
	var cells_text: Array = ui("StatsPanel/Content/TableScroll/Table").get_children().map(func(c: Node) -> String: return (c as Label).text)
	check(cells_text.has("Shop") and cells_text.has("Café"), "statistics list the shop and the café")
