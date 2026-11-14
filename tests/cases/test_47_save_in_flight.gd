extends TestCase
## Flights on their way are saved (tech_architecture.md §13): a loaded game
## continues exactly where it stopped, and gets the same future as the game that was saved.

const SHOWCASE_V3: String = "res://tests/saves/v3_showcase.json"


# A busy showcase airport after about five game minutes, with everything in flight.
func _busy_airport() -> void:
	ShowcaseAirport.build()
	Airport.economy.balance = Economy.STARTING_MONEY
	# Painting walkways doesn't refresh the running costs until the next building change (an old
	# quirk, not part of this task); a load always works them out fresh. Refresh here so both agree.
	Airport.brain.layout_changed.emit()
	sim_seconds(20.0)


# Loads a save into a brand-new brain, the way a restart would.
func _load_fresh(saved: Dictionary) -> AirportWorld:
	var brain := AirportWorld.new()
	brain.load_state(saved)
	return brain


# The numbers that show whether two airports are in the same state.
func _summary(brain: AirportWorld) -> Dictionary:
	var phases: Array[int] = []
	var delays := 0.0
	var tonnes := 0.0
	for flight in brain.schedule.flights:
		phases.append(int(flight.phase))
		delays += flight.delay
		tonnes += flight.tonnes_handled
	return {
		"flights": brain.schedule.flights.size(), "phases": phases, "delays": snappedf(delays, 0.001),
		"tonnes": snappedf(tonnes, 0.001), "departed": brain.reputation.departures,
		"money": snappedf(brain.economy.balance, 0.01),
		"time": snappedf(brain.sim_time, 0.001), "clock": snappedf(brain.clock.game_seconds, 0.001),
	}


func _through_json(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state, "", true, true))


func test_loaded_game_continues_exactly() -> void:
	_busy_airport()
	var original := Airport.brain
	check(original.schedule.flights.size() > 3, "flights are on their way")
	var phases := {}
	for flight in original.schedule.flights:
		phases[flight.phase] = true
	check(phases.size() >= 2, "flights are in several phases (%s)" % [phases.keys()])
	# Saved as the real file would be: through JSON text.
	var saved := _through_json(original.save_state())
	check(not saved.has("flow"), "no passenger data is written any more")
	var loaded := _load_fresh(saved)
	check_eq(_summary(loaded), _summary(original), "right after loading: the same airport")
	# Both run on for two more game minutes (8 real seconds), then compare.
	for i in int(60.0 / AirportWorld.SIM_STEP):
		original.step(AirportWorld.SIM_STEP)
		loaded.step(AirportWorld.SIM_STEP)
	var a := _summary(original)
	var b := _summary(loaded)
	check_eq(b, a, "a minute later: the same airport")
	check(a["departed"] > 0 or a["phases"].size() > 0, "something actually happened meanwhile")
	loaded.dispose()


func test_saved_flights_keep_their_places() -> void:
	_busy_airport()
	var loaded := _load_fresh(_through_json(Airport.save_state()))
	check_eq(loaded.sim_time, Airport.sim_time, "the clock is saved, not restarted")
	check_eq(loaded.schedule.flights.size(), Airport.schedule.flights.size(), "every flight is back")
	for i in loaded.schedule.flights.size():
		var flight := loaded.schedule.flights[i]
		var twin := Airport.schedule.flights[i]
		check_eq(flight.number, twin.number, "the same flight number")
		check_eq(flight.gate.id, twin.gate.id, "at the same gate")
		check(flight.gate != null and loaded.buildings.has(flight.gate), "a flight stands at a loaded gate")
	loaded.dispose()


func test_old_save_starts_empty_apron() -> void:
	_busy_airport()
	var state := _through_json(Airport.save_state())
	state.erase("schedule")
	var loaded := _load_fresh(state)
	check_eq(loaded.schedule.flights.size(), 0, "no flights in a save without any")
	# The timetable (a slot opens a flight every minute or two) keeps planning them.
	for i in int(600.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.schedule.flights.size() > 0, "new flights get planned as before")
	loaded.dispose()


func test_save_before_the_strip_keeps_its_schedule_in_the_flow() -> void:
	# Saves written until 2026-11-14 kept the schedule inside the passenger flow ("flow").
	_busy_airport()
	var state := _through_json(Airport.save_state())
	state["flow"] = {"schedule": state["schedule"], "passengers": {"junk": true}, "stations": []}
	state.erase("schedule")
	var loaded := _load_fresh(state)
	check_eq(loaded.schedule.flights.size(), Airport.schedule.flights.size(), "its flights are read from the old place")
	loaded.dispose()


func test_demolished_gate_drops_its_flights() -> void:
	_busy_airport()
	var state := _through_json(Airport.save_state())
	var gate_id := int(((state["schedule"]["flights"] as Array)[0] as Dictionary)["gate"])
	state["buildings"] = (state["buildings"] as Array).filter(func(b: Dictionary) -> bool: return int(b["id"]) != gate_id)
	var loaded := _load_fresh(state)
	for flight in loaded.schedule.flights:
		check(flight.gate.id != gate_id, "no flight at the missing gate")
	for i in int(20.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(true, "it keeps running")
	loaded.dispose()


func test_example_v3_loads_with_flights() -> void:
	var text := FileAccess.get_file_as_string(SHOWCASE_V3)
	var saved: Dictionary = JSON.parse_string(text)
	check_eq(int(saved["version"]), 3, "an example save of version 3")
	var loaded := _load_fresh(SaveGame.migrate(saved.duplicate(true)))
	check(loaded.schedule.flights.size() > 0, "its flights are back")
	check_eq(loaded.sim_time, float(saved["flow"]["time"]), "its clock is back")
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.sim_time > float(saved["flow"]["time"]), "it keeps running")
	loaded.dispose()


func test_place_demolish_place_gives_new_ids() -> void:
	var type := type_of(&"check_in")
	var first := Airport.place_building(type, at(Vector2i(10, 10)), 0)
	var first_id := first.id
	check(Airport.demolish(first), "demolished")
	var second := Airport.place_building(type, at(Vector2i(10, 10)), 0)
	check(second != null and second.id != first_id, "the new building gets a new ID (%d, was %d)" % [second.id, first_id])
