class_name ZoneMap
extends RefCounted
## Zones worked out from the layout (tech_architecture.md §4, game_design §8.1): the brain walks
## from the entrance along the walkways. Everything reached without passing security is landside,
## everything behind security is airside. Pure data, no nodes.
## `recompute` also writes the result into the grid, which everything else reads (AirportGrid.get_zone).
## Border buildings are security only: transfer security joins two airside walkways but is no border.

## The grid holds the result (AirportGrid.get_zone). The work follows the used cells (walkways, taxiways
## and building footprints), never the map size: nothing here scans the whole map.
var _grid: AirportGrid = null
## True once security's back reaches a walkway: the airside exists.
var airside_reached: bool = false
## Debug counter: cells visited by the last `recompute` (flood fill, taxiway cells, footprint
## cells). Tests use it to check that the cost does not grow with the map.
var last_work_cells: int = 0

const _STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# What the last recompute wrote into the grid (airside only: landside is the default), so the next
# one can undo exactly that without scanning the map.
var _written_cells: Array[Vector2i] = []
var _written_rects: Array[Rect2i] = []
# Walkway cells that either flood reached (used to find the side of ANY buildings).
var _walkable_seen: Dictionary[Vector2i, bool] = {}


func zone_at(cell: Vector2i) -> AirportGrid.Zone:
	if _grid == null:
		return AirportGrid.Zone.LANDSIDE
	return _grid.get_zone(cell)


func recompute(grid: AirportGrid, buildings: Array[Building]) -> void:
	# Undo the last result (on the same grid; a new grid starts all landside).
	if _grid == grid:
		for cell: Vector2i in _written_cells:
			grid.set_zone(cell, AirportGrid.Zone.LANDSIDE)
		for rect: Rect2i in _written_rects:
			grid.set_zone_rect(rect, AirportGrid.Zone.LANDSIDE)
	_grid = grid
	_written_cells.clear()
	_written_rects.clear()
	airside_reached = false
	_walkable_seen.clear()

	# Landside: from both outside rows of every entrance, over walkway cells. Buildings are never
	# walked through, so security (and every other building) stops the walk by itself.
	var landside_seeds: Array[Vector2i] = []
	var airside_seeds: Array[Vector2i] = []
	var transfers: Array[Building] = []
	for building: Building in buildings:
		match building.type.role:
			BuildingType.Role.ENTRANCE:
				landside_seeds.append_array(_rows(building, true))
				landside_seeds.append_array(_rows(building, false))
			BuildingType.Role.SECURITY:
				# Security is the border: its back is the only way into the airside.
				airside_seeds.append_array(Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false))
			BuildingType.Role.TRANSFER_SECURITY:
				transfers.append(building)
	var landside := _flood(grid, landside_seeds, {})
	# Transfer security joins two airside walkways: once one side is reached, so is the other.
	var airside := _flood(grid, airside_seeds, landside)
	var changed: bool = not transfers.is_empty()
	while changed:
		changed = false
		for building: Building in transfers:
			var front: Array[Vector2i] = Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, true)
			var back: Array[Vector2i] = Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false)
			var reached: bool = false
			for cell: Vector2i in front + back:
				reached = reached or airside.has(cell)
			if reached:
				var before: int = airside.size()
				airside = _flood(grid, front + back, landside, airside)
				changed = changed or airside.size() != before
	airside_reached = not airside.is_empty()
	for cell: Vector2i in airside:
		grid.set_zone(cell, AirportGrid.Zone.AIRSIDE)
		_written_cells.append(cell)
	last_work_cells = landside.size() + airside.size()

	# Cells without a walkway: planes' ground and airside buildings are airside by rule. Only the
	# flagged cells are visited (taxiways), and building footprints are filled as rectangles.
	var taxiways := grid.get_cells_with_flag(AirportGrid.TAXIWAY_BIT)
	for cell: Vector2i in taxiways:
		grid.set_zone(cell, AirportGrid.Zone.AIRSIDE)
		_written_cells.append(cell)
	last_work_cells += taxiways.size()
	for building: Building in buildings:
		var zone: int = _building_zone(building)
		if zone >= 0:
			var rect := Rect2i(building.origin_cell, Building.rotated_size(building.type.footprint, building.rotation_steps))
			grid.set_zone_rect(rect, zone as AirportGrid.Zone)
			_written_rects.append(rect)
			last_work_cells += rect.get_area()


# The zone of a building's footprint, or -1 for border buildings (they have two sides).
func _building_zone(building: Building) -> int:
	match building.type.zone_rule:
		BuildingType.ZoneRule.LANDSIDE:
			return AirportGrid.Zone.LANDSIDE
		BuildingType.ZoneRule.AIRSIDE:
			return AirportGrid.Zone.AIRSIDE
		BuildingType.ZoneRule.ANY:
			# Like a cafe: it stands on the side of the walkway it serves.
			for front: bool in [true, false]:
				for cell: Vector2i in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, front):
					if _walkable_seen.has(cell):
						return zone_at(cell)
	return -1


func _rows(building: Building, front: bool) -> Array[Vector2i]:
	return Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, front)


# Walks over walkable cells (4 neighbours) from `seeds` and returns every cell reached. Cells in
# `blocked` are not entered; `into` continues an earlier walk.
func _flood(grid: AirportGrid, seeds: Array[Vector2i], blocked: Dictionary, into: Dictionary = {}) -> Dictionary:
	var reached: Dictionary = into
	var queue: Array[Vector2i] = []
	for cell: Vector2i in seeds:
		if grid.is_walkable(cell) and not blocked.has(cell) and not reached.has(cell):
			reached[cell] = true
			_walkable_seen[cell] = true
			queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in _STEPS:
			var next := cell + step
			if grid.is_walkable(next) and not blocked.has(next) and not reached.has(next):
				reached[next] = true
				_walkable_seen[next] = true
				queue.append(next)
	return reached
