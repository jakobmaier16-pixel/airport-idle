class_name Building
extends RefCounted
## One placed building in the simulation: pure data, no visuals.

var type: BuildingType
## The footprint's corner cell with the smallest x and y.
var origin_cell: Vector2i
## Clockwise 90° steps as seen from above (0..3).
var rotation_steps: int


func _init(building_type: BuildingType, origin: Vector2i, rotation: int) -> void:
	type = building_type
	origin_cell = origin
	rotation_steps = posmod(rotation, 4)


## The grid cells this building covers.
func get_cells() -> Array[Vector2i]:
	return footprint_cells(type.footprint, origin_cell, rotation_steps)


## Footprint size after rotation: a quarter turn swaps width and depth.
static func rotated_size(footprint: Vector2i, rotation: int) -> Vector2i:
	if posmod(rotation, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint


## The zone each affected cell must have for this building to be allowed there (cell -> Zone).
static func zone_requirements(type: BuildingType, origin: Vector2i, rotation: int) -> Dictionary[Vector2i, int]:
	var result: Dictionary[Vector2i, int] = {}
	match type.zone_rule:
		BuildingType.ZoneRule.LANDSIDE:
			for cell in footprint_cells(type.footprint, origin, rotation):
				result[cell] = AirportGrid.Zone.LANDSIDE
		BuildingType.ZoneRule.AIRSIDE:
			for cell in footprint_cells(type.footprint, origin, rotation):
				result[cell] = AirportGrid.Zone.AIRSIDE
		BuildingType.ZoneRule.BORDER:
			for cell in outside_row(type.footprint, origin, rotation, true):
				result[cell] = AirportGrid.Zone.LANDSIDE
			for cell in outside_row(type.footprint, origin, rotation, false):
				result[cell] = AirportGrid.Zone.AIRSIDE
	return result


## The row of cells just outside the footprint, along its front side (or back side).
static func outside_row(footprint: Vector2i, origin: Vector2i, rotation: int, front: bool) -> Array[Vector2i]:
	var size := rotated_size(footprint, rotation)
	# Direction the front faces for each clockwise step: up, right, down, left (on screen).
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var direction := directions[posmod(rotation, 4)]
	if not front:
		direction = -direction
	var cells: Array[Vector2i] = []
	if direction.y != 0:
		var row_y := origin.y - 1 if direction.y < 0 else origin.y + size.y
		for x in size.x:
			cells.append(Vector2i(origin.x + x, row_y))
	else:
		var column_x := origin.x - 1 if direction.x < 0 else origin.x + size.x
		for y in size.y:
			cells.append(Vector2i(column_x, origin.y + y))
	return cells


static func footprint_cells(footprint: Vector2i, origin: Vector2i, rotation: int) -> Array[Vector2i]:
	var size := rotated_size(footprint, rotation)
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells
