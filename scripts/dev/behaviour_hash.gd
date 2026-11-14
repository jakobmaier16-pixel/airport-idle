class_name BehaviourHash
extends RefCounted
## A fingerprint of what the simulation does, to compare before and after a refactor.
## Builds the benchmark airport with the benchmark seed, runs it for a fixed number of steps and
## hashes the brain's save state. Print it with tools/behaviour_hash.sh.

## The same seed as the device benchmark.
const SEED: int = Benchmark.SEED
const STEPS: int = 600
## Save fields that depend on the time of the run, never on the simulation.
const WALL_CLOCK_KEYS: Array[String] = ["saved_at"]
## The part of the map the hash looks at, in cells of the 64 x 64 reference map (MapAnchor): 256 x 256
## cells from the reference corner, which holds the whole real-scale benchmark airport (the stands
## and taxiways reach about 105 cells east and south of it).
const HASH_AREA: Vector2i = Vector2i(256, 256)


## SHA-256 (hex) of the canonical JSON of the save state after STEPS steps on the benchmark
## airport. Never saves. The global airport is replaced by a fresh one with the caller's seed
## afterwards, so the benchmark airport does not leak into whatever runs next.
## `map_size` (zero = the game's map) builds the airport on a map of another size; the hash must not change.
static func compute(map_size: Vector2i = Vector2i.ZERO) -> String:
	var previous_seed: int = Airport.game_seed
	Airport.reseed(SEED)
	ShowcaseAirport.build(180.0, map_size)
	Airport.passenger_flow.max_passengers = Benchmark.PASSENGER_LIMIT
	for i in STEPS:
		Airport.step(Airport.SIM_STEP)
	var result := hash_state(Airport.save_state())
	Airport.reset(true, previous_seed)
	return result


## SHA-256 (hex) of `state` without wall-clock fields, keys in sorted order at every level.
static func hash_state(state: Dictionary) -> String:
	return canonical_json(state).sha256_text()


static func canonical_json(state: Dictionary) -> String:
	return JSON.stringify(_strip(_canonical_layers(state)), "", true, true)


# The hash must not depend on how a save stores the map, nor on how big the map is.
# - Format 9 saves walkways and taxiways as chunk lists; they are turned back into the dense base64
#   text of formats 1-8, so the hash stays what it was before the format change.
# - Every cell is moved to where it is on the reference map (relative to the map centre; HASH_AREA of it is hashed), and
#   "map_size" is written as that map's size. The same airport built at the same place relative to
#   the centre therefore hashes the same on a map of any size (see MapAnchor). World positions
#   (metres) need no change: the world origin is the map centre on every size.
static func _canonical_layers(state: Dictionary) -> Dictionary:
	var result := state.duplicate()
	var map_size: Array = state.get("map_size", [])
	if map_size.size() != 2:
		return result
	var size := Vector2i(int(map_size[0]), int(map_size[1]))
	var shift := MapAnchor.shift_for(size)  # reference cell + shift = cell on this map
	var reference := HASH_AREA
	result["map_size"] = [reference.x, reference.y]
	for key in ["walkways", "taxiways"]:
		if state.get(key) is Array:
			result[key] = Marshalls.raw_to_base64(_dense_on_reference(state[key], shift))
	if state.get("buildings") is Array:
		var buildings: Array = []
		for entry: Variant in state["buildings"]:
			var moved: Dictionary = (entry as Dictionary).duplicate()
			var cell: Array = moved["cell"]
			moved["cell"] = [int(cell[0]) - shift.x, int(cell[1]) - shift.y]
			buildings.append(moved)
		result["buildings"] = buildings
	var flow: Variant = state.get("flow")
	if flow is Dictionary and (flow as Dictionary).get("passengers") is Dictionary:
		var moved_flow: Dictionary = (flow as Dictionary).duplicate()
		moved_flow["passengers"] = _passengers_on_reference(moved_flow["passengers"], shift)
		result["flow"] = moved_flow
	return result


# The cells of a saved layer on the reference map, as the old dense 0/1 bytes.
static func _dense_on_reference(chunks: Array, shift: Vector2i) -> PackedByteArray:
	var reference := HASH_AREA
	var dense := PackedByteArray()
	dense.resize(reference.x * reference.y)
	for cell in GridSave.cells_of(chunks):
		var moved := cell - shift
		if moved.x >= 0 and moved.y >= 0 and moved.x < reference.x and moved.y < reference.y:
			dense[moved.y * reference.x + moved.x] = 1
	return dense


# The saved passengers with their path cells moved onto the reference map.
static func _passengers_on_reference(packed: Dictionary, shift: Vector2i) -> Dictionary:
	var reference := HASH_AREA
	var width := int(packed.get("grid_width", reference.x))
	if width == reference.x and shift == Vector2i.ZERO:
		return packed
	var records := PassengerSave.decode(packed)
	for record in records:
		record["path"] = PassengerSave.remap_path(record["path"], width, reference, -shift)
	return PassengerSave.encode(records, reference.x)


static func _strip(value: Variant) -> Variant:
	if value is Dictionary:
		var clean := {}
		for key in value:
			if not (key is String and key in WALL_CLOCK_KEYS):
				clean[key] = _strip(value[key])
		return clean
	if value is Array:
		return (value as Array).map(_strip)
	return value
