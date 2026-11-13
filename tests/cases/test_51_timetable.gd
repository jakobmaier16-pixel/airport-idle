extends TestCase
## The daily timetable (tech_architecture.md §6): slots are planned once per game day from the
## demand curve, and the planner turns them into flights. Everything is checked over a span
## (a whole day), never at one random moment, so it holds for any seed.

const SHOWCASE_V7: String = "res://tests/saves/v7_showcase.json"
const SHOWCASE_V8: String = "res://tests/saves/v8_showcase.json"
const PEAK_HOURS: Array[int] = [7, 8, 18]
const NIGHT_HOURS: Array[int] = [21, 22, 23]


# The game hour a real-seconds time falls in.
func _hour_of(time: float) -> int:
	return int(Airport.clock.hour_at(time - Airport.passenger_flow.time))


# Plans tomorrow: the clock is at 23:00 of day 1, so day 2 is made whole. Returns day 2's slots.
func _tomorrows_slots(tier: Progression.Tier) -> Array[TimetableSlot]:
	Airport.progression.tier = tier
	Airport.clock.game_seconds = 23.0 * 3600.0
	Airport.step(Airport.SIM_STEP)
	check(Airport.timetable.generated_days.has(2), "tomorrow is planned shortly before midnight")
	var result: Array[TimetableSlot] = []
	for slot in Airport.timetable.slots:
		if slot.day == 2:
			result.append(slot)
	return result


func _per_hour(slots: Array[TimetableSlot]) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(24)
	counts.fill(0)
	for slot in slots:
		counts[_hour_of(slot.departure_time)] += 1
	return counts


func _sum(counts: Array[int], hours: Array[int]) -> int:
	var total := 0
	for hour in hours:
		total += counts[hour]
	return total


func test_a_new_airport_plans_today() -> void:
	Airport.step(Airport.SIM_STEP)
	check(Airport.timetable.generated_days.has(1), "day 1 is planned on the first step")
	var pending := Airport.timetable.pending()
	check(pending.size() > 10, "slots for the rest of the day: %d" % pending.size())
	var now := Airport.passenger_flow.time
	check(pending.all(func(s: TimetableSlot) -> bool: return s.departure_time >= now + FlightSchedule.FIRST_DEPARTURE_DELAY - 0.2), "none of them has already begun")
	for i in range(1, pending.size()):
		check(pending[i - 1].departure_time <= pending[i].departure_time, "in departure order")
		if pending[i - 1].departure_time > pending[i].departure_time:
			break


func test_a_day_follows_the_demand_curve() -> void:
	var slots := _tomorrows_slots(Progression.Tier.HUB)  # no curfew: all 24 hours
	var counts := _per_hour(slots)
	var total := slots.size()
	# About 3 narrow flights an hour on average, plus a few wide-bodies and freighters.
	check(total > 50 and total < 120, "a day of slots: %d" % total)
	check(_sum(counts, PEAK_HOURS) > _sum(counts, NIGHT_HOURS), "rush hours have more flights than the late evening: %s vs %s" % [_sum(counts, PEAK_HOURS), _sum(counts, NIGHT_HOURS)])
	var rush_average := float(_sum(counts, [6, 7, 8, 9, 17, 18, 19])) / 7.0
	var night_average := float(_sum(counts, [0, 1, 2, 3, 4])) / 5.0
	check(rush_average > night_average * 1.5, "and far more than the night: %.1f vs %.1f an hour %s" % [rush_average, night_average, counts])
	check(_sum(counts, [0, 1, 2, 3, 4]) > 0, "a hub plans night flights too: %s" % [counts])
	for slot in slots:
		check(slot.state == TimetableSlot.State.PENDING, "planned, not yet flown")
		match slot.plane_class:
			TimetableSlot.PlaneClass.NARROW: check_eq(slot.seats, FlightSchedule.SEATS, "narrow-body seats")
			TimetableSlot.PlaneClass.WIDE: check_eq(slot.seats, FlightSchedule.SEATS * 2, "wide-body seats")
			TimetableSlot.PlaneClass.CARGO: check_eq(slot.seats, 0, "freighters carry freight")


func test_no_slots_in_curfew_hours() -> void:
	var slots := _tomorrows_slots(Progression.Tier.NATIONAL)
	check(slots.size() > 40, "a day of slots: %d" % slots.size())
	for slot in slots:
		var hour := _hour_of(slot.departure_time)
		check(hour >= int(Clock.CURFEW_END), "no slot at hour %d" % hour)
		check(not Airport.timetable.in_curfew(slot.departure_time), "the plane neither lands nor leaves in the curfew")


func test_seasons_change_the_slots_per_route() -> void:
	# Holiday demand: x1.35 in summer, x0.75 in winter (design doc §12.2). Averaged over several
	# days so a few slots more or less don't matter.
	var count_days := func(first_day: int) -> int:
		var total := 0
		Airport.progression.tier = Progression.Tier.HUB
		for day in range(first_day, first_day + 2):
			Airport.timetable.generate_day(day)
		for slot in Airport.timetable.slots:
			if slot.plane_class == TimetableSlot.PlaneClass.NARROW and slot.day >= first_day and slot.day < first_day + 2:
				total += 1
		return total
	Airport.step(Airport.SIM_STEP)
	Airport.timetable.slots.clear()
	var summer: int = count_days.call(3)   # days 3-4 are summer
	Airport.timetable.slots.clear()
	var winter: int = count_days.call(7)   # days 7-8 are winter
	check(summer > winter * 1.25, "more holiday flights in summer than in winter: %d vs %d" % [summer, winter])


func test_a_full_day_of_flights() -> void:
	ShowcaseAirport.build(0.0)
	Airport.progression.tier = Progression.Tier.INTERNATIONAL
	var by_hour: Array[int] = []
	by_hour.resize(24)
	by_hour.fill(0)
	var seen: Dictionary[Flight, bool] = {}
	var all: Array[Flight] = []
	for i in int(5760.0 / Airport.SIM_STEP):  # one game day
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.passenger_flow.schedule.flights:
			if not seen.has(flight):
				seen[flight] = true
				all.append(flight)
				by_hour[_hour_of(flight.departure_time)] += 1
	check(all.size() > 25, "flights over a full day: %d" % all.size())
	# The showcase's three gates are full at the rush (their turnaround caps a single hour), so only
	# "not fewer" can hold here; the slots themselves follow the curve (test_a_day_follows_the_demand_curve).
	var rush: Array[int] = [6, 7, 8, 9, 17, 18, 19]
	var evening: Array[int] = [20, 21, 22, 23]
	var rush_average := float(_sum(by_hour, rush)) / rush.size()
	var evening_average := float(_sum(by_hour, evening)) / evening.size()
	check(rush_average >= evening_average, "an average rush hour is at least as busy as an evening hour: %.1f vs %.1f" % [rush_average, evening_average])
	for hour in 5:
		check_eq(by_hour[hour], 0, "no flight departs in curfew hour %d" % hour)
	for flight in all:
		check(not Airport.timetable.in_curfew(flight.departure_time), "%s is outside the curfew" % flight.number)
		check(flight.booked <= flight.seats, "%s: bookings %d within %d seats" % [flight.number, flight.booked, flight.seats])
		check(flight.boarded <= flight.seats, "%s: boarded %d within %d seats" % [flight.number, flight.boarded, flight.seats])
	var slots := Airport.timetable.slots
	var filled := slots.filter(func(s: TimetableSlot) -> bool: return s.state == TimetableSlot.State.FILLED).size()
	check(filled > 25, "filled slots: %d" % filled)


func test_a_dropped_slot_is_not_flown() -> void:
	# No gate at all: every slot that comes up is dropped, and no flight appears.
	Airport.progression.tier = Progression.Tier.HUB
	sim_seconds(900.0)
	check(Airport.passenger_flow.schedule.flights.is_empty(), "nothing flies without a gate")
	var dropped := Airport.timetable.slots.filter(func(s: TimetableSlot) -> bool: return s.state == TimetableSlot.State.DROPPED)
	check(dropped.size() > 3, "the slots that came up were dropped: %d" % dropped.size())


func test_slots_are_saved_and_not_planned_twice() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(600.0)
	var slots := Airport.timetable.slots
	var saved := JSON.parse_string(JSON.stringify(Airport.save_state(), "", true, true)) as Dictionary
	check(saved.has("timetable"), "the timetable is saved")
	var loaded := AirportWorld.new()
	loaded.load_state(saved)
	check_eq(loaded.timetable.slots.size(), slots.size(), "all slots are back")
	check_eq(loaded.timetable.generated_days, Airport.timetable.generated_days, "and the days that are planned")
	var states_a: Array[int] = []
	var states_b: Array[int] = []
	for i in slots.size():
		states_a.append(int(slots[i].state))
		states_b.append(int(loaded.timetable.slots[i].state))
		check(is_equal_approx(loaded.timetable.slots[i].departure_time, slots[i].departure_time), "same departure time")
	check_eq(states_b, states_a, "same states")
	loaded.step(AirportWorld.SIM_STEP)
	check_eq(loaded.timetable.slots.size(), slots.size(), "loading does not plan the day again")
	loaded.dispose()


func test_v7_converter_builds_slots_from_the_saved_flights() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V7))
	var flights: Array = saved["flow"]["schedule"]["flights"].filter(func(f: Dictionary) -> bool: return bool(f["scheduled"]))
	check(flights.size() > 0, "the example has flights on their way (%d)" % flights.size())
	var converted := SaveGame.migrate(saved)
	check_eq(converted["version"], SaveGame.FORMAT_VERSION, "up to the current version")
	var slots: Array = converted["timetable"]["slots"]
	check_eq(slots.size(), flights.size(), "one filled slot per planned flight")
	for i in slots.size():
		check_eq(int(slots[i]["state"]), int(TimetableSlot.State.FILLED), "already flown or on its way")
		check_eq(slots[i]["number"], flights[i]["number"], "same flight number")
	var loaded := AirportWorld.new()
	loaded.load_state(converted)
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.timetable.pending().size() > 5, "the rest of the day is planned on the first step: %d" % loaded.timetable.pending().size())
	loaded.dispose()


func test_example_v8_loads() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V8))
	check_eq(int(saved["version"]), 8, "an example save of version 8")
	check_eq(SaveGame.migrate(saved)["version"], SaveGame.FORMAT_VERSION, "converted to the newest version")
	check((saved["timetable"]["slots"] as Array).size() > 10, "it has slots")
	var loaded := AirportWorld.new()
	loaded.load_state(saved)
	check_eq(loaded.timetable.slots.size(), (saved["timetable"]["slots"] as Array).size(), "its slots are back")
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.passenger_flow.passengers.size() > 0, "it keeps running")
	loaded.dispose()


func test_jumping_the_time_of_day_replans_the_pending_slots() -> void:
	Airport.step(Airport.SIM_STEP)
	var before := Airport.timetable.pending().size()
	check(before > 0, "slots are planned")
	Airport.progression.tier = Progression.Tier.HUB
	Airport.clock.game_seconds = 2.0 * 3600.0
	Airport.step(Airport.SIM_STEP)
	var pending := Airport.timetable.pending()
	check(pending.size() > 0 and pending.all(func(s: TimetableSlot) -> bool: return s.day == 1), "slots for the new time of day")
	# Slots are spread over the 22 hours ahead, starting at 02:00.
	check(_hour_of(pending[0].departure_time) in [2, 3, 4], "the first one is in the next hours: %d" % _hour_of(pending[0].departure_time))
