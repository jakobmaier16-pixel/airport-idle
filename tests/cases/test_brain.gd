extends TestCase
## The simulation is one self-contained object (tech_architecture.md §3, §17 step 2).


# The brain must never reach for the global `Airport` (the "no globals in scripts/simulation/" rule).
func test_simulation_code_has_no_global_airport() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for path in _gd_files("res://scripts/simulation"):
		scanned += 1
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := lines[i].split("#")[0]  # comments may mention Airport
			if RegEx.create_from_string("\\bAirport\\.").search(code) != null:
				offenders.append("%s:%d" % [path, i + 1])
	check(scanned > 10, "the scan found the simulation scripts (%d)" % scanned)
	check(offenders.is_empty(), "scripts/simulation/ uses the global Airport: %s" % [offenders])


func test_fresh_brain_runs_on_its_own() -> void:
	var brain := AirportWorld.new()
	var placed: Array[Building] = []
	brain.building_placed.connect(func(b: Building) -> void: placed.append(b))
	var check_in := brain.place_building(Airport.CATALOG.find(&"check_in"), MapAnchor.cell(Vector2i(20, 20), brain.grid.size), 0)
	check(check_in != null, "a building can be placed in a fresh brain")
	check_eq(placed.size(), 1, "the fresh brain sent its own building_placed signal")
	var start_seconds := brain.clock.game_seconds
	for i in int(60.0 / AirportWorld.SIM_STEP):
		brain.step(AirportWorld.SIM_STEP)
	check(brain.clock.game_seconds > start_seconds, "the fresh brain's clock advanced")
	check_eq(brain.buildings.size(), 1, "the fresh brain holds its building")
	check(brain.passenger_flow.world == brain, "the parts point at their own brain")
	check(Airport.buildings.is_empty(), "the running game's airport is untouched")
	brain.dispose()


func test_disposed_brain_is_freed() -> void:
	var brain := AirportWorld.new()
	brain.place_building(Airport.CATALOG.find(&"check_in"), MapAnchor.cell(Vector2i(20, 20), brain.grid.size), 0)
	for i in 50:
		brain.step(AirportWorld.SIM_STEP)
	var ref: WeakRef = weakref(brain)
	brain.dispose()
	brain = null
	check(ref.get_ref() == null, "a disposed brain is freed once nobody holds it")


# The host forwards to the brain, so `Airport.x` and `Airport.brain.x` are one and the same.
func test_host_forwards_to_its_brain() -> void:
	check(Airport.grid == Airport.brain.grid, "grid forwards")
	Airport.manager_yaw = 1.5
	check_eq(Airport.brain.manager_yaw, 1.5, "property writes reach the brain")
	var heard: Array[int] = [0]
	Airport.layout_changed.connect(func() -> void: heard[0] += 1)
	Airport.place_building(type_of(&"check_in"), at(Vector2i(20, 20)), 0)
	check(heard[0] >= 1, "brain signals are re-emitted by the host")
	Airport.manager_yaw = 0.0


func _gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	for sub in DirAccess.get_directories_at(dir_path):
		found.append_array(_gd_files(dir_path.path_join(sub)))
	return found


# reset() replaces the brain; the host re-binds its signals to the new one, exactly once.
func test_reset_gives_a_fresh_brain_and_signals_fire_once() -> void:
	var old_brain := Airport.brain
	var placed: Array[int] = [0]
	Airport.building_placed.connect(func(_b: Building) -> void: placed[0] += 1)
	Airport.reset(false)
	Airport.reset(false)
	check(Airport.brain != old_brain, "reset created a fresh brain")
	check(old_brain.passenger_flow.world == null, "the old brain was disposed")
	Airport.place_building(type_of(&"check_in"), at(Vector2i(20, 20)), 0)
	check_eq(placed[0], 1, "building_placed fires exactly once after resets")
	var relayed: Array[int] = [0]
	Airport.tier_reached.connect(func(_t: Progression.Tier) -> void: relayed[0] += 1)
	Airport.brain.progression.tier_reached.emit(Progression.Tier.REGIONAL)
	check_eq(relayed[0], 1, "signals of the brain's parts are re-sent once too")


# Same seed, same actions, same game: each run starts on a fresh brain (reset) and must end the same.
func test_same_seed_gives_identical_games() -> void:
	var results: Array[Array] = []
	for run in 2:
		Airport.reseed(1234)  # the reset inside build() takes its new seed from these dice
		ShowcaseAirport.build(0.0)
		sim_seconds(120.0)
		results.append([Airport.economy.balance, Airport.progression.passengers, Airport.passenger_flow.passengers.size(), Airport.passenger_flow.departed_count])
	check(results[0][1] > 0 or results[0][2] > 0, "the showcase airport had passengers (%s)" % [results[0]])
	check_eq(results[0], results[1], "two fresh brains with the same seed end the same")
