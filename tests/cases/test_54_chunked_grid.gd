extends TestCase
## The chunked flag storage of AirportGrid: round trips at chunk borders and map edges, lazy
## allocation, and the dense arrays the save code reads.

# 150 x 130 cells: 3 x 3 chunks, the last row and column of chunks are only partly on the map.
const SIZE := Vector2i(150, 130)


func _grid() -> AirportGrid:
	return AirportGrid.new(SIZE, 2.0)


func test_fresh_grid_is_empty() -> void:
	var grid := _grid()
	check_eq(grid.get_allocated_chunk_count(), 0, "no chunk allocated")
	check_eq(grid.get_allocated_chunks().size(), 0, "no chunk listed")
	check_eq(grid.get_nonempty_cells().size(), 0, "no non-empty cell")
	check(not grid.is_walkway(Vector2i(70, 70)), "unallocated chunk: no walkway")
	check(not grid.is_taxiway(Vector2i(149, 129)), "unallocated chunk: no taxiway")
	check_eq(grid.get_zone(Vector2i(0, 0)), AirportGrid.Zone.LANDSIDE, "unallocated chunk: landside")
	check_eq(grid.get_flags(Vector2i(5, 5)), 0, "unallocated chunk: flags 0")
	check_eq(grid.get_flags(Vector2i(-1, 0)), 0, "outside the map reads 0")
	check_eq(grid.get_flags(Vector2i(150, 0)), 0, "outside the map reads 0 (right)")
	check_eq(grid.get_flags(Vector2i(0, 130)), 0, "outside the map reads 0 (bottom)")


func test_round_trip_at_borders_and_edges() -> void:
	var grid := _grid()
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(63, 63), Vector2i(64, 64), Vector2i(63, 64), Vector2i(64, 63),
		Vector2i(127, 127), Vector2i(128, 128), Vector2i(149, 129), Vector2i(149, 0), Vector2i(0, 129)]
	for cell in cells:
		grid.set_walkway(cell, true)
		grid.set_taxiway(cell + Vector2i(0, 0), true)
		grid.set_zone(cell, AirportGrid.Zone.AIRSIDE)
	for cell in cells:
		check(grid.is_walkway(cell), "walkway at %s" % [cell])
		check(grid.is_taxiway(cell), "taxiway at %s" % [cell])
		check_eq(grid.get_zone(cell), AirportGrid.Zone.AIRSIDE, "zone at %s" % [cell])
	check(not grid.is_walkway(Vector2i(1, 0)), "a neighbour stays empty")
	check(not grid.is_walkway(Vector2i(62, 63)), "a neighbour across the chunk border stays empty")
	check_eq(grid.get_nonempty_cells().size(), cells.size(), "exactly the touched cells are non-empty")
	grid.set_walkway(Vector2i(64, 64), false)
	check(not grid.is_walkway(Vector2i(64, 64)), "walkway cleared")
	check(grid.is_taxiway(Vector2i(64, 64)), "clearing one flag keeps the others")


func test_layers_are_independent() -> void:
	var grid := _grid()
	var cell := Vector2i(10, 10)
	grid.set_zone(cell, AirportGrid.Zone.AIRSIDE)
	check(not grid.is_walkway(cell) and not grid.is_taxiway(cell), "a zone alone is no walkway or taxiway")
	grid.set_walkway(cell, true)
	check_eq(grid.get_zone(cell), AirportGrid.Zone.AIRSIDE, "the walkway did not touch the zone")
	grid.set_zone(cell, AirportGrid.Zone.LANDSIDE)
	check(grid.is_walkway(cell), "the zone did not touch the walkway")
	check_eq(grid.get_flags(cell) & AirportGrid.OWNED_BIT, 0, "the owned bit is unused")


func test_only_touched_chunks_are_allocated() -> void:
	var grid := _grid()
	grid.set_walkway(Vector2i(3, 3), true)
	grid.set_walkway(Vector2i(60, 60), true)
	check_eq(grid.get_allocated_chunk_count(), 1, "two cells in one chunk: one chunk")
	grid.set_taxiway(Vector2i(100, 5), true)
	grid.set_zone(Vector2i(149, 129), AirportGrid.Zone.AIRSIDE)
	check_eq(grid.get_allocated_chunk_count(), 3, "three chunks touched")
	var chunks := grid.get_allocated_chunks()
	check_eq(chunks, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 2)] as Array[Vector2i], "the allocated chunks")
	check_eq(grid.get_chunk_flags(Vector2i(2, 1)).size(), 0, "an unallocated chunk has no data")
	check_eq(grid.get_chunk_flags(Vector2i(0, 0)).size(), AirportGrid.CHUNK_SIZE * AirportGrid.CHUNK_SIZE, "a chunk is CHUNK_SIZE squared")
	# Writing zeros into untouched chunks allocates nothing.
	grid.set_walkway(Vector2i(130, 70), false)
	grid.set_zone(Vector2i(130, 70), AirportGrid.Zone.LANDSIDE)
	check_eq(grid.get_allocated_chunk_count(), 3, "clearing an empty cell allocates nothing")


func test_all_zero_after_clearing() -> void:
	var grid := _grid()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(64, 0), Vector2i(64, 64), Vector2i(149, 129)]
	for cell in cells:
		grid.set_walkway(cell, true)
		grid.set_taxiway(cell, true)
	for cell in cells:
		grid.set_walkway(cell, false)
		check_eq(grid.get_allocated_chunk_count(), 4, "taxiway keeps the chunk alive")
	for cell in cells:
		grid.set_taxiway(cell, false)
	check_eq(grid.get_allocated_chunk_count(), 0, "all chunks freed again")
	check_eq(grid.get_nonempty_cells().size(), 0, "no non-empty cell left")
	var sum := 0
	for value in grid.get_walkway_data():
		sum += value
	for value in grid.get_taxiway_data():
		sum += value
	check_eq(sum, 0, "dense data is all zero")


func test_dense_arrays_match_cells() -> void:
	var grid := _grid()
	grid.set_walkway(Vector2i(64, 3), true)
	grid.set_walkway(Vector2i(149, 129), true)
	grid.set_taxiway(Vector2i(0, 0), true)
	grid.set_zone(Vector2i(63, 64), AirportGrid.Zone.AIRSIDE)
	var walkways := grid.get_walkway_data()
	check_eq(walkways.size(), SIZE.x * SIZE.y, "one byte per cell")
	check_eq(walkways[3 * SIZE.x + 64], 1, "walkway byte is 1")
	check_eq(walkways[129 * SIZE.x + 149], 1, "walkway byte at the last cell")
	check_eq(grid.get_taxiway_data()[0], 1, "taxiway byte")
	check_eq(grid.get_zone_data()[64 * SIZE.x + 63], AirportGrid.Zone.AIRSIDE, "zone byte")
	var sum := 0
	for value in walkways:
		sum += value
	check_eq(sum, 2, "exactly two walkway cells")


func test_set_dense_data_round_trip() -> void:
	var grid := _grid()
	grid.set_walkway(Vector2i(5, 5), true)
	grid.set_taxiway(Vector2i(5, 5), true)
	var data := PackedByteArray()
	data.resize(SIZE.x * SIZE.y)
	data[70 * SIZE.x + 70] = 1
	data[129 * SIZE.x + 149] = 1
	grid.set_walkway_data(data)
	check(not grid.is_walkway(Vector2i(5, 5)), "the old walkway is replaced")
	check(grid.is_taxiway(Vector2i(5, 5)), "the taxiway layer is untouched")
	check(grid.is_walkway(Vector2i(70, 70)) and grid.is_walkway(Vector2i(149, 129)), "the new walkways are set")
	check_eq(grid.get_walkway_data(), data, "reads back identically")
	grid.set_walkway_data(PackedByteArray([1, 2, 3]))
	check_eq(grid.get_walkway_data(), data, "data of the wrong size is ignored")
	var zones := PackedByteArray()
	zones.resize(SIZE.x * SIZE.y)
	zones[64] = AirportGrid.Zone.AIRSIDE
	grid.set_zone_data(zones)
	check_eq(grid.get_zone(Vector2i(64, 0)), AirportGrid.Zone.AIRSIDE, "zone data applied")
	check_eq(grid.get_zone_data(), zones, "zones read back identically")


func test_writes_stick_in_a_second_chunk_access() -> void:
	# The Gotcha: packed arrays are values. Many writes into one chunk must all stay.
	var grid := _grid()
	for x in 64:
		grid.set_walkway(Vector2i(x, 7), true)
	var count := 0
	for x in 64:
		if grid.is_walkway(Vector2i(x, 7)):
			count += 1
	check_eq(count, 64, "all 64 writes into one chunk stuck")
