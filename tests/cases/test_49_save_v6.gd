extends TestCase
## Save format 6 (tech_architecture.md §13): the passengers are one compressed block with their
## paths as grid cells. A save is small, loads back exactly, and old saves are converted.

const SHOWCASE_V5: String = "res://tests/saves/v5_showcase.json"
const SHOWCASE_V6: String = "res://tests/saves/v6_showcase.json"
## About 1,000 passengers must save in less than this (version 5 needed about 1,030,000 bytes;
## version 6 about 60,000).
const SIZE_LIMIT_BYTES: int = 100000


func _through_json(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state, "", true, true))


# Everything about the passengers that decides what happens next, in list order.
func _passenger_state(brain: AirportWorld) -> Array:
	var result: Array = []
	for p in brain.passenger_flow.passengers:
		result.append([p.state, p.goal, p.step, p.position, p.mood, p.walked, p.queued_since, p.visit_left, p.target.id if p.target != null else 0])
	return result


# "" if both lists are the same, else the first place where they differ (short, unlike printing them).
func _difference(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "%d against %d passengers" % [a.size(), b.size()]
	for i in a.size():
		if a[i] != b[i]:
			return "passenger %d: %s against %s" % [i, a[i], b[i]]
	return ""


func _fresh(saved: Dictionary) -> AirportWorld:
	var brain := AirportWorld.new()
	brain.load_state(saved)
	return brain


func test_a_thousand_passengers_save_small_and_load_back_exactly() -> void:
	Benchmark.prepare_airport()
	# A load works the running costs out fresh; refresh them here so both agree (see test_47).
	Airport.brain.layout_changed.emit()
	for i in 40:
		Benchmark.top_up(100)
		sim_seconds(1.0)
	var original := Airport.brain
	var count := original.passenger_flow.passengers.size()
	check(count >= 900, "about 1,000 passengers (%d)" % count)
	var text := JSON.stringify(original.save_state(), "", true, true)
	print("INFO save with %d passengers: %d bytes (limit %d)" % [count, text.length(), SIZE_LIMIT_BYTES])
	check(text.length() < SIZE_LIMIT_BYTES, "the save is small (%d bytes)" % text.length())
	var loaded := _fresh(JSON.parse_string(text))
	check_eq(loaded.passenger_flow.passengers.size(), count, "every passenger is back")
	check_eq(_difference(_passenger_state(loaded), _passenger_state(original)), "", "right after loading: the same passengers, to the last digit")
	loaded.passenger_flow.max_passengers = original.passenger_flow.max_passengers  # the benchmark raised it
	# Both run on for a game minute: they must stay the same.
	for i in int(60.0 / AirportWorld.SIM_STEP):
		original.step(AirportWorld.SIM_STEP)
		loaded.step(AirportWorld.SIM_STEP)
	check_eq(_difference(_passenger_state(loaded), _passenger_state(original)), "", "a minute later: still the same")
	check_eq(loaded.economy.balance, original.economy.balance, "the same money")
	loaded.dispose()


func test_v5_converter_packs_the_passengers() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V5))
	check_eq(int(saved["version"]), 5, "an example save of version 5")
	var old_passengers: Array = saved["flow"]["passengers"]
	check(old_passengers.size() > 10, "it has passengers (%d)" % old_passengers.size())
	var converted := SaveGame.migrate(saved)
	check_eq(converted["version"], 6, "now version 6")
	var packed: Dictionary = converted["flow"]["passengers"]
	check_eq(int(packed["count"]), old_passengers.size(), "no passenger lost")
	check_eq(int(packed["grid_width"]), 64, "the grid width is stored")
	var loaded := _fresh(converted)
	var flow := loaded.passenger_flow
	check_eq(flow.passengers.size(), old_passengers.size(), "they all load")
	for i in mini(flow.passengers.size(), old_passengers.size()):
		var entry: Dictionary = old_passengers[i]
		var p := flow.passengers[i]
		var saved_position := Vector3(entry["position"][0], entry["position"][1], entry["position"][2])
		check_eq(p.position, saved_position, "position of passenger %d" % i)
		check_eq(int(p.goal), int(entry["goal"]), "goal of passenger %d" % i)
		check_eq(p.mood, float(entry["mood"]), "mood of passenger %d" % i)
		# The way still ahead leads along the same cells.
		var ahead := ((entry["path"] as Array).size() / 3) - int(entry["path_index"])
		check_eq(p.path.size(), ahead, "cells still ahead of passenger %d" % i)
	for i in int(30.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.passenger_flow.passengers.size() > 0, "it keeps running")
	loaded.dispose()


func test_example_v6_loads() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHOWCASE_V6))
	check_eq(int(saved["version"]), 6, "an example save of version 6")
	check_eq(SaveGame.migrate(saved)["version"], 6, "nothing left to convert")
	var loaded := _fresh(saved)
	check_eq(loaded.passenger_flow.passengers.size(), int(saved["flow"]["passengers"]["count"]), "its passengers are back")
	check_eq(loaded.buildings.size(), SHOWCASE_BUILDINGS, "its buildings are back")
	for i in int(60.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(loaded.passenger_flow.passengers.size() > 0, "it keeps running")
	loaded.dispose()


func test_paths_follow_the_grid_width() -> void:
	var path := PackedInt32Array([2 + 64 * 3, 3 + 64 * 3, 3 + 64 * 4])  # (2,3) (3,3) (3,4) on a 64-wide grid
	check_eq(PassengerSave.remap_path(path, 64, Vector2i(64, 64)), path, "same width: unchanged")
	check_eq(PassengerSave.remap_path(path, 64, Vector2i(100, 64)), PackedInt32Array([2 + 100 * 3, 3 + 100 * 3, 3 + 100 * 4]), "a wider grid: same cells")
	check(PassengerSave.remap_path(path, 64, Vector2i(3, 64)).is_empty(), "a cell outside the new grid: the passenger plans a new way")
	check(PassengerSave.remap_path(PackedInt32Array([64 * 70]), 64, Vector2i(64, 64)).is_empty(), "a cell below the grid: dropped")
	check(PassengerSave.remap_path(path, 0, Vector2i(64, 64)).is_empty(), "no width: dropped")


func test_saved_with_another_grid_width_still_loads() -> void:
	ShowcaseAirport.build()
	sim_seconds(120.0)
	var state := _through_json(Airport.save_state())
	var packed: Dictionary = state["flow"]["passengers"]
	var records := PassengerSave.decode(packed)
	check(records.size() > 5, "passengers to move around (%d)" % records.size())
	# Pretend the save came from a grid 100 cells wide: the cells mean other places now.
	for record in records:
		var path: PackedInt32Array = record["path"]
		for k in path.size():
			path[k] = path[k] % 64 + (path[k] / 64) * 100
		record["path"] = path
	state["flow"]["passengers"] = PassengerSave.encode(records, 100)
	var loaded := _fresh(state)
	check_eq(loaded.passenger_flow.passengers.size(), records.size(), "all load")
	for i in int(20.0 / AirportWorld.SIM_STEP):
		loaded.step(AirportWorld.SIM_STEP)
	check(true, "it keeps running")
	loaded.dispose()


func test_damaged_passenger_block_is_dropped_not_fatal() -> void:
	ShowcaseAirport.build()
	sim_seconds(60.0)
	var state := _through_json(Airport.save_state())
	state["flow"]["passengers"]["raw_size"] = int(state["flow"]["passengers"]["raw_size"]) + 7
	var loaded := _fresh(state)
	check_eq(loaded.passenger_flow.passengers.size(), 0, "no passengers from a damaged block")
	loaded.step(AirportWorld.SIM_STEP)
	loaded.dispose()


func test_inconsistent_lengths_are_dropped() -> void:
	ShowcaseAirport.build()
	sim_seconds(60.0)
	var packed: Dictionary = _through_json(Airport.save_state())["flow"]["passengers"]
	check(PassengerSave.decode(packed).size() > 0, "the intact block decodes")
	# A count far beyond what the bytes can hold.
	var too_many := packed.duplicate()
	too_many["count"] = 100000000
	check(PassengerSave.decode(too_many).is_empty(), "an impossible passenger count is dropped")
	# A path length that runs past the end of the buffer.
	var records := PassengerSave.decode(packed)
	var raw_block := PassengerSave.encode(records, 64)
	var raw := (Marshalls.base64_to_raw(raw_block["data"])).decompress(int(raw_block["raw_size"]), FileAccess.COMPRESSION_DEFLATE)
	var length_at := PassengerSave.RECORD_BYTES * records.size() - 4 * records.size()
	raw.encode_u32(length_at, 0x7fffffff)
	var broken := raw_block.duplicate()
	broken["data"] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	check(PassengerSave.decode(broken).is_empty(), "a path length beyond the buffer is dropped")
	# Cells right of the grid's last column.
	check(PassengerSave.remap_path(PackedInt32Array([70]), 100, Vector2i(64, 64)).is_empty(), "x beyond the width is rejected")
