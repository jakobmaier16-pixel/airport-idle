extends TestCase
## Save format 10 (tech_architecture.md §13): the 6 m prototype's stands, runway and taxiway paint are
## removed with a full refund, and the real-scale runway is laid. Rules, not pasted numbers: every
## amount is worked out from the example save itself (see TestCase.legacy_refund_of).

const TEST_SAVE: String = "user://test_save_v10.json"
const V9: String = "res://tests/saves/v9_showcase.json"
const V10: String = "res://tests/saves/v10_showcase.json"
## The footprints of the removed types (stand 12 x 12, wide-body stand 16 x 16, runway 52 x 6).
const LEGACY_FOOTPRINTS: Array[Vector2i] = [Vector2i(12, 12), Vector2i(16, 16), Vector2i(52, 6)]


func _example(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _clean_up() -> void:
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func test_the_format_is_10_and_there_is_a_v10_example() -> void:
	check_eq(SaveGame.FORMAT_VERSION, 10, "the newest format")
	check_eq(int(_example(V10)["version"]), 10, "an example save of version 10")
	check(SaveGame.migrations.has(9), "a converter for version 9")


func test_v9_example_loses_its_old_airside_and_gets_money_back() -> void:
	var saved := _example(V9)
	var refund := legacy_refund_of(saved)
	check(refund > 0.0, "the example has old stands, a runway and taxiways (%.0f)" % refund)
	var converted := SaveGame.migrate(_example(V9))
	check_eq(SaveGame.legacy_refund, refund, "the converter reports what it paid back")
	check_eq(converted["money"], float(saved["money"]) + refund, "the refund is added to the saved money")
	for entry: Dictionary in converted["buildings"]:
		check(not LEGACY_AIRSIDE_PRICES.has(str(entry["type"])), "no %s left in the save" % entry["type"])
	check_eq((converted["taxiways"] as Array).size(), 0, "no taxiway chunks left")
	# Everything else stays: the saved buildings minus the removed ones.
	var kept: int = saved["buildings"].filter(func(e: Dictionary) -> bool: return not LEGACY_AIRSIDE_PRICES.has(str(e["type"]))).size()
	check_eq((converted["buildings"] as Array).size(), kept, "the other buildings are untouched")


func test_loading_v9_leaves_no_legacy_footprint_and_the_balance_adds_up() -> void:
	var saved := _example(V9)
	var refund := legacy_refund_of(saved)
	Airport.load_state(SaveGame.migrate(_example(V9)))
	var runways := 0
	for building in Airport.buildings:
		check(building.type.footprint not in LEGACY_FOOTPRINTS, "%s has a real-scale footprint" % building.type.display_name)
		if building.type.role == BuildingType.Role.RUNWAY:
			runways += 1
			check_eq(building.type.footprint, Vector2i(1000, 23), "the new runway")
	check_eq(runways, 1, "exactly one runway is laid")
	check_eq(Airport.grid.count_flag(AirportGrid.TAXIWAY_BIT), 0, "no old taxiway paint")
	check_eq(Airport.economy.balance, float(saved["money"]) + refund + Airport.load_refund, "balance = saved money + refunds")
	check_eq(Airport.load_refund, 0.0, "nothing else had to be refunded")
	# The gates stay and wait for new stands.
	check(Airport.buildings.any(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE), "the gates are still there")
	check(not Airport.passenger_flow.route_problem.is_empty(), "no flights until stands are built")
	sim_seconds(1.0)
	check_eq(Airport.passenger_flow.schedule.flights.size(), 0, "flights of the removed stands are cancelled at the first step")


func test_the_player_is_told_what_was_refunded() -> void:
	var saved := _example(V9)
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(V9))
	file.close()
	SaveGame.save_path = TEST_SAVE
	SaveGame.enabled = true
	SaveGame.load_game()
	check_eq(SaveGame.load_problem, "Old stands and runway were removed: %s refunded." % Economy.format(legacy_refund_of(saved)), "the notice")
	_clean_up()


func test_converter_works_on_small_hand_made_saves() -> void:
	var grid := AirportGrid.new(Vector2i(128, 128), 2.0)
	for x in 10:
		grid.set_taxiway(Vector2i(70 + x, 70), true)
	var data := {
		"version": 9, "money": 100.0, "taxiways": GridSave.encode(grid, AirportGrid.TAXIWAY_BIT),
		"buildings": [
			{"id": 1, "type": "aircraft_stand", "cell": [5, 5], "cost": 5500.0},
			{"id": 2, "type": "wide_body_stand", "cell": [30, 5]},
			{"id": 3, "type": "gate", "cell": [5, 1], "cost": 4000.0},
		],
	}
	var converted := SaveGame.migrate(data)
	var expected := 100.0 + 5500.0 + LEGACY_AIRSIDE_PRICES["wide_body_stand"] + 10 * LEGACY_TAXIWAY_PRICE
	check_eq(converted["money"], expected, "the entry's own price, the old list price when it has none, and the taxiway cells")
	check_eq((converted["buildings"] as Array).size(), 1, "only the gate is kept")
	var plain := SaveGame.migrate({"version": 9, "money": 100.0, "buildings": [], "taxiways": []})
	check_eq(plain["money"], 100.0, "nothing to remove: the money stays")
	check_eq(SaveGame.legacy_refund, 0.0, "and nothing is reported")


func test_v10_example_loads_completely_and_saves_the_same() -> void:
	var saved := _example(V10)
	check_eq(SaveGame.migrate(_example(V10)), saved, "a current save needs no conversion")
	check_eq(SaveGame.legacy_refund, 0.0, "nothing is refunded")
	check_eq(Airport.load_state(saved), 0, "every building loads")
	check_eq(Airport.buildings.size(), SHOWCASE_BUILDINGS, "all of its buildings")
	check_eq(Airport.load_refund, 0.0, "no refund")
	check(Airport.passenger_flow.schedule.flights.size() > 0 or Airport.timetable.slots.size() > 0, "its flights and timetable are back")
	var again := JSON.parse_string(JSON.stringify(Airport.save_state(), "", true, true)) as Dictionary
	var types_before: Array = saved["buildings"].map(func(e: Dictionary) -> Array: return [e["type"], e["cell"], e["rotation"]])
	var types_after: Array = again["buildings"].map(func(e: Dictionary) -> Array: return [e["type"], e["cell"], e["rotation"]])
	check_eq(types_after, types_before, "saving it again gives the same buildings")
	sim_seconds(120.0)
	check(Airport.passenger_flow.passengers.size() > 0, "it keeps running")
