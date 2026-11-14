extends TestCase
## One time (tech_architecture.md §3): everything runs on the brain's simulation seconds, which
## format 12 saves as "sim_time". Older saves are converted step by step.

const SHOWCASE_V6: String = "res://tests/saves/v6_showcase.json"
const SHOWCASE_V7: String = "res://tests/saves/v7_showcase.json"


func _fresh(saved: Dictionary) -> AirportWorld:
	var brain := AirportWorld.new()
	brain.load_state(saved)
	return brain


func test_one_time_runs_in_seconds() -> void:
	ShowcaseAirport.build()
	var before := Airport.sim_time
	sim_seconds(30.0)
	check(is_equal_approx(Airport.sim_time, before + 30.0), "30 simulation steps of a second are 30 seconds")
	check(Airport.get("clock") == null, "there is no clock (docs/removed_features.md)")
	check(not ResourceLoader.exists("res://scripts/simulation/clock.gd"), "the clock script is deleted")
	check(not ResourceLoader.exists("res://scenes/day_night/day_night.gd"), "the day/night script is deleted")


func test_v6_converter_moves_the_timer_over() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V6))
	var timer := float(saved["flow"]["time"])
	SaveGame.format_version = 7  # stop after the v6 converter: format 11 drops "flow" altogether
	var converted := SaveGame.migrate(saved)
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	check_eq(converted["version"], 7, "converted by the v6 step")
	check(not (converted["flow"] as Dictionary).has("time"), "the passenger timer is gone")
	check_eq(float(converted["clock_elapsed"]), timer * 15.0, "the clock carried it in game seconds (x 15) at format 7")
	var loaded := _fresh(SaveGame.migrate(converted))
	check(is_equal_approx(loaded.sim_time, timer), "the flights see the same time as before")
	for i in int(30.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()


func test_example_v7_loads() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V7))
	check_eq(int(saved["version"]), 7, "an example save of version 7")
	var elapsed := float(saved["clock_elapsed"])
	check_eq(SaveGame.migrate(saved)["version"], SaveGame.FORMAT_VERSION, "only the later converters run")
	var loaded := _fresh(saved)
	check(is_equal_approx(loaded.sim_time, elapsed / 15.0), "its time is back")
	check_eq(loaded.schedule.flights.size(), 0, "its old flights are dropped (format 11)")
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()
