class_name PlaneNetwork
extends RefCounted
## Where planes can move (design doc §7.5a): taxiways, aircraft stands and runways. Each paved
## cell gets an area id, so "is this stand connected to a runway?" is a quick lookup, and planes
## find their way with Godot's grid pathfinding. Rebuilt when the layout changes.

var _grid: AirportGrid
# Sparse, like WalkwayNetwork: one AStar2D (point id = y * map width + x) with only the paved cells,
# linked the way AStarGrid2D (no diagonals) visits neighbours, so paths and ties are unchanged.
var _paths: AStar2D = AStar2D.new()
# Connected-area id by cell id; a cell without an entry is not paved for planes.
var _areas: Dictionary[int, int] = {}
# Areas that contain a runway cell.
var _runway_areas: Dictionary[int, bool] = {}
var _runways: Array[Building] = []
# What the current network was built from (see rebuild).
var _signature_of_network: PackedInt64Array = PackedInt64Array()


func rebuild(grid: AirportGrid, buildings: Array[Building]) -> void:
	# Only the paved cells matter: a layout change that moved none of them (a walkway, a shop)
	# leaves the network as it is. With a 1,000-cell runway a rebuild is the costliest part of a
	# layout change.
	var signature := _signature(grid, buildings)
	if grid == _grid and signature == _signature_of_network:
		return
	_grid = grid
	_signature_of_network = signature
	_runways.clear()
	var width := grid.size.x
	var seen: Dictionary[int, bool] = {}
	for cell in grid.get_cells_with_flag(AirportGrid.TAXIWAY_BIT):
		seen[cell.y * width + cell.x] = true
	for building in buildings:
		if building.type.role == BuildingType.Role.RUNWAY:
			_runways.append(building)
		if building.type.role in [BuildingType.Role.RUNWAY, BuildingType.Role.AIRCRAFT_STAND]:
			# Every cell of a stand or runway is paved: the rectangle goes in row by row.
			var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
			for y in range(building.origin_cell.y, building.origin_cell.y + size.y):
				var row := y * width
				for x in range(building.origin_cell.x, building.origin_cell.x + size.x):
					seen[row + x] = true
	var ids := PackedInt32Array(seen.keys())
	# Row by row, like the dense scan this replaced: area ids come out the same.
	ids.sort()
	_paths = AStar2D.new()
	if not ids.is_empty():
		_paths.reserve_space(ids.size())
	for id in ids:
		_paths.add_point(id, Vector2(id % width, id / width))
	for id in ids:
		# Top, right, bottom, left: the order AStarGrid2D visits them.
		if seen.has(id - width):
			_paths.connect_points(id, id - width, false)
		if id % width < width - 1 and seen.has(id + 1):
			_paths.connect_points(id, id + 1, false)
		if seen.has(id + width):
			_paths.connect_points(id, id + width, false)
		if id % width > 0 and seen.has(id - 1):
			_paths.connect_points(id, id - 1, false)
	_label_areas(ids)


# What decides the paved cells: the taxiway layer and where the stands and runways are.
func _signature(grid: AirportGrid, buildings: Array[Building]) -> PackedInt64Array:
	var result := PackedInt64Array([grid.taxiway_revision])
	for building in buildings:
		if building.type.role in [BuildingType.Role.RUNWAY, BuildingType.Role.AIRCRAFT_STAND]:
			result.append_array(PackedInt64Array([building.id, building.origin_cell.x, building.origin_cell.y, building.rotation_steps]))
	return result


## True for cells planes can use: taxiway, stands and runways.
func is_paved(cell: Vector2i) -> bool:
	if not _grid.is_inside(cell):
		return false
	if _grid.is_taxiway(cell):
		return true
	var building := _grid.get_content(cell) as Building
	return building != null and building.type.role in [BuildingType.Role.AIRCRAFT_STAND, BuildingType.Role.RUNWAY]


## True if a plane can get from a runway to `cells` (e.g. the cells around a stand).
func reaches_runway(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if _grid.is_inside(cell) and _runway_areas.has(_areas.get(cell.y * _grid.size.x + cell.x, -1)):
			return true
	return false


func runways() -> Array[Building]:
	return _runways


## The cells from a runway to `stand`'s middle, or [] if there is no way. Starts on the runway
## cell closest to where the taxiway leaves it.
func path_to_stand(stand: Building) -> Array[Vector2i]:
	var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
	var target := stand.origin_cell + size / 2
	var best: Array[Vector2i] = []
	for runway in _runways:
		var runway_cell := _nearest_cell(runway, target)
		var path := _path(runway_cell, target)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
			best = path
	return best


## The runway a path starts on (the one containing `cell`), or null.
func runway_at(cell: Vector2i) -> Building:
	var building := _grid.get_content(cell) as Building if _grid.is_inside(cell) else null
	return building if building != null and building.type.role == BuildingType.Role.RUNWAY else null


# The cell of `building` closest to `to`.
func _nearest_cell(building: Building, to: Vector2i) -> Vector2i:
	var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
	return Vector2i(clampi(to.x, building.origin_cell.x, building.origin_cell.x + size.x - 1),
		clampi(to.y, building.origin_cell.y, building.origin_cell.y + size.y - 1))


# The cells from `from` to `to`, or [] if one of them is not paved or there is no way.
func _path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var width := _grid.size.x
	var from_id := from.y * width + from.x
	var to_id := to.y * width + to.x
	if not _areas.has(from_id) or _areas.get(from_id) != _areas.get(to_id, -2):
		return result
	for id in _paths.get_id_path(from_id, to_id):
		result.append(Vector2i(id % width, id / width))
	return result


## Number of paved cells (for tests and diagnostics).
func paved_count() -> int:
	return _areas.size()


## Connected-area id of a cell, or -1 if planes can't use it.
func area_of(cell: Vector2i) -> int:
	if not _grid.is_inside(cell):
		return -1
	return _areas.get(cell.y * _grid.size.x + cell.x, -1)


# Flood fill over the paved cells; `ids` is sorted, so area ids are numbered in row order.
func _label_areas(ids: PackedInt32Array) -> void:
	var width := _grid.size.x
	_areas = {}
	_runway_areas.clear()
	var next_id := 0
	var steps := PackedInt32Array([1, -1, width, -width])
	for start in ids:
		if _areas.has(start):
			continue
		_areas[start] = next_id
		var open := PackedInt32Array([start])
		while not open.is_empty():
			var id := open[open.size() - 1]
			open.resize(open.size() - 1)
			var cell := Vector2i(id % width, id / width)
			for k in 4:
				if (k == 0 and cell.x == width - 1) or (k == 1 and cell.x == 0):
					continue
				var next := id + steps[k]
				if _areas.has(next) or not _paths.has_point(next):
					continue
				_areas[next] = next_id
				open.append(next)
		next_id += 1
	# A runway is one connected rectangle: its first cell tells which area it is in.
	for runway in _runways:
		_runway_areas[_areas[runway.origin_cell.y * width + runway.origin_cell.x]] = true
