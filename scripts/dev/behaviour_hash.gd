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


## SHA-256 (hex) of the canonical JSON of the save state after STEPS steps on the benchmark
## airport. Resets the global airport; the caller's airport is gone afterwards.
static func compute() -> String:
	Airport.reseed(SEED)
	ShowcaseAirport.build()
	Airport.passenger_flow.max_passengers = Benchmark.PASSENGER_LIMIT
	for i in STEPS:
		Airport.step(Airport.SIM_STEP)
	return hash_state(Airport.save_state())


## SHA-256 (hex) of `state` without wall-clock fields, keys in sorted order at every level.
static func hash_state(state: Dictionary) -> String:
	return canonical_json(state).sha256_text()


static func canonical_json(state: Dictionary) -> String:
	return JSON.stringify(_strip(state), "", true)


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
