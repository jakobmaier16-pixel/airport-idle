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


static func footprint_cells(footprint: Vector2i, origin: Vector2i, rotation: int) -> Array[Vector2i]:
	var size := rotated_size(footprint, rotation)
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells
