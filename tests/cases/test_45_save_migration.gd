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
## What the showcase example save holds (written 2026-11-06, format version 1).
const EXAMPLE_BUILDINGS: Dictionary = {
	"runway": 1, "entrance": 1, "check_in": 2, "security": 1, "gate": 3, "aircraft_stand": 3,
	"wide_body_stand": 1, "deicing_pad": 1, "cargo_terminal": 1, "baggage_claim": 1,
	"transfer_security": 1, "shop": 1, "cafe": 1, "lounge": 1, "car_park": 1,
}


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
	var saved := _example(SHOWCASE_V1)
	_install_example(SHOWCASE_V1)
	SaveGame.load_game()
	check_eq(SaveGame.load_problem, "", "no problem loading")
	check_eq(_building_counts(), EXAMPLE_BUILDINGS, "every building is back")
	check_eq(Airport.staff.size(), 15, "every employee is back")
	check(Airport.staff.all(func(e: Employee) -> bool: return e.workplace != null and Airport.needs_staff(e.workplace)),
		"every employee works at a station that needs staff")
	check_eq(Airport.progression.tier, Progression.Tier.INTERNATIONAL, "the tier is back")
	var airlines: Array[String] = []
	for airline in Airport.airlines.signed:
		airlines.append(String(airline.type.id))
	check_eq(airlines, ["velora", "zippa", "norvane", "orynth", "paqet"] as Array[String], "the signed airlines are back")
	check_eq(Airport.clock.game_seconds, 28800.0, "the clock is back (08:00)")
	check_eq(Airport.game_seed, 4259094339, "the seed is back")
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.id == &"security")[0]
	check_eq(security.level, 3, "upgrades are back")
	check(security.fast_track, "the fast track is back")
	check(Airport.passenger_flow.route_problem.is_empty(), "passengers can flow")
	# Written long ago: the player gets the welcome-back income once (design doc §3.4).
	check(SaveGame.away_seconds > 36 * 3600.0, "the save is old")
	check_eq(Airport.economy.balance, float(saved["money"]) + SaveGame.welcome_back_bonus, "money plus the welcome-back income")
	_clean_up()


func test_early_v1_loads() -> void:
	_install_example(EARLY_V1)
	SaveGame.load_game()
	check_eq(SaveGame.load_problem, "", "no problem loading")
	check_eq(Airport.buildings.size(), 6, "its 5 buildings plus the starting runway it never had")
	check(Airport.staff.size() > 0, "stations get the staff they didn't need back then")
	check_eq(Airport.airlines.signed.size(), 1, "the starting airline")
	check_eq(Airport.progression.tier, Progression.Tier.REGIONAL, "a Regional airport")
	check_eq(Airport.clock.game_seconds, Clock.START_HOUR * 3600.0, "the clock starts at 06:00")
	check(Airport.passenger_flow.rng == Airport.rng, "it rolls the shared dice")
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
	var saved := _example(SHOWCASE_V1)
	# A pretend version 2 whose converter adds 1 € to the money, so we can see it ran before loading.
	SaveGame.format_version = 2
	SaveGame.migrations[1] = func(data: Dictionary) -> Dictionary:
		data["money"] = float(data["money"]) + 1.0
		return data
	_install_example(SHOWCASE_V1)
	SaveGame.load_game()
	check_eq(SaveGame.load_problem, "", "an old save loads in a newer version")
	check_eq(_building_counts(), EXAMPLE_BUILDINGS, "with every building")
	check_eq(Airport.economy.balance, float(saved["money"]) + 1.0 + SaveGame.welcome_back_bonus, "after its converter ran")
	_clean_up()


func test_missing_converter_keeps_the_save() -> void:
	SaveGame.format_version = 2  # newer build, but nobody wrote the converter
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


## Saves store these lists as plain numbers (zones per cell, the building kinds in staff
## experience, the tier, the weather). Reordering them, or inserting a value in the middle,
## silently changes what old saves mean. New values go at the end; anything else needs a
## converter (SaveGame.migrations) and a new FORMAT_VERSION.
func test_saved_number_lists_unchanged() -> void:
	var fix := " is stored as numbers in saves: add new values at the end, or write a converter"
	check_eq(AirportGrid.Zone.keys(), ["LANDSIDE", "AIRSIDE"], "AirportGrid.Zone" + fix)
	check_eq(BuildingType.Role.keys(), ["NONE", "ENTRANCE", "CHECK_IN", "SECURITY", "GATE", "AIRCRAFT_STAND", "SHOP",
		"BAGGAGE_CLAIM", "TRANSFER_SECURITY", "CAR_PARK", "LOUNGE", "RUNWAY", "CARGO_TERMINAL"], "BuildingType.Role" + fix)
	check_eq(Progression.Tier.keys(), ["REGIONAL", "NATIONAL", "INTERNATIONAL", "HUB"], "Progression.Tier" + fix)
	check_eq(Weather.Kind.keys(), ["CLEAR", "RAIN", "STORM", "FOG", "SNOW"], "Weather.Kind" + fix)
