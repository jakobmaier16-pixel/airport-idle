class_name PlaneRoute
extends RefCounted
## A ground route for one stand as a smooth polyline in metres (world x / z), from the runway exit
## to the stand's lead-in point (taxi in; taxi out is the same line driven backwards). Planes ask
## it for a position and heading by distance driven: a binary search over the cumulative lengths,
## no allocation per call (design doc §7.5a, step 7b).

## Push-back: slow (about 3 m/s, accelerating at 1 m/s^2), straight back and then along a reverse arc;
## the tug lets go for a few seconds before the plane rolls forward.
const PUSHBACK_SPEED: float = 3.0
const PUSHBACK_ACCEL: float = 1.0
const PUSHBACK_HOLD: float = 4.0
## Metres over which the nose turns while rolling forward when there is no room for a reverse arc.
const BLEND_M: float = 40.0
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
## The way out, stand first: the push-back path (straight back, reverse arc, ends on the taxiway), then
## forward over the push-back point B (a vertex) and along the taxiway to the runway entry. There is a
## cusp where the push-back ends: the plane stops and rolls forward.
var out_points: PackedVector2Array = PackedVector2Array()
var out_cumulative: PackedFloat32Array = PackedFloat32Array()
var out_length: float = 0.0
## Metres pushed back (straight and along the arc) before the tug lets go.
var pushback_length: float = 0.0
## Seconds of the push-back (the tug lets go for PUSHBACK_HOLD more, then the taxi follows).
var pushback_time: float = 0.0
## Metres of forward roll over which the nose turns to the direction of travel (only without a reverse arc).
var blend_length: float = 0.0
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


## Sets the way out (metres). `back` is the push-back path from the stand's middle: straight back along the
## stand's axis, then a reverse arc that ends on the taxiway with the nose already pointing the way
## the plane will taxi (empty if there is no room for one). `to_pushback` is the line from the runway
## exit to the push-back point B on the taxiway (empty if the stand has none): after the tug let go the
## plane rolls forward from the end of `back` over B and along that line to the runway.
## Without a `back` the plane is pushed straight back to B (or PUSHBACK_FALLBACK_M of the line it came
## in on) and turns while rolling forward (BLEND_M): no turn on the spot ever.
func set_way_out(back: PackedVector2Array, to_pushback: PackedVector2Array) -> void:
	if points.is_empty():
		return
	var middle := points[points.size() - 1]
	var line := PackedVector2Array()
	blend_length = 0.0
	if not back.is_empty() and to_pushback.size() >= 2:
		line.append_array(back)
		var forward := to_pushback.duplicate()
		forward.reverse()
		line.append_array(forward)
	elif to_pushback.size() >= 2:
		line.append(middle)
		var forward := to_pushback.duplicate()
		forward.reverse()
		line.append_array(forward)
		blend_length = BLEND_M
	else:
		var backwards := points.duplicate()
		backwards.reverse()
		line = backwards
		blend_length = BLEND_M
	out_points = line
	out_cumulative.resize(line.size())
	var total := 0.0
	for i in line.size():
		if i > 0:
			total += line[i].distance_to(line[i - 1])
		out_cumulative[i] = total
	out_length = total
	if not back.is_empty() and to_pushback.size() >= 2:
		pushback_length = 0.0
		for i in range(1, back.size()):
			pushback_length += back[i].distance_to(back[i - 1])
	elif to_pushback.size() >= 2:
		pushback_length = out_cumulative[1]
	else:
		pushback_length = minf(PUSHBACK_FALLBACK_M, total)


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


# The way out: pushed back backwards (slow) along the path to the taxiway, the tug lets go (the plane
# stands still, heading unchanged), then it taxis forward to the runway at normal speed.
func _plan_way_out() -> void:
	if out_points.size() < 2:
		pushback_time = 0.0
		taxi_out_time = 0.0
		return
	pushback_time = _pushback_time(pushback_length)
	var rest := PackedVector2Array([_out_position(pushback_length)])
	for i in out_points.size():
		if out_cumulative[i] > pushback_length + 0.001:
			rest.append(out_points[i])
	if rest.size() < 2:
		rest.append(rest[0] + _out_direction(pushback_length))
	_profile_rest = TaxiProfile.build(rest, 0.0, TaxiProfile.TAXI_SPEED)
	taxi_out_time = pushback_time + PUSHBACK_HOLD + _profile_rest.duration


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
	if time < pushback_time + PUSHBACK_HOLD:
		return pushback_length
	return pushback_length + _profile_rest.distance_at(time - pushback_time - PUSHBACK_HOLD)


## Where the nose points `time` seconds after the push-back began, `distance` metres from the stand:
## while pushed back it is opposite to the direction of travel (tail first, so it swings with the
## arc), the same while the tug lets go, and along the way once the plane rolls forward.
func nose_out(time: float, distance: float) -> Vector2:
	var end_nose := -_out_direction(maxf(pushback_length - 0.01, 0.0))
	if time < pushback_time:
		return -_out_direction(minf(distance, maxf(pushback_length - 0.01, 0.0)))
	if blend_length <= 0.0:
		# The arc ends exactly facing the taxi direction (up to the arc's chords).
		return end_nose if time < pushback_time + PUSHBACK_HOLD else heading_out(distance)
	var u := clampf((distance - pushback_length) / blend_length, 0.0, 1.0)
	return end_nose.slerp(heading_out(distance), u * u * (3.0 - 2.0 * u)).normalized()


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
