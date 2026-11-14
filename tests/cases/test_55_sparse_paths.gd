extends TestCase
## The sparse plane network (scripts/simulation/): same paths and area ids as a full
## AStarGrid2D built in the test, and memory and time that follow the used cells, not the map.


func _reference_areas(grid: AirportGrid, is_open: Callable) -> Dictionary[Vector2i, int]:
	var areas: Dictionary[Vector2i, int] = {}
	var next_id := 0
	for y in grid.size.y:
		for x in grid.size.x:
			var start := Vector2i(x, y)
			if areas.has(start) or not is_open.call(start):
				continue
			var zone := grid.get_zone(start)
			areas[start] = next_id
			var open: Array[Vector2i] = [start]
			while not open.is_empty():
				var cell: Vector2i = open.pop_back()
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next := cell + step
					if grid.is_inside(next) and not areas.has(next) and is_open.call(next) and grid.get_zone(next) == zone:
						areas[next] = next_id
						open.append(next)
			next_id += 1
	return areas


# --- Planes ---

func _reference_plane(network: PlaneNetwork, grid: AirportGrid) -> AStarGrid2D:
	var paths := AStarGrid2D.new()
	paths.region = Rect2i(Vector2i.ZERO, grid.size)
	paths.cell_size = Vector2.ONE
	paths.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	paths.update()
	paths.fill_solid_region(paths.region, true)
	for y in grid.size.y:
		for x in grid.size.x:
			if network.is_paved(Vector2i(x, y)):
				paths.set_point_solid(Vector2i(x, y), false)
	return paths


func test_plane_paths_equal_the_full_grid_on_the_showcase() -> void:
	ShowcaseAirport.build(0.0)
	var network := Airport.plane_network
	var grid := Airport.grid
	var reference := _reference_plane(network, grid)
	var paved := _reference_areas(grid, func(c: Vector2i) -> bool: return network.is_paved(c))
	# Plane areas ignore zones in the network, so compare through the reference labels only where
	# the whole area has one zone (the showcase's airside has).
	check_eq(network.paved_count(), paved.size(), "paved cell count")
	var stands := 0
	for building in Airport.buildings:
		if building.type.role != BuildingType.Role.AIRCRAFT_STAND:
			continue
		stands += 1
		var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
		var target := building.origin_cell + size / 2
		var best: Array[Vector2i] = []
		for runway in network.runways():
			var rsize := Building.rotated_size(runway.type.footprint, runway.rotation_steps)
			var from := Vector2i(clampi(target.x, runway.origin_cell.x, runway.origin_cell.x + rsize.x - 1),
				clampi(target.y, runway.origin_cell.y, runway.origin_cell.y + rsize.y - 1))
			var path: Array[Vector2i] = reference.get_id_path(from, target)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		check_eq(network.path_to_stand(building), best, "stand path at %s" % building.origin_cell)
	check(stands > 0, "the showcase has stands")
	# Area ids by cell, plus any-to-any paths between taxiway cells.
	var rng := RandomNumberGenerator.new()
	rng.seed = 57
	var cells: Array[Vector2i] = paved.keys()
	for i in 600:
		var a: Vector2i = cells[rng.randi() % cells.size()]
		var b: Vector2i = cells[rng.randi() % cells.size()]
		check_eq(network.area_of(a) == network.area_of(b), reference.get_id_path(a, b).size() > 0,
			"same plane area %s %s" % [a, b])
	check_eq(network.area_of(Vector2i(-3, 4)), -1, "outside the map")


# --- Scale ---

func test_rebuild_follows_used_cells_not_map_size() -> void:
	var big := AirportGrid.new(Vector2i(2200, 1600), 2.0)
	var small := AirportGrid.new(Vector2i(64, 64), 2.0)
	# The same small airport in both: a walkway hall, a taxiway strip, one far-away walkway.
	for grid in [big, small]:
		for y in range(10, 30):
			for x in range(10, 40):
				grid.set_walkway(Vector2i(x, y), true)
		for x in range(5, 60):
			grid.set_taxiway(Vector2i(x, 50), true)
	var plane_big := PlaneNetwork.new()
	var before := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	plane_big.rebuild(big, [] as Array[Building])
	var big_ms := (Time.get_ticks_usec() - started) / 1000.0
	var grown := OS.get_static_memory_usage() - before
	var plane_small := PlaneNetwork.new()
	started = Time.get_ticks_usec()
	plane_small.rebuild(small, [] as Array[Building])
	var small_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("INFO sparse rebuild 2200x1600: %.1f ms, +%.2f MB; 64x64: %.1f ms" % [big_ms, grown / 1048576.0, small_ms])
	check_eq(plane_big.paved_count(), 55, "paved cells on the big map")
	# A full-map version needs over 100 MB here; the sparse one a few MB at most.
	check(grown < 16 * 1048576, "memory follows the used cells (+%.1f MB)" % [grown / 1048576.0])
	# Generous: the same work as the small map, plus the cost of walking the (few) chunks.
	check(big_ms < maxf(10.0 * small_ms, 250.0), "time follows the used cells (%.1f ms vs %.1f ms)" % [big_ms, small_ms])


func test_chunk_constants_agree() -> void:
	check_eq(AirportGrid.CHUNK_SIZE, 1 << AirportGrid.CHUNK_SHIFT, "chunk size is a power of two")
	check_eq(AirportGrid.CHUNK_MASK, AirportGrid.CHUNK_SIZE - 1, "mask matches the size")
	var grid := AirportGrid.new(Vector2i(150, 130), 2.0)
	grid.set_walkway(Vector2i(70, 5), true)
	grid.set_walkway(Vector2i(71, 5), true)
	grid.set_taxiway(Vector2i(71, 5), true)
	check_eq(grid.count_flag(AirportGrid.WALKWAY_BIT), 2, "two walkway cells")
	check_eq(grid.count_flag(AirportGrid.TAXIWAY_BIT), 1, "one taxiway cell")
