extends Node
## Root of the airport simulation, registered as the autoload "Airport".
## The simulation is pure data: it runs all the time, for the whole airport, independent of
## what is on screen (see "Performance architecture" in CLAUDE.md).
## Visuals listen to its signals and never change simulation data directly.

signal building_placed(building: Building)
signal zones_changed

## Grid cell size in meters. Terminal and landside are near-realistic at this scale; airside is
## scaled down (design doc §7.1). Change it only here: the ground and all tools derive from it.
const CELL_SIZE: float = 2.0
## Map size in cells: 64 x 64 cells = 128 x 128 m (design doc §7.1).
const MAP_SIZE_CELLS: Vector2i = Vector2i(64, 64)
## Every building type in the game.
const CATALOG: BuildingCatalog = preload("res://data/buildings/catalog.tres")

var grid: AirportGrid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
var buildings: Array[Building] = []

# Cells whose zone a placed building depends on (cell -> required Zone). They can't be repainted.
var _zone_locks: Dictionary[Vector2i, int] = {}


## Why a building can't go here, as a short hint for the player, or "" if it can.
func check_placement(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> String:
	for cell in Building.footprint_cells(type.footprint, origin_cell, rotation_steps):
		if not grid.is_inside(cell):
			return "Outside the map"
		if not grid.is_empty(cell):
			return "Space is taken"
	var requirements := Building.zone_requirements(type, origin_cell, rotation_steps)
	for cell in requirements:
		if not grid.is_inside(cell) or grid.get_zone(cell) != requirements[cell]:
			return _zone_hint(type)
	return ""


func can_place(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> bool:
	return check_placement(type, origin_cell, rotation_steps).is_empty()


## Places a building if the spot is allowed. Returns the new building, or null if it isn't.
## Building is free for now; costs come with the economy (design doc §7.1a).
func place_building(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> Building:
	if not can_place(type, origin_cell, rotation_steps):
		return null
	var building := Building.new(type, origin_cell, rotation_steps)
	for cell in building.get_cells():
		grid.set_content(cell, building)
	var requirements := Building.zone_requirements(type, origin_cell, rotation_steps)
	for cell in requirements:
		_zone_locks[cell] = requirements[cell]
	buildings.append(building)
	building_placed.emit(building)
	return building


## Paints `cells` with `zone`. Cells a building depends on keep their zone.
## Returns how many cells were blocked that way, so the player can be told.
func paint_zone(cells: Array[Vector2i], zone: AirportGrid.Zone) -> int:
	var blocked := 0
	var changed := false
	for cell in cells:
		if not grid.is_inside(cell) or grid.get_zone(cell) == zone:
			continue
		if _zone_locks.has(cell) and _zone_locks[cell] != zone:
			blocked += 1
			continue
		grid.set_zone(cell, zone)
		changed = true
	if changed:
		zones_changed.emit()
	return blocked


## Removes everything: buildings and zones. Visuals must be rebuilt afterwards (reload the scene).
func reset() -> void:
	grid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
	buildings.clear()
	_zone_locks.clear()


## The whole airport as plain data, for the save game.
func save_state() -> Dictionary:
	var saved_buildings: Array[Dictionary] = []
	for building in buildings:
		saved_buildings.append({
			"type": String(building.type.id),
			"cell": [building.origin_cell.x, building.origin_cell.y],
			"rotation": building.rotation_steps,
		})
	return {
		"map_size": [grid.size.x, grid.size.y],
		"zones": Marshalls.raw_to_base64(grid.get_zone_data()),
		"buildings": saved_buildings,
	}


## Restores an airport from save_state() data. Buildings go through the normal placement rules,
## so a save from an older version (e.g. different sizes) can't create an invalid airport;
## buildings that no longer fit are skipped. Returns how many were skipped.
func load_state(data: Dictionary) -> int:
	reset()
	# JSON stores every number as a float, hence the explicit conversion.
	var saved_size: Array = data.get("map_size", [])
	if saved_size.size() == 2 and Vector2i(int(saved_size[0]), int(saved_size[1])) == grid.size:
		grid.set_zone_data(Marshalls.base64_to_raw(data.get("zones", "")))
	var skipped := 0
	for entry: Dictionary in data.get("buildings", []):
		var type := CATALOG.find(StringName(entry.get("type", "")))
		var cell: Array = entry.get("cell", [0, 0])
		var origin := Vector2i(int(cell[0]), int(cell[1]))
		if type == null or place_building(type, origin, int(entry.get("rotation", 0))) == null:
			skipped += 1
	zones_changed.emit()
	return skipped


func _zone_hint(type: BuildingType) -> String:
	match type.zone_rule:
		BuildingType.ZoneRule.AIRSIDE:
			return "Must be built on airside"
		BuildingType.ZoneRule.BORDER:
			return "Front must face landside, back must face airside"
		_:
			return "Must be built on landside"
