extends TestCase
## Statistics panel (design doc §13): money, airlines and messages.


func test_stats_panel_opens_and_shows_rows() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(150)
	await start_game()
	await press(ui("TopButtons/StatsButton"))
	await frames(2)
	check(hud().is_stats_open(), "Stats opens the panel")
	check_eq(hud().stats_tab, Hud.StatsTab.MONEY, "the money tab is the first one")
	var table := ui("StatsPanel/Content/TableScroll/Table") as GridContainer
	check(table.get_child_count() > 3, "the money table has rows")
	var punctuality := (ui("StatsPanel/Content/PunctualityLabel") as Label).text
	check(punctuality.contains("On time") and punctuality.contains("Demand"), "punctuality and demand: '%s'" % punctuality)
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


func test_station_panel_shows_name_and_zone() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var gate: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)[0]
	hud().show_station(gate)
	await frames(2)
	check_eq((ui("StationPanel/Content/TitleLabel") as Label).text, "Gate", "the panel names the building")
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("Zone: Airside"), "a gate is airside: '%s'" % info)
	var entrance: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.ENTRANCE)[0]
	hud().show_station(entrance)
	await frames(2)
	check((ui("StationPanel/Content/InfoLabel") as Label).text.contains("Zone: Landside"), "an entrance is landside")
	await press(ui("StationPanel/Content/CloseButton"))
	check(hud().shown_station == null, "Close hides the panel")
