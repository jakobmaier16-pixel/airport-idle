extends TestCase
## The showcase airport: test builds open with it after each update (scripts/dev/showcase_airport.gd).

const TEST_SAVE: String = "user://test_savegame.json"


func _use_test_save(stamp: String) -> void:
	SaveGame.save_path = TEST_SAVE
	SaveGame.enabled = true
	SaveGame.build_stamp = stamp


func _restore_save_settings() -> void:
	SaveGame.reset_game()
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"
	SaveGame.build_stamp = BuildStamp.DEV


func test_showcase_uses_every_building_type() -> void:
	ShowcaseAirport.build(0.0)
	var used: Dictionary[StringName, bool] = {}
	for building in Airport.buildings:
		used[building.type.id] = true
	for type in Airport.CATALOG.types:
		check(used.has(type.id), "showcase contains a %s (add new buildings to the showcase!)" % type.display_name)


func test_showcase_is_complete_and_busy() -> void:
	ShowcaseAirport.build()
	check(Airport.passenger_flow.route_problem.is_empty(), "complete route: %s" % Airport.passenger_flow.route_problem)
	check(Airport.passenger_flow.passengers.size() > 5, "passengers already walking after the warm-up")
	var plane_near_stand := Airport.passenger_flow.schedule.flights.any(func(f: Flight) -> bool:
		return f.phase in [Flight.Phase.ARRIVING, Flight.Phase.AT_STAND, Flight.Phase.BOARDING])
	check(plane_near_stand, "a plane is at or arriving at a stand right away")
	for building in Airport.buildings:
		var problem := Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps)
		check(problem.is_empty(), "%s connected: %s" % [building.type.display_name, problem])


func test_new_export_replaces_map_with_showcase() -> void:
	_use_test_save("abc1234 · old")
	Airport.place_building(type_of(&"check_in"), Vector2i(5, 5), 0)
	SaveGame.save_now()

	SaveGame.build_stamp = "def5678 · new"
	Airport.reset()
	SaveGame.load_game()
	check_eq(Airport.buildings.size(), 1, "own save loads first")
	check(SaveGame.load_showcase_if_new_build(), "new export loads the showcase")
	check_eq(Airport.buildings.size(), 8, "showcase replaced the map")

	# Next start of the same export: keep what the player built since.
	Airport.place_building(type_of(&"check_in"), Vector2i(2, 2), 0)
	SaveGame.save_now()
	Airport.reset()
	SaveGame.load_game()
	check(not SaveGame.load_showcase_if_new_build(), "same export keeps the save")
	check_eq(Airport.buildings.size(), 9, "player's additions kept")
	_restore_save_settings()


func test_editor_runs_never_replace_the_map() -> void:
	_use_test_save(BuildStamp.DEV)
	Airport.place_building(type_of(&"check_in"), Vector2i(5, 5), 0)
	SaveGame.save_now()
	Airport.reset()
	SaveGame.load_game()
	check(not SaveGame.load_showcase_if_new_build(), "'dev' never loads the showcase")
	check_eq(Airport.buildings.size(), 1, "own map kept")
	_restore_save_settings()


func test_demo_button_needs_two_taps() -> void:
	await start_game()
	await open_build_view()
	# Don't let the real handler reload the scene (that would reload the test runner).
	hud().showcase_confirmed.disconnect(main._on_showcase_confirmed)
	var confirmed := [0]
	hud().showcase_confirmed.connect(func() -> void: confirmed[0] += 1)
	var button := ui("BuildMenu/PaintButtons/DemoButton") as Button
	check(button.visible, "demo button visible in debug builds")
	await press(button)
	check_eq(confirmed[0], 0, "first tap only arms it")
	await press(button)
	check_eq(confirmed[0], 1, "second tap loads the showcase")
