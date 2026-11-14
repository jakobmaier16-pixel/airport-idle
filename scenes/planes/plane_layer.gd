class_name PlaneLayer
extends Node3D
## Draws the plane of every flight that is at or near its stand (design doc §8.5): taxiing in,
## parked nose-in facing the gate, and pushing back. Reads the flight schedule; never changes it.

var _planes: Dictionary[Flight, PlaneVisual] = {}


func _ready() -> void:
	# Planes are moved every frame from simulation time (already smooth), so Godot's physics
	# interpolation must stay out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	# Smooth time between simulation steps.
	var now := Airport.sim_time + Airport.sim_alpha * Airport.SIM_STEP
	var shown: Dictionary[Flight, bool] = {}
	for flight in Airport.schedule.flights:
		var pose: Variant = _pose(flight, now)
		if pose == null:
			continue
		if not _planes.has(flight):
			var plane := PlaneVisual.new()
			plane.size_factor = PlaneVisual.size_for(flight)
			plane.wide_body = flight.plane_class == TimetableSlot.PlaneClass.WIDE
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


# Where the plane of `flight` is at time `now`, or null if it isn't near the airport. The times
# are the simulation's own (FlightSchedule): the plane touches down `lead_of(route)` before the
# doors close, rolls out, taxis in along the route's speed profile, stands, pushes back, taxis out,
# waits for the runway if it has to, rolls and climbs away (design doc §7.5a).
func _pose(flight: Flight, now: float) -> Variant:
	if flight.stand == null or flight.phase == Flight.Phase.CANCELLED or flight.phase == Flight.Phase.SCHEDULED:
		return null
	var schedule := Airport.schedule
	var route := schedule.route_of(flight)
	var parked := _parked_pose(flight)
	var time_left := flight.departs_at() - now
	var arrival_left := time_left + flight.arrival_delay
	if route == null:
		return parked if arrival_left <= FlightSchedule.STAND_DWELL else null
	if time_left > 0.0:
		# 0 at the start of the approach.
		var since := FlightSchedule.lead_of(route) + FlightSchedule.APPROACH_TIME - arrival_left
		return _arriving(route, maxf(since, 0.0))
	var left := now - flight.departs_at()
	return _departing(route, left, now - flight.takeoff_at if flight.takeoff_booked else -1.0)


# `since` seconds after the approach began: approach, landing roll, taxi in, then parked.
func _arriving(route: PlaneRoute, since: float) -> Transform3D:
	var runway_dir := (route.points[0] - route.touchdown).normalized()
	var approach := FlightSchedule.APPROACH_TIME
	if since < approach:
		# Final approach: a straight glide down to the touchdown point.
		var t := since / approach
		var ground := route.touchdown - runway_dir * APPROACH_DISTANCE * (1.0 - t)
		return _flat(ground, APPROACH_HEIGHT * (1.0 - t), runway_dir)
	since -= approach
	if since < route.roll_in_time:
		var roll := TaxiProfile.landing_roll_distance(since, route.roll_in_distance)
		return _flat(route.touchdown.lerp(route.points[0], roll / maxf(route.roll_in_distance, 0.001)), 0.0, runway_dir)
	since -= route.roll_in_time
	var distance := route.profile_in.distance_at(since)
	var position := route.position_at(distance)
	# The last stretch of the route runs straight along the stand's axis, so the plane arrives with the
	# parked heading: nose towards the gate, no turn on the spot at the stand.
	return Transform3D(Basis.looking_at(_to_3d(route.heading_at(distance)), Vector3.UP), Vector3(position.x, 0.0, position.y))


# `time` seconds after push-back; `rolled` seconds since the take-off run began (-1 = not yet).
func _departing(route: PlaneRoute, time: float, rolled: float) -> Transform3D:
	var runway_dir := (route.liftoff - route.points[0]).normalized()
	if rolled >= 0.0:
		if rolled < route.roll_out_time:
			var run := TaxiProfile.takeoff_roll_distance(rolled, route.roll_out_distance)
			return _flat(route.points[0].lerp(route.liftoff, run / maxf(route.roll_out_distance, 0.001)), 0.0, runway_dir)
		# Lifted off: climbing away beyond the end of the runway.
		var t := clampf((rolled - route.roll_out_time) / FlightSchedule.CLIMB_TIME, 0.0, 1.0)
		var ahead := route.liftoff + runway_dir * CLIMB_DISTANCE * t
		return _flat(ahead, APPROACH_HEIGHT * t, runway_dir)
	if time >= route.taxi_out_time:
		# Waiting at the holding point for the runway.
		return _flat(route.points[0], 0.0, runway_dir)
	# Push-back: straight back along the stand's axis, nose still towards the gate; on the taxiway
	# the plane turns on the spot, then taxis out (PlaneRoute.nose_out).
	var distance := route.out_distance_at(time)
	var position := route.position_out(distance)
	return Transform3D(Basis.looking_at(_to_3d(route.nose_out(time, distance)), Vector3.UP), Vector3(position.x, 0.0, position.y))


func _flat(position: Vector2, height: float, direction: Vector2) -> Transform3D:
	return Transform3D(Basis.looking_at(_to_3d(direction), Vector3.UP), Vector3(position.x, height, position.y))


static func _to_3d(direction: Vector2) -> Vector3:
	return Vector3(direction.x, 0.0, direction.y)


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


## Height where the final approach starts (about 3 degrees of glide), in meters; and how far before
## the touchdown point that is (the approach speed times the approach time).
const APPROACH_HEIGHT: float = 22.0
const APPROACH_DISTANCE: float = 420.0
## How far beyond the end of the runway a plane climbs before it is gone, in meters.
const CLIMB_DISTANCE: float = 420.0
