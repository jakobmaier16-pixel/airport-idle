extends TestCase
## Seeded randomness (tech_architecture.md §3): the dice are kept and restored with the save, and a
## new game can be given its seed. Nothing rolls them since the timetable became fixed, so the
## same airport plays the same game whatever the seed is.


# A short summary of a running airport: if anything differed, this differs too.
func _fingerprint() -> String:
	var flights: PackedStringArray = []
	for flight in Airport.schedule.flights:
		flights.append("%s %.1ft" % [flight.number, flight.departure_time])
	return "departed %d, flights %s, slots %d" % [Airport.schedule.departures, ",".join(flights), Airport.timetable.slots.size()]


# Builds the showcase airport with dice started from `seed_value` and runs it for 15 minutes.
func _play(seed_value: int) -> String:
	Airport.reseed(seed_value)
	build_reference_airport()
	sim_seconds(900.0)
	return _fingerprint()


func test_same_game_for_every_seed() -> void:
	var first := _play(1234)
	var second := _play(1234)
	var other := _play(5)
	check(Airport.schedule.departures > 0, "the airport was busy (flights departed)")
	check_eq(second, first, "the same seed plays exactly the same game")
	check_eq(other, first, "so does another seed: the timetable is fixed")


func test_new_game_gets_a_seed_from_the_dice() -> void:
	Airport.reseed(5)
	Airport.reset()
	var first := Airport.game_seed
	Airport.reseed(5)
	Airport.reset()
	check_eq(Airport.game_seed, first, "a new game started from the same dice gets the same seed")
	Airport.reset(true, 777)
	check_eq(Airport.game_seed, 777, "a new game can be given its seed")


func test_dice_continue_after_loading() -> void:
	Airport.reseed(99)
	build_reference_airport()
	sim_seconds(60.0)
	var seed_before := Airport.game_seed
	# Through JSON text, like the real save file.
	var data: Dictionary = JSON.parse_string(JSON.stringify(Airport.save_state()))
	var next_rolls: Array[int] = []
	for i in 5:
		next_rolls.append(Airport.rng.randi())
	Airport.reset(false, 1)
	Airport.load_state(data)
	check_eq(Airport.game_seed, seed_before, "the seed is restored")
	var rolls_after_loading: Array[int] = []
	for i in 5:
		rolls_after_loading.append(Airport.rng.randi())
	check_eq(rolls_after_loading, next_rolls, "the dice continue exactly where they were")


func test_old_save_without_seed_loads() -> void:
	build_reference_airport()
	var data: Dictionary = JSON.parse_string(JSON.stringify(Airport.save_state()))
	var building_count := Airport.buildings.size()
	data.erase("seed")
	data.erase("rng_state")
	Airport.load_state(data)
	check_eq(Airport.buildings.size(), building_count, "a save from before seeds still loads completely")
