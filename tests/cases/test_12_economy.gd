extends TestCase
## Money (design doc §11.5): construction, running costs, fees, saving, display.


func test_starting_money_and_construction_cost() -> void:
	check_eq(Airport.economy.balance, Economy.STARTING_MONEY, "start with €50,000")
	await start_game()
	await open_build_view()
	check(await place("Check-in", Vector2i(30, 20)), "check-in placed")
	check_eq(Airport.economy.balance, Economy.STARTING_MONEY - 3000.0, "check-in cost €3,000")
	check_eq(Economy.format(Airport.economy.balance), "€47,000", "formatted balance")


func test_price_shown_while_placing() -> void:
	await start_game()
	await open_build_view()
	await press(ui("BuildMenu/BuildingButtons").get_child(2))  # Security
	var hint := (ui("ToolPanel/HintLabel") as Label).text
	build_mode()._set_preview_origin(Vector2i(5, 5))
	hint = (ui("ToolPanel/HintLabel") as Label).text
	check(hint.contains("€") or hint.begins_with("Front must"), "hint names the price or the problem: '%s'" % hint)
	await press(ui("ToolPanel/ToolBar/CancelButton"))
	await press(ui("BuildMenu/BuildingButtons").get_child(1))  # Check-in on landside: allowed
	build_mode()._set_preview_origin(Vector2i(5, 5))
	hint = (ui("ToolPanel/HintLabel") as Label).text
	check(hint.ends_with("€3,000"), "valid spot shows the price: '%s'" % hint)


func test_not_enough_money_blocks_placing() -> void:
	Airport.economy.balance = 1000.0
	await start_game()
	await open_build_view()
	await press(ui("BuildMenu/BuildingButtons").get_child(1))  # Check-in, €3,000
	build_mode()._set_preview_origin(Vector2i(30, 20))
	var place_button := ui("ToolPanel/ToolBar/PlaceButton") as Button
	check(place_button.disabled, "Place disabled without enough money")
	check_eq((ui("ToolPanel/HintLabel") as Label).text, "Not enough money (€3,000)", "hint")
	await press(place_button)
	check_eq(Airport.buildings.size(), 0, "nothing built")
	check_eq(Airport.economy.balance, 1000.0, "nothing paid")


func test_walkway_costs_per_cell_and_removal_is_free() -> void:
	await start_game()
	await open_build_view()
	await paint("WalkwayButton", Vector2i(28, 28), Vector2i(32, 29))  # 10 cells
	check_eq(Airport.economy.balance, Economy.STARTING_MONEY - 200.0, "10 cells x €20")
	await paint("RemoveButton", Vector2i(28, 28), Vector2i(32, 29))
	check_eq(Airport.economy.balance, Economy.STARTING_MONEY - 200.0, "removing is free, no refund")


func test_walkway_too_expensive_paints_nothing() -> void:
	Airport.economy.balance = 100.0
	await start_game()
	await open_build_view()
	await press(ui("BuildMenu/PaintButtons/WalkwayButton"))
	drag(screen_of_cell(Vector2i(28, 28)), screen_of_cell(Vector2i(32, 29)))  # 10 cells = €200
	var hint := (ui("ToolPanel/HintLabel") as Label).text
	check_eq(hint, "Not enough money (€200 for 10 cells)", "hint")
	var walkway := 0
	for value in Airport.grid.get_walkway_data():
		walkway += value
	check_eq(walkway, 0, "nothing painted")
	await press(ui("ToolPanel/ToolBar/DoneButton"))


func test_running_costs() -> void:
	Airport.place_building(type_of(&"check_in"), Vector2i(10, 10), 0)
	var after_building := Airport.economy.balance
	check_eq(Airport.running_cost_per_minute(), 30.0, "one check-in costs €30 per minute")
	sim_seconds(60)
	check(is_equal_approx(Airport.economy.balance, after_building - 30.0), "one minute later €30 less: %s" % Airport.economy.balance)
	check(is_equal_approx(Airport.economy.profit_per_minute(), -30.0), "profit per minute -€30: %s" % Airport.economy.profit_per_minute())


func test_flights_earn_money() -> void:
	ShowcaseAirport.build(0.0)
	var start := Airport.economy.balance
	var flight: Flight = null
	sim_seconds(1)
	for f in Airport.passenger_flow.schedule.upcoming():
		flight = f
		break
	var running := Airport.running_cost_per_minute()
	sim_seconds(flight.departure_time - Airport.passenger_flow.time + 1.0)
	var elapsed_minutes := Airport.passenger_flow.time / 60.0
	var expected := start + flight.boarded * Economy.PASSENGER_FEE + Economy.FLIGHT_FEE - running * elapsed_minutes
	check(absf(Airport.economy.balance - expected) < 1.0, "fees for %d passengers + flight, minus running costs: %s vs %s" % [flight.boarded, Airport.economy.balance, expected])


func test_showcase_makes_a_profit() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(600)
	check(Airport.economy.balance > Economy.STARTING_MONEY, "after 10 minutes the showcase has earned money: %s" % Economy.format(Airport.economy.balance))


func test_money_saved_and_loading_does_not_charge() -> void:
	ShowcaseAirport.build(0.0)
	Airport.economy.balance = 12345.0
	var state := Airport.save_state()
	Airport.reset()
	Airport.load_state(state)
	check_eq(Airport.economy.balance, 12345.0, "balance restored, buildings not paid again")
	check_eq(Airport.buildings.size(), 8, "all buildings loaded")
	state.erase("money")
	Airport.load_state(state)
	check_eq(Airport.economy.balance, Economy.STARTING_MONEY, "old save without money starts with the starting money")


func test_money_display() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	await frames(2)
	var label := ui("InfoPanel/MoneyLabel") as Label
	check(label.text.begins_with("€50,000"), "balance shown: '%s'" % label.text)
	check(label.text.ends_with("/min"), "profit per minute shown")
	Airport.economy.balance = -500.0
	await frames(1)
	check(label.text.begins_with("-€500"), "negative balance: '%s'" % label.text)
	check_eq(label.modulate, Hud.DEBT_COLOR, "shown in red")
