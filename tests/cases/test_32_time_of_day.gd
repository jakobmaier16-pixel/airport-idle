extends TestCase
## Time of day: clock, demand by hour, day and night light (design doc §12.1).


func test_clock_runs_fifteen_times_faster() -> void:
	var clock := Airport.clock
	check_eq(clock.text(), "Day 1 · 06:00", "a new airport opens at 6 in the morning")
	sim_seconds(60)
	check_eq(clock.text(), "Day 1 · 06:15", "one real minute = 15 minutes")
	clock.game_seconds = 23.5 * 3600.0
	sim_seconds(240)
	check_eq(clock.text(), "Day 2 · 00:30", "a new day")
	check(is_equal_approx(clock.hour_at(120.0), 1.0), "two real minutes ahead is 01:00")


func test_demand_follows_the_day() -> void:
	check(Clock.demand_factor(3.0) < 0.5, "quiet at night")
	check(Clock.demand_factor(7.5) > 1.2, "morning rush")
	check(Clock.demand_factor(18.0) > 1.2, "evening rush")
	var total := 0.0
	for hour in 24:
		total += Clock.demand_factor(hour)
	check(absf(total / 24.0 - 0.9) < 0.1, "about the usual number over a day: %.2f" % (total / 24.0))


func test_clock_is_saved() -> void:
	Airport.clock.game_seconds = 3.0 * 86400.0 + 14.5 * 3600.0
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check_eq(Airport.clock.text(), "Day 4 · 14:30", "restored")


func test_day_and_night_light() -> void:
	await start_game()
	var sun := main.get_node("Sun") as DirectionalLight3D
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	Airport.clock.game_seconds = 13.0 * 3600.0
	await frames(1)
	var noon_energy := sun.light_energy
	var noon_elevation := -sun.rotation.x
	Airport.clock.game_seconds = 1.0 * 3600.0
	await frames(1)
	check(sun.light_energy < noon_energy * 0.5, "dim at night: %.2f vs %.2f" % [sun.light_energy, noon_energy])
	check(environment.ambient_light_energy < 0.7, "darker ambient at night")
	check(sun.light_color.b > sun.light_color.r, "blue moonlight")
	Airport.clock.game_seconds = 7.0 * 3600.0
	await frames(1)
	check(-sun.rotation.x < noon_elevation, "the morning sun is lower than at noon")
	check((ui("TopButtons/ClockLabel") as Label).text == "Day 1 · 07:00 · Spring", "clock and season in the HUD")
