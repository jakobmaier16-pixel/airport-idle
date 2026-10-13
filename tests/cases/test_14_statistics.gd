extends TestCase
## Statistics panel and bottleneck finder (design doc §13.1).


func _station(role: BuildingType.Role) -> Station:
	for station in Airport.passenger_flow.stations():
		if station.role() == role:
			return station
	return null


func test_stations_record_queue_and_wait() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(180)
	var flow := Airport.passenger_flow
	var check_in := _station(BuildingType.Role.CHECK_IN)
	check(check_in.average_wait(flow.time) >= 0.0, "check-in has served passengers")
	check(check_in.longest_queue() >= check_in.queue_length(), "longest queue covers the current one")
	var busy := check_in.busy_share()
	check(busy > 0.0 and busy <= 1.0, "busy share between 0 and 100 %%: %s" % busy)


func test_old_waits_are_forgotten() -> void:
	var building := Airport.place_building(type_of(&"check_in"), Vector2i(10, 10), 0)
	var station := Station.new(building)
	station.record_wait(0.0, 30.0)
	check_eq(station.average_wait(10.0), 30.0, "recent wait counts")
	station.record_wait(400.0, 10.0)
	check_eq(station.average_wait(400.0), 10.0, "waits older than 5 minutes are forgotten")
	check_eq(station.average_wait(800.0), -1.0, "no recent waits")


func test_slow_security_is_the_bottleneck() -> void:
	var security := type_of(&"security")
	var normal_time := security.service_time
	security.service_time = 25.0
	ShowcaseAirport.build(0.0)
	sim_seconds(200)
	security.service_time = normal_time
	var bottleneck := Airport.passenger_flow.bottleneck()
	check(bottleneck != null and bottleneck.role() == BuildingType.Role.SECURITY, "security is the bottleneck")


func test_station_labels() -> void:
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	var labels := flow.stations().map(func(s: Station) -> String: return flow.station_label(s.building))
	check_eq(labels, ["Check-in 1", "Check-in 2", "Security", "Transfer security", "Gate 1", "Gate 2", "Gate 3", "Shop", "Café", "Lounge", "Baggage claim", "Car park"], "stations in order with numbers")


func test_stats_panel_opens_and_shows_rows() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(150)
	await start_game()
	await press(ui("TopButtons/StatsButton"))
	await frames(2)
	check(hud().is_stats_open(), "Stats opens the panel")
	var table := ui("StatsPanel/Content/TableScroll/Table") as GridContainer
	check_eq(table.get_child_count(), 13 * 5, "header + 12 stations, 5 columns")
	var bottleneck := (ui("StatsPanel/Content/BottleneckLabel") as Label).text
	check(bottleneck.begins_with("Bottleneck:") or bottleneck.begins_with("No bottleneck"), "bottleneck line: '%s'" % bottleneck)
	await press(ui("StatsPanel/Content/CloseButton"))
	check(not hud().is_stats_open(), "Close hides it")


func test_stats_and_station_panel_never_overlap() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	await press(ui("TopButtons/StatsButton"))
	hud().show_station(Airport.buildings[1])
	check(not hud().is_stats_open(), "opening a station closes the statistics")
	hud().show_stats()
	check(not ui("StationPanel").visible, "opening statistics closes the station panel")


func test_stats_only_in_manager_view() -> void:
	await start_game()
	await press(ui("TopButtons/StatsButton"))
	await open_build_view()
	check(not hud().is_stats_open(), "statistics close in the build view")
	check(not ui("TopButtons/StatsButton").visible, "no Stats button in the build view")
	await close_build_view()
	check(ui("TopButtons/StatsButton").visible, "Stats button back in the manager view")
