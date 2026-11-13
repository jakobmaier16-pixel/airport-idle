class_name ZoneMap
extends RefCounted
## Zones worked out from the layout (tech_architecture.md §4, game_design §8.1): the brain walks
## from the entrance along the walkways. Everything reached without passing security is landside,
## everything behind security is airside. Pure data, no nodes.
## Step 4a: computed next to the painted zones (AirportGrid) and only compared; nothing reads it
## yet. Step 4b switches the game to it and removes painting.

## One byte per cell (row by row), an AirportGrid.Zone value. Cells nobody walks to stay landside.
var computed: PackedByteArray = PackedByteArray()
var _size: Vector2i = Vector2i.ZERO

const _STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func zone_at(cell: Vector2i) -> AirportGrid.Zone:
	if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
		return AirportGrid.Zone.LANDSIDE
	return computed[cell.y * _size.x + cell.x] as AirportGrid.Zone


func recompute(grid: AirportGrid, buildings: Array[Building]) -> void:
	_size = grid.size
	computed.resize(_size.x * _size.y)
	computed.fill(AirportGrid.Zone.LANDSIDE)
	_walkable_seen.clear()

	# Landside: from both outside rows of every entrance, over walkway cells. Buildings are never
	# walked through, so security (and every other building) stops the walk by itself.
	var landside_seeds: Array[Vector2i] = []
	var airside_seeds: Array[Vector2i] = []
	var transfers: Array[Building] = []
	for building in buildings:
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
	var changed := not transfers.is_empty()
	while changed:
		changed = false
		for building in transfers:
			var front := Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, true)
			var back := Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false)
			var reached := false
			for cell in front + back:
				reached = reached or airside.has(cell)
			if reached:
				var before := airside.size()
				airside = _flood(grid, front + back, landside, airside)
				changed = changed or airside.size() != before
	for cell in airside:
		computed[cell.y * _size.x + cell.x] = AirportGrid.Zone.AIRSIDE

	# Cells without a walkway: planes' ground and airside buildings are airside by rule.
	for y in _size.y:
		for x in _size.x:
			if grid.is_taxiway(Vector2i(x, y)):
				computed[y * _size.x + x] = AirportGrid.Zone.AIRSIDE
	for building in buildings:
		var zone := _building_zone(building)
		if zone >= 0:
			for cell in Building.footprint_cells(building.type.footprint, building.origin_cell, building.rotation_steps):
				if grid.is_inside(cell):
					computed[cell.y * _size.x + cell.x] = zone


## Cells where the painted zones (`grid`) and the computed ones disagree, as readable lines.
## Only cells that matter are compared: walkway, taxiway, and the footprints of buildings whose
## zone is fixed by their rule or by the walkway beside them (security and baggage claim stand on
## the border, so they have no single zone). Empty ground has no computed zone, so it is skipped.
## Temporary 4a aid: removed with the painted zones in 4b.
func differences(grid: AirportGrid, buildings: Array[Building]) -> Array[String]:
	var lines: Array[String] = []
	for y in _size.y:
		for x in _size.x:
			var cell := Vector2i(x, y)
			if (grid.is_walkway(cell) or grid.is_taxiway(cell)) and grid.is_empty(cell) and grid.get_zone(cell) != zone_at(cell):
				lines.append("%s %s: painted %s, computed %s" % [
					"taxiway" if grid.is_taxiway(cell) else "walkway", cell,
					AirportGrid.Zone.keys()[grid.get_zone(cell)], AirportGrid.Zone.keys()[zone_at(cell)]])
	for building in buildings:
		if building.type.role == BuildingType.Role.RUNWAY:
			continue
		var zone := _building_zone(building)
		if zone < 0:
			continue
		var painted := grid.get_zone(building.origin_cell)
		if painted != zone:
			lines.append("%s at %s: painted %s, computed %s" % [
				building.type.display_name, building.origin_cell,
				AirportGrid.Zone.keys()[painted], AirportGrid.Zone.keys()[zone]])
	return lines


# The zone of a building's footprint, or -1 for border buildings (they have two sides).
func _building_zone(building: Building) -> int:
	match building.type.zone_rule:
		BuildingType.ZoneRule.LANDSIDE:
			return AirportGrid.Zone.LANDSIDE
		BuildingType.ZoneRule.AIRSIDE:
			return AirportGrid.Zone.AIRSIDE
		BuildingType.ZoneRule.ANY:
			# Like a café: it stands on the side of the walkway it serves.
			for front in [true, false]:
				for cell in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, front):
					if _is_marked_side(cell):
						return zone_at(cell)
	return -1


func _is_marked_side(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y and _walkable_seen.has(cell)


# Walkway cells that either flood reached (used to find the side of ANY buildings).
var _walkable_seen: Dictionary[Vector2i, bool] = {}


func _rows(building: Building, front: bool) -> Array[Vector2i]:
	return Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, front)


# Walks over walkable cells (4 neighbours) from `seeds` and returns every cell reached. Cells in
# `blocked` are not entered; `into` continues an earlier walk.
func _flood(grid: AirportGrid, seeds: Array[Vector2i], blocked: Dictionary, into: Dictionary = {}) -> Dictionary:
	var reached: Dictionary = into
	var queue: Array[Vector2i] = []
	for cell in seeds:
		if grid.is_walkable(cell) and not blocked.has(cell) and not reached.has(cell):
			reached[cell] = true
			queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in _STEPS:
			var next := cell + step
			if grid.is_walkable(next) and not blocked.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	for cell in reached:
		_walkable_seen[cell] = true
	return reached
