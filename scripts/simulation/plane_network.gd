class_name PlaneNetwork
extends RefCounted
## Where planes can move (design doc §7.5a): taxiways, aircraft stands and runways. Each paved
## cell gets an area id, so "is this stand connected to a runway?" is a quick lookup, and planes
## find their way with Godot's grid pathfinding. Rebuilt when the layout changes.

var _grid: AirportGrid
var _paths: AStarGrid2D = AStarGrid2D.new()
# Connected-area id per cell (row by row); -1 = not paved for planes.
var _areas: PackedInt32Array = PackedInt32Array()
# Areas that contain a runway cell.
var _runway_areas: Dictionary[int, bool] = {}
var _runways: Array[Building] = []


func rebuild(grid: AirportGrid, buildings: Array[Building]) -> void:
	_grid = grid
	_runways.clear()
	for building in buildings:
		if building.type.role == BuildingType.Role.RUNWAY:
			_runways.append(building)
	_paths = AStarGrid2D.new()
	_paths.region = Rect2i(Vector2i.ZERO, grid.size)
	_paths.cell_size = Vector2.ONE
	_paths.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_paths.update()
	_paths.fill_solid_region(_paths.region, true)
	for y in grid.size.y:
		for x in grid.size.x:
			if is_paved(Vector2i(x, y)):
				_paths.set_point_solid(Vector2i(x, y), false)
	_label_areas()


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
		if _grid.is_inside(cell) and _runway_areas.has(_areas[cell.y * _grid.size.x + cell.x]):
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
		var path := _paths.get_id_path(runway_cell, target)
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


func _label_areas() -> void:
	var size := _grid.size
	_areas.resize(size.x * size.y)
	_areas.fill(-1)
	_runway_areas.clear()
	var next_id := 0
	var neighbours: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in size.y:
		for x in size.x:
			var start := Vector2i(x, y)
			if _areas[y * size.x + x] >= 0 or not is_paved(start):
				continue
			_areas[y * size.x + x] = next_id
			var open: Array[Vector2i] = [start]
			while not open.is_empty():
				var cell: Vector2i = open.pop_back()
				if runway_at(cell) != null:
					_runway_areas[next_id] = true
				for step in neighbours:
					var next := cell + step
					if _grid.is_inside(next) and _areas[next.y * size.x + next.x] < 0 and is_paved(next):
						_areas[next.y * size.x + next.x] = next_id
						open.append(next)
			next_id += 1
