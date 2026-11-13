class_name AreaMap
extends RefCounted
## Named areas worked out from the layout (tech_architecture.md §4, game_design §8.2): connected
## walkway cells of one zone form one area. Derived data, never saved: `recompute` runs after
## ZoneMap and again after a load. Pure data, no nodes.
##
## Names: landside with check-in -> "Check-in Hall", otherwise touching security -> "Security";
## airside with gates or stands -> "Gates", otherwise touching security -> "Security"; anything
## else "Landside N" / "Airside N" (N counts those unnamed areas). Equal names get " 2", " 3".
## Order is always by the lowest cell index, so names only change when the layout does.

const _STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## One entry per area: {"name": String, "zone": AirportGrid.Zone, "cells": Array[Vector2i]}.
var _areas: Array = []
## Area index per walkway cell; cells outside every area have no entry (sparse: the cost follows the
## walkway cells, never the map size).
var _area_of: Dictionary[Vector2i, int] = {}
var _size: Vector2i = Vector2i.ZERO
## Debug counter: walkway cells looked at by the last `recompute`. Tests use it to check that the
## cost does not grow with the map.
var last_work_cells: int = 0


func recompute(grid: AirportGrid, buildings: Array[Building]) -> void:
	_size = grid.size
	_areas.clear()
	_area_of.clear()
	# Only walkway cells can start an area. Sorting their cell indices (row by row) finds the areas
	# in order of their lowest cell index.
	var indices := PackedInt64Array()
	for cell: Vector2i in grid.get_cells_with_flag(AirportGrid.WALKWAY_BIT):
		indices.append(cell.y * _size.x + cell.x)
	indices.sort()
	last_work_cells = indices.size()
	for index in indices:
		var start := Vector2i(index % _size.x, index / _size.x)
		if not _area_of.has(start) and grid.is_walkable(start):
			_flood(grid, start)
	var touching: Array[Dictionary] = []
	for area: Dictionary in _areas:
		touching.append({})
	for building: Building in buildings:
		var role := building.type.role
		if role in [BuildingType.Role.CHECK_IN, BuildingType.Role.SECURITY, BuildingType.Role.GATE, BuildingType.Role.AIRCRAFT_STAND]:
			for front: bool in [true, false]:
				for cell in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, front):
					var index := _index_at(cell)
					if index >= 0:
						touching[index][role] = true
	var unnamed: Dictionary[int, int] = {}
	var used: Dictionary[String, int] = {}
	for index in _areas.size():
		var area: Dictionary = _areas[index]
		var landside: bool = area["zone"] == AirportGrid.Zone.LANDSIDE
		var roles: Dictionary = touching[index]
		var base: String
		if landside and roles.has(BuildingType.Role.CHECK_IN):
			base = "Check-in Hall"
		elif not landside and (roles.has(BuildingType.Role.GATE) or roles.has(BuildingType.Role.AIRCRAFT_STAND)):
			base = "Gates"
		elif roles.has(BuildingType.Role.SECURITY):
			base = "Security"
		else:
			var prefix := "Landside" if landside else "Airside"
			unnamed[area["zone"]] = unnamed.get(area["zone"], 0) + 1
			base = "%s %d" % [prefix, unnamed[area["zone"]]]
		used[base] = used.get(base, 0) + 1
		area["name"] = base if used[base] == 1 else "%s %d" % [base, used[base]]


## The name of the area a walkway cell belongs to, "" for cells outside every area.
func area_name(cell: Vector2i) -> String:
	var index := _index_at(cell)
	return "" if index < 0 else _areas[index]["name"]


## Every area: {"name", "zone", "cells"}, ordered by lowest cell index.
func areas() -> Array:
	return _areas


func _index_at(cell: Vector2i) -> int:
	return _area_of.get(cell, -1)


func _flood(grid: AirportGrid, start: Vector2i) -> void:
	var index := _areas.size()
	var zone := grid.get_zone(start)
	var cells: Array[Vector2i] = [start]
	_area_of[start] = index
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in _STEPS:
			var next := cell + step
			if grid.is_walkable(next) and not _area_of.has(next) and grid.get_zone(next) == zone:
				_area_of[next] = index
				cells.append(next)
				queue.append(next)
	_areas.append({"name": "", "zone": zone, "cells": cells})
