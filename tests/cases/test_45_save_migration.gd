extends TestCase
## Save migration safety net (tech_architecture.md §13): saves written by older versions keep
## loading, old saves are converted step by step, and a save that can't be loaded is kept aside,
## never overwritten.
##
## tests/saves/ holds example saves as real players have them. **Never regenerate or edit them.**
## When the save format changes, add a converter (SaveGame.migrations), bump FORMAT_VERSION, add an
## example save of the new version, and keep every old one: they must all keep loading.

const TEST_SAVE: String = "user://test_migration.json"
const SHOWCASE_V1: String = "res://tests/saves/v1_showcase.json"
const EARLY_V1: String = "res://tests/saves/v1_early.json"
## What the showcase example save holds (written 2026-11-06, format version 1), without its
## de-icing pad: that building type was removed on 2026-11-13 and is dropped on loading.
## (Loading today removes the old stands and runway: see counts_after_legacy_removal.)
const EXAMPLE_BUILDINGS: Dictionary = {
	"runway": 1, "entrance": 1, "check_in": 2, "security": 1, "gate": 3, "aircraft_stand": 3,
	"wide_body_stand": 1, "cargo_terminal": 1, "baggage_claim": 1,
	"transfer_security": 1, "shop": 1, "cafe": 1, "lounge": 1, "car_park": 1,
}
# What loading an example save leaves of `counts`: the removed types are dropped (silently).
func _loadable(counts: Dictionary) -> Dictionary:
	var result := counts.duplicate()
	for type in REMOVED_TYPES:
		result.erase(type)
	return result


# Removed building types (and the old airside) leave without a notice.
func _check_removed_types_silent() -> void:
	check_eq(SaveGame.load_problem, "", "the player is not bothered about removed buildings: '%s'" % SaveGame.load_problem)


# Puts `text` where SaveGame loads from, with saving switched on for this test only.
func _install(text: String) -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	SaveGame.save_path = TEST_SAVE
	SaveGame.enabled = true


func _install_example(path: String) -> void:
	_install(FileAccess.get_file_as_string(path))


func _example(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# Saving off again, the real save path back, and every test file removed.
func _clean_up() -> void:
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"
	var folder := ProjectSettings.globalize_path("user://")
	for file in DirAccess.get_files_at(folder):
		if file.begins_with("test_migration.json"):
			DirAccess.remove_absolute(folder.path_join(file))


func _building_counts() -> Dictionary:
	var counts := {}
	for building in Airport.buildings:
		var id := String(building.type.id)
		counts[id] = counts.get(id, 0) + 1
	return counts


func test_showcase_v1_loads_completely() -> void:
	_install_example(SHOWCASE_V1)
	SaveGame.load_game()
	_check_removed_types_silent()
	check_eq(_building_counts(), _loadable(counts_after_legacy_removal(EXAMPLE_BUILDINGS)), "every other building is back, with the new runway")
	check_eq(Airport.clock.game_seconds, 28800.0, "the clock is back (08:00)")
	check_eq(Airport.game_seed, 4259094339, "the seed is back")
	check(Airport.usable_gates().is_empty(), "the gates wait for new stands")
	check_eq(Airport.schedule.flights.size(), 0, "flights of an old save are dropped")
	_clean_up()


func test_early_v1_loads() -> void:
	_install_example(EARLY_V1)
	SaveGame.load_game()
	var saved := _example(EARLY_V1)
	var kept: Array = saved["buildings"].filter(func(e: Dictionary) -> bool: return not LEGACY_AIRSIDE_TYPES.has(str(e["type"])))
	_check_removed_types_silent()
	check_eq(Airport.buildings.size(), kept.size() + 1, "its other buildings plus the starting runway")
	check_eq(Airport.clock.game_seconds, Clock.START_HOUR * 3600.0, "the clock starts at 06:00")
	_clean_up()


func test_converters_run_in_order() -> void:
	SaveGame.format_version = 3
	SaveGame.migrations[1] = func(data: Dictionary) -> Dictionary:
		data["steps"] = ["1 to 2"]
		return data
	SaveGame.migrations[2] = func(data: Dictionary) -> Dictionary:
		data["steps"].append("2 to 3")
		return data
	var converted := SaveGame.migrate(_example(SHOWCASE_V1))
	check_eq(converted.get("version"), 3, "converted to the newest version")
	check_eq(converted.get("steps"), ["1 to 2", "2 to 3"], "one step after another, in order")


func test_converted_save_loads() -> void:
	# A converter that marks the save, so we can see it ran before loading (the rest still run).
	SaveGame.migrations[1] = func(data: Dictionary) -> Dictionary:
		data["converted_by_test"] = true
		return data
	_install_example(SHOWCASE_V1)
	SaveGame.load_game()
	_check_removed_types_silent()
	check_eq(_building_counts(), _loadable(counts_after_legacy_removal(EXAMPLE_BUILDINGS)), "an old save loads in a newer version, with every other building")
	_clean_up()


func test_missing_converter_keeps_the_save() -> void:
	SaveGame.format_version = SaveGame.FORMAT_VERSION + 1  # newer build, but nobody wrote the converter
	_install_example(SHOWCASE_V1)
	var original := FileAccess.get_file_as_string(TEST_SAVE)
	SaveGame.load_game()
	_check_kept_aside(original, "unconvertible")
	_clean_up()


func test_newer_save_is_kept() -> void:
	var data := _example(SHOWCASE_V1)
	data["version"] = 99
	_install(JSON.stringify(data))
	var original := FileAccess.get_file_as_string(TEST_SAVE)
	SaveGame.load_game()
	_check_kept_aside(original, "newer")
	_clean_up()


func test_unreadable_save_is_kept() -> void:
	_install("{ this is not a save game")
	SaveGame.load_game()
	_check_kept_aside("{ this is not a save game", "unreadable")
	_clean_up()


func test_player_is_told() -> void:
	_install("{ broken")
	SaveGame.load_game()
	var problem := SaveGame.load_problem
	await start_game()
	check_eq(hud().notice_text(), problem, "a notice explains what happened to the save")
	_clean_up()


# The save was moved aside unchanged, the game starts fresh, and saving can't overwrite it.
func _check_kept_aside(original: String, reason: String) -> void:
	check(not SaveGame.load_problem.is_empty(), "the player is told")
	check(SaveGame.backup_path.contains(reason), "the backup says why (%s)" % SaveGame.backup_path)
	check_eq(FileAccess.get_file_as_string(SaveGame.backup_path), original, "the backup is the save, unchanged")
	check(Airport.buildings.size() <= 1, "a new airport starts")
	SaveGame.save_now()
	check_eq(FileAccess.get_file_as_string(SaveGame.backup_path), original, "saving the new airport doesn't touch the backup")


## Saves store these lists as plain numbers (zones per cell, the building kinds). Reordering them, or inserting a value in the middle,
## silently changes what old saves mean. New values go at the end; anything else needs a
## converter (SaveGame.migrations) and a new FORMAT_VERSION.
func test_saved_number_lists_unchanged() -> void:
	var fix := " is stored as numbers in saves: add new values at the end, or write a converter"
	check_eq(AirportGrid.Zone.keys(), ["LANDSIDE", "AIRSIDE"], "AirportGrid.Zone" + fix)
	check_eq(BuildingType.Role.keys(), ["NONE", "ENTRANCE", "CHECK_IN", "SECURITY", "GATE", "AIRCRAFT_STAND", "SHOP",
		"BAGGAGE_CLAIM", "TRANSFER_SECURITY", "CAR_PARK", "LOUNGE", "RUNWAY", "CARGO_TERMINAL"], "BuildingType.Role" + fix)


const SHOWCASE_V2: String = "res://tests/saves/v2_showcase.json"


func test_showcase_v2_loads_completely() -> void:
	_install_example(SHOWCASE_V2)
	SaveGame.load_game()
	_check_removed_types_silent()
	var legacy: int = _example(SHOWCASE_V2)["buildings"].filter(func(e: Dictionary) -> bool: return LEGACY_AIRSIDE_TYPES.has(str(e["type"]))).size()
	var gone: int = _example(SHOWCASE_V2)["buildings"].filter(func(e: Dictionary) -> bool: return REMOVED_TYPES.has(str(e["type"])) or str(e["type"]) == "deicing_pad").size()
	check_eq(Airport.buildings.size(), _example(SHOWCASE_V2)["buildings"].size() - gone - legacy + 1, "every building but the pad, the removed types and the old airside is back (plus the new runway)")
	_clean_up()


func test_v1_converter_gives_ids_and_staff_ids() -> void:
	SaveGame.format_version = 2  # stop after the v1 converter
	var converted := SaveGame.migrate(_example(SHOWCASE_V1))
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	check_eq(converted["version"], 2, "now version 2")
	var ids := {}
	for entry: Dictionary in converted["buildings"]:
		ids[int(entry["id"])] = true
	check_eq(ids.size(), (converted["buildings"] as Array).size(), "every building has its own ID")
	for entry: Dictionary in converted["staff"]:
		check(not entry.has("building") and ids.has(int(entry["building_id"])), "staff point to a building ID")
	# The converted v1 save loads.
	Airport.load_state(converted)
	var seen := {}
	for building in Airport.buildings:
		check(building.id > 0 and not seen.has(building.id), "IDs are unique")
		seen[building.id] = true


func test_ids_survive_save_and_load_after_reset() -> void:
	build_reference_airport()
	var check_in: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.id == &"check_in")[0]
	var state := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	var saved_id := check_in.id
	Airport.reset()
	Airport.load_state(state)
	var again: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.id == saved_id)[0]
	check_eq(again.type.id, &"check_in", "same ID, same building")
	var fresh := Airport.place_building(Airport.CATALOG.find(&"check_in"), at(Vector2i(2, 2)), 0)
	check(fresh == null or fresh.id > saved_id or not Airport.buildings.any(func(b: Building) -> bool: return b != fresh and b.id == fresh.id), "a new building never reuses an ID")


func test_vanished_building_type_is_dropped_silently() -> void:
	var state := {
		"map_size": [64, 64],
		"buildings": [
			{"id": 1, "type": "gone_for_good", "cell": [20, 20], "rotation": 0, "cost": 400.0},
		],
	}
	check_eq(Airport.load_state(state), 0, "nothing is counted as a failure")
	check_eq(Airport.buildings.size(), 1, "only the starting runway is there")
	_install(JSON.stringify(state.merged({"version": 2})))
	SaveGame.load_game()
	check_eq(SaveGame.load_problem, "", "and nobody is told")
	_clean_up()


const SHOWCASE_V4: String = "res://tests/saves/v4_showcase.json"
const SHOWCASE_V5: String = "res://tests/saves/v5_showcase.json"
## Fields of the removed extras (weather, incidents, VIPs, first-landing cutscene).
const REMOVED_KEYS: Array[String] = ["weather", "next_incident_in", "next_vip_in"]


func test_showcase_v5_loads_completely() -> void:
	check_eq(int(_example(SHOWCASE_V5)["version"]), 5, "an example save of version 5")
	_install_example(SHOWCASE_V5)
	SaveGame.load_game()
	_check_removed_types_silent()
	check_eq(_building_counts(), _loadable(counts_after_legacy_removal(EXAMPLE_BUILDINGS)), "every other building is back, with the new runway")
	check(Airport.usable_gates().is_empty(), "the gates wait for new stands")
	_clean_up()


func test_v4_converter_drops_the_removed_extras() -> void:
	var saved := _example(SHOWCASE_V4)
	for key in REMOVED_KEYS:
		check(saved.has(key), "the old example still has '%s'" % key)
	SaveGame.format_version = 5  # stop after the v4 converter
	var converted := SaveGame.migrate(saved)
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	check_eq(converted["version"], 5, "now version 5")
	for key in REMOVED_KEYS:
		check(not converted.has(key), "'%s' is dropped" % key)
	check(not (converted["buildings"] as Array).any(func(e: Dictionary) -> bool: return e.has("closed")), "no closed stations")
	check(not (converted["airlines"]["signed"] as Array).any(func(e: Dictionary) -> bool: return e.has("first_landing")), "no first-landing flags")
	check(not (converted["flow"]["passengers"] as Array).any(func(e: Dictionary) -> bool: return e.has("vip")), "no VIP flags")
	check(not (converted["flow"]["schedule"]["flights"] as Array).any(func(e: Dictionary) -> bool: return e.has("weather_delay") or e.has("deiced") or e.has("vip_pending")), "no weather or VIP fields on flights")
