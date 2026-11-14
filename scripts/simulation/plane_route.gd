class_name PlaneRoute
extends RefCounted
## A ground route for one stand as a smooth polyline in metres (world x / z), from the runway exit
## to the stand's lead-in point (taxi in; taxi out is the same line driven backwards). Planes ask
## it for a position and heading by distance driven: a binary search over the cumulative lengths,
## no allocation per call (design doc §7.5a, step 7b).

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
## Speed profiles of the taxi in (exit to stand) and taxi out (stand to the runway entry).
var profile_in: TaxiProfile = TaxiProfile.new()
var profile_out: TaxiProfile = TaxiProfile.new()
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


## Works out the speed profiles and runway rolls (call once `points`, `runway`, `touchdown` and
## `liftoff` are set).
func plan_timing() -> void:
	profile_in = TaxiProfile.build(points, TaxiProfile.TAXI_SPEED, 0.0)
	var backwards := points.duplicate()
	backwards.reverse()
	profile_out = TaxiProfile.build(backwards, 0.0, TaxiProfile.TAXI_SPEED)
	taxi_in_time = profile_in.duration
	taxi_out_time = profile_out.duration
	if not points.is_empty():
		roll_in_distance = touchdown.distance_to(points[0])
		roll_out_distance = points[0].distance_to(liftoff)
	roll_in_time = TaxiProfile.landing_roll_time(roll_in_distance)
	roll_out_time = TaxiProfile.takeoff_roll_time(roll_out_distance)


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


## Taxi out: `distance` metres driven from the stand towards the runway.
func position_out(distance: float) -> Vector2:
	return position_at(length - distance)


## Heading while taxiing out (the opposite of `heading_at` at the same spot).
func heading_out(distance: float) -> Vector2:
	return -heading_at(length - distance)


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
