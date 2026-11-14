class_name TaxiProfile
extends RefCounted
## How fast a plane drives along a polyline (design doc §7.5a, step 7c). Deterministic: a plane
## taxis at TAXI_SPEED, slows to TURN_SPEED in tight turns (from the polyline's curvature) and
## accelerates / brakes at fixed rates, so each segment is a trapezoid of speed. Built once per
## route; asking for a position by time is a binary search with no allocation.
## Also holds the two runway rolls (landing and take-off), which are one constant acceleration.

## Metres per second on a straight taxiway (27 km/h) and in a tight turn.
const TAXI_SPEED: float = 7.5
const TURN_SPEED: float = 3.0
## A turn with this radius (or tighter) is taken at TURN_SPEED; wider ones are in between.
const TURN_RADIUS_REF: float = 30.0
## Metres per second squared.
const ACCEL: float = 1.0
const BRAKE: float = 1.5
## Touchdown speed and lift-off speed on the runway (m/s).
const TOUCHDOWN_SPEED: float = 70.0
const LIFTOFF_SPEED: float = 80.0

var length: float = 0.0
## Seconds to drive the whole line.
var duration: float = 0.0
# Per point: distance from the start and time since the start.
var _dist: PackedFloat32Array = PackedFloat32Array()
var _time: PackedFloat32Array = PackedFloat32Array()
# Per segment: speed at its start / peak / end, and the distance spent speeding up and braking.
var _v_start: PackedFloat32Array = PackedFloat32Array()
var _v_peak: PackedFloat32Array = PackedFloat32Array()
var _v_end: PackedFloat32Array = PackedFloat32Array()
var _x_up: PackedFloat32Array = PackedFloat32Array()
var _x_down: PackedFloat32Array = PackedFloat32Array()


## The profile of `points` driven from the first to the last point, starting at `start_speed` and
## ending at `end_speed` (m/s).
static func build(points: PackedVector2Array, start_speed: float, end_speed: float) -> TaxiProfile:
	var profile := TaxiProfile.new()
	var n := points.size()
	profile._dist.resize(n)
	profile._time.resize(n)
	if n < 2:
		return profile
	var seg_len := PackedFloat32Array()
	seg_len.resize(n - 1)
	for i in n - 1:
		seg_len[i] = points[i].distance_to(points[i + 1])
		profile._dist[i + 1] = profile._dist[i] + seg_len[i]
	profile.length = profile._dist[n - 1]
	# The most speed each point allows: a turn's sharpness is the angle per metre around it.
	var limit := PackedFloat32Array()
	limit.resize(n)
	limit.fill(TAXI_SPEED)
	for i in range(1, n - 1):
		if seg_len[i - 1] < 0.001 or seg_len[i] < 0.001:
			continue
		var turn := absf((points[i] - points[i - 1]).angle_to(points[i + 1] - points[i]))
		var curvature := turn / (0.5 * (seg_len[i - 1] + seg_len[i]))
		limit[i] = TAXI_SPEED - (TAXI_SPEED - TURN_SPEED) * clampf(curvature * TURN_RADIUS_REF, 0.0, 1.0)
	# Speed at every point: forward for what acceleration allows, backward for what braking allows.
	var speed := limit.duplicate()
	speed[0] = minf(start_speed, limit[0])
	for i in range(1, n):
		speed[i] = minf(speed[i], sqrt(speed[i - 1] * speed[i - 1] + 2.0 * ACCEL * seg_len[i - 1]))
	speed[n - 1] = minf(speed[n - 1], end_speed)
	for i in range(n - 2, -1, -1):
		speed[i] = minf(speed[i], sqrt(speed[i + 1] * speed[i + 1] + 2.0 * BRAKE * seg_len[i]))
	profile._v_start.resize(n - 1)
	profile._v_peak.resize(n - 1)
	profile._v_end.resize(n - 1)
	profile._x_up.resize(n - 1)
	profile._x_down.resize(n - 1)
	var total := 0.0
	for i in n - 1:
		var d := seg_len[i]
		var v0 := speed[i]
		var v1 := speed[i + 1]
		var cap := maxf(limit[i], limit[i + 1])
		var peak := v0
		var x_up := 0.0
		var x_down := 0.0
		if d > 0.0001:
			# Speed up to `peak` and brake down to v1 so that both fit in the segment.
			x_up = clampf((v1 * v1 - v0 * v0 + 2.0 * BRAKE * d) / (2.0 * (ACCEL + BRAKE)), 0.0, d)
			peak = sqrt(v0 * v0 + 2.0 * ACCEL * x_up)
			if peak > cap:
				peak = cap
				x_up = maxf((peak * peak - v0 * v0) / (2.0 * ACCEL), 0.0)
			x_down = maxf((peak * peak - v1 * v1) / (2.0 * BRAKE), 0.0)
			# A segment too short for both is rare (rounding); the cruise share is then zero.
			if x_up + x_down > d:
				var scale := d / (x_up + x_down)
				x_up *= scale
				x_down *= scale
		profile._v_start[i] = v0
		profile._v_peak[i] = peak
		profile._v_end[i] = v1
		profile._x_up[i] = x_up
		profile._x_down[i] = x_down
		profile._time[i] = total
		total += profile._segment_time(i, d)
	profile._time[n - 1] = total
	profile.duration = total
	return profile


## Distance driven `time` seconds after the start (clamped to the line).
func distance_at(time: float) -> float:
	if _dist.size() < 2:
		return 0.0
	if time <= 0.0:
		return 0.0
	if time >= duration:
		return length
	var low := 0
	var high := _dist.size() - 2
	while low < high:
		var mid := (low + high + 1) >> 1
		if _time[mid] <= time:
			low = mid
		else:
			high = mid - 1
	var span := _dist[low + 1] - _dist[low]
	return _dist[low] + _segment_distance(low, time - _time[low], span)


## Seconds the plane needs for the first `distance` metres (clamped to the line).
func time_at(distance: float) -> float:
	if _dist.size() < 2 or distance <= 0.0:
		return 0.0
	if distance >= length:
		return duration
	var low := 0
	var high := _dist.size() - 2
	while low < high:
		var mid := (low + high + 1) >> 1
		if _dist[mid] <= distance:
			low = mid
		else:
			high = mid - 1
	return _time[low] + _segment_time(low, distance - _dist[low])


# Seconds to drive the first `d` metres of segment `i`.
func _segment_time(i: int, d: float) -> float:
	var v0 := _v_start[i]
	var peak := _v_peak[i]
	var v1 := _v_end[i]
	var x_up := _x_up[i]
	var x_down := _x_down[i]
	var cruise_end := _dist[i + 1] - _dist[i] - x_down
	var total := 0.0
	if x_up > 0.0:
		var up := minf(d, x_up)
		var accel := (peak * peak - v0 * v0) / (2.0 * x_up)
		if accel > 0.0001:
			total += (sqrt(v0 * v0 + 2.0 * accel * up) - v0) / accel
		else:
			total += up / maxf(v0, 0.0001)
	if d > x_up and peak > 0.0:
		total += (minf(d, cruise_end) - x_up) / peak if cruise_end > x_up else 0.0
	if d > cruise_end and x_down > 0.0:
		var braked := d - maxf(cruise_end, x_up)
		var decel := (peak * peak - v1 * v1) / (2.0 * x_down)
		if decel > 0.0001:
			total += (peak - sqrt(maxf(peak * peak - 2.0 * decel * braked, 0.0))) / decel
		else:
			total += braked / maxf(peak, 0.0001)
	return total


# Metres driven `t` seconds into segment `i`.
func _segment_distance(i: int, t: float, seg_len: float) -> float:
	var v0 := _v_start[i]
	var peak := _v_peak[i]
	var v1 := _v_end[i]
	var x_up := _x_up[i]
	var x_down := _x_down[i]
	var accel := 0.0 if x_up <= 0.0 else (peak * peak - v0 * v0) / (2.0 * x_up)
	var t_up := 0.0
	if x_up > 0.0:
		t_up = (peak - v0) / accel if accel > 0.0001 else x_up / maxf(v0, 0.0001)
	if t <= t_up:
		return minf(v0 * t + 0.5 * accel * t * t, x_up)
	var cruise_len := maxf(seg_len - x_up - x_down, 0.0)
	var t_cruise := 0.0 if peak <= 0.0 else cruise_len / peak
	var after := t - t_up
	if after <= t_cruise:
		return x_up + peak * after
	var decel := 0.0 if x_down <= 0.0 else (peak * peak - v1 * v1) / (2.0 * x_down)
	var u := after - t_cruise
	return minf(x_up + cruise_len + peak * u - 0.5 * decel * u * u, seg_len)


## Seconds to roll `distance` metres from touchdown to the runway exit: constant braking from
## TOUCHDOWN_SPEED to TAXI_SPEED.
static func landing_roll_time(distance: float) -> float:
	return 2.0 * distance / (TOUCHDOWN_SPEED + TAXI_SPEED)


## Metres rolled `time` seconds after touchdown on a roll of `distance` metres.
static func landing_roll_distance(time: float, distance: float) -> float:
	var total := landing_roll_time(distance)
	if total <= 0.0:
		return distance
	var t := clampf(time, 0.0, total)
	var decel := (TOUCHDOWN_SPEED - TAXI_SPEED) / total
	return minf(TOUCHDOWN_SPEED * t - 0.5 * decel * t * t, distance)


## Seconds to roll `distance` metres from stand-still to lift-off at LIFTOFF_SPEED (constant
## acceleration over the whole run).
static func takeoff_roll_time(distance: float) -> float:
	return 2.0 * distance / LIFTOFF_SPEED


## Metres rolled `time` seconds after the start of a take-off run of `distance` metres.
static func takeoff_roll_distance(time: float, distance: float) -> float:
	var total := takeoff_roll_time(distance)
	if total <= 0.0:
		return distance
	var t := clampf(time, 0.0, total)
	return distance * (t / total) * (t / total)
