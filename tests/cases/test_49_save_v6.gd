extends TestCase
## Old example saves (versions 5 and 6, written while passengers existed) still load: they are
## converted up to the current version, the removed building types are skipped with a refund,
## and the airport keeps running. The passenger data in them is ignored.

const SHOWCASE_V5: String = "res://tests/saves/v5_showcase.json"
const SHOWCASE_V6: String = "res://tests/saves/v6_showcase.json"


func _fresh(saved: Dictionary) -> AirportWorld:
	var brain := AirportWorld.new()
	brain.load_state(saved)
	return brain


func test_example_v5_loads_without_its_passengers() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V5))
	check_eq(int(saved["version"]), 5, "an example save of version 5")
	check(saved.has("flow"), "it still carries its passenger data")
	var converted := SaveGame.migrate(saved)
	check_eq(converted["version"], SaveGame.FORMAT_VERSION, "converted up to the current version")
	var loaded := _fresh(converted)
	check(loaded.buildings.size() > 5, "its buildings are back (%d)" % loaded.buildings.size())
	for i in int(30.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()


func test_example_v6_loads() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V6))
	check_eq(int(saved["version"]), 6, "an example save of version 6")
	check_eq(SaveGame.migrate(saved)["version"], SaveGame.FORMAT_VERSION, "converted up to the current version")
	var loaded := _fresh(saved)
	check(loaded.buildings.size() > 5, "its buildings are back (%d)" % loaded.buildings.size())
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()
