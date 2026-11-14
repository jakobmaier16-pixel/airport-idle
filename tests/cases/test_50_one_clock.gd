extends TestCase
## One clock (tech_architecture.md §3): the passengers have no timer of their own, everything runs
## on the brain's clock. Save format 7 carries it as "clock_elapsed".

const SHOWCASE_V6: String = "res://tests/saves/v6_showcase.json"
const SHOWCASE_V7: String = "res://tests/saves/v7_showcase.json"


func _fresh(saved: Dictionary) -> AirportWorld:
	var brain := AirportWorld.new()
	brain.load_state(saved)
	return brain


func test_passenger_time_is_the_clock() -> void:
	ShowcaseAirport.build()
	sim_seconds(30.0)
	var clock := Airport.clock
	check_eq(Airport.sim_time, clock.real_elapsed, "one number for both")
	check_eq(clock.elapsed, clock.real_elapsed * Clock.GAME_PER_REAL, "game seconds are 15 per second")
	check(clock.real_elapsed >= 30.0, "the clock ran")


func test_jumping_the_time_of_day_keeps_flights_in_place() -> void:
	ShowcaseAirport.build()
	sim_seconds(20.0)
	var before := Airport.sim_time
	Airport.clock.game_seconds = 14.5 * 3600.0
	check_eq(Airport.clock.hour(), 14.5, "the time of day jumped")
	check_eq(Airport.sim_time, before, "flight timing did not")
	sim_seconds(10.0)
	check(is_equal_approx(Airport.sim_time, before + 10.0), "and both run on")


func test_v6_converter_moves_the_timer_to_the_clock() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V6))
	var timer := float(saved["flow"]["time"])
	SaveGame.format_version = 7  # stop after the v6 converter: format 11 drops "flow" altogether
	var converted := SaveGame.migrate(saved)
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	check_eq(converted["version"], 7, "converted by the v6 step")
	check(not (converted["flow"] as Dictionary).has("time"), "the passenger timer is gone")
	check_eq(float(converted["clock_elapsed"]), timer * Clock.GAME_PER_REAL, "the clock carries it in game seconds")
	var loaded := _fresh(converted)
	check(is_equal_approx(loaded.sim_time, timer), "the flights see the same time as before")
	check_eq(loaded.clock.game_seconds, float(converted["clock"]), "the time of day is unchanged")
	for i in int(30.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()


func test_example_v7_loads() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V7))
	check_eq(int(saved["version"]), 7, "an example save of version 7")
	check_eq(SaveGame.migrate(saved)["version"], SaveGame.FORMAT_VERSION, "only the later converters run")
	var loaded := _fresh(saved)
	check(is_equal_approx(loaded.clock.elapsed, float(saved["clock_elapsed"])), "its clock is back")
	check_eq(loaded.schedule.flights.size(), 0, "its old flights are dropped (format 11)")
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()
