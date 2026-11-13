class_name WalkwayNetwork
extends RefCounted
## Where passengers can walk (design doc §7.1b). Landside and airside walkways are never linked
## directly: security is the only way across. Each walkable cell also gets an area id, so "can A
## reach B?" is a quick lookup. Rebuilt when the layout changes.
##
## Sparse (tech_architecture.md, real-scale map): only walkable cells exist here, in one AStar2D
## (point id = y * map width + x) and one Dictionary for the area ids. Memory and rebuild time grow
## with the number of walkway cells, not with the map size. Paths are the same as with the
## AStarGrid2D this replaced: same cost, same heuristic, same corner rule, and the neighbours of a
## point are linked in the order AStarGrid2D visits them, so ties break the same way.

var _grid: AirportGrid
# One graph for both zones; cells of different zones are never linked.
var _paths: AStar2D = AStar2D.new()
# Connected-area id by cell id (y * width + x); a cell without an entry is not walkable.
var _areas: Dictionary[int, int] = {}

const _TOP := Vector2i(0, -1)
const _RIGHT := Vector2i(1, 0)
const _BOTTOM := Vector2i(0, 1)
const _LEFT := Vector2i(-1, 0)


func rebuild(grid: AirportGrid) -> void:
	_grid = grid
	_paths = AStar2D.new()
	_areas = {}
	var width := grid.size.x
	var ids := PackedInt32Array()
	for cell in grid.get_nonempty_cells():
		if grid.is_walkable(cell):
			ids.append(cell.y * width + cell.x)
	# Row by row, like the dense scan this replaced: area ids come out the same.
	ids.sort()
	_label_areas(ids)
	_link(ids)


func is_walkable(cell: Vector2i) -> bool:
	return _grid.is_inside(cell) and _areas.has(cell.y * _grid.size.x + cell.x)


## Number of walkable cells (for tests and diagnostics).
func walkable_count() -> int:
	return _areas.size()


## Connected-area id of a cell, or -1 if nobody can stand there.
func area_of(cell: Vector2i) -> int:
	if not _grid.is_inside(cell):
		return -1
	return _areas.get(cell.y * _grid.size.x + cell.x, -1)


## Cells from `from` to `to` (both included), or an empty array if there is no way.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if area_of(from) < 0 or area_of(from) != area_of(to):
		return result
	var width := _grid.size.x
	for id in _paths.get_id_path(from.y * width + from.x, to.y * width + to.x):
		result.append(Vector2i(id % width, id / width))
	return result


## The closest walkable cell around `cell` (e.g. after a building was placed on a passenger).
func nearest_walkable(cell: Vector2i, max_radius: int = 4) -> Variant:
	for radius in range(0, max_radius + 1):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) == radius and is_walkable(cell + Vector2i(x, y)):
					return cell + Vector2i(x, y)
	return null


# Flood fill: neighbouring walkable cells of the same zone share an area id. `ids` is sorted, so
# the area of the first cell in row order gets the lowest id.
func _label_areas(ids: PackedInt32Array) -> void:
	var width := _grid.size.x
	var next_id := 0
	var steps := PackedInt32Array([1, -1, width, -width])
	for start in ids:
		if _areas.has(start):
			continue
		var zone := _grid.get_zone(Vector2i(start % width, start / width))
		_areas[start] = next_id
		var open := PackedInt32Array([start])
		while not open.is_empty():
			var id := open[open.size() - 1]
			open.resize(open.size() - 1)
			var x := id % width
			for k in 4:
				# Don't wrap around the map edge.
				if (k == 0 and x == width - 1) or (k == 1 and x == 0):
					continue
				var next := id + steps[k]
				if _areas.has(next) or not _walkable_id(next, zone):
					continue
				_areas[next] = next_id
				open.append(next)
		next_id += 1


# The cell with this id is walkable and in `zone`. Only called with ids that are on the map or
# next to it (the sorted ids and their neighbours); off-map ids are never in the walkable set.
func _walkable_id(id: int, zone: int) -> bool:
	var width := _grid.size.x
	return id >= 0 and id < width * _grid.size.y and _grid.is_walkable(Vector2i(id % width, id / width)) \
		and _grid.get_zone(Vector2i(id % width, id / width)) == zone


# Adds every cell as a point and links each to its neighbours in the order AStarGrid2D visits them
# (top, right, bottom, left, then the diagonals), diagonals only where neither side is blocked.
func _link(ids: PackedInt32Array) -> void:
	var width := _grid.size.x
	if not ids.is_empty():
		_paths.reserve_space(ids.size())
	for id in ids:
		_paths.add_point(id, Vector2(id % width, id / width))
	for id in ids:
		var cell := Vector2i(id % width, id / width)
		var zone := _grid.get_zone(cell)
		var top := _open(cell + _TOP, zone)
		var right := _open(cell + _RIGHT, zone)
		var bottom := _open(cell + _BOTTOM, zone)
		var left := _open(cell + _LEFT, zone)
		if top:
			_paths.connect_points(id, id - width, false)
		if right:
			_paths.connect_points(id, id + 1, false)
		if bottom:
			_paths.connect_points(id, id + width, false)
		if left:
			_paths.connect_points(id, id - 1, false)
		if top and left and _open(cell + _TOP + _LEFT, zone):
			_paths.connect_points(id, id - width - 1, false)
		if top and right and _open(cell + _TOP + _RIGHT, zone):
			_paths.connect_points(id, id - width + 1, false)
		if bottom and right and _open(cell + _BOTTOM + _RIGHT, zone):
			_paths.connect_points(id, id + width + 1, false)
		if bottom and left and _open(cell + _BOTTOM + _LEFT, zone):
			_paths.connect_points(id, id + width - 1, false)


func _open(cell: Vector2i, zone: int) -> bool:
	return is_walkable(cell) and _grid.get_zone(cell) == zone
