extends TestCase
## Seeded randomness (tech_architecture.md §3): the same seed and the same actions give exactly
## the same game, and the dice continue where they were after loading a save.


# A short summary of a running airport: if any random choice differed, this differs too.
func _fingerprint() -> String:
	var flow := Airport.passenger_flow
	var positions := 0.0
	for passenger in flow.passengers:
		positions += passenger.position.x * 3.0 + passenger.position.z
	var names: PackedStringArray = []
	for employee in Airport.staff:
		names.append(employee.name)
	return "departed %d, missed %d, in airport %d, money %.2f, positions %.3f, staff %s" % [
		flow.departed_count, flow.missed_count, flow.passengers.size(), Airport.economy.balance,
		positions, ",".join(names)]


# Builds the showcase airport with dice started from `seed_value` and runs it for 5 minutes.
func _play(seed_value: int) -> String:
	Airport.reseed(seed_value)
	build_reference_airport()
	sim_seconds(300.0)
	return _fingerprint()


func test_same_seed_same_game() -> void:
	var first := _play(1234)
	var second := _play(1234)
	check(Airport.passenger_flow.departed_count > 0, "the airport was busy (passengers departed)")
	check_eq(second, first, "the same seed plays exactly the same game")


func test_other_seed_other_game() -> void:
	check(_play(1) != _play(2), "a different seed plays a different game")


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
	check(Airport.passenger_flow.rng == Airport.rng and Airport.airlines.rng == Airport.rng \
		and Airport.weather.rng == Airport.rng and Airport.passenger_flow.schedule.rng == Airport.rng,
		"every part of the simulation rolls the same dice after loading")


func test_old_save_without_seed_loads() -> void:
	build_reference_airport()
	var data: Dictionary = JSON.parse_string(JSON.stringify(Airport.save_state()))
	var building_count := Airport.buildings.size()
	data.erase("seed")
	data.erase("rng_state")
	Airport.load_state(data)
	check_eq(Airport.buildings.size(), building_count, "a save from before seeds still loads completely")
	check(Airport.passenger_flow.rng == Airport.rng, "it gets fresh shared dice")
