extends TestCase
## The game stripped to its core (docs/removed_features.md, strip PR 2): building is free and the
## whole map is buildable, the removed features are really gone, the save is format 11, and the
## showcase shows a plane on its way right after the start.

const V10: String = "res://tests/saves/v10_showcase.json"
const V11: String = "res://tests/saves/v11_showcase.json"
const REMOVED_FILES: Array[String] = [
	"res://scripts/simulation/economy.gd", "res://scripts/simulation/airlines.gd", "res://scripts/simulation/airline.gd",
	"res://scripts/simulation/airline_offer.gd", "res://scripts/simulation/demand.gd", "res://scripts/simulation/goals.gd",
	"res://scripts/simulation/progression.gd", "res://scripts/simulation/reputation.gd", "res://scripts/simulation/seasons.gd",
	"res://scenes/ui/airlines_panel.gd", "res://scenes/ui/star_rating.gd", "res://scripts/resources/airline_type.gd",
	"res://data/airlines/catalog.tres", "res://data/buildings/cargo_terminal.tres",
]
## Keys of the save state that belonged to removed features.
const REMOVED_KEYS: Array[String] = [
	"money", "over_limit", "average_profit", "satisfaction", "reputation", "airlines", "progression",
	"goals_hidden", "demand", "staff", "flow",
]


func _example(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_removed_features_are_deleted_not_switched_off() -> void:
	for path in REMOVED_FILES:
		check(not ResourceLoader.exists(path), "%s is gone" % path)
	for name in ["economy", "airlines", "goals", "progression", "demand", "reputation"]:
		check(Airport.get(name) == null, "Airport has no %s" % name)
	check(Airport.CATALOG.find(&"cargo_terminal") == null, "there is no cargo terminal to build")
	var ground_shader := FileAccess.get_file_as_string("res://assets/materials/ground_grid.gdshader")
	check(not ground_shader.contains("owned_rect"), "the ground does not shade unowned land")


func test_building_costs_nothing_and_needs_no_money() -> void:
	Airport.reset()
	# The most expensive things of the old game, one after the other, on a brand-new airport.
	check(Airport.place_building(type_of(&"wide_body_stand"), at(Vector2i(20, 36)), 0) != null, "a wide-body stand")
	check(Airport.place_building(type_of(&"gate"), at(Vector2i(24, 31)), 0) != null, "a gate")
	check_eq(Airport.paint_walkway(cells(at(Vector2i(10, 20)), Vector2i(40, 20)), true), "", "800 cells of walkway")
	check_eq(Airport.paint_taxiway(cells(at(Vector2i(10, 60)), Vector2i(60, 12)), true), "", "720 cells of taxiway")
	check(Airport.grid.is_taxiway(at(Vector2i(10, 60))) and Airport.grid.is_walkway(at(Vector2i(10, 20))), "both were laid")
	var building: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)[0]
	check(Airport.demolish(building), "demolishing works")
	for type in Airport.CATALOG.types:
		check("build_cost" not in type and "unlocked_at" not in type and "running_cost_per_minute" not in type, "%s has no price, unlock or running cost" % type.id)


func test_the_whole_map_is_buildable() -> void:
	Airport.reset()
	var size := Airport.grid.size
	var check_in := type_of(&"check_in")
	var footprint := check_in.footprint
	for corner in [Vector2i(0, 0), Vector2i(size.x - footprint.x, 0), Vector2i(0, size.y - footprint.y), size - footprint]:
		check_eq(Airport.check_placement(check_in, corner, 0), "", "a building in the corner %s" % corner)
	check_eq(Airport.check_placement(check_in, size - footprint + Vector2i.ONE, 0), "Outside the map", "only the map's edge limits it")
	# Far from where the old starting land was: paint and place there.
	check_eq(Airport.paint_walkway(cells(Vector2i(5, 5), Vector2i(10, 2)), true), "", "walkway in the far corner")
	check(Airport.grid.is_walkway(Vector2i(5, 5)), "laid there")
	check_eq(Airport.paint_taxiway(cells(size - Vector2i(20, 20), Vector2i(10, 2)), true), "", "taxiway in the opposite corner")
	check(Airport.grid.is_taxiway(size - Vector2i(20, 20)), "laid there")
	check(Airport.place_building(check_in, Vector2i(2, 2), 0) != null, "placed in the corner")
	# The runway is laid where it always was, and a save from anywhere loads (nothing is "unowned").
	Airport.reset()
	var runway := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY)
	check_eq(runway.size(), 1, "a new game has its runway")


func test_save_format_is_11_and_the_state_has_no_removed_keys() -> void:
	check_eq(SaveGame.FORMAT_VERSION, 11, "the newest format")
	check(SaveGame.migrations.has(10), "a converter for version 10")
	ShowcaseAirport.build(0.0, Vector2i.ZERO, false)
	var state := Airport.save_state()
	for key in REMOVED_KEYS:
		check(not state.has(key), "no '%s' in the saved state" % key)
	for entry: Dictionary in state["buildings"]:
		check(not entry.has("cost") and not entry.has("level"), "a building entry holds no price or level")
		break


func test_v10_converter_drops_what_was_removed() -> void:
	var saved := _example(V10)
	for key in REMOVED_KEYS:
		check(saved.has(key), "the v10 example still has '%s'" % key)
	var cargo_before: int = saved["buildings"].filter(func(e: Dictionary) -> bool: return str(e["type"]) in SaveGame.V11_REMOVED_TYPES).size()
	check(cargo_before > 0, "it holds buildings of removed types (%d)" % cargo_before)
	var count_before: int = (saved["buildings"] as Array).size()
	var converted := SaveGame.migrate(saved)
	check_eq(converted["version"], 11, "now version 11")
	for key in REMOVED_KEYS:
		check(not converted.has(key), "'%s' is dropped" % key)
	check(not converted.has("schedule") and not converted.has("timetable"), "old flights and the old timetable are dropped")
	check_eq((converted["buildings"] as Array).size(), count_before - cargo_before, "removed types leave without a trace")
	for entry: Dictionary in converted["buildings"]:
		check(not entry.has("cost"), "no stored price on %s" % entry["type"])
	# Everything else stays.
	check(converted.has("clock") and converted.has("seed") and converted.has("walkways") and converted.has("taxiways"), "the clock, the seed and the layout stay")
	check_eq(Airport.load_state(converted), 0, "it loads without a single failure")
	check_eq(Airport.load_skipped.size(), 0, "nothing was reported")
	check_eq(Airport.schedule.flights.size(), 0, "no flights on the apron after loading")
	sim_seconds(Timetable.period_real() + FlightSchedule.FIRST_DEPARTURE_DELAY)
	check(Airport.timetable.slots.size() > 0, "the new timetable plans itself")


func test_v11_example_loads_unchanged_and_round_trips() -> void:
	var saved := _example(V11)
	check_eq(int(saved["version"]), 11, "an example save of version 11")
	check_eq(SaveGame.migrate(_example(V11)), saved, "a current save needs no conversion")
	check_eq(Airport.load_state(_example(V11)), 0, "it loads completely")
	check_eq(Airport.buildings.size(), SHOWCASE_BUILDINGS, "all its buildings")
	check_eq(Airport.schedule.flights.size(), (saved["schedule"]["flights"] as Array).size(), "its flights are back")
	check_eq(Airport.timetable.slots.size(), (saved["timetable"]["slots"] as Array).size(), "and its timetable")
	var again := JSON.parse_string(JSON.stringify(Airport.save_state(), "", true, true)) as Dictionary
	for key in ["buildings", "walkways", "taxiways", "clock", "clock_elapsed", "schedule", "timetable", "seed", "rng_state"]:
		check_eq(again[key], saved[key], "saving it again gives the same '%s'" % key)
	sim_seconds(300.0)
	check(Airport.sim_time > float(saved["clock_elapsed"]) / Clock.GAME_PER_REAL, "it keeps running")


func test_showcase_shows_a_plane_on_its_way_at_the_start() -> void:
	ShowcaseAirport.build()
	var seen := {}
	for i in int(120.0 / Airport.SIM_STEP):
		for flight in Airport.schedule.flights:
			if flight.phase in [Flight.Phase.ARRIVING, Flight.Phase.AT_STAND, Flight.Phase.BOARDING]:
				seen[flight] = true
		Airport.step(Airport.SIM_STEP)
	check(not seen.is_empty(), "a plane lands, stands or boards within two minutes of the start")
	check(Airport.schedule.flights.size() > 0 or Airport.schedule.departures > 0, "the airport is busy")
