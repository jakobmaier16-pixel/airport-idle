class_name Station
extends RefCounted
## A building passengers visit (check-in, security, gate) with its queue. Pure data.

var building: Building
## Walkable cells along the side where passengers arrive (front), in row order.
var entry_cells: Array[Vector2i] = []
## Walkable cells along the side where passengers leave (security: the airside back).
var exit_cells: Array[Vector2i] = []
## Direction from the building out of its front side, on the ground (world).
var outward: Vector3 = Vector3.ZERO

var queue: Array[Passenger] = []
## One entry per counter / lane; null = free.
var serving: Array[Passenger] = []
var service_left: PackedFloat32Array = PackedFloat32Array()
## Gates only: passengers waiting inside, and time since the last boarding.
var waiting: Array[Passenger] = []
var boarding_timer: float = 0.0


func _init(placed: Building) -> void:
	building = placed
	serving.resize(placed.type.service_slots)
	service_left.resize(placed.type.service_slots)
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var front := directions[placed.rotation_steps]
	outward = Vector3(front.x, 0.0, front.y)


func role() -> BuildingType.Role:
	return building.type.role


## How many passengers are queuing or being served, for passengers choosing between stations.
func busyness() -> int:
	return queue.size() + serving.size() - serving.count(null)
