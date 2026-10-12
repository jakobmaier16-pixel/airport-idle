extends Node
## Root of the airport simulation, registered as the autoload "Airport".
## The simulation is pure data: it runs all the time, for the whole airport, independent of
## what is on screen (see "Performance architecture" in CLAUDE.md).
## Visuals listen to its signals and never change simulation data directly.

signal building_placed(building: Building)

## Grid cell size in meters. Terminal and landside are near-realistic at this scale; airside is
## scaled down (design doc §7.1). Change it only here: the ground and all tools derive from it.
const CELL_SIZE: float = 2.0
## Map size in cells: 64 x 64 cells = 128 x 128 m (design doc §7.1).
const MAP_SIZE_CELLS: Vector2i = Vector2i(64, 64)

var grid: AirportGrid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
var buildings: Array[Building] = []


func can_place(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> bool:
	return grid.are_cells_free(Building.footprint_cells(type.footprint, origin_cell, rotation_steps))


## Places a building if its cells are free. Returns the new building, or null if the spot is taken.
## Building is free for now; costs come with the economy (design doc §7.1a).
func place_building(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> Building:
	if not can_place(type, origin_cell, rotation_steps):
		return null
	var building := Building.new(type, origin_cell, rotation_steps)
	for cell in building.get_cells():
		grid.set_content(cell, building)
	buildings.append(building)
	building_placed.emit(building)
	return building
