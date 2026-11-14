extends TestCase
## Save format 10 (tech_architecture.md §13): the 6 m prototype's stands, runway and taxiway paint are
## removed, and the real-scale runway is laid. (Their refund went away with money, format 11.)

const TEST_SAVE: String = "user://test_save_v10.json"
const V9: String = "res://tests/saves/v9_showcase.json"
const V10: String = "res://tests/saves/v10_showcase.json"
## The footprints of the removed types (stand 12 x 12, wide-body stand 16 x 16, runway 52 x 6).
const LEGACY_FOOTPRINTS: Array[Vector2i] = [Vector2i(12, 12), Vector2i(16, 16), Vector2i(52, 6)]


func _example(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _clean_up() -> void:
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func test_there_is_a_v10_example_and_a_converter_for_v9() -> void:
	check_eq(int(_example(V10)["version"]), 10, "an example save of version 10")
	check(SaveGame.migrations.has(9), "a converter for version 9")


func test_v9_example_loses_its_old_airside() -> void:
	var saved := _example(V9)
	check(saved["buildings"].any(func(e: Dictionary) -> bool: return LEGACY_AIRSIDE_TYPES.has(str(e["type"]))), "the example has old stands or a runway")
	SaveGame.format_version = 10  # stop after the v9 converter
	var converted := SaveGame.migrate(_example(V9))
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	for entry: Dictionary in converted["buildings"]:
		check(not LEGACY_AIRSIDE_TYPES.has(str(entry["type"])), "no %s left in the save" % entry["type"])
	check_eq((converted["taxiways"] as Array).size(), 0, "no taxiway chunks left")
	var kept: int = saved["buildings"].filter(func(e: Dictionary) -> bool: return not LEGACY_AIRSIDE_TYPES.has(str(e["type"]))).size()
	check_eq((converted["buildings"] as Array).size(), kept, "the other buildings are untouched")


func test_loading_v9_leaves_no_legacy_footprint() -> void:
	Airport.load_state(SaveGame.migrate(_example(V9)))
	var runways := 0
	for building in Airport.buildings:
		check(building.type.footprint not in LEGACY_FOOTPRINTS, "%s has a real-scale footprint" % building.type.display_name)
		if building.type.role == BuildingType.Role.RUNWAY:
			runways += 1
			check_eq(building.type.footprint, Vector2i(1000, 23), "the new runway")
	check_eq(runways, 1, "exactly one runway is laid")
	check_eq(Airport.grid.count_flag(AirportGrid.TAXIWAY_BIT), 0, "no old taxiway paint")
	check(Airport.buildings.any(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE), "the gates are still there")
	sim_seconds(1.0)
	check_eq(Airport.schedule.flights.size(), 0, "no flights without stands")


func test_converter_works_on_small_hand_made_saves() -> void:
	var grid := AirportGrid.new(Vector2i(128, 128), 2.0)
	for x in 10:
		grid.set_taxiway(Vector2i(70 + x, 70), true)
	var data := {
		"version": 9, "taxiways": GridSave.encode(grid, AirportGrid.TAXIWAY_BIT),
		"buildings": [
			{"id": 1, "type": "aircraft_stand", "cell": [5, 5]},
			{"id": 2, "type": "wide_body_stand", "cell": [30, 5]},
			{"id": 3, "type": "gate", "cell": [5, 1]},
		],
	}
	SaveGame.format_version = 10
	var converted := SaveGame.migrate(data)
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	check_eq((converted["buildings"] as Array).size(), 1, "only the gate is kept")
	check_eq((converted["taxiways"] as Array).size(), 0, "the taxiway paint is gone")


func test_v10_example_loads_completely() -> void:
	var saved := _example(V10)
	var converted := SaveGame.migrate(_example(V10))
	check_eq(converted["version"], SaveGame.FORMAT_VERSION, "converted to the newest format")
	check_eq(Airport.load_state(converted), 0, "nothing fails to load")
	check_eq(Airport.buildings.size(), EXAMPLE_SAVE_BUILDINGS, "all of its other buildings")
	check_eq(Airport.load_skipped.size(), 0, "none was skipped")
	var again := JSON.parse_string(JSON.stringify(Airport.save_state(), "", true, true)) as Dictionary
	var types_before: Array = saved["buildings"].filter(func(e: Dictionary) -> bool: return not REMOVED_TYPES.has(str(e["type"]))).map(func(e: Dictionary) -> Array: return [e["type"], e["cell"], e["rotation"]])
	var types_after: Array = again["buildings"].map(func(e: Dictionary) -> Array: return [e["type"], e["cell"], e["rotation"]])
	check_eq(types_after, types_before, "saving it again gives the same buildings")
	sim_seconds(120.0)
	check(Airport.sim_time > 0.0, "it keeps running")


# A v9 save with a building in the default runway band (rows 81 to 103 of the reference map): the
# new runway moves to the nearest free spot instead of silently not being laid.
func _v9_with_a_building_in_the_runway_band() -> Dictionary:
	var saved := _example(V9)
	saved["buildings"].append({"id": 99, "type": "car_park", "cell": [30, 90], "rotation": 0})
	return saved


func _runway() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.RUNWAY:
			return building
	return null


func test_a_building_in_the_runway_band_moves_the_runway_and_flights_still_happen() -> void:
	var saved := _v9_with_a_building_in_the_runway_band()
	check_eq(Airport.load_state(SaveGame.migrate(saved)), 0, "nobody had to leave")
	var runway := _runway()
	check(runway != null, "a runway was laid")
	var shop: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.id == &"car_park" and b.id == 99)[0]
	check(not Rect2i(runway.origin_cell, runway.type.footprint).intersects(Rect2i(shop.origin_cell, shop.type.footprint)), "it does not touch the car park")
	check(Rect2i(Vector2i.ZERO, Airport.grid.size).encloses(Rect2i(runway.origin_cell, runway.type.footprint)), "it lies on the map")
	# Give gate 1 a stand and a taxiway down to wherever the runway is: flights come.
	var gate: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)[0]
	var stand := Airport.place_building(type_of(&"aircraft_stand"), gate.origin_cell + Vector2i(-8, 5), 0)
	check(stand != null, "a stand under the gate")
	var link_x := stand.origin_cell.x + 9
	var link_top := stand.origin_cell.y + stand.type.footprint.y
	Airport.paint_taxiway(cells(Vector2i(link_x, link_top), Vector2i(2, runway.origin_cell.y - link_top)), true)
	check(Airport.usable_gates().size() > 0, "a complete route")
	check(first_flight(0, 3000.0) != null, "flights happen")


func test_with_no_free_spot_the_buildings_in_the_way_are_removed() -> void:
	# A map just 46 cells high: only two runway rows fit, and a wide-body stand blocks both.
	var brain := AirportWorld.new(Vector2i(1200, 46))
	var stand := brain.place_building(AirportWorld.CATALOG.find(&"wide_body_stand"), Vector2i(500, 3), 0)
	check(stand != null, "the blocking stand is placed")
	var removed := brain.add_starting_runway()
	check_eq(removed, [stand] as Array[Building], "the stand had to leave")
	var runways := brain.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY)
	check_eq(runways.size(), 1, "and the runway is there")
	check(not brain.buildings.has(stand), "the stand is gone")
	check_eq(brain.add_starting_runway().size(), 0, "a second call does nothing")
	check_eq(brain.buildings.size(), 1, "still one building")
	brain.dispose()
