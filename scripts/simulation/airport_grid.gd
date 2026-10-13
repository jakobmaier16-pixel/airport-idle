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
# One byte per cell (row by row), holding a Zone value. All zeros = all landside.
var _zones: PackedByteArray = PackedByteArray()
# One byte per cell (row by row): 1 = walkway floor.
var _walkways: PackedByteArray = PackedByteArray()
# One byte per cell (row by row): 1 = taxiway.
var _taxiways: PackedByteArray = PackedByteArray()


func _init(size_in_cells: Vector2i, cell_size_meters: float) -> void:
	size = size_in_cells
	cell_size = cell_size_meters
	origin = Vector3(-size.x * cell_size * 0.5, 0.0, -size.y * cell_size * 0.5)
	_zones.resize(size.x * size.y)
	_walkways.resize(size.x * size.y)
	_taxiways.resize(size.x * size.y)


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
	return _zones[cell.y * size.x + cell.x] as Zone


func set_zone(cell: Vector2i, zone: Zone) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	_zones[cell.y * size.x + cell.x] = zone


## All zones, one byte per cell, row by row (for the ground overlay and save games).
func get_zone_data() -> PackedByteArray:
	return _zones


func set_zone_data(data: PackedByteArray) -> void:
	if data.size() == _zones.size():
		_zones = data


func is_walkway(cell: Vector2i) -> bool:
	return _walkways[cell.y * size.x + cell.x] == 1


func set_walkway(cell: Vector2i, walkway: bool) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	_walkways[cell.y * size.x + cell.x] = 1 if walkway else 0


func is_taxiway(cell: Vector2i) -> bool:
	return _taxiways[cell.y * size.x + cell.x] == 1


func set_taxiway(cell: Vector2i, taxiway: bool) -> void:
	assert(is_inside(cell), "Cell %s is outside the map" % cell)
	_taxiways[cell.y * size.x + cell.x] = 1 if taxiway else 0


## All taxiway flags, one byte per cell, row by row (for the ground and save games).
func get_taxiway_data() -> PackedByteArray:
	return _taxiways


func set_taxiway_data(data: PackedByteArray) -> void:
	if data.size() == _taxiways.size():
		_taxiways = data


## True if passengers can stand on `cell`: walkway floor without a building on it.
func is_walkable(cell: Vector2i) -> bool:
	return is_inside(cell) and is_walkway(cell) and is_empty(cell)


## All walkway flags, one byte per cell, row by row (for the ground and save games).
func get_walkway_data() -> PackedByteArray:
	return _walkways


func set_walkway_data(data: PackedByteArray) -> void:
	if data.size() == _walkways.size():
		_walkways = data
