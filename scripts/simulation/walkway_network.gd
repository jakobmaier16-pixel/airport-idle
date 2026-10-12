class_name WalkwayNetwork
extends RefCounted
## Where passengers can walk (design doc §7.1b). One path grid per zone, so landside and airside
## walkways are never linked directly: security is the only way across. Each walkable cell also
## gets an area id, so "can A reach B?" is a quick lookup. Rebuilt when the layout changes.

var _grid: AirportGrid
# Godot's built-in grid pathfinding, one per zone (index = AirportGrid.Zone).
var _paths: Array[AStarGrid2D] = []
# Connected-area id per cell (row by row); -1 = not walkable.
var _areas: PackedInt32Array = PackedInt32Array()


func rebuild(grid: AirportGrid) -> void:
	_grid = grid
	_paths.clear()
	for zone in [AirportGrid.Zone.LANDSIDE, AirportGrid.Zone.AIRSIDE]:
		var paths := AStarGrid2D.new()
		paths.region = Rect2i(Vector2i.ZERO, grid.size)
		paths.cell_size = Vector2.ONE
		# Diagonal steps only where they don't cut a corner.
		paths.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		paths.update()
		paths.fill_solid_region(paths.region, true)
		for y in grid.size.y:
			for x in grid.size.x:
				var cell := Vector2i(x, y)
				if grid.is_walkable(cell) and grid.get_zone(cell) == zone:
					paths.set_point_solid(cell, false)
		_paths.append(paths)
	_label_areas()


func is_walkable(cell: Vector2i) -> bool:
	return _grid.is_inside(cell) and _areas[cell.y * _grid.size.x + cell.x] >= 0


## Connected-area id of a cell, or -1 if nobody can stand there.
func area_of(cell: Vector2i) -> int:
	if not _grid.is_inside(cell):
		return -1
	return _areas[cell.y * _grid.size.x + cell.x]


## Cells from `from` to `to` (both included), or an empty array if there is no way.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if area_of(from) < 0 or area_of(from) != area_of(to):
		return []
	return _paths[_grid.get_zone(from)].get_id_path(from, to)


## The closest walkable cell around `cell` (e.g. after a building was placed on a passenger).
func nearest_walkable(cell: Vector2i, max_radius: int = 4) -> Variant:
	for radius in range(0, max_radius + 1):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) == radius and is_walkable(cell + Vector2i(x, y)):
					return cell + Vector2i(x, y)
	return null


# Flood fill: neighbouring walkable cells of the same zone share an area id.
func _label_areas() -> void:
	var size := _grid.size
	_areas.resize(size.x * size.y)
	_areas.fill(-1)
	var next_id := 0
	var neighbours: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in size.y:
		for x in size.x:
			var start := Vector2i(x, y)
			if _areas[y * size.x + x] >= 0 or not _grid.is_walkable(start):
				continue
			var zone := _grid.get_zone(start)
			_areas[y * size.x + x] = next_id
			var open: Array[Vector2i] = [start]
			while not open.is_empty():
				var cell: Vector2i = open.pop_back()
				for step in neighbours:
					var next := cell + step
					if not _grid.is_inside(next) or _areas[next.y * size.x + next.x] >= 0:
						continue
					if _grid.is_walkable(next) and _grid.get_zone(next) == zone:
						_areas[next.y * size.x + next.x] = next_id
						open.append(next)
			next_id += 1
