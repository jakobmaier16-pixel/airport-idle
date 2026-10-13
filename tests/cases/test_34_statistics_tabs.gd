extends TestCase
## Statistics tabs: money by source, airlines (design doc §13.2).


func _cells() -> Array:
	return ui("StatsPanel/Content/TableScroll/Table").get_children().map(func(c: Node) -> String: return (c as Label).text)


func test_money_by_source() -> void:
	var economy := Economy.new()
	economy.earn(100.0, Economy.SHOPS)
	economy.earn(40.0, Economy.PARKING)
	economy.tick(60.0, 60.0, 30.0)
	check(is_equal_approx(economy.source_total(Economy.SHOPS), 100.0), "shops")
	check(is_equal_approx(economy.source_total(Economy.PARKING), 40.0), "parking")
	check(absf(economy.source_total(Economy.RUNNING_COSTS) - 60.0) < 0.01, "a minute of running costs: %.2f" % economy.source_total(Economy.RUNNING_COSTS))
	check(absf(economy.source_total(Economy.SALARIES) - 30.0) < 0.01, "a minute of salaries")
	for i in Economy.SOURCE_WINDOW_SECONDS:
		economy.tick(1.0, 0.0, 0.0)
	check_eq(economy.source_total(Economy.SHOPS), 0.0, "forgotten after five minutes")


func test_showcase_money_adds_up() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(420)
	var economy := Airport.economy
	check(economy.source_total(Economy.AIRLINE_FEES) > 1000.0, "airline fees: %s" % Economy.format(economy.source_total(Economy.AIRLINE_FEES)))
	for source in [Economy.SHOPS, Economy.LOUNGE, Economy.PARKING, Economy.FAST_TRACK, Economy.ARRIVAL_FEES, Economy.SALARIES, Economy.RUNNING_COSTS]:
		check(economy.source_total(source) > 0.0, "%s counted" % source)
	# The last minute of the sources equals the profit per minute.
	var income := 0.0
	for source in Economy.INCOME_SOURCES:
		income += economy.source_total(source)
	var costs := 0.0
	for source in Economy.COST_SOURCES:
		costs += economy.source_total(source)
	check(income - costs > 0.0, "the showcase makes a profit over five minutes")


func test_airlines_count_late_flights() -> void:
	var airline: Airline = Airport.airlines.signed[0]
	Airport.airlines.record_flight(airline, false, 0.0)
	Airport.airlines.record_flight(airline, true, 0.0)
	check_eq(airline.flown, 2, "flown")
	check_eq(airline.late, 1, "one late")


func test_tabs() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(200)
	await start_game()
	await press(ui("TopButtons/StatsButton"))
	await frames(1)
	check_eq((ui("StatsPanel/Content/TableScroll/Table") as GridContainer).columns, 5, "stations first")
	await press(ui("StatsPanel/Content/Tabs/MoneyTab"))
	await frames(1)
	var cells := _cells()
	check(cells.has("Airline fees") and cells.has("Salaries") and cells.has("Profit"), "money by source: %s" % [cells])
	check(not ui("StatsPanel/Content/BottleneckLabel").visible, "no bottleneck line here")
	check((ui("StatsPanel/Content/Tabs/MoneyTab") as Button).button_pressed, "tab marked")
	await press(ui("StatsPanel/Content/Tabs/AirlinesTab"))
	await frames(1)
	cells = _cells()
	check(cells.has("Velora Regional") and cells.has("On time"), "airlines: %s" % [cells])
	check_eq(cells.size(), (1 + Airport.airlines.signed.size()) * 6, "one row per airline")
	hud().notify("Test message")
	await press(ui("StatsPanel/Content/Tabs/MessagesTab"))
	await frames(1)
	cells = _cells()
	check(cells.has("Test message") and cells[0].begins_with("Day 1"), "the message log: %s" % [cells])
	await press(ui("StatsPanel/Content/Tabs/StationsTab"))
	await frames(1)
	check(_cells().has("Security"), "back to the stations")
