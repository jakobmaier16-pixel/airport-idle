extends TestCase
## The showcase airport (the "Everything together" world; scripts/dev/showcase_airport.gd).

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


func test_showcase_is_complete_and_busy() -> void:
	ShowcaseAirport.build()
	check_eq(Airport.usable_gates().size(), 3, "all three gates can have flights")
	var plane_near_stand := Airport.schedule.flights.any(func(f: Flight) -> bool:
		return f.phase in [Flight.Phase.ARRIVING, Flight.Phase.AT_STAND, Flight.Phase.BOARDING])
	check(plane_near_stand, "a plane is at or arriving at a stand right away")
	for building in Airport.buildings:
		var problem := Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps)
		check(problem.is_empty(), "%s connected: %s" % [building.type.display_name, problem])


func test_new_export_keeps_the_players_map() -> void:
	# The showcase no longer opens by itself after an update: the world list replaces that
	# (scripts/dev/worlds/). A new export keeps what the player built.
	_use_test_save("abc1234 · old")
	Airport.place_building(type_of(&"check_in"), at(Vector2i(20, 20)), 0)
	SaveGame.save_now()
	SaveGame.build_stamp = "def5678 · new"
	Airport.reset()
	SaveGame.load_game()
	check_eq(Airport.buildings.size(), 2, "own save loads (plus the runway old saves get)")
	check(Airport.buildings.any(func(b: Building) -> bool: return b.type.id == &"check_in"), "the player's check-in is there")
	_restore_save_settings()


func test_the_showcase_is_the_everything_together_world() -> void:
	await enter_world(TestWorlds.EVERYTHING_TOGETHER)
	check_eq(Airport.buildings.size(), SHOWCASE_WITH_LANDSIDE_BUILDINGS, "the world holds the whole showcase, landside included")
	check(not SaveGame.has_method("load_showcase"), "SaveGame has no showcase loader any more")
	check(ui("BuildMenu/PaintButtons").get_node_or_null("DemoButton") == null, "no Demo button: the world list replaced it")
