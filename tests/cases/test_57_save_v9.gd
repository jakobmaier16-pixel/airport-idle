extends TestCase
## Save format 9 (tech_architecture.md §13): walkways and taxiways are lists of non-empty 64 x 64
## chunks, and a save from a map of another size is placed in the middle of the current map.

const SAVES: Array[String] = [
	"v1_early", "v1_showcase", "v2_showcase", "v3_showcase", "v4_showcase", "v5_showcase",
	"v6_showcase", "v7_showcase", "v8_showcase", "v9_showcase", "v10_showcase",
]
const SIZE_LIMIT_BYTES: int = 50000
const BIG := Vector2i(2200, 1600)


func _path(name: String) -> String:
	return "res://tests/saves/%s.json" % name


func _example(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path(name)))


func _through_json(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state, "", true, true))


# The example save of version 8, converted to the newest format, loaded into a brain of `size`.
func _load_v8_into(size: Vector2i) -> AirportWorld:
	var brain := AirportWorld.new(size)
	brain.load_state(SaveGame.migrate(_example("v8_showcase")))
	return brain


func _is_chunk_list(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is Dictionary or not (entry as Dictionary).has_all(["cx", "cy", "data"]):
			return false
	return true


func test_save_has_chunk_lists_and_no_dense_arrays() -> void:
	ShowcaseAirport.build()
	var state := Airport.save_state()
	check(_is_chunk_list(state["walkways"]) and not (state["walkways"] as Array).is_empty(), "walkways are a list of chunks")
	check(_is_chunk_list(state["taxiways"]) and not (state["taxiways"] as Array).is_empty(), "taxiways are a list of chunks")
	check_eq(state["map_size"], [Airport.grid.size.x, Airport.grid.size.y], "the map size is still saved")
	# The showcase is 64 x 64 cells around the map centre: it touches a few chunks, never the whole map.
	check((state["walkways"] as Array).size() <= 4, "a showcase is a few chunks, not a whole map")


func test_round_trip_is_exact() -> void:
	ShowcaseAirport.build()
	var state := _through_json(Airport.save_state())
	var loaded := AirportWorld.new()
	loaded.load_state(state)
	check_eq(loaded.grid.get_walkway_data(), Airport.grid.get_walkway_data(), "walkways")
	check_eq(loaded.grid.get_taxiway_data(), Airport.grid.get_taxiway_data(), "taxiways")
	check_eq(loaded.grid.get_zone_data(), Airport.grid.get_zone_data(), "zones (recomputed)")
	check_eq(JSON.stringify(_through_json(loaded.save_state())["walkways"]), JSON.stringify(state["walkways"]), "saving again gives the same chunks")
	loaded.dispose()


func test_chunks_of_a_bigger_map_are_sparse() -> void:
	var brain := AirportWorld.new(BIG)
	brain.grid.set_walkway(Vector2i(5, 5), true)
	brain.grid.set_walkway(Vector2i(2100, 1500), true)
	brain.grid.set_taxiway(Vector2i(2100, 1501), true)
	var state := _through_json(brain.save_state())
	check_eq((state["walkways"] as Array).size(), 2, "two used chunks, nothing else")
	check_eq((state["taxiways"] as Array).size(), 1, "one used taxiway chunk")
	var cells := GridSave.cells_of(state["walkways"])
	cells.sort()
	check_eq(cells, [Vector2i(5, 5), Vector2i(2100, 1500)] as Array[Vector2i], "the cells come back")
	brain.dispose()


func test_v8_converter_makes_chunks() -> void:
	var old := _example("v8_showcase")
	var dense: PackedByteArray = Marshalls.base64_to_raw(old["walkways"])
	var converted := SaveGame.migrate(old)
	check_eq(int(converted["version"]), SaveGame.FORMAT_VERSION, "newest version")
	check(_is_chunk_list(converted["walkways"]) and _is_chunk_list(converted["taxiways"]), "both layers are chunk lists")
	check_eq(GridSave.to_dense(converted["walkways"], Vector2i(64, 64)), dense, "the same walkway cells as before")


func test_every_example_save_loads() -> void:
	for name in SAVES:
		var converted := SaveGame.migrate(_example(name))
		check(not converted.is_empty(), "%s converts" % name)
		var brain := AirportWorld.new()
		brain.load_state(converted)
		check(brain.buildings.size() > 4, "%s loads (%d buildings)" % [name, brain.buildings.size()])
		check(brain.grid.count_flag(AirportGrid.WALKWAY_BIT) > 20, "%s has its walkways" % name)
		brain.dispose()


func test_v9_example_is_in_the_newest_format() -> void:
	var saved := _example("v9_showcase")
	check_eq(int(saved["version"]), 9, "an example save of version 9")
	check(_is_chunk_list(saved["walkways"]), "chunk lists")
	var loaded := AirportWorld.new()
	loaded.load_state(SaveGame.migrate(saved))
	var walking := loaded.passenger_flow.passengers.filter(func(p: Passenger) -> bool: return p.state == Passenger.State.WALKING and p.path.size() > 1)
	check(walking.size() > 0, "passengers are on their way (%d)" % walking.size())
	for i in int(30.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.passenger_flow.passengers.size() > 0, "it keeps running")
	loaded.dispose()


func test_showcase_save_stays_small() -> void:
	var file_size := FileAccess.get_file_as_string(_path("v9_showcase")).length()
	var v8_size := FileAccess.get_file_as_string(_path("v8_showcase")).length()
	# Without the landside pieces: each saved building costs about 160 bytes, and the limit is about the map layers.
	ShowcaseAirport.build(180.0, Vector2i.ZERO, false)
	sim_seconds(20.0)
	var live_size := JSON.stringify(Airport.save_state(), "", true, true).length()
	print("INFO showcase save: v8 example %d bytes, v9 example %d bytes, v9 live %d bytes (limit %d)" % [v8_size, file_size, live_size, SIZE_LIMIT_BYTES])
	check(file_size < SIZE_LIMIT_BYTES, "the v9 example is small (%d bytes)" % file_size)
	check(live_size < SIZE_LIMIT_BYTES, "a fresh showcase save is small (%d bytes)" % live_size)
	check(file_size < v8_size, "smaller than version 8")


func test_save_does_not_grow_with_the_map() -> void:
	var small := _load_v8_into(SMALL_MAP)
	var big := _load_v8_into(BIG)
	# The 64 x 64 airport sits in the middle of the big map and may straddle up to four chunks.
	check((big.save_state()["walkways"] as Array).size() <= 4, "a few chunks on a big map")
	var started := Time.get_ticks_usec()
	var text := JSON.stringify(big.save_state(), "", true, true)
	print("INFO save on %dx%d: %.1f ms, %d bytes" % [BIG.x, BIG.y, (Time.get_ticks_usec() - started) / 1000.0, text.length()])
	check(text.length() < 2 * JSON.stringify(small.save_state(), "", true, true).length(), "the save is about as big as on the small map")
	small.dispose()
	big.dispose()


func test_loading_into_a_bigger_map_centres_everything() -> void:
	var small := _load_v8_into(SMALL_MAP)
	var started := Time.get_ticks_usec()
	var big := _load_v8_into(BIG)
	print("INFO load into %dx%d: %.1f ms" % [BIG.x, BIG.y, (Time.get_ticks_usec() - started) / 1000.0])
	var shift := (BIG - SMALL_MAP) / 2
	check_eq(shift, Vector2i(500, 600), "the shift")
	check_eq(big.grid.size, BIG, "the map is still the big one")
	# Buildings: same types, ids, levels, shifted cells, same place in metres.
	check_eq(big.buildings.size(), small.buildings.size(), "every building is back")
	for i in small.buildings.size():
		var a := small.buildings[i]
		var b := big.buildings[i]
		check(a.type == b.type and a.id == b.id and a.level == b.level and a.rotation_steps == b.rotation_steps, "building %d is the same" % i)
		check_eq(b.origin_cell, a.origin_cell + shift, "building %d moved by the shift" % i)
		var size := Building.rotated_size(a.type.footprint, a.rotation_steps)
		check_eq(big.grid.block_center(b.origin_cell, size), small.grid.block_center(a.origin_cell, size), "building %d stands at the same place in metres" % i)
	# Walkways, taxiways, zones, areas.
	var walkways: Array[Vector2i] = small.grid.get_cells_with_flag(AirportGrid.WALKWAY_BIT)
	check(walkways.size() > 100, "the example has walkways (%d)" % walkways.size())
	check_eq(big.grid.count_flag(AirportGrid.WALKWAY_BIT), walkways.size(), "as many walkway cells")
	check_eq(big.grid.count_flag(AirportGrid.TAXIWAY_BIT), small.grid.count_flag(AirportGrid.TAXIWAY_BIT), "as many taxiway cells")
	var wrong := 0
	for cell in small.grid.get_nonempty_cells():
		var other := cell + shift
		if big.grid.get_flags(other) != small.grid.get_flags(cell):
			wrong += 1
	check_eq(wrong, 0, "every flag byte (walkway, taxiway, zone) is the same, shifted")
	check_eq(big.grid.get_nonempty_cells().size(), small.grid.get_nonempty_cells().size(), "nothing else is marked")
	check(small.zone_map.airside_reached and big.zone_map.airside_reached, "the airside exists on both")
	var small_areas := small.areas()
	var big_areas := big.areas()
	check_eq(big_areas.size(), small_areas.size(), "the same areas")
	for i in small_areas.size():
		check_eq(big_areas[i]["name"], small_areas[i]["name"], "area %d has the same name" % i)
		check_eq((big_areas[i]["cells"] as Array).size(), (small_areas[i]["cells"] as Array).size(), "area %d has the same size" % i)
	# Owned land moves too: a regional airport owns the same part of the airport, not of the map.
	small.progression.tier = Progression.Tier.REGIONAL
	big.progression.tier = Progression.Tier.REGIONAL
	var land := big.progression.owned_land(big.grid.size)
	check_eq(land, Progression.STARTING_LAND, "the big map's regional land is the starting land")
	var owned_wrong := 0
	for building in small.buildings:
		if not land.encloses(Rect2i(building.origin_cell + shift, Building.rotated_size(building.type.footprint, building.rotation_steps))) \
				or not small.owns_cell(building.origin_cell):
			owned_wrong += 1
	check_eq(owned_wrong, 0, "every building of the loaded airport stands on the regional land")
	# Passengers: the same places in metres, and a walking one keeps its way (re-encoded to the new width).
	check_eq(big.passenger_flow.passengers.size(), small.passenger_flow.passengers.size(), "every passenger is back")
	var walking_checked := 0
	for i in small.passenger_flow.passengers.size():
		var a := small.passenger_flow.passengers[i]
		var b := big.passenger_flow.passengers[i]
		check_eq(b.position, a.position, "passenger %d is at the same place in metres" % i)
		if a.state == Passenger.State.WALKING and a.path.size() > 1:
			walking_checked += 1
			check_eq(b.path.size(), a.path.size(), "passenger %d keeps its path" % i)
			for k in a.path.size():
				var cell_a := Vector2i(a.path[k] % small.grid.size.x, a.path[k] / small.grid.size.x)
				var cell_b := Vector2i(b.path[k] % big.grid.size.x, b.path[k] / big.grid.size.x)
				if cell_b != cell_a + shift or big.grid.cell_to_world(cell_b) != small.grid.cell_to_world(cell_a):
					check(false, "passenger %d: path cell %d is not the same place" % [i, k])
					break
	check(walking_checked > 0, "at least one passenger was in the middle of a path (%d)" % walking_checked)
	# Flights and money survive, and the airport runs on.
	check_eq(big.passenger_flow.schedule.flights.size(), small.passenger_flow.schedule.flights.size(), "the same flights")
	check_eq(big.economy.balance, small.economy.balance, "the same money")
	for i in int(30.0 / AirportWorld.SIM_STEP):
		small.step(AirportWorld.SIM_STEP)
		big.step(AirportWorld.SIM_STEP)
	check(big.passenger_flow.passengers.size() > 0, "the big airport keeps running")
	check_eq(big.passenger_flow.departed_count, small.passenger_flow.departed_count, "30 s later: the same departures")
	check_eq(big.passenger_flow.passengers.size(), small.passenger_flow.passengers.size(), "30 s later: the same passengers")
	small.dispose()
	big.dispose()


func test_loading_into_a_smaller_map_skips_what_does_not_fit() -> void:
	var tiny := Vector2i(40, 40)
	var brain := AirportWorld.new(tiny)
	var skipped := brain.load_state(SaveGame.migrate(_example("v8_showcase")))
	check(skipped > 0, "buildings outside the small map are skipped (%d)" % skipped)
	check(brain.buildings.size() > 0, "the others are loaded")
	for building in brain.buildings:
		check(building.get_cells().all(func(c: Vector2i) -> bool: return brain.grid.is_inside(c)), "a loaded building is inside the map")
	for cell in brain.grid.get_nonempty_cells():
		check(brain.grid.is_inside(cell), "marked cells are inside the map")
	for i in int(20.0 / AirportWorld.SIM_STEP):
		brain.step(AirportWorld.SIM_STEP)
	check(true, "it runs on without a crash")
	brain.dispose()


func test_remap_path_with_a_shift() -> void:
	var path := PackedInt32Array([2 + 64 * 3, 3 + 64 * 3])
	var moved := PassengerSave.remap_path(path, 64, Vector2i(100, 80), Vector2i(10, 5))
	check_eq(moved, PackedInt32Array([12 + 100 * 8, 13 + 100 * 8]), "shifted and re-encoded with the new width")
	check(PassengerSave.remap_path(path, 64, Vector2i(100, 80), Vector2i(-3, 0)).is_empty(), "shifted off the left edge: dropped")
	check(PassengerSave.remap_path(path, 64, Vector2i(10, 80), Vector2i(8, 0)).is_empty(), "shifted off the right edge: dropped")


func test_behaviour_hash_ignores_the_layer_format() -> void:
	ShowcaseAirport.build()
	var state := Airport.save_state()
	var dense := state.duplicate()
	# The old dense text of formats 1-8, over the area the behaviour hash looks at (which holds the showcase).
	var reference := BehaviourHash.HASH_AREA
	var walkways := PackedByteArray()
	var taxiways := PackedByteArray()
	walkways.resize(reference.x * reference.y)
	taxiways.resize(reference.x * reference.y)
	for y in reference.y:
		for x in reference.x:
			var cell := at(Vector2i(x, y))
			walkways[y * reference.x + x] = int(Airport.grid.is_walkway(cell))
			taxiways[y * reference.x + x] = int(Airport.grid.is_taxiway(cell))
	dense["walkways"] = Marshalls.raw_to_base64(walkways)
	dense["taxiways"] = Marshalls.raw_to_base64(taxiways)
	check_eq(BehaviourHash.hash_state(state), BehaviourHash.hash_state(dense), "chunk lists hash like the old dense text")
