class_name GridSave
extends RefCounted
## Walkway and taxiway layers in a save game (save format 9, tech_architecture.md §13): a list of
## the non-empty chunks of AirportGrid.CHUNK_SIZE x CHUNK_SIZE cells, `{"cx", "cy", "data"}`, where
## "data" is the chunk's 0/1 flags (row by row) deflated and stored as base64 text. The size of a
## save follows the used chunks, never the map, and saving or loading never loops over the map.
## Older saves (format 8 and below) stored one dense array over the whole map; `from_dense`
## converts it, `to_dense` rebuilds it (the behaviour hash needs the old form, see BehaviourHash).

const CELLS_PER_CHUNK: int = AirportGrid.CHUNK_SIZE * AirportGrid.CHUNK_SIZE


## The chunks of `grid` that have at least one cell with a bit of `mask` set, in row-by-row chunk order.
static func encode(grid: AirportGrid, mask: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for coord in grid.get_allocated_chunks():
		var flags := grid.get_chunk_flags(coord)
		var bytes := PackedByteArray()
		bytes.resize(CELLS_PER_CHUNK)
		var any := false
		for i in CELLS_PER_CHUNK:
			if flags[i] & mask != 0:
				bytes[i] = 1
				any = true
		if any:
			result.append(_entry(coord, bytes))
	return result


## Every cell stored in `chunks` (unshifted, in the saved map's coordinates). Damaged entries are
## skipped with a warning; nothing here can crash on bad data.
static func cells_of(chunks: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for entry: Variant in chunks:
		if not entry is Dictionary:
			push_warning("A saved map chunk is damaged and was skipped.")
			continue
		var chunk := entry as Dictionary
		var cx := int(chunk.get("cx", -1))
		var cy := int(chunk.get("cy", -1))
		var bytes := Marshalls.base64_to_raw(String(chunk.get("data", ""))).decompress(CELLS_PER_CHUNK, FileAccess.COMPRESSION_DEFLATE)
		if cx < 0 or cy < 0 or bytes.size() != CELLS_PER_CHUNK:
			push_warning("A saved map chunk is damaged and was skipped.")
			continue
		var base := Vector2i(cx, cy) * AirportGrid.CHUNK_SIZE
		for i in CELLS_PER_CHUNK:
			if bytes[i] != 0:
				cells.append(base + Vector2i(i & AirportGrid.CHUNK_MASK, i >> AirportGrid.CHUNK_SHIFT))
	return cells


## Converts a dense layer (one byte per cell, row by row, `size` cells) to chunks. Empty chunks are
## left out. Only for old saves.
static func from_dense(dense: PackedByteArray, size: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if dense.size() != size.x * size.y:
		push_warning("A saved dense map layer has %d cells, expected %d; it was ignored." % [dense.size(), size.x * size.y])
		return result
	var wide := ceili(float(size.x) / AirportGrid.CHUNK_SIZE)
	var high := ceili(float(size.y) / AirportGrid.CHUNK_SIZE)
	for cy in high:
		for cx in wide:
			var bytes := PackedByteArray()
			bytes.resize(CELLS_PER_CHUNK)
			var any := false
			for y in mini(AirportGrid.CHUNK_SIZE, size.y - cy * AirportGrid.CHUNK_SIZE):
				var from := (cy * AirportGrid.CHUNK_SIZE + y) * size.x + cx * AirportGrid.CHUNK_SIZE
				for x in mini(AirportGrid.CHUNK_SIZE, size.x - cx * AirportGrid.CHUNK_SIZE):
					if dense[from + x] != 0:
						bytes[y * AirportGrid.CHUNK_SIZE + x] = 1
						any = true
			if any:
				result.append(_entry(Vector2i(cx, cy), bytes))
	return result


## The old dense form (one 0/1 byte per cell of a `size` map, row by row) of a chunk list. Loops
## over the whole map: for tests and tools, never for saving or loading.
static func to_dense(chunks: Array, size: Vector2i) -> PackedByteArray:
	var dense := PackedByteArray()
	dense.resize(size.x * size.y)
	for cell in cells_of(chunks):
		if cell.x < size.x and cell.y < size.y:
			dense[cell.y * size.x + cell.x] = 1
	return dense


static func _entry(coord: Vector2i, bytes: PackedByteArray) -> Dictionary:
	return {"cx": coord.x, "cy": coord.y, "data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_DEFLATE))}
