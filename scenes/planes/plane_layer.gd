class_name PlaneLayer
extends Node3D
## Draws the plane of every flight that is at or near its stand (design doc §8.5): taxiing in,
## parked nose-in facing the gate, and pushing back. Reads the flight schedule; never changes it.

## How far from the stand a plane appears / disappears while taxiing, in meters.
const TAXI_DISTANCE: float = 30.0

var _planes: Dictionary[Flight, PlaneVisual] = {}


func _ready() -> void:
	# Planes are moved every frame from simulation time (already smooth), so Godot's physics
	# interpolation must stay out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


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
			add_child(plane)
			_planes[flight] = plane
		_planes[flight].transform = pose
		shown[flight] = true
	for flight in _planes.keys():
		if not shown.has(flight):
			_planes[flight].queue_free()
			_planes.erase(flight)


## How many planes are currently drawn (used by tests).
func plane_count() -> int:
	return _planes.size()


# Where the plane of `flight` is at time `now`, or null if it isn't near the stand.
func _pose(flight: Flight, now: float) -> Variant:
	if flight.stand == null or flight.phase == Flight.Phase.CANCELLED:
		return null
	var time_left := flight.departs_at() - now
	var taxi := FlightSchedule.TAXI_TIME
	if time_left > FlightSchedule.PLANE_ARRIVES or time_left < -taxi:
		return null

	var grid := Airport.grid
	var stand := flight.stand
	var gate := flight.gate
	var stand_center := grid.block_center(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
	var gate_center := grid.block_center(gate.origin_cell, Building.rotated_size(gate.type.footprint, gate.rotation_steps))
	# Park straight along the stand's axis (like a real stand centerline), facing the gate's side.
	var offset := stand_center - gate_center
	var away := Vector3(signf(offset.x), 0.0, 0.0) if absf(offset.x) > absf(offset.z) else Vector3(0.0, 0.0, signf(offset.z))

	# 0 = parked at the stand, 1 = TAXI_DISTANCE away from it.
	var out := 0.0
	if time_left > FlightSchedule.PLANE_ARRIVES - taxi:
		out = (time_left - (FlightSchedule.PLANE_ARRIVES - taxi)) / taxi
	elif time_left < 0.0:
		out = -time_left / taxi
	out = smoothstep(0.0, 1.0, out)

	# Parked nose-in: the nose (-Z of the model) points at the gate.
	var basis := Basis.looking_at(-away, Vector3.UP)
	return Transform3D(basis, stand_center + away * out * TAXI_DISTANCE)
