extends TestCase
## Growing demand (tech_architecture.md §6, design doc §3): one value, updated once per game day
## from stars and punctuality. Days are skipped by moving the clock, so a week costs a few steps.

const START: float = Demand.START
const CAP: float = 6.0  # the regional maximum at 5 stars


# Runs `days` game days with the airport in a fixed condition; returns the demand after each day.
func _run_days(days: int, stars_bonus: float, on_time: float) -> Array[float]:
	var values: Array[float] = []
	for i in days:
		Airport.reputation.penalty = stars_bonus
		Airport.reputation.on_time_rate = on_time
		Airport.clock.game_seconds += 86400.0
		Airport.step(Airport.SIM_STEP)
		values.append(Airport.demand.value)
	return values


func test_a_new_airport_starts_at_the_base_demand() -> void:
	check_eq(Airport.demand.value, START, "starting demand")
	check(Airport.demand.flights_per_day() > 50.0, "about 70 flights a day: %f" % Airport.demand.flights_per_day())


func test_a_good_airport_reaches_the_cap_in_about_five_days() -> void:
	Airport.step(Airport.SIM_STEP)
	var values := _run_days(8, -5.0, 1.0)
	check(Airport.stars() >= 4.99, "five stars")
	check(values[2] < CAP, "not there after three days: %f" % values[2])
	check(values[5] >= CAP - 0.001, "there after six days at the latest: %f" % values[5])
	check(values[0] > START, "it grows from the first day")
	check(values[7] <= CAP + 0.001, "never above the cap: %f" % values[7])
	check(Airport.demand.trend() == "steady", "steady once at the cap")


func test_the_cap_follows_the_stars_and_the_tier() -> void:
	Airport.step(Airport.SIM_STEP)
	var values := _run_days(10, 0.0, 1.0)
	var cap := Demand.cap_for(Progression.Tier.REGIONAL, Airport.stars())
	check(cap < CAP, "fewer stars, a lower cap: %f" % cap)
	check(absf(values[9] - cap) < 0.001, "demand stops at that cap: %f vs %f" % [values[9], cap])
	check(Demand.cap_for(Progression.Tier.NATIONAL, 5.0) > Demand.cap_for(Progression.Tier.REGIONAL, 5.0), "a higher tier allows more")


func test_a_bad_airport_loses_demand_slowly_but_not_below_the_start() -> void:
	Airport.step(Airport.SIM_STEP)
	var grown := _run_days(8, -5.0, 1.0)[7]
	var values := _run_days(40, 5.0, 0.2)
	var fall := grown - values[0]
	check(fall > 0.0, "it falls")
	check(fall < (CAP - START) / Demand.DAYS_TO_MAX * 0.5, "slower than it grew: %f" % fall)
	check(values[4] > START + 1.0, "still well above the start after five days: %f" % values[4])
	for value in values:
		check(value >= START, "never below the start: %f" % value)
	check_eq(values[39], START, "settles at the start")
	check(Airport.demand.trend() == "steady", "steady at the start")


func test_the_timetable_follows_demand() -> void:
	Airport.step(Airport.SIM_STEP)
	Airport.demand.value = START
	Airport.timetable.clear()
	Airport.clock.game_seconds = 5.0 * 3600.0
	Airport.step(Airport.SIM_STEP)
	var low := Airport.timetable.pending().size()
	Airport.demand.value = CAP
	Airport.timetable.clear()
	Airport.step(Airport.SIM_STEP)
	var high := Airport.timetable.pending().size()
	check(high > low * 1.5, "twice the demand, about twice the slots: %d vs %d" % [low, high])


func test_demand_is_saved() -> void:
	Airport.step(Airport.SIM_STEP)
	_run_days(3, -5.0, 1.0)
	var before := Airport.demand.value
	check(before > START, "grown")
	var brain := AirportWorld.new()
	brain.load_state(Airport.brain.save_state())
	check_eq(brain.demand.value, before, "demand survives save and load")
	check_eq(brain.demand.last_day, Airport.demand.last_day, "and its day")
	brain.dispose()


func test_an_old_save_without_demand_starts_at_the_base_without_catching_up() -> void:
	Airport.step(Airport.SIM_STEP)
	Airport.clock.game_seconds += 5.0 * 86400.0
	var saved := Airport.brain.save_state()
	saved.erase("demand")
	var brain := AirportWorld.new()
	brain.load_state(saved)
	brain.step(AirportWorld.SIM_STEP)
	check_eq(brain.demand.value, START, "no days of growth are invented")
	brain.dispose()


func test_the_hud_line_names_demand_and_trend() -> void:
	var text := Hud.demand_text(Airport.demand, 3.0)
	check(text.begins_with("Demand: "), "starts with the name: " + text)
	check(text.contains("flights/day") and text.contains("% full"), "flights and load factor: " + text)
