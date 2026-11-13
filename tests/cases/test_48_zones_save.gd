extends TestCase
## Zones are computed, not saved (format version 4): old saves lose their painted zones on
## loading and get the same zones computed from their layout.

const SHOWCASE_V3: String = "res://tests/saves/v3_showcase.json"
const SHOWCASE_V4: String = "res://tests/saves/v4_showcase.json"


func _loaded(path: String) -> AirportWorld:
	var brain := AirportWorld.new()
	brain.weather.automatic = false
	brain.incidents_automatic = false
	brain.load_state(SaveGame.migrate(JSON.parse_string(FileAccess.get_file_as_string(path))))
	return brain


func test_example_v4_has_no_zones_and_loads() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V4))
	check_eq(int(saved["version"]), 4, "an example save of version 4")
	check(not saved.has("zones"), "no zones in it")
	var loaded := _loaded(SHOWCASE_V4)
	check_eq(loaded.grid.get_zone(Vector2i(20, 32)), AirportGrid.Zone.AIRSIDE, "airside behind security")
	check_eq(loaded.grid.get_zone(Vector2i(20, 25)), AirportGrid.Zone.LANDSIDE, "the hall is landside")
	loaded.dispose()


func test_v3_zones_are_dropped_and_recomputed() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V3))
	check(saved.has("zones"), "the old example still has painted zones")
	check(not SaveGame.migrate(saved).has("zones"), "the converter drops them")
	var old := _loaded(SHOWCASE_V3)
	var current := _loaded(SHOWCASE_V4)
	check_eq(old.grid.get_zone(Vector2i(20, 32)), AirportGrid.Zone.AIRSIDE, "airside behind security")
	check_eq(old.grid.get_zone(Vector2i(20, 25)), AirportGrid.Zone.LANDSIDE, "the hall is landside")
	check_eq(old.buildings.size(), current.buildings.size(), "same airport")
	old.dispose()
	current.dispose()
