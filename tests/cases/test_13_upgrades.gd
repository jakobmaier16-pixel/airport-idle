extends TestCase
## Station upgrades (design doc §7.8).


func _building(id: StringName) -> Building:
	for building in Airport.buildings:
		if building.type.id == id:
			return building
	return null


func test_small_upgrade_is_instant() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), Vector2i(10, 10), 0)
	var balance := Airport.economy.balance
	check_eq(check_in.service_slots(), 3, "3 counters at level 1")
	check(Airport.start_upgrade(check_in), "upgrade started")
	check_eq(check_in.level, 2, "level 2 at once")
	check_eq(check_in.service_slots(), 4, "4 counters")
	check_eq(Airport.economy.balance, balance - 2500.0, "paid €2,500")
	check_eq(Airport.running_cost_per_minute(), 40.0, "running cost +€10/min")


func test_big_upgrade_takes_time() -> void:
	# Security must sit on the border: landside in front (row 9), airside behind (row 13).
	Airport.paint_zone(cells(Vector2i(0, 13), Vector2i(64, 51)), AirportGrid.Zone.AIRSIDE)
	var security := Airport.place_building(type_of(&"security"), Vector2i(10, 10), 0)
	check(security != null, "security placed on the border")
	security.level = 2
	check_eq(security.service_time(), 6.0, "6 s per passenger before")
	check(Airport.start_upgrade(security), "big upgrade started")
	check(security.is_upgrading(), "under construction")
	check_eq(security.level, 2, "still level 2 while building")
	check_eq(Airport.upgrade_problem(security), "Upgrade in progress", "can't start twice")
	sim_seconds(59)
	check_eq(security.level, 2, "not done after 59 s")
	sim_seconds(2)
	check_eq(security.level, 3, "done after 60 s")
	check(is_equal_approx(security.service_time(), 4.5), "25 %% faster: %s" % security.service_time())
	check_eq(Airport.upgrade_problem(security), "Fully upgraded", "top level reached")


func test_upgrade_needs_money() -> void:
	var check_in := Airport.place_building(type_of(&"check_in"), Vector2i(10, 10), 0)
	Airport.economy.balance = 1000.0
	check_eq(Airport.upgrade_problem(check_in), "Not enough money (€2,500)", "hint")
	check(not Airport.start_upgrade(check_in), "no upgrade without money")
	check_eq(check_in.level, 1, "still level 1")


func test_gates_have_no_upgrades_yet() -> void:
	Airport.paint_zone(cells(Vector2i(0, 32), Vector2i(64, 32)), AirportGrid.Zone.AIRSIDE)
	var gate := Airport.place_building(type_of(&"gate"), Vector2i(10, 40), 0)
	check_eq(Airport.upgrade_problem(gate), "No upgrades for this building yet", "gate")


func test_more_lanes_mean_faster_security() -> void:
	ShowcaseAirport.build(0.0)  # security starts at level 2 in the showcase
	var security := _building(&"security")
	check_eq(security.service_slots(), 3, "showcase security has 3 lanes")
	var station := Airport.passenger_flow.station_for(security)
	sim_seconds(10)
	check_eq(station.serving.size(), 3, "the station uses all 3 lanes")


func test_level_and_running_upgrade_are_saved() -> void:
	ShowcaseAirport.build(0.0)
	var check_in := _building(&"check_in")
	check(check_in.is_upgrading(), "showcase check-in is being upgraded")
	sim_seconds(20)
	var left := check_in.upgrade_seconds_left
	var state := Airport.save_state()
	Airport.load_state(state)
	var loaded := _building(&"check_in")
	check_eq(loaded.level, 2, "level restored")
	check(absf(loaded.upgrade_seconds_left - left) < 0.01, "upgrade time left restored")
	check_eq(_building(&"security").level, 2, "security level restored")


func test_tap_station_opens_panel_and_upgrades() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var security := _building(&"security")
	# Stand south of security on the airside walkway; the camera looks north at it.
	manager().global_position = Airport.grid.cell_to_world(Vector2i(32, 33))
	manager_camera().snap_to_target()
	await physics_frames(2)
	var center := Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 1.5, 0.0)
	# Like a real finger: the tap wobbles a little before it is lifted.
	var at := manager_camera().unproject_position(center)
	touch(0, true, at)
	move(0, at + Vector2(TouchGestures.tap_slop * 0.7, 3.0))
	touch(0, false, at + Vector2(TouchGestures.tap_slop * 0.7, 3.0))
	await frames(1)
	check(ui("StationPanel").visible, "tapping security opens its panel")
	check(hud().shown_station == security, "panel shows security")
	var title := (ui("StationPanel/Content/TitleLabel") as Label).text
	check_eq(title, "Security · Level 2", "title")
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("3 lanes"), "info shows the lanes: '%s'" % info)
	var button := ui("StationPanel/Content/UpgradeButton") as Button
	check_eq(button.text, "Upgrade: Faster scanners · €6,000 · 1 min", "upgrade button")
	await press(button)
	check(security.is_upgrading(), "upgrade started from the panel")
	await frames(1)
	check(button.disabled, "button disabled while building")

	# Tapping empty ground closes the panel.
	tap(manager_camera().unproject_position(Airport.grid.cell_to_world(Vector2i(32, 36))))
	await frames(1)
	check(not ui("StationPanel").visible, "tapping elsewhere closes the panel")


func test_panel_closes_in_build_view() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	hud().show_station(_building(&"security"))
	await open_build_view()
	check(not ui("StationPanel").visible, "station panel hidden in the build view")


func test_upgrade_label_counts_down() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	await frames(1)
	var label: Label3D = main.get_node("Buildings")._hints[_building(&"check_in")]
	check(label.visible, "upgrading building shows a label")
	check(label.text.begins_with("Upgrading… 1:00") or label.text.begins_with("Upgrading… 0:"), "countdown: '%s'" % label.text)


func test_station_found_on_screen_without_physics() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var security := _building(&"security")
	manager().global_position = Airport.grid.cell_to_world(Vector2i(32, 33))
	manager_camera().snap_to_target()
	await physics_frames(2)
	var center := Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 1.0, 0.0)
	check(main._station_on_screen(manager_camera().unproject_position(center)) == security, "found by its box on screen")
	check(main._station_on_screen(Vector2(5, 5)) == null, "nothing in the corner of the screen")


func test_tap_report_line() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	manager().global_position = Airport.grid.cell_to_world(Vector2i(32, 33))
	manager_camera().snap_to_target()
	await physics_frames(2)
	var security := _building(&"security")
	tap(manager_camera().unproject_position(Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 1.5, 0.0)))
	await frames(1)
	var feedback := hud().get_node("TapFeedback") as TapFeedback
	check(feedback.report_text.contains("→ Security"), "report names the station: '%s'" % feedback.report_text)
	await open_build_view()
	tap(screen_size() * 0.5)
	check(feedback.report_text.contains("build view"), "build view taps explain where stations open: '%s'" % feedback.report_text)
