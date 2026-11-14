class_name AirportGrid
extends RefCounted
## The building grid as pure simulation data: no nodes, no visuals.
## Converts between world positions and grid cells, and stores what occupies each cell.
## Cell (0, 0) is the map corner at `origin`; cell x grows along world +X, cell y along world +Z.
## Every cell also has a zone (design doc §7.2), landside by default, and may be walkway floor (§7.1b)
## or taxiway for planes (§7.5a), never both.

enum Zone { LANDSIDE, AIRSIDE }

## Map size in cells.
var size: Vector2i
## Edge length of one cell in meters.
var cell_size: float
## World position of the map corner where cell (0, 0) starts. The map is centered on the world origin.
var origin: Vector3

# Sparse storage: only occupied cells have an entry (the Building on that cell).
var _contents: Dictionary[Vector2i, Variant] = {}
# One flag byte per cell, stored in CHUNK_SIZE x CHUNK_SIZE chunks (index = chunk x + chunk y * width
# in chunks). A chunk that is all zero is not allocated (null). Chunks are GridChunk objects, not
# PackedByteArrays: a packed array read out of an Array is a copy, so writes to it would be lost.
var _chunks: Array = []
var _chunks_wide: int = 0
var _chunks_high: int = 0
var _allocated_chunks: int = 0
# Chunks whose flags changed since the last `take_dirty_chunks()`: chunk index -> true. Filled by every
# flag write that changes a value (so a rebuild of the ground texture only visits these chunks).
var _dirty: Dictionary[int, bool] = {}
## Counts every change of the taxiway layer: lets the plane network skip a rebuild when no paved
## cell moved (see PlaneNetwork.rebuild).
var taxiway_revision: int = 0


## Edge length of a storage chunk in cells.
const CHUNK_SHIFT: int = 6
const CHUNK_SIZE: int = 1 << CHUNK_SHIFT
## Masks a cell coordinate down to its position inside a chunk.
const CHUNK_MASK: int = CHUNK_SIZE - 1
## Bit layout of the flag byte of a cell.
const ZONE_MASK: int = 0x07
const WALKWAY_BIT: int = 0x08
const TAXIWAY_BIT: int = 0x10
## Reserved (nothing sets it): the whole map is buildable since the strip to core, 2026-11-14.
const OWNED_BIT: int = 0x20
## Ground surface under stands and runways (bits 6-7, a 2-bit value; 0 = none). These are buildings, not
## painted layers: the brain fills the footprint when one is placed and clears it when it is demolished,
## so the bits are derived from the buildings and never saved (a load places the buildings again).
## Only the ground shader reads them (concrete apron, asphalt runway).
const SURFACE_MASK: int = 0xC0
const SURFACE_CONCRETE: int = 0x40
const SURFACE_RUNWAY: int = 0x80


## One chunk: the flag bytes of its cells (row by row) and how many of them are not zero.
class GridChunk extends RefCounted:
	var cells: PackedByteArray = PackedByteArray()
	var nonzero: int = 0
	## How many cells have each flag bit set (index = bit number; the zone bits 0-2 are not counted).
	## Lets a scan for walkway or taxiway cells skip chunks that only hold zone flags, e.g. the
	## ones under a 1,000-cell runway.
	var bit_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])

	func _init() -> void:
		cells.resize(CHUNK_SIZE * CHUNK_SIZE)


func _init(size_in_cells: Vector2i, cell_size_meters: float) -> void:
	# Even sizes only: the map is centered on the world origin, and a save of another map size is
	# placed in the middle by (size difference) / 2 cells; both stay on whole cells only if every
	# size is even.
	assert(size_in_cells.x % 2 == 0 and size_in_cells.y % 2 == 0, "Map size %s must be even" % size_in_cells)
	size = size_in_cells
	cell_size = cell_size_meters
	origin = Vector3(-size.x * cell_size * 0.5, 0.0, -size.y * cell_size * 0.5)
	_chunks_wide = ceili(float(size.x) / CHUNK_SIZE)
	_chunks_high = ceili(float(size.y) / CHUNK_SIZE)
	_chunks.resize(_chunks_wide * _chunks_high)


## The cell that contains `world_position`. May be outside the map; check with `is_inside()`.
func world_to_cell(world_position: Vector3) -> Vector2i:
	var local := world_position - origin
	return Vector2i(floori(local.x / cell_size), floori(local.z / cell_size))


## World position of the center of `cell`, on the ground (y = 0).
func cell_to_world(cell: Vector2i) -> Vector3:
	return origin + Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func is_empty(cell: Vector2i) -> bool:
	return not _contents.has(cell)


## True if every cell is on the map and empty.
func are_cells_free(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not is_inside(cell) or not is_empty(cell):
			return false
	return true


## World position of the center of a rectangular block of cells, on the ground (y = 0).
func block_center(origin_cell: Vector2i, size_in_cells: Vector2i) -> Vector3:
	var center_in_cells := Vector2(origin_cell) + Vector2(size_in_cells) * 0.5
	return origin + Vector3(center_in_cells.x * cell_size, 0.0, center_in_cells.y * cell_size)


## What occupies `cell`, or null if it is empty.
func get_content(cell: Vector2i) -> Variant:
	return _contents.get(cell)


## Puts `content` into `cell`. Passing null empties the cell.
func set_content(cell: Vector2i, content: Variant) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	if content == null:
		_contents.erase(cell)
	else:
		_contents[cell] = content


## The map area on the ground plane in meters: position = (min x, min z), size = (width, depth).
func get_world_rect() -> Rect2:
	return Rect2(origin.x, origin.z, size.x * cell_size, size.y * cell_size)


func get_zone(cell: Vector2i) -> Zone:
	return (get_flags(cell) & ZONE_MASK) as Zone


func set_zone(cell: Vector2i, zone: Zone) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	_write(cell, ZONE_MASK, int(zone) & ZONE_MASK)


## All zones, one byte per cell, row by row (for the ground overlay and save games).
func get_zone_data() -> PackedByteArray:
	return _dense(ZONE_MASK)


func set_zone_data(data: PackedByteArray) -> void:
	if data.size() == size.x * size.y:
		_set_dense(ZONE_MASK, data)


func is_walkway(cell: Vector2i) -> bool:
	return get_flags(cell) & WALKWAY_BIT != 0


func set_walkway(cell: Vector2i, walkway: bool) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	_write(cell, WALKWAY_BIT, WALKWAY_BIT if walkway else 0)


func is_taxiway(cell: Vector2i) -> bool:
	return get_flags(cell) & TAXIWAY_BIT != 0


func set_taxiway(cell: Vector2i, taxiway: bool) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	_write(cell, TAXIWAY_BIT, TAXIWAY_BIT if taxiway else 0)


## The ground surface of `cell`: 0, SURFACE_CONCRETE or SURFACE_RUNWAY.
func get_surface(cell: Vector2i) -> int:
	return get_flags(cell) & SURFACE_MASK


## Sets the surface (0, SURFACE_CONCRETE or SURFACE_RUNWAY) of every cell of `rect` (clipped to the
## map). The cost follows the rectangle; chunks that stay all zero are not allocated.
func set_surface_rect(rect: Rect2i, surface: int) -> void:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, size))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			_write(Vector2i(x, y), SURFACE_MASK, surface & SURFACE_MASK)


## All taxiway flags, one byte per cell (0 or 1), row by row (for the ground and save games).
func get_taxiway_data() -> PackedByteArray:
	return _dense(TAXIWAY_BIT)


func set_taxiway_data(data: PackedByteArray) -> void:
	if data.size() == size.x * size.y:
		_set_dense(TAXIWAY_BIT, data)


## True if passengers can stand on `cell`: walkway floor without a building on it.
func is_walkable(cell: Vector2i) -> bool:
	return is_inside(cell) and is_walkway(cell) and is_empty(cell)


## All walkway flags, one byte per cell (0 or 1), row by row (for the ground and save games).
func get_walkway_data() -> PackedByteArray:
	return _dense(WALKWAY_BIT)


func set_walkway_data(data: PackedByteArray) -> void:
	if data.size() == size.x * size.y:
		_set_dense(WALKWAY_BIT, data)


## The raw flag byte of `cell` (zone bits, walkway, taxiway, owned); 0 for unallocated chunks and
## cells outside the map.
func get_flags(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return 0
	var chunk: GridChunk = _chunks[(cell.y >> CHUNK_SHIFT) * _chunks_wide + (cell.x >> CHUNK_SHIFT)]
	if chunk == null:
		return 0
	return chunk.cells[(cell.y & CHUNK_MASK) * CHUNK_SIZE + (cell.x & CHUNK_MASK)]


## Number of chunks that hold at least one non-zero cell (the only ones that use memory).
func get_allocated_chunk_count() -> int:
	return _allocated_chunks


## Chunk coordinates (cell / CHUNK_SIZE) of every allocated chunk, row by row.
func get_allocated_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in _chunks.size():
		if _chunks[index] != null:
			result.append(Vector2i(index % _chunks_wide, index / _chunks_wide))
	return result


## The flag bytes of the allocated chunk at `chunk_coord` (CHUNK_SIZE x CHUNK_SIZE, row by row), or
## an empty array if that chunk is not allocated. A copy: changing it does not change the grid.
func get_chunk_flags(chunk_coord: Vector2i) -> PackedByteArray:
	var chunk := _chunk_at(chunk_coord)
	return chunk.cells if chunk != null else PackedByteArray()


## How many cells have any of the bits in `mask` set (e.g. WALKWAY_BIT), counted chunk by chunk.
func count_flag(mask: int) -> int:
	var total := 0
	# One flag bit (not a zone): the chunks keep the count, no scanning.
	var single_bit := mask & (mask - 1) == 0 and mask & ZONE_MASK == 0
	for chunk: GridChunk in _chunks:
		if chunk == null:
			continue
		if single_bit:
			total += chunk.bit_counts[_bit_number(mask)]
			continue
		for value in chunk.cells:
			if value & mask != 0:
				total += 1
	return total


## Chunk coordinates of every chunk whose flags changed since the last call, row by row, and forgets
## them. A chunk that became empty (and is no longer allocated) is listed too: its cells are now 0.
## Meant for one consumer, the ground texture (scenes/ground/ground_flag_texture.gd).
func take_dirty_chunks() -> Array[Vector2i]:
	var indices := _dirty.keys()
	indices.sort()
	_dirty.clear()
	var result: Array[Vector2i] = []
	for index: int in indices:
		result.append(Vector2i(index % _chunks_wide, index / _chunks_wide))
	return result


## How many chunks are waiting in the dirty set.
func get_dirty_chunk_count() -> int:
	return _dirty.size()


## Every cell whose flag byte is not zero, chunk by chunk (cheap: unallocated chunks are skipped).
func get_nonempty_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in _chunks.size():
		var chunk: GridChunk = _chunks[index]
		if chunk == null:
			continue
		var base := Vector2i(index % _chunks_wide, index / _chunks_wide) * CHUNK_SIZE
		for i in chunk.cells.size():
			if chunk.cells[i] != 0:
				result.append(base + Vector2i(i & CHUNK_MASK, i >> CHUNK_SHIFT))
	return result


## Every cell with any of the bits in `mask` set (e.g. TAXIWAY_BIT), chunk by chunk: the cost follows
## the allocated chunks, not the map. The order is chunk by chunk, not row by row.
func get_cells_with_flag(mask: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var counted := mask & ZONE_MASK == 0
	for index in _chunks.size():
		var chunk: GridChunk = _chunks[index]
		if chunk == null:
			continue
		# Chunks without a cell of these bits are skipped (not the zone bits: they are not counted).
		if counted and not _chunk_has_bits(chunk, mask):
			continue
		var base := Vector2i(index % _chunks_wide, index / _chunks_wide) * CHUNK_SIZE
		for i in chunk.cells.size():
			if chunk.cells[i] & mask != 0:
				result.append(base + Vector2i(i & CHUNK_MASK, i >> CHUNK_SHIFT))
	return result


## Sets the zone of every cell of `rect` (clipped to the map), row by row. The cost follows the
## rectangle, never the map; chunks that stay all zero are not allocated.
func set_zone_rect(rect: Rect2i, zone: Zone) -> void:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, size))
	var bits := int(zone) & ZONE_MASK
	for y in range(area.position.y, area.end.y):
		# One chunk at a time along the row: a 1,000-cell runway touches 16 chunks per row, not 1,000 cells.
		var x := area.position.x
		while x < area.end.x:
			var run_end := mini(area.end.x, (x | CHUNK_MASK) + 1)
			_write_run(y, x, run_end, bits)
			x = run_end


func _chunk_at(chunk_coord: Vector2i) -> GridChunk:
	if chunk_coord.x < 0 or chunk_coord.y < 0 or chunk_coord.x >= _chunks_wide or chunk_coord.y >= _chunks_high:
		return null
	return _chunks[chunk_coord.y * _chunks_wide + chunk_coord.x]


func _bit_number(mask: int) -> int:
	return int(log(float(mask)) / log(2.0) + 0.5)


func _chunk_has_bits(chunk: GridChunk, mask: int) -> bool:
	for bit in range(3, 8):
		if mask & (1 << bit) != 0 and chunk.bit_counts[bit] > 0:
			return true
	return false


# Keeps a chunk's per-bit counts (and the taxiway revision) right after a cell changed from `old` to `value`.
func _count_change(chunk: GridChunk, old: int, value: int) -> void:
	var diff := (old ^ value) & ~ZONE_MASK
	if diff == 0:
		return
	for bit in range(3, 8):
		if diff & (1 << bit) != 0:
			chunk.bit_counts[bit] += 1 if value & (1 << bit) != 0 else -1
	if diff & TAXIWAY_BIT != 0:
		taxiway_revision += 1


# Sets the zone bits of the cells (x0 .. x1 - 1, y), all inside one chunk, like `_write` for each.
func _write_run(y: int, x0: int, x1: int, bits: int) -> void:
	var chunk_index := (y >> CHUNK_SHIFT) * _chunks_wide + (x0 >> CHUNK_SHIFT)
	var chunk: GridChunk = _chunks[chunk_index]
	if chunk == null:
		if bits == 0:
			return
		chunk = GridChunk.new()
		_chunks[chunk_index] = chunk
		_allocated_chunks += 1
	var first := (y & CHUNK_MASK) * CHUNK_SIZE + (x0 & CHUNK_MASK)
	var changed := false
	for i in range(first, first + (x1 - x0)):
		var old: int = chunk.cells[i]
		var value := (old & ~ZONE_MASK) | bits
		if value == old:
			continue
		chunk.cells[i] = value
		changed = true
		if old == 0:
			chunk.nonzero += 1
		elif value == 0:
			chunk.nonzero -= 1
	if not changed:
		return
	_dirty[chunk_index] = true
	if chunk.nonzero == 0:
		_chunks[chunk_index] = null
		_allocated_chunks -= 1


# Sets the bits in `mask` of `cell` to `bits`; allocates the chunk on first non-zero write and frees
# it again when its last non-zero cell is cleared.
func _write(cell: Vector2i, mask: int, bits: int) -> void:
	var chunk_index := (cell.y >> CHUNK_SHIFT) * _chunks_wide + (cell.x >> CHUNK_SHIFT)
	var chunk: GridChunk = _chunks[chunk_index]
	if chunk == null:
		if bits == 0:
			return
		chunk = GridChunk.new()
		_chunks[chunk_index] = chunk
		_allocated_chunks += 1
	var i := (cell.y & CHUNK_MASK) * CHUNK_SIZE + (cell.x & CHUNK_MASK)
	var old: int = chunk.cells[i]
	var value := (old & ~mask) | bits
	if value == old:
		return
	_dirty[chunk_index] = true
	chunk.cells[i] = value
	_count_change(chunk, old, value)
	if old == 0:
		chunk.nonzero += 1
	elif value == 0:
		chunk.nonzero -= 1
		if chunk.nonzero == 0:
			_chunks[chunk_index] = null
			_allocated_chunks -= 1


# One byte per cell, row by row: the cell's bits in `mask`, as 0/1 for a single-bit layer or the
# zone value for the zone layer.
func _dense(mask: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(size.x * size.y)
	var single := mask != ZONE_MASK
	for index in _chunks.size():
		var chunk: GridChunk = _chunks[index]
		if chunk == null:
			continue
		var base_x := (index % _chunks_wide) * CHUNK_SIZE
		var base_y := (index / _chunks_wide) * CHUNK_SIZE
		var rows := mini(CHUNK_SIZE, size.y - base_y)
		var columns := mini(CHUNK_SIZE, size.x - base_x)
		for y in rows:
			var from := y * CHUNK_SIZE
			var to := (base_y + y) * size.x + base_x
			for x in columns:
				var bits: int = chunk.cells[from + x] & mask
				if bits != 0:
					data[to + x] = 1 if single else bits
	return data


# Replaces one layer (`mask`) from a dense array: nonzero byte = flag set (for a single-bit layer),
# or the byte is the zone value.
func _set_dense(mask: int, data: PackedByteArray) -> void:
	var single := mask != ZONE_MASK
	var w := size.x
	for y in size.y:
		for x in w:
			var value := data[y * w + x]
			var cell := Vector2i(x, y)
			# Skip the many untouched zeros without allocating a chunk.
			if value == 0 and get_flags(cell) & mask == 0:
				continue
			_write(cell, mask, (mask if value == 1 else 0) if single else (value & ZONE_MASK))
