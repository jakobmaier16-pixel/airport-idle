extends TestCase
## The ground is one R8 texture that is exactly the grid's flag layer, updated chunk by chunk.

const BIG := Vector2i(2200, 1600)


# The flag byte of every cell of `grid`, row by row (loops over the map: only for small test maps).
func _dense_flags(grid: AirportGrid) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(grid.size.x * grid.size.y)
	for y in grid.size.y:
		for x in grid.size.x:
			data[y * grid.size.x + x] = grid.get_flags(Vector2i(x, y))
	return data


func _ground_texture() -> GroundFlagTexture:
	return (main.get_node("Ground") as Ground).get_flag_texture()


func test_texture_is_the_flag_layer_of_the_showcase() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var flags := _ground_texture()
	check_eq(flags.image.get_format(), Image.FORMAT_R8, "one byte per cell")
	check_eq(flags.image.get_size(), Airport.grid.size, "one texel per cell")
	check(flags.image.get_data() == _dense_flags(Airport.grid), "the texture bytes are the flag layer")
	check(Airport.grid.count_flag(AirportGrid.WALKWAY_BIT) > 0 and Airport.grid.count_flag(AirportGrid.TAXIWAY_BIT) > 0, "the showcase has walkways and taxiways")
	check_eq(flags.texture.get_size(), Vector2(Airport.grid.size), "the GPU texture has the map size")
	var material := (main.get_node("Ground/MeshInstance3D") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	check(material.get_shader_parameter(&"flag_map") == flags.texture, "the shader reads that texture")


func test_edits_update_the_texture() -> void:
	await start_game()
	var cells: Array[Vector2i] = [Vector2i(20, 25), Vector2i(21, 25), Vector2i(22, 25)]
	Airport.paint_walkway(cells, true)
	await frames(1)
	var flags := _ground_texture()
	check(flags.image.get_data() == _dense_flags(Airport.grid), "painted walkway is in the texture")
	check_eq(flags.image.get_pixel(21, 25).r8, AirportGrid.WALKWAY_BIT, "the walkway bit")
	Airport.paint_walkway(cells, false)
	await frames(1)
	check(flags.image.get_data() == _dense_flags(Airport.grid), "erased walkway is out of the texture")
	check_eq(flags.image.get_pixel(21, 25).r8, 0, "empty again")


func test_many_edits_in_one_frame_upload_once() -> void:
	await start_game()
	var flags := _ground_texture()
	await frames(2)
	var before := flags.upload_count
	for i in 5:
		var cells: Array[Vector2i] = [Vector2i(20 + i, 25), Vector2i(20 + i, 26)]
		Airport.paint_walkway(cells, true)
	Airport.paint_walkway([Vector2i(20, 25)] as Array[Vector2i], false)
	check_eq(flags.upload_count, before, "nothing is uploaded inside the frame")
	await frames(1)
	check_eq(flags.upload_count, before + 1, "one upload for all edits")
	check(flags.image.get_data() == _dense_flags(Airport.grid), "and it has every edit")
	await frames(2)
	check_eq(flags.upload_count, before + 1, "no change, no upload")


func test_one_walkway_paint_marks_one_chunk() -> void:
	var grid := AirportGrid.new(Vector2i(256, 192), 2.0)
	check_eq(grid.get_dirty_chunk_count(), 0, "a new grid is clean")
	grid.set_walkway(Vector2i(70, 130), true)
	check_eq(grid.get_dirty_chunk_count(), 1, "one cell: one dirty chunk")
	var cells: Array[Vector2i] = []
	for x in range(66, 120):
		cells.append(Vector2i(x, 129))
		grid.set_walkway(Vector2i(x, 129), true)
	check_eq(grid.get_dirty_chunk_count(), 1, "a strip inside the same chunk: still one")
	check_eq(grid.take_dirty_chunks(), [Vector2i(1, 2)] as Array[Vector2i], "the chunk of those cells")
	check_eq(grid.get_dirty_chunk_count(), 0, "taking clears the set")
	grid.set_walkway(Vector2i(70, 130), true)
	check_eq(grid.get_dirty_chunk_count(), 0, "writing the same value is not a change")
	grid.set_walkway(Vector2i(63, 10), true)
	grid.set_walkway(Vector2i(64, 10), true)
	check_eq(grid.get_dirty_chunk_count(), 2, "a strip over a chunk border: two chunks")


func test_freed_chunk_is_cleared_in_the_texture() -> void:
	var grid := AirportGrid.new(Vector2i(256, 192), 2.0)
	grid.set_taxiway(Vector2i(100, 100), true)
	var flags := GroundFlagTexture.new(grid)
	check_eq(flags.image.get_pixel(100, 100).r8, AirportGrid.TAXIWAY_BIT, "filled on build")
	grid.set_taxiway(Vector2i(100, 100), false)
	check_eq(grid.get_allocated_chunk_count(), 0, "the chunk is freed")
	check_eq(flags.refresh(), 1, "one chunk to clear")
	check_eq(flags.image.get_pixel(100, 100).r8, 0, "cleared in the image")


func test_big_map_touches_only_allocated_chunks() -> void:
	var grid := AirportGrid.new(BIG, 2.0)
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(1100, 800), Vector2i(2199, 1599), Vector2i(2150, 40)]:
		grid.set_walkway(cell, true)
	grid.set_zone_rect(Rect2i(1000, 700, 300, 5), AirportGrid.Zone.AIRSIDE)
	var allocated := grid.get_allocated_chunk_count()
	check(allocated < 40, "a handful of chunks on a map of %d" % ((BIG.x / 64 + 1) * (BIG.y / 64 + 1)))
	var started := Time.get_ticks_usec()
	var flags := GroundFlagTexture.new(grid)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	check_eq(flags.last_chunks_copied, allocated, "the first build copies the allocated chunks only")
	check_eq(flags.image.get_size(), BIG, "the image covers the map")
	check_eq(flags.image.get_pixel(2199, 1599).r8, AirportGrid.WALKWAY_BIT, "the corner chunk is clipped correctly")
	check_eq(flags.image.get_pixel(1100, 800).r8, AirportGrid.WALKWAY_BIT, "a walkway in the middle")
	check_eq(flags.image.get_pixel(1200, 702).r8, AirportGrid.Zone.AIRSIDE, "the airside rectangle")
	check_eq(flags.image.get_pixel(500, 500).r8, 0, "an untouched cell")

	grid.set_taxiway(Vector2i(1101, 801), true)
	started = Time.get_ticks_usec()
	var copied := flags.refresh()
	var edit_ms := (Time.get_ticks_usec() - started) / 1000.0
	check_eq(copied, 1, "a single edit copies one chunk")
	check_eq(flags.image.get_pixel(1101, 801).r8, AirportGrid.TAXIWAY_BIT, "the edit arrived")
	check_eq(flags.refresh(), 0, "nothing changed: nothing copied")
	print("INFO ground texture on %dx%d: build %.1f ms (%d chunks), one-chunk edit %.1f ms" % [BIG.x, BIG.y, build_ms, allocated, edit_ms])
