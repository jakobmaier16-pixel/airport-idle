class_name PlaneRoute
extends RefCounted
## A ground route for one stand as a smooth polyline in metres (world x / z), from the runway exit
## to the stand's lead-in point (taxi in; taxi out is the same line driven backwards). Planes ask
## it for a position and heading by distance driven: a binary search over the cumulative lengths,
## no allocation per call (design doc §7.5a, step 7b).

## Push-back: slow and straight (about 3 m/s, accelerating at 1 m/s^2), then a turn on the spot at
## the push-back point at 20 degrees a second.
const PUSHBACK_SPEED: float = 3.0
const PUSHBACK_ACCEL: float = 1.0
const TURN_RATE: float = 0.349066
## Without a push-back point (no gate in front, tests): the plane is pushed back this far.
const PUSHBACK_FALLBACK_M: float = 15.0

## Points in metres (x / z on the ground), runway exit first.
var points: PackedVector2Array = PackedVector2Array()
## Distance along the line at each point; the first is 0.
var cumulative: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
## True if the centreline graph had no way and the 4-way cell path was smoothed instead.
var from_fallback: bool = false

## The runway this route starts on (the exit is `points[0]`), and where planes touch down on it
## and lift off from it, in metres. Landing and take-off use the same line, in opposite directions.
var runway: Building = null
var touchdown: Vector2 = Vector2.ZERO
var liftoff: Vector2 = Vector2.ZERO
## Metres of the landing roll (touchdown to the exit) and of the take-off run (entry to lift-off).
var roll_in_distance: float = 0.0
var roll_out_distance: float = 0.0
## Speed profile of the taxi in (exit to stand).
var profile_in: TaxiProfile = TaxiProfile.new()
## The way out, stand first: straight back from the stand to the push-back point (a vertex of the
## line, on the taxiway behind the stand), then along the taxiway to the runway entry. Same as the way
## in driven backwards, except that the corner at the push-back point is sharp (the plane turns there).
var out_points: PackedVector2Array = PackedVector2Array()
var out_cumulative: PackedFloat32Array = PackedFloat32Array()
var out_length: float = 0.0
## Metres from the stand pushed back before the plane turns onto the taxiway (the first leg of the way out).
var pushback_length: float = 0.0
## Seconds of the push-back, of the turn on the spot at its end, and of the taxi after it.
var pushback_time: float = 0.0
var turn_time: float = 0.0
var _profile_rest: TaxiProfile = TaxiProfile.new()
## Seconds, all from the profiles: the planned timing of every flight at this stand.
var roll_in_time: float = 0.0
var taxi_in_time: float = 0.0
var taxi_out_time: float = 0.0
var roll_out_time: float = 0.0


static func from_points(line: PackedVector2Array, fallback: bool = false) -> PlaneRoute:
	var route := PlaneRoute.new()
	route.points = line
	route.from_fallback = fallback
	route.cumulative.resize(line.size())
	var total := 0.0
	for i in line.size():
		if i > 0:
			total += line[i].distance_to(line[i - 1])
		route.cumulative[i] = total
	route.length = total
	return route


## Sets the way out. `to_pushback` is the line from the runway exit to the push-back point in metres
## (its last corner sharp); empty if the stand has none: then the plane is pushed back along the
## first PUSHBACK_FALLBACK_M of the line it came in on.
func set_pushback(to_pushback: PackedVector2Array) -> void:
	var line := PackedVector2Array()
	if points.is_empty():
		return
	line.append(points[points.size() - 1])
	if to_pushback.size() >= 2:
		var backwards := to_pushback.duplicate()
		backwards.reverse()
		line.append_array(backwards)
	else:
		var backwards := points.duplicate()
		backwards.reverse()
		line = backwards
	out_points = line
	out_cumulative.resize(line.size())
	var total := 0.0
	for i in line.size():
		if i > 0:
			total += line[i].distance_to(line[i - 1])
		out_cumulative[i] = total
	out_length = total
	pushback_length = out_cumulative[1] if to_pushback.size() >= 2 and line.size() > 1 else minf(PUSHBACK_FALLBACK_M, total)


## Works out the speed profiles and runway rolls (call once `points`, `runway`, `touchdown` and
## `liftoff` are set).
func plan_timing() -> void:
	profile_in = TaxiProfile.build(points, TaxiProfile.TAXI_SPEED, 0.0)
	taxi_in_time = profile_in.duration
	_plan_way_out()
	if not points.is_empty():
		roll_in_distance = touchdown.distance_to(points[0])
		roll_out_distance = points[0].distance_to(liftoff)
	roll_in_time = TaxiProfile.landing_roll_time(roll_in_distance)
	roll_out_time = TaxiProfile.takeoff_roll_time(roll_out_distance)


# The way out: pushed back (slow, straight, nose still towards the gate), a turn on the spot at the
# push-back point on the taxiway, then taxiing to the runway at normal speed.
func _plan_way_out() -> void:
	if out_points.size() < 2:
		pushback_time = 0.0
		turn_time = 0.0
		taxi_out_time = 0.0
		return
	pushback_time = _pushback_time(pushback_length)
	var nose := nose_direction()
	var travel := _out_direction(pushback_length)
	turn_time = absf(nose.angle_to(travel)) / TURN_RATE
	var rest := PackedVector2Array([_out_position(pushback_length)])
	for i in out_points.size():
		if out_cumulative[i] > pushback_length + 0.001:
			rest.append(out_points[i])
	if rest.size() < 2:
		rest.append(rest[0] + travel)
	_profile_rest = TaxiProfile.build(rest, 0.0, TaxiProfile.TAXI_SPEED)
	taxi_out_time = pushback_time + turn_time + _profile_rest.duration


## The direction the nose points when parked: the way the plane was driving as it came in.
func nose_direction() -> Vector2:
	return heading_at(length)


static func _pushback_time(distance: float) -> float:
	var ramp := PUSHBACK_SPEED * PUSHBACK_SPEED / (2.0 * PUSHBACK_ACCEL)
	if distance >= 2.0 * ramp:
		return (distance - 2.0 * ramp) / PUSHBACK_SPEED + 2.0 * PUSHBACK_SPEED / PUSHBACK_ACCEL
	return 2.0 * sqrt(distance / PUSHBACK_ACCEL)


# Metres pushed back after `time` seconds: accelerate, cruise, brake to a stop.
static func _pushback_distance(time: float, distance: float) -> float:
	var total := _pushback_time(distance)
	time = clampf(time, 0.0, total)
	var left := total - time
	var ramp := PUSHBACK_SPEED * PUSHBACK_SPEED / (2.0 * PUSHBACK_ACCEL)
	var ramp_time := PUSHBACK_SPEED / PUSHBACK_ACCEL
	if distance >= 2.0 * ramp:
		if time < ramp_time:
			return 0.5 * PUSHBACK_ACCEL * time * time
		if left < ramp_time:
			return distance - 0.5 * PUSHBACK_ACCEL * left * left
		return ramp + (time - ramp_time) * PUSHBACK_SPEED
	if time < total * 0.5:
		return 0.5 * PUSHBACK_ACCEL * time * time
	return distance - 0.5 * PUSHBACK_ACCEL * left * left


## Metres driven on the way out (from the stand) `time` seconds after the push-back began.
func out_distance_at(time: float) -> float:
	if time < pushback_time:
		return _pushback_distance(time, pushback_length)
	if time < pushback_time + turn_time:
		return pushback_length
	return pushback_length + _profile_rest.distance_at(time - pushback_time - turn_time)


## Where the nose points `time` seconds after the push-back began: still the parked heading while
## pushed back, then turning on the spot to the direction of the taxiway, then along the way.
func nose_out(time: float, distance: float) -> Vector2:
	if time < pushback_time:
		return nose_direction()
	if time < pushback_time + turn_time:
		var u := (time - pushback_time) / turn_time
		return nose_direction().slerp(_out_direction(pushback_length), u * u * (3.0 - 2.0 * u)).normalized()
	return heading_out(distance)


## Position `distance` metres from the runway exit (clamped to the route).
func position_at(distance: float) -> Vector2:
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector2.ZERO
	var i := _segment(distance)
	var span := cumulative[i + 1] - cumulative[i]
	var t := 0.0 if span <= 0.0 else clampf((distance - cumulative[i]) / span, 0.0, 1.0)
	return points[i].lerp(points[i + 1], t)


## Unit direction of travel (towards the stand) at `distance`.
func heading_at(distance: float) -> Vector2:
	if points.size() < 2:
		return Vector2.RIGHT
	var i := _segment(distance)
	return (points[i + 1] - points[i]).normalized()


## Taxi out: `distance` metres driven from the stand towards the runway, along `out_points`.
func position_out(distance: float) -> Vector2:
	return _out_position(distance)


## The direction of travel on the way out at `distance` (not where the nose points: see nose_out).
func heading_out(distance: float) -> Vector2:
	return _out_direction(distance)


func _out_position(distance: float) -> Vector2:
	if out_points.size() < 2:
		return out_points[0] if out_points.size() == 1 else Vector2.ZERO
	var i := _out_segment(distance)
	var span := out_cumulative[i + 1] - out_cumulative[i]
	var t := 0.0 if span <= 0.0 else clampf((distance - out_cumulative[i]) / span, 0.0, 1.0)
	return out_points[i].lerp(out_points[i + 1], t)


func _out_direction(distance: float) -> Vector2:
	if out_points.size() < 2:
		return Vector2.RIGHT
	var i := _out_segment(distance)
	return (out_points[i + 1] - out_points[i]).normalized()


func _out_segment(distance: float) -> int:
	var low := 0
	var high := out_points.size() - 2
	while low < high:
		var mid := (low + high + 1) >> 1
		if out_cumulative[mid] <= distance:
			low = mid
		else:
			high = mid - 1
	return low


# Index of the segment that holds `distance`: the last point with cumulative <= distance.
func _segment(distance: float) -> int:
	var low := 0
	var high := points.size() - 2
	while low < high:
		var mid := (low + high + 1) >> 1
		if cumulative[mid] <= distance:
			low = mid
		else:
			high = mid - 1
	return low
