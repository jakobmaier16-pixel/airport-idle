extends TestCase
## The behaviour hash (scripts/dev/behaviour_hash.gd): the simulation does the same thing every time.

## Refactors must not change this. A PR that changes behaviour on purpose updates it and says so in the PR text.
## Re-baselined on purpose by PR 6B (real-scale stands, runway and showcase): 3546a4ab... -> 7ff28f52... (the hash now also covers the whole airside: 256 x 256 reference cells instead of 64 x 64)
## Re-baselined on purpose by step 7c (taxiing at real scale: taxi times from the route, runway rolls, take-off start saved per flight): 7ff28f52... -> 8ebdd6c4...
## Print the current value with tools/behaviour_hash.sh.
const GOLDEN_BEHAVIOUR_HASH: String = "8ebdd6c49503d42a73a68a21e0bf5ba73f1fd738a42c9a6e4ad0bb9c32f458f8"


func test_behaviour_hash_is_deterministic() -> void:
	var first := BehaviourHash.compute()
	# Another dice seed in between must not matter: the hash forces its own.
	Airport.reseed(7)
	var second := BehaviourHash.compute()
	check_eq(first.length(), 64, "a SHA-256 hex string")
	check_eq(second, first, "two runs in one process give the same hash")


func test_behaviour_hash_matches_golden() -> void:
	check_eq(BehaviourHash.compute(), GOLDEN_BEHAVIOUR_HASH, "behaviour hash (refactors must not change it)")


func test_wall_clock_fields_are_ignored() -> void:
	var state := {"b": 1, "a": {"saved_at": 5.0, "z": [1, {"saved_at": 1, "y": 2}]}}
	var other := {"a": {"z": [1, {"y": 2}]}, "b": 1}
	check_eq(BehaviourHash.hash_state(state), BehaviourHash.hash_state(other), "saved_at and key order don't matter")


func test_behaviour_hash_does_not_depend_on_the_map_size() -> void:
	# The same airport at the same place relative to the map centre behaves the same on a small and on
	# the full-size map (cells are normalised to the centre, the map size is ignored).
	var small := BehaviourHash.compute(SMALL_MAP)
	var big := BehaviourHash.compute(Vector2i(2200, 1600))
	check_eq(small, GOLDEN_BEHAVIOUR_HASH, "benchmark airport on a 1,200 x 400 map")
	check_eq(big, small, "benchmark airport on 2,200 x 1,600 cells gives the same hash")
	var odd_shape := BehaviourHash.compute(Vector2i(1100, 300))
	check_eq(odd_shape, small, "and on a 1,100 x 300 map")
