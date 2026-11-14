class_name Building
extends RefCounted
## One placed building in the simulation: pure data, no visuals.

## Permanent ID, stable across save and load (tech_architecture.md §13); staff in saves point to it.
## 0 = not assigned yet (the brain assigns it when the building is placed).
var id: int = 0
var type: BuildingType
## The footprint's corner cell with the smallest x and y.
var origin_cell: Vector2i
## Clockwise 90° steps as seen from above (0..3).
var rotation_steps: int
## Upgrade level, starting at 1 (design doc §7.8).
var level: int = 1
## Seconds until a running big upgrade is finished; 0 = no upgrade running.
var upgrade_seconds_left: float = 0.0
## Security with a fast track lane (design doc §11.8).
var fast_track: bool = false


func _init(building_type: BuildingType, origin: Vector2i, rotation: int) -> void:
	type = building_type
	origin_cell = origin
	rotation_steps = posmod(rotation, 4)


## The upgrade that would take this building to the next level, or null at the top level.
## While an upgrade is running, this is the one being built.
func next_upgrade() -> StationUpgrade:
	if level - 1 < type.upgrades.size():
		return type.upgrades[level - 1]
	return null


func is_upgrading() -> bool:
	return upgrade_seconds_left > 0.0


## Counters / lanes at the current level.
func service_slots() -> int:
	var slots := type.service_slots
	for upgrade in _done_upgrades():
		slots += upgrade.extra_slots
	return slots


## Average seconds per passenger at the current level.
func service_time() -> float:
	var time := type.service_time
	for upgrade in _done_upgrades():
		time *= upgrade.service_time_factor
	return time


func running_cost_per_minute() -> float:
	var cost := type.running_cost_per_minute
	for upgrade in _done_upgrades():
		cost += upgrade.extra_running_cost_per_minute
	return cost


func _done_upgrades() -> Array[StationUpgrade]:
	return type.upgrades.slice(0, level - 1)


## The grid cells this building covers.
func get_cells() -> Array[Vector2i]:
	return footprint_cells(type.footprint, origin_cell, rotation_steps)


## The ground surface this building lays under itself (AirportGrid.SURFACE_*), 0 for none. The ground
## shader paints it (concrete under stands, asphalt under runways); the building's own box is not drawn.
static func ground_surface_of(type: BuildingType) -> int:
	match type.role:
		BuildingType.Role.AIRCRAFT_STAND:
			return AirportGrid.SURFACE_CONCRETE
		BuildingType.Role.RUNWAY:
			return AirportGrid.SURFACE_RUNWAY
	return 0


## The footprint as a cell rectangle (after rotation).
func get_rect() -> Rect2i:
	return Rect2i(origin_cell, rotated_size(type.footprint, rotation_steps))


## Footprint size after rotation: a quarter turn swaps width and depth.
static func rotated_size(footprint: Vector2i, rotation: int) -> Vector2i:
	if posmod(rotation, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint


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
