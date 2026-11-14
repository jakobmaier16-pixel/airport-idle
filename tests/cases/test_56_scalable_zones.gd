extends TestCase
## ZoneMap and AreaMap cost follows the used cells (walkways, taxiways, buildings), not the map size.

# Showcase results of the old dense implementation (recorded before the refactor).
const SHOWCASE_ZONE_HASH := "a9e1b5a6c095cb4b12fdce65db0e3ea7f8603f338858a0131724fa4fbeb4f64b"
const SHOWCASE_AREA_HASH := "46af9c9c4390a8ce0fabb2b700ce6787ef7b755da98a72a0285d5807a15e1e52"
const BIG := Vector2i(2200, 1600)


# The game's airport laid out on a map of another size: the same walkways, taxiways and buildings
# at the same spot relative to the map centre (MapAnchor).
func _move() -> Vector2i:
	return -MapAnchor.shift_for(Airport.grid.size)  # to the 64 x 64 reference map


func _buildings_on(size: Vector2i) -> Array[Building]:
	var delta := _move() + MapAnchor.shift_for(size)
	var result: Array[Building] = []
	for building in Airport.brain.buildings:
		result.append(Building.new(building.type, building.origin_cell + delta, building.rotation_steps))
	return result


func _clone(size: Vector2i) -> AirportGrid:
	var delta := _move() + MapAnchor.shift_for(size)
	var copy := AirportGrid.new(size, Airport.grid.cell_size)
	for cell in Airport.grid.get_nonempty_cells():
		copy.set_walkway(cell + delta, Airport.grid.is_walkway(cell))
		copy.set_taxiway(cell + delta, Airport.grid.is_taxiway(cell))
	for building in _buildings_on(size):
		for cell in building.get_cells():
			copy.set_content(cell, building)
	return copy


# Zone of every used cell, as one comparable list (independent of the map size: cells are given on
# the 64 x 64 reference map).
func _zones_of(grid: AirportGrid) -> Array:
	var result: Array = []
	var back := -MapAnchor.shift_for(grid.size)
	for cell in grid.get_nonempty_cells():
		result.append([cell + back, grid.get_zone(cell)])
	# The order of the cells follows the chunk layout, which depends on the map width: compare sorted.
	result.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y or (a[0].y == b[0].y and a[0].x < b[0].x))
	return result


# The zones of the airport's grid as the old dense bytes of the 64 x 64 reference map.
func _reference_zone_bytes() -> PackedByteArray:
	var reference := MapAnchor.REFERENCE_SIZE
	var bytes := PackedByteArray()
	bytes.resize(reference.x * reference.y)
	for y in reference.y:
		for x in reference.x:
			bytes[y * reference.x + x] = Airport.grid.get_zone(MapAnchor.cell(Vector2i(x, y), Airport.grid.size))
	return bytes


# `areas` (from an AreaMap on a map of `size`) with their cells on the 64 x 64 reference map.
func _reference_areas(areas: Array, size: Vector2i) -> Array:
	var back := -MapAnchor.shift_for(size)
	var result: Array = []
	for area: Dictionary in areas:
		var moved: Array[Vector2i] = []
		for cell: Vector2i in area["cells"]:
			moved.append(cell + back)
		var copy := area.duplicate()
		copy["cells"] = moved
		result.append(copy)
	return result


func test_showcase_unchanged() -> void:
	await start_game()
	build_reference_airport()
	check_eq(Marshalls.raw_to_base64(_reference_zone_bytes()).sha256_text(), SHOWCASE_ZONE_HASH, "zones of the showcase")
	check_eq(JSON.stringify(_reference_areas(Airport.areas(), Airport.grid.size)).sha256_text(), SHOWCASE_AREA_HASH, "areas of the showcase")


func test_big_map_costs_the_same_as_a_small_one() -> void:
	await start_game()
	build_reference_airport()
	var small := _clone(Vector2i(64, 64))
	var big := _clone(BIG)
	var small_buildings := _buildings_on(Vector2i(64, 64))
	var big_buildings := _buildings_on(BIG)
	var small_zones := ZoneMap.new()
	var big_zones := ZoneMap.new()
	var small_areas := AreaMap.new()
	var big_areas := AreaMap.new()
	var t0 := Time.get_ticks_usec()
	small_zones.recompute(small, small_buildings)
	small_areas.recompute(small, small_buildings)
	var t1 := Time.get_ticks_usec()
	big_zones.recompute(big, big_buildings)
	big_areas.recompute(big, big_buildings)
	var t2 := Time.get_ticks_usec()
	var small_ms := (t1 - t0) / 1000.0
	var big_ms := (t2 - t1) / 1000.0
	print("INFO recompute 64x64: %.2f ms, %dx%d: %.2f ms" % [small_ms, BIG.x, BIG.y, big_ms])
	check(small_zones.last_work_cells > 0 and small_areas.last_work_cells > 0, "the counters count something")
	check_eq(big_zones.last_work_cells, small_zones.last_work_cells, "zone work does not depend on the map size")
	check_eq(big_areas.last_work_cells, small_areas.last_work_cells, "area work does not depend on the map size")
	check_eq(_zones_of(big), _zones_of(small), "same zones on both maps")
	check_eq(JSON.stringify(_reference_areas(big_areas.areas(), BIG)), JSON.stringify(_reference_areas(small_areas.areas(), Vector2i(64, 64))), "same areas on both maps")
	# The old dense version needed about 2,300 ms + 2,500 ms for the big map. Generous bounds.
	check(big_ms < 400.0, "big map recompute is fast (%.1f ms)" % big_ms)
	check(big_ms < small_ms * 10.0 + 100.0, "big map is not much slower than the small one")


# Random edits: a map that is recomputed over and over (stale zones must be undone) gives the same
# result as a fresh computation of the same grid. Edits add and remove walkways, taxiways and
# buildings (all types, any rotation), not just add walkways.
func test_repeated_recompute_equals_fresh() -> void:
	await start_game()
	build_reference_airport()
	var grid := _clone(Vector2i(64, 64))
	var buildings := _buildings_on(Vector2i(64, 64))
	var types := AirportWorld.CATALOG.types
	var zones := ZoneMap.new()
	var areas := AreaMap.new()
	var dice := RandomNumberGenerator.new()
	dice.seed = 56
	var added := 0
	var removed := 0
	for round in 120:
		for edit in dice.randi_range(1, 6):
			var cell := Vector2i(dice.randi_range(0, 63), dice.randi_range(0, 63))
			match dice.randi_range(0, 9):
				0, 1, 2:
					if grid.is_empty(cell):
						grid.set_walkway(cell, dice.randf() < 0.6)
				3, 4:
					# Removing walkways: also next to and under buildings.
					grid.set_walkway(cell, false)
				5:
					if grid.is_empty(cell):
						grid.set_taxiway(cell, dice.randf() < 0.6)
				6:
					grid.set_taxiway(cell, false)
				7, 8:
					var building := Building.new(types[dice.randi_range(0, types.size() - 1)], cell, dice.randi_range(0, 3))
					if grid.are_cells_free(building.get_cells()):
						for own in building.get_cells():
							grid.set_content(own, building)
						buildings.append(building)
						added += 1
				_:
					if not buildings.is_empty():
						var gone: Building = buildings.pop_at(dice.randi_range(0, buildings.size() - 1))
						for own in gone.get_cells():
							grid.set_content(own, null)
						removed += 1
		zones.recompute(grid, buildings)
		areas.recompute(grid, buildings)
		var fresh := ZoneMap.new()
		var fresh_areas := AreaMap.new()
		var reference := _clone_grid(grid, buildings)
		fresh.recompute(reference, buildings)
		fresh_areas.recompute(reference, buildings)
		if _zones_of(grid) != _zones_of(reference) or zones.airside_reached != fresh.airside_reached \
				or JSON.stringify(areas.areas()) != JSON.stringify(fresh_areas.areas()):
			check(false, "round %d: repeated recompute differs from a fresh one" % round)
			return
	check(added > 10 and removed > 10, "the edits really added (%d) and removed (%d) buildings" % [added, removed])
	check(true, "120 rounds of random edits: repeated == fresh")


func _clone_grid(source: AirportGrid, buildings: Array[Building]) -> AirportGrid:
	var copy := AirportGrid.new(source.size, source.cell_size)
	for cell in source.get_nonempty_cells():
		copy.set_walkway(cell, source.is_walkway(cell))
		copy.set_taxiway(cell, source.is_taxiway(cell))
	for building in buildings:
		for cell in building.get_cells():
			copy.set_content(cell, building)
	return copy
