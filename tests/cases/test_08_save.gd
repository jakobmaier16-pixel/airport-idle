extends TestCase
## Saving and loading (design doc §5). Uses a separate test file, never the real save.

const TEST_SAVE: String = "user://test_savegame.json"


func test_state_round_trip() -> void:
	build_reference_airport()
	var state := Airport.save_state()
	var building_count := Airport.buildings.size()
	var zones := Airport.grid.get_zone_data().duplicate()
	var walkways := Airport.grid.get_walkway_data().duplicate()
	Airport.reset()
	check_eq(Airport.buildings.size(), 0, "reset clears buildings")
	var skipped := Airport.load_state(state)
	check_eq(skipped, 0, "nothing skipped")
	check_eq(Airport.buildings.size(), building_count, "buildings restored")
	check_eq(Airport.grid.get_zone_data(), zones, "zones restored")
	check_eq(Airport.grid.get_walkway_data(), walkways, "walkways restored")
	check(Airport.passenger_flow.route_problem.is_empty(), "route works after loading")
	check_eq(Airport.paint_zone([Vector2i(31, 31)] as Array[Vector2i], AirportGrid.Zone.LANDSIDE), 1, "zone locks restored")


func test_file_save_and_load() -> void:
	SaveGame.save_path = TEST_SAVE
	SaveGame.enabled = true
	build_reference_airport()
	SaveGame.save_now()
	check(FileAccess.file_exists(TEST_SAVE), "save file written")
	Airport.reset()
	SaveGame.load_game()
	check_eq(Airport.buildings.size(), 8, "loaded from file")
	SaveGame.reset_game()
	check(not FileAccess.file_exists(TEST_SAVE), "reset deletes the save")
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"


func test_old_save_without_walkways_loads() -> void:
	build_reference_airport()
	var state := Airport.save_state()
	state.erase("walkways")
	Airport.load_state(state)
	check_eq(Airport.buildings.size(), 8, "buildings load from an older save")


func test_outdated_building_is_skipped() -> void:
	var state := {
		"map_size": [64, 64],
		"buildings": [
			{"type": "check_in", "cell": [10, 10], "rotation": 0},
			{"type": "no_longer_exists", "cell": [20, 20], "rotation": 0},
			{"type": "check_in", "cell": [11, 11], "rotation": 0},
		],
	}
	check_eq(Airport.load_state(state), 2, "unknown type and overlapping building skipped")
	check_eq(Airport.buildings.size(), 1, "the valid building loads")


func test_reset_button_needs_two_taps() -> void:
	await start_game()
	await open_build_view()
	# Don't let the real handler reload the scene (that would reload the test runner).
	hud().reset_confirmed.disconnect(main._on_reset_confirmed)
	var confirmed := [0]
	hud().reset_confirmed.connect(func() -> void: confirmed[0] += 1)
	var button := ui("BuildMenu/PaintButtons/ResetButton") as Button
	check(button.visible, "reset button visible in debug builds")
	await press(button)
	check_eq(confirmed[0], 0, "first tap only arms it")
	check_eq(button.text, "Tap again", "button asks for a second tap")
	await press(button)
	check_eq(confirmed[0], 1, "second tap confirms")
