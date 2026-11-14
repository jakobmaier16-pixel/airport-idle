extends TestCase
## The fixed timetable (tech_architecture.md §6): every usable gate with its stand gets one
## turnaround every Timetable.TURNAROUND_MINUTES game minutes, staggered by the gate's ID, with no
## dice. Everything is checked over a span, never at one moment.

const SHOWCASE_V7: String = "res://tests/saves/v7_showcase.json"
const SHOWCASE_V8: String = "res://tests/saves/v8_showcase.json"


# The slots of `gate`, in departure order.
func _slots_of(gate: Building) -> Array[TimetableSlot]:
	return Airport.timetable.slots.filter(func(s: TimetableSlot) -> bool: return s.gate == gate)


# A readable list of the whole pattern: gate ID, plane class and departure time of every slot.
func _pattern() -> Array:
	return Airport.timetable.slots.map(func(s: TimetableSlot) -> Array: return [s.gate.id, int(s.plane_class), snappedf(s.departure_time, 0.001)])


func test_the_turnaround_is_one_number() -> void:
	check_eq(Timetable.period_game(), Timetable.TURNAROUND_MINUTES * 60.0, "game seconds between two departures")
	check_eq(Timetable.period_real(), Timetable.TURNAROUND_MINUTES * 60.0 / Clock.GAME_PER_REAL, "real seconds between two departures")
	check(Timetable.period_real() > FlightSchedule.STAND_DWELL + FlightSchedule.BOARDING_OPENS, "long enough for a plane to stand there")


func test_each_usable_gate_gets_a_turnaround_every_period() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(5.0 * Timetable.period_real())
	var gates := Airport.usable_gates()
	check_eq(gates.size(), 3, "the showcase has three usable gates")
	for gate in gates:
		var slots := _slots_of(gate)
		check(slots.size() >= 5, "gate %d has slots for several turnarounds: %d" % [gate.id, slots.size()])
		for i in range(1, slots.size()):
			check(absf(slots[i].departure_time - slots[i - 1].departure_time - Timetable.period_real()) < 0.01,
				"gate %d: exactly one turnaround between departures (%s)" % [gate.id, slots.map(func(s: TimetableSlot) -> float: return s.departure_time)])
		# On the pattern: the game time of every departure is the gate's phase plus whole turnarounds.
		var phase := fmod(gate.id * Timetable.STAGGER_MINUTES, Timetable.TURNAROUND_MINUTES) * 60.0
		for slot in slots:
			var game_time := Airport.clock.game_seconds + (slot.departure_time - Airport.sim_time) * Clock.GAME_PER_REAL
			var steps := (game_time - phase) / Timetable.period_game()
			check(absf(steps - roundf(steps)) < 0.0001, "gate %d: departure on its own grid (%.4f)" % [gate.id, steps])


func test_gates_are_staggered_by_their_id() -> void:
	var phases := {}
	for gate_id in range(1, 4):
		phases[Timetable.next_departure_at_or_after(gate_id, 0.0)] = true
	check_eq(phases.size(), 3, "three neighbouring gate IDs start at three different times")
	var base := Timetable.next_departure_at_or_after(5, 100000.0)
	check_eq(Timetable.next_departure_at_or_after(5, base), base, "a departure on the grid is its own next one")
	check_eq(Timetable.next_departure_at_or_after(5, base + 1.0), base + Timetable.period_game(), "just after it: the next turnaround")


func test_the_plane_class_fits_the_stand() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(3.0 * Timetable.period_real())
	var wide := 0
	var narrow := 0
	for slot in Airport.timetable.slots:
		var stand := Airport.stand_behind(slot.gate)
		check(stand.type.fits(slot.plane_class), "the stand takes the plane of its slot")
		if stand.type.wide_body:
			check_eq(slot.plane_class, TimetableSlot.PlaneClass.WIDE, "a wide stand gets wide planes")
			wide += 1
		else:
			check_eq(slot.plane_class, TimetableSlot.PlaneClass.NARROW, "a narrow stand gets narrow planes")
			narrow += 1
	check(wide > 0 and narrow > 0, "both kinds are planned (%d wide, %d narrow)" % [wide, narrow])
	sim_seconds(600.0)
	for flight in Airport.schedule.flights:
		check_eq(flight.plane_class == TimetableSlot.PlaneClass.WIDE, flight.stand.type.wide_body, "flights fly the class of their stand")


func test_the_timetable_is_deterministic_and_rolls_no_dice() -> void:
	Airport.reseed(1)
	ShowcaseAirport.build(0.0)
	var dice_before := Airport.rng.state
	sim_seconds(1200.0)
	check_eq(Airport.rng.state, dice_before, "no dice were rolled")
	var first := _pattern()
	Airport.reseed(99999)
	ShowcaseAirport.build(0.0)
	sim_seconds(1200.0)
	check(not first.is_empty(), "there is a pattern")
	check_eq(_pattern(), first, "another seed gives exactly the same timetable")


func test_a_full_day_has_flights_all_day_and_night() -> void:
	ShowcaseAirport.build(0.0)
	var by_gate: Dictionary[Building, int] = {}
	var by_hour: Array[int] = []
	by_hour.resize(24)
	by_hour.fill(0)
	var seen: Dictionary[Flight, bool] = {}
	for i in int(5760.0 / Airport.SIM_STEP):  # one game day
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if not seen.has(flight):
				seen[flight] = true
				by_gate[flight.gate] = by_gate.get(flight.gate, 0) + 1
				by_hour[int(Airport.clock.hour_at(flight.departure_time - Airport.sim_time))] += 1
	var expected := int(5760.0 / Timetable.period_real())
	for gate in Airport.usable_gates():
		check(by_gate.get(gate, 0) >= expected - 3, "gate %d flew about %d times a day: %d" % [gate.id, expected, by_gate.get(gate, 0)])
	for hour in 24:
		check(by_hour[hour] > 0, "a departure in hour %d (no curfew, no rush): %s" % [hour, by_hour])


func test_no_gate_no_slots() -> void:
	sim_seconds(900.0)
	check(Airport.timetable.slots.is_empty(), "nothing is planned without a usable gate")
	check(Airport.schedule.flights.is_empty(), "nothing flies without a gate")


func test_a_gate_that_stops_working_loses_its_slots() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(60.0)
	var gate := Airport.usable_gates()[0]
	check(not _slots_of(gate).is_empty(), "it has slots")
	Airport.demolish(Airport.stand_behind(gate))
	sim_seconds(1.0)
	check(_slots_of(gate).filter(func(s: TimetableSlot) -> bool: return s.state == TimetableSlot.State.PENDING).is_empty(), "its pending slots are gone")


func test_a_rebuilt_gate_starts_on_its_own_grid() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(60.0)
	var old := Airport.usable_gates()[0]
	var type := old.type
	var origin := old.origin_cell
	Airport.demolish(old)
	sim_seconds(1.0)
	check_eq(Airport.usable_gates().size(), 2, "one gate less")
	var gate := Airport.place_building(type, origin, 0)
	check(gate != null and gate.id != old.id, "a new gate with a new ID")
	sim_seconds(5.0)
	check_eq(Airport.usable_gates().size(), 3, "it works again")
	var slots := _slots_of(gate)
	check(not slots.is_empty(), "it got its own slots")
	var phase := fmod(gate.id * Timetable.STAGGER_MINUTES, Timetable.TURNAROUND_MINUTES) * 60.0
	for slot in slots:
		var game_time := Airport.clock.game_seconds + (slot.departure_time - Airport.sim_time) * Clock.GAME_PER_REAL
		var steps := (game_time - phase) / Timetable.period_game()
		check(absf(steps - roundf(steps)) < 0.0001, "on the grid of its new ID")


func test_slots_are_saved_and_not_planned_twice() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(600.0)
	var slots := Airport.timetable.slots
	var saved := JSON.parse_string(JSON.stringify(Airport.save_state(), "", true, true)) as Dictionary
	check(saved.has("timetable"), "the timetable is saved")
	var loaded := AirportWorld.new()
	loaded.load_state(saved)
	check_eq(loaded.timetable.slots.size(), slots.size(), "all slots are back")
	var states_a: Array[int] = []
	var states_b: Array[int] = []
	for i in slots.size():
		states_a.append(int(slots[i].state))
		states_b.append(int(loaded.timetable.slots[i].state))
		check(is_equal_approx(loaded.timetable.slots[i].departure_time, slots[i].departure_time), "same departure time")
		check_eq(loaded.timetable.slots[i].gate.id, slots[i].gate.id, "same gate")
	check_eq(states_b, states_a, "same states")
	loaded.step(AirportWorld.SIM_STEP)
	check_eq(loaded.timetable.slots.size(), slots.size(), "loading does not plan the same turnarounds again")
	loaded.dispose()


func test_v7_converter_drops_the_old_timetable() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V7))
	var flights: Array = saved["flow"]["schedule"]["flights"].filter(func(f: Dictionary) -> bool: return bool(f["scheduled"]))
	check(flights.size() > 0, "the example has flights on their way (%d)" % flights.size())
	SaveGame.format_version = 8  # stop after the v7 converter, which builds the old slots
	var converted := SaveGame.migrate(JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V7)))
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	var slots: Array = converted["timetable"]["slots"]
	check_eq(slots.size(), flights.size(), "one filled slot per planned flight")
	check_eq(SaveGame.migrate(saved)["version"], SaveGame.FORMAT_VERSION, "and all the way up to the current version")
	check(not saved.has("flow") and not saved.has("timetable"), "the old timetable and flights are dropped")


func test_example_v8_loads_and_keeps_running() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V8))
	check_eq(int(saved["version"]), 8, "an example save of version 8")
	var converted := SaveGame.migrate(saved)
	check_eq(converted["version"], SaveGame.FORMAT_VERSION, "converted to the newest version")
	var loaded := AirportWorld.new()
	loaded.load_state(converted)
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > 0.0, "it keeps running")
	loaded.dispose()


func test_jumping_the_time_of_day_replans_the_pending_slots() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(1.0)
	var before := Airport.timetable.pending().size()
	check(before > 0, "slots are planned")
	Airport.clock.game_seconds = 2.0 * 3600.0
	sim_seconds(1.0)
	var pending := Airport.timetable.pending()
	check(pending.size() > 0, "slots for the new time of day")
	var hour := int(Airport.clock.hour_at(pending[0].departure_time - Airport.sim_time))
	check(hour in [2, 3, 4, 5], "the first one is in the next hours: %d" % hour)
