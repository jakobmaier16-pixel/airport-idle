class_name PlaneLayer
extends Node3D
## Draws the plane of every flight that is at or near its stand (design doc §8.5): taxiing in,
## parked nose-in facing the gate, and pushing back. Reads the flight schedule; never changes it.

var _planes: Dictionary[Flight, PlaneVisual] = {}


func _ready() -> void:
	# Planes are moved every frame from simulation time (already smooth), so Godot's physics
	# interpolation must stay out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Airport.layout_changed.connect(_forget_routes)


func _process(_delta: float) -> void:
	var flow := Airport.passenger_flow
	# Smooth time between simulation steps.
	var now := flow.time + Airport.sim_alpha * Airport.SIM_STEP
	var shown: Dictionary[Flight, bool] = {}
	for flight in flow.schedule.flights:
		var pose: Variant = _pose(flight, now)
		if pose == null:
			continue
		if not _planes.has(flight):
			var plane := PlaneVisual.new()
			if flight.airline != null:
				plane.tail_color = flight.airline.type.color
			if flight.wide_body:
				plane.size_factor = PlaneVisual.WIDE_BODY_SIZE
			plane.cargo = flight.cargo
			add_child(plane)
			_planes[flight] = plane
		_planes[flight].transform = pose
		shown[flight] = true
	for flight in _planes.keys():
		if not shown.has(flight):
			_planes[flight].queue_free()
			_planes.erase(flight)


func has_plane(flight: Flight) -> bool:
	return _planes.has(flight)


func plane_of(flight: Flight) -> PlaneVisual:
	return _planes.get(flight)


## How many planes are currently drawn (used by tests).
func plane_count() -> int:
	return _planes.size()


# Where the plane of `flight` is at time `now`, or null if it isn't near the airport.
# Arriving (the ARRIVING phase): final approach and touchdown, rollout along the runway, then the
# taxiways to the stand (design doc §7.5a). Departing: pushback, taxi back to the runway, take-off
# roll and climb. Parked: nose-in, facing the gate.
func _pose(flight: Flight, now: float) -> Variant:
	if flight.stand == null or flight.phase == Flight.Phase.CANCELLED:
		return null
	var time_left := flight.departs_at() - now
	var taxi := FlightSchedule.TAXI_TIME
	if time_left > FlightSchedule.PLANE_ARRIVES or time_left < -taxi:
		return null
	var parked := _parked_pose(flight)
	var route := _route_for(flight.stand)
	if route.is_empty():
		return parked
	# A plane that landed a little late (turnaround buffer) runs its arrival late.
	var arrival_left := time_left + flight.arrival_delay
	if arrival_left > FlightSchedule.PLANE_ARRIVES:
		return null
	if arrival_left > FlightSchedule.PLANE_ARRIVES - taxi:
		# 0 at the start of the approach, 1 parked.
		var progress := 1.0 - (arrival_left - (FlightSchedule.PLANE_ARRIVES - taxi)) / taxi
		return _along(route, progress, parked, true)
	if time_left < 0.0:
		return _along(route, -time_left / taxi, parked, false)
	return parked


func _forget_routes() -> void:
	_routes.clear()
	_runway_lengths.clear()


func _parked_pose(flight: Flight) -> Transform3D:
	var grid := Airport.grid
	var stand := flight.stand
	var gate := flight.gate
	var stand_center := grid.block_center(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
	var gate_center := grid.block_center(gate.origin_cell, Building.rotated_size(gate.type.footprint, gate.rotation_steps))
	# Park straight along the stand's axis (like a real stand centerline), facing the gate's side.
	var offset := stand_center - gate_center
	var away := Vector3(signf(offset.x), 0.0, 0.0) if absf(offset.x) > absf(offset.z) else Vector3(0.0, 0.0, signf(offset.z))
	# Nose-in: the nose (-Z of the model) points at the gate.
	return Transform3D(Basis.looking_at(-away, Vector3.UP), stand_center)


# Share of the arrival (or departure) time spent in the air: approach and touchdown, or take-off.
const AIR_SHARE: float = 0.3
## Height where the final approach starts and where a departing plane disappears, in meters.
const APPROACH_HEIGHT: float = 22.0
## How far before the runway threshold the approach starts, in meters.
const APPROACH_DISTANCE: float = 60.0
## Looking this far ahead along the route gives the heading (smooth turns).
const LOOK_AHEAD: float = 4.0
## Within this distance of the stand's middle the plane turns to face the gate.
const PARK_TURN: float = 6.0

# Ground routes from the runway to each stand (world points), rebuilt after layout changes, and
# the usable length of each route's runway.
var _routes: Dictionary[Building, PackedVector3Array] = {}
var _runway_lengths: Dictionary[PackedVector3Array, float] = {}


# `progress` 0..1 along an arrival (approach, rollout, taxi in) or a departure (taxi out, take-off
# roll, climb).
func _along(route: PackedVector3Array, progress: float, parked: Transform3D, arriving: bool) -> Transform3D:
	progress = clampf(progress, 0.0, 1.0)
	var runway_dir := (route[1] - route[0]).normalized()
	var air_from := route[0] - runway_dir * APPROACH_DISTANCE + Vector3.UP * APPROACH_HEIGHT
	if arriving and progress < AIR_SHARE:
		# Final approach down to the threshold (route[0]).
		var t := progress / AIR_SHARE
		return Transform3D(Basis.looking_at(runway_dir, Vector3.UP), air_from.lerp(route[0], t))
	if not arriving and progress > 1.0 - AIR_SHARE:
		# Take-off: turned round at the threshold, rolling down the whole runway, lifting off
		# halfway and climbing away beyond the far end.
		var t := (progress - (1.0 - AIR_SHARE)) / AIR_SHARE
		var roll := _runway_lengths.get(route, 80.0) as float
		var position := route[0] + runway_dir * roll * 1.4 * t * t
		position.y = maxf(t - 0.5, 0.0) * 2.0 * APPROACH_HEIGHT
		return Transform3D(Basis.looking_at(runway_dir, Vector3.UP), position)
	# On the ground: share of the ground part.
	var ground := progress / (1.0 - AIR_SHARE) if arriving else progress / (1.0 - AIR_SHARE)
	var length := _length(route)
	var distance := ground * length if arriving else (1.0 - ground) * length
	var position := _point_at(route, distance)
	var heading := _point_at(route, distance + LOOK_AHEAD) - position
	if not arriving:
		heading = _point_at(route, distance - LOOK_AHEAD) - position
	if heading.length() < 0.01:
		heading = -parked.basis.z
	var basis := Basis.looking_at(heading.normalized(), Vector3.UP)
	var to_stand := length - distance
	if to_stand < PARK_TURN:
		# Turn into the parked heading at the end of the route (nose-in towards the gate). Leaving,
		# this is the pushback: backwards out of the stand.
		basis = parked.basis.slerp(basis, to_stand / PARK_TURN)
	return Transform3D(basis.orthonormalized(), position)


# The ground route for planes to `stand`: from the far end of the runway (where they touch down,
# and where they take off going the other way) along the runway to the taxiway, then to the stand.
func _route_for(stand: Building) -> PackedVector3Array:
	if _routes.has(stand):
		return _routes[stand]
	var route := PackedVector3Array()
	var cells := Airport.plane_network.path_to_stand(stand)
	var runway := Airport.plane_network.runway_at(cells[0]) if not cells.is_empty() else null
	if runway != null:
		var grid := Airport.grid
		var size := Building.rotated_size(runway.type.footprint, runway.rotation_steps)
		var center := grid.block_center(runway.origin_cell, size)
		var along_x := size.x >= size.y
		var half := (size.x if along_x else size.y) * grid.cell_size * 0.5 - grid.cell_size * 2.0
		var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var exit := grid.cell_to_world(cells[0])
		var exit_on_axis := center + axis * axis.dot(exit - center)
		# Touch down at the end farther from the exit, so there is room to roll out.
		var side := -1.0 if axis.dot(exit - center) > 0.0 else 1.0
		route.append(center + axis * side * half)
		route.append(exit_on_axis)
		for cell in cells.slice(1):
			route.append(grid.cell_to_world(cell))
		var stand_size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
		route.append(grid.block_center(stand.origin_cell, stand_size))
		_runway_lengths[route] = half * 2.0
	_routes[stand] = route
	return route


static func _length(route: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i].distance_to(route[i - 1])
	return total


static func _point_at(route: PackedVector3Array, distance: float) -> Vector3:
	if distance <= 0.0:
		return route[0]
	for i in range(1, route.size()):
		var segment := route[i].distance_to(route[i - 1])
		if distance <= segment:
			return route[i - 1].lerp(route[i], distance / segment if segment > 0.0 else 1.0)
		distance -= segment
	return route[route.size() - 1]
