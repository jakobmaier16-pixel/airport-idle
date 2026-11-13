extends TestCase
## Flights and passengers on their way are saved (tech_architecture.md §13): a loaded game
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
	var flow := brain.passenger_flow
	var phases: Array[int] = []
	var delays := 0.0
	var boarded := 0
	for flight in flow.schedule.flights:
		phases.append(int(flight.phase))
		delays += flight.delay
		boarded += flight.boarded
	var moods := 0.0
	var queued := 0
	for station in flow.stations():
		queued += station.queue.size() + station.waiting.size()
	for passenger in flow.passengers:
		moods += passenger.mood
	return {
		"passengers": flow.passengers.size(), "flights": flow.schedule.flights.size(), "phases": phases,
		"delays": delays, "boarded": boarded, "departed": flow.departed_count, "arrived": flow.arrived_count,
		"in_stations": queued, "mood": snappedf(moods, 0.001), "money": snappedf(brain.economy.balance, 0.01),
		"time": snappedf(flow.time, 0.001), "clock": snappedf(brain.clock.game_seconds, 0.001),
	}


func _through_json(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state, "", true, true))


func test_loaded_game_continues_exactly() -> void:
	_busy_airport()
	var original := Airport.brain
	check(original.passenger_flow.passengers.size() > 10, "a busy airport (%d passengers)" % original.passenger_flow.passengers.size())
	check(original.passenger_flow.schedule.flights.size() > 3, "flights are on their way")
	var states := {}
	for passenger in original.passenger_flow.passengers:
		states[passenger.state] = true
	check(states.size() >= 3, "passengers are in several states (%s)" % [states.keys()])
	# Saved as the real file would be: through JSON text.
	var saved := _through_json(original.save_state())
	var loaded := _load_fresh(saved)
	check_eq(_summary(loaded), _summary(original), "right after loading: the same airport")
	# Both run on for two more game minutes (8 real seconds), then compare.
	for i in int(60.0 / AirportWorld.SIM_STEP):
		original.step(AirportWorld.SIM_STEP)
		loaded.step(AirportWorld.SIM_STEP)
	var a := _summary(original)
	var b := _summary(loaded)
	check_eq(b, a, "a minute later: the same airport")
	check(a["boarded"] > 0 or a["departed"] > 0 or a["arrived"] > 0, "something actually happened meanwhile")
	loaded.dispose()


func test_saved_passengers_keep_their_places() -> void:
	_busy_airport()
	var flow := Airport.passenger_flow
	var loaded := _load_fresh(_through_json(Airport.save_state()))
	var again := loaded.passenger_flow
	check_eq(again.time, flow.time, "the passenger clock is saved, not restarted")
	check_eq(again.passengers.size(), flow.passengers.size(), "every passenger is back")
	for station in flow.stations():
		var twin := loaded.buildings.filter(func(b: Building) -> bool: return b.id == station.building.id)
		var copy := again.station_for(twin[0]) if not twin.is_empty() else null
		check(copy != null and copy.building.id == station.building.id, "the station is back")
		if copy == null:
			continue
		check_eq(copy.queue.size(), station.queue.size(), "queue of %s" % station.building.type.id)
		check_eq(copy.waiting.size(), station.waiting.size(), "waiting at %s" % station.building.type.id)
		check_eq(copy.serving.count(null), station.serving.count(null), "free counters at %s" % station.building.type.id)
	for flight in again.schedule.flights:
		check(flight.gate != null and loaded.buildings.has(flight.gate), "a flight stands at a loaded gate")
	loaded.dispose()


func test_old_save_starts_empty_apron() -> void:
	_busy_airport()
	var state := _through_json(Airport.save_state())
	state.erase("flow")
	var loaded := _load_fresh(state)
	check_eq(loaded.passenger_flow.passengers.size(), 0, "no passengers in a save without any")
	check_eq(loaded.passenger_flow.schedule.flights.size(), 0, "no flights either")
	# The timetable (a slot opens a flight every minute or two) keeps planning them.
	for i in int(600.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.passenger_flow.schedule.flights.size() > 0, "new flights get planned as before")
	loaded.dispose()


func test_demolished_gate_drops_its_flights() -> void:
	_busy_airport()
	var state := _through_json(Airport.save_state())
	var gate_id := int(((state["flow"]["schedule"]["flights"] as Array)[0] as Dictionary)["gate"])
	state["buildings"] = (state["buildings"] as Array).filter(func(b: Dictionary) -> bool: return int(b["id"]) != gate_id)
	var loaded := _load_fresh(state)
	for flight in loaded.passenger_flow.schedule.flights:
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
	check(loaded.passenger_flow.passengers.size() > 0, "its passengers are back")
	check(loaded.passenger_flow.schedule.flights.size() > 0, "its flights are back")
	check_eq(loaded.passenger_flow.time, float(saved["flow"]["time"]), "its passenger clock is back")
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.passenger_flow.passengers.size() > 0, "it keeps running")
	loaded.dispose()


func test_place_demolish_place_gives_new_ids() -> void:
	var type := type_of(&"check_in")
	var first := Airport.place_building(type, Vector2i(10, 10), 0)
	var first_id := first.id
	check(Airport.demolish(first), "demolished")
	var second := Airport.place_building(type, Vector2i(10, 10), 0)
	check(second != null and second.id != first_id, "the new building gets a new ID (%d, was %d)" % [second.id, first_id])
