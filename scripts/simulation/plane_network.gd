class_name PlaneNetwork
extends RefCounted
## Where planes can move (design doc §7.5a): taxiways, aircraft stands and runways. Each paved
## cell gets an area id, so "is this stand connected to a runway?" is a quick lookup, and planes
## find their way with Godot's grid pathfinding. Rebuilt when the layout changes.

## A taxiway must be at least this many cells (24 m) wide, across, to count for planes: thinner
## pavement is not part of the network, so no route runs on it (ICAO taxiways are 15 to 23 m wide
## with the wings reaching beyond the edge). Stands and runways are always wide enough.
const MIN_TAXIWAY_CELLS: int = 12
## How far the push-back point lies beyond the stand's back edge at most (cells): the middle of the
## pavement behind the stand, at most half of a taxiway's width.
const PUSHBACK_REACH_CELLS: int = MIN_TAXIWAY_CELLS
## Where on the runway a plane touches down, measured from its far end, and how far before that end
## it lifts off (metres).
const TOUCHDOWN_ZONE_M: float = 300.0
const LIFTOFF_MARGIN_M: float = 100.0

var _grid: AirportGrid
# Sparse: one AStar2D (point id = y * map width + x) with only the paved cells,
# linked the way AStarGrid2D (no diagonals) visits neighbours, so paths and ties are unchanged.
var _paths: AStar2D = AStar2D.new()
# Connected-area id by cell id; a cell without an entry is not paved for planes.
var _areas: Dictionary[int, int] = {}
# Areas that contain a runway cell.
var _runway_areas: Dictionary[int, bool] = {}
var _runways: Array[Building] = []
# The buildings of the last rebuild (to find the gate in front of a stand).
var _buildings: Array[Building] = []
# What the current network was built from (see rebuild).
var _signature_of_network: PackedInt64Array = PackedInt64Array()
# The middle lines of the pavement (step 7b), derived in rebuild; not used for timing yet.
var _centreline: CentrelineGraph = CentrelineGraph.new()
# Smoothed routes by stand id (null = the stand has none): all built right after a rebuild (never
# inside a simulation step) and dropped with the network.
var _routes: Dictionary[int, PlaneRoute] = {}
# The longest planned drive of any route: landing roll + taxi in, and taxi out + take-off run (seconds).
var _longest_arrival: float = 0.0
var _longest_departure: float = 0.0
## Counts the real rebuilds (a layout change that moved no paved cell does not count).
var rebuild_count: int = 0
## How long the last real rebuild took in total / of that the centreline graph (milliseconds).
var last_rebuild_ms: float = 0.0
var last_centreline_ms: float = 0.0
## How long building every stand's route took in the last real rebuild (it is part of last_rebuild_ms).
var last_routes_ms: float = 0.0
## How many routes were made so far (a debug counter: the simulation must never make one).
var routes_built: int = 0


func rebuild(grid: AirportGrid, buildings: Array[Building]) -> void:
	# Only the paved cells matter: a layout change that moved none of them (a walkway, a shop)
	# leaves the network as it is. With a 1,000-cell runway a rebuild is the costliest part of a
	# layout change.
	var signature := _signature(grid, buildings)
	if grid == _grid and signature == _signature_of_network:
		return
	var started := Time.get_ticks_usec()
	_grid = grid
	_buildings = buildings
	_signature_of_network = signature
	_runways.clear()
	_routes.clear()
	_longest_arrival = 0.0
	_longest_departure = 0.0
	var stands: Array[Building] = []
	var width := grid.size.x
	var seen: Dictionary[int, bool] = {}
	var taxiway: Array[int] = []
	for cell in grid.get_cells_with_flag(AirportGrid.TAXIWAY_BIT):
		taxiway.append(cell.y * width + cell.x)
		seen[cell.y * width + cell.x] = true
	var solid: Dictionary[int, bool] = {}
	for building in buildings:
		if building.type.role == BuildingType.Role.RUNWAY:
			_runways.append(building)
		if building.type.role == BuildingType.Role.AIRCRAFT_STAND:
			stands.append(building)
		if building.type.role in [BuildingType.Role.RUNWAY, BuildingType.Role.AIRCRAFT_STAND]:
			# Every cell of a stand or runway is paved: the rectangle goes in row by row.
			var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
			for y in range(building.origin_cell.y, building.origin_cell.y + size.y):
				var row := y * width
				for x in range(building.origin_cell.x, building.origin_cell.x + size.x):
					seen[row + x] = true
					solid[row + x] = true
	# Thin taxiway is not part of the network (see MIN_TAXIWAY_CELLS).
	for id in taxiway:
		if not solid.has(id) and not _is_wide_enough(id, seen, width, grid.size.y):
			seen.erase(id)
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
	var centreline_started := Time.get_ticks_usec()
	_centreline.build(_areas, width, grid.size.y, stands, _runways)
	var routes_started := Time.get_ticks_usec()
	last_centreline_ms = (routes_started - centreline_started) / 1000.0
	# Every stand's route now, so the simulation only ever looks them up.
	for stand in stands:
		var route := route_to_stand(stand)
		if route != null:
			_longest_arrival = maxf(_longest_arrival, route.roll_in_time + route.taxi_in_time)
			_longest_departure = maxf(_longest_departure, route.taxi_out_time + route.roll_out_time)
	var finished := Time.get_ticks_usec()
	last_routes_ms = (finished - routes_started) / 1000.0
	last_rebuild_ms = (finished - started) / 1000.0
	rebuild_count += 1


# True if the pavement through `id` is at least MIN_TAXIWAY_CELLS cells long both across and along:
# the run of paved cells in a row and in a column through the cell.
func _is_wide_enough(id: int, paved: Dictionary, width: int, height: int) -> bool:
	var x := id % width
	var y := id / width
	var run := 1
	var k := 1
	while run < MIN_TAXIWAY_CELLS and x - k >= 0 and paved.has(id - k):
		run += 1
		k += 1
	k = 1
	while run < MIN_TAXIWAY_CELLS and x + k < width and paved.has(id + k):
		run += 1
		k += 1
	if run < MIN_TAXIWAY_CELLS:
		return false
	run = 1
	k = 1
	while run < MIN_TAXIWAY_CELLS and y - k >= 0 and paved.has(id - k * width):
		run += 1
		k += 1
	k = 1
	while run < MIN_TAXIWAY_CELLS and y + k < height and paved.has(id + k * width):
		run += 1
		k += 1
	return run >= MIN_TAXIWAY_CELLS


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


## The middle lines graph (for tests and diagnostics).
func centreline() -> CentrelineGraph:
	return _centreline


## The smooth ground route from a runway exit to `stand`, or null if the stand has no way to a
## runway. Made for every stand by rebuild(); a stand that is not part of the network yet (tests
## that skip the rebuild) gets one on first use. Deterministic: ties go to the first runway and
## exit in id order.
func route_to_stand(stand: Building) -> PlaneRoute:
	if _routes.has(stand.id):
		return _routes[stand.id]
	var route := _make_route(stand)
	routes_built += 1
	_routes[stand.id] = route
	return route


## Seconds of the longest landing roll plus taxi in over all stands, and of the longest taxi out
## plus take-off run: the timetable plans ahead by these (no cap: a far stand lands earlier).
func longest_arrival() -> float:
	return _longest_arrival


func longest_departure() -> float:
	return _longest_departure


func _make_route(stand: Building) -> PlaneRoute:
	# The centreline graph can link pavement the cell network cannot walk (a cut taxiway): only a
	# stand that really reaches a runway gets a route.
	var size_of_stand := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
	var middle := stand.origin_cell + size_of_stand / 2
	if not _runway_areas.has(area_of(middle)):
		return null
	var lead_in := _centreline.lead_in_of(stand.id)
	var best := PackedVector2Array()
	var best_length := INF
	var best_runway: Building = null
	if _centreline.has_lead_in(stand.id):
		# Every runway exit is a candidate; the straight distance is the least a way to it can be, so
		# the nearest are tried first and the rest are skipped once a way is shorter than that.
		# Ties still go to the first exit in (runway, exit) order.
		var from := _centreline.point_of(lead_in)
		var candidates: Array = []
		var order := 0
		for runway in _runways:
			for exit: int in _centreline.exits_of(runway.id):
				candidates.append([from.distance_to(_centreline.point_of(exit)), order, exit, runway])
				order += 1
		candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var best_order := -1
		for candidate: Array in candidates:
			if candidate[0] > best_length + 0.001:
				break
			var nodes := _centreline.node_path(lead_in, candidate[2])
			if nodes.is_empty():
				continue
			var line := PackedVector2Array()
			var length := 0.0
			# Runway exit first, the stand last.
			for k in range(nodes.size() - 1, -1, -1):
				var point := _centreline.point_of(nodes[k])
				if not line.is_empty():
					length += point.distance_to(line[line.size() - 1])
				line.append(point)
			var shorter := length < best_length - 0.0001
			if shorter or (absf(length - best_length) <= 0.0001 and candidate[1] < best_order):
				best = line
				best_length = length
				best_runway = candidate[3]
				best_order = candidate[1]
	var fallback := false
	if best.is_empty():
		# The axis graph has no way (e.g. a stand too far from any axis): smooth the 4-way path.
		var cells := path_to_stand(stand)
		if cells.is_empty():
			return null
		fallback = true
		best_runway = runway_at(cells[0])
		for cell in cells:
			best.append(Vector2(cell) + Vector2(0.5, 0.5))
		var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
		best[best.size() - 1] = Vector2(stand.origin_cell) + Vector2(size) * 0.5
	var origin := Vector2(_grid.origin.x, _grid.origin.z)
	var route: PlaneRoute
	var pushback: Variant = _pushback_point(stand) if not fallback else null
	if pushback != null:
		# The plane drives the last stretch straight along the stand's axis, and is pushed back along
		# it: the route reaches the axis at the push-back point B on the taxiway behind the stand.
		var to_b := best.duplicate()
		to_b.remove_at(to_b.size() - 1)  # the stand's lead-in: B replaces it
		# The nodes on the stand's side of B go too (the way to the lead-in ran through the stand).
		var b_point := pushback[0] as Vector2
		var away := pushback[1] as Vector2
		while to_b.size() > 1 and (to_b[to_b.size() - 1] - b_point).dot(away) < 0.0:
			to_b.remove_at(to_b.size() - 1)
		to_b.append(pushback[0] as Vector2)
		var lines := _centreline.smooth_to_stand(to_b, Vector2(stand.origin_cell) + Vector2(size_of_stand) * 0.5, origin, _grid.cell_size)
		route = PlaneRoute.from_points(lines[0], false)
		route.set_pushback(lines[1])
	else:
		route = PlaneRoute.from_points(_centreline.smooth(best, origin, _grid.cell_size), fallback)
		route.set_pushback(PackedVector2Array())
	route.runway = best_runway
	_place_runway_rolls(route)
	route.plan_timing()
	return route


# The push-back point of `stand`: [B (cell corner coordinates), the unit direction pointing away from the gate], or
# null if the stand has no gate in front or no pavement right behind it. The plane parks nose-in
# towards its gate (like PlaneLayer._parked_pose) and is pushed back straight away from it, to
# B: the middle of the pavement just behind the stand, at most PUSHBACK_REACH_CELLS / 2 beyond the edge.
func _pushback_point(stand: Building) -> Variant:
	var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
	var rect := Rect2i(stand.origin_cell, size)
	var gate: Building = null
	for building in _buildings:
		if building.type.role != BuildingType.Role.GATE:
			continue
		for cell in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false):
			if rect.has_point(cell):
				gate = building
				break
		if gate != null:
			break
	if gate == null:
		return null
	var middle := Vector2(stand.origin_cell) + Vector2(size) * 0.5
	var gate_size := Building.rotated_size(gate.type.footprint, gate.rotation_steps)
	var offset := middle - (Vector2(gate.origin_cell) + Vector2(gate_size) * 0.5)
	var away := Vector2(signf(offset.x), 0.0) if absf(offset.x) > absf(offset.y) else Vector2(0.0, signf(offset.y))
	if away == Vector2.ZERO:
		return null
	# The paved run behind the stand's back edge, along its axis (the cell the axis runs through; an
	# axis on a cell border counts either neighbour).
	var half := (size.x if away.x != 0.0 else size.y) * 0.5
	var width := _grid.size.x
	var run := 0
	for k in PUSHBACK_REACH_CELLS:
		var point := middle + away * (half + k + 0.5)
		var cell := Vector2i(floori(point.x), floori(point.y))
		var side := Vector2i(floori(point.x - absf(away.y) * 0.5), floori(point.y - absf(away.x) * 0.5))
		if not (_grid.is_inside(cell) and _areas.has(cell.y * width + cell.x)) \
				and not (_grid.is_inside(side) and _areas.has(side.y * width + side.x)):
			break
		run += 1
	if run < 4:
		return null
	return [middle + away * (half + run * 0.5), away]


# Where planes touch down and lift off for `route`: on the runway's middle line, towards the end
# farther from the exit (so there is room to roll out), the touchdown a little way in.
func _place_runway_rolls(route: PlaneRoute) -> void:
	var runway := route.runway
	if runway == null or route.points.is_empty():
		return
	var size := Building.rotated_size(runway.type.footprint, runway.rotation_steps)
	var middle3 := _grid.block_center(runway.origin_cell, size)
	var middle := Vector2(middle3.x, middle3.z)
	var along_x := size.x >= size.y
	var axis := Vector2.RIGHT if along_x else Vector2.DOWN
	var half := (size.x if along_x else size.y) * _grid.cell_size * 0.5
	var exit := route.points[0]
	var far := -1.0 if axis.dot(exit - middle) > 0.0 else 1.0
	var inside := maxf(half - TOUCHDOWN_ZONE_M, 0.0)
	route.touchdown = middle + axis * far * inside
	route.liftoff = middle + axis * far * maxf(half - LIFTOFF_MARGIN_M, 0.0)


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
