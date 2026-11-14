extends TestCase
## The airside of the showcase works like a real one: planes are pushed back out of the stand and
## along a reverse arc onto the taxiway (never turning on the spot), they stay on pavement, taxiways must be 12 cells
## (24 m) wide to count, and a fresh airport sees its first landing within a minute.

## Half the width of a taxiway (12 cells = 24 m). Real taxiways (ICAO code C to E: 15 to 23 m) are
## narrower than the planes' wingspan too: the wings reach beyond the pavement, so a wingtip or a
## nose / tail tip may be this much beyond the edge ...
const TAXIWAY_HALF_M: float = 12.0
## ... plus this tolerance for the curves (the line is rounded with a 30 m radius and the wings swing out).
const CURVE_TOLERANCE_M: float = 4.0
## The middle of the fuselage stays this far (metres) inside the pavement.
const MIN_CENTRE_CLEARANCE_M: float = 8.0
const CELL: float = 2.0


func _stands() -> Array[Building]:
	var result: Array[Building] = []
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.AIRCRAFT_STAND:
			result.append(building)
	return result


func _gate_of(stand: Building) -> Building:
	var rect := Rect2i(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
	for building in Airport.buildings:
		if building.type.role != BuildingType.Role.GATE:
			continue
		for cell in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false):
			if rect.has_point(cell):
				return building
	return null


func _cell_of(point: Vector2) -> Vector2i:
	return Airport.grid.world_to_cell(Vector3(point.x, 0.0, point.y))


# Metres from `point` to the nearest cell that is not paved (`limit` if none within it); 0 if the point
# is not paved itself.
func _clearance(point: Vector2, limit: float) -> float:
	var cell := _cell_of(point)
	if not Airport.plane_network.is_paved(cell):
		return 0.0
	var radius := int(ceilf(limit / CELL)) + 1
	var best := limit
	var origin := Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var other := cell + Vector2i(dx, dy)
			if Airport.plane_network.is_paved(other):
				continue
			var low := origin + Vector2(other) * CELL
			var nearest := Vector2(clampf(point.x, low.x, low.x + CELL), clampf(point.y, low.y, low.y + CELL))
			best = minf(best, point.distance_to(nearest))
	return best


# Metres from `point` to the nearest paved cell (0 if it is on one), searched up to `limit`.
func _overhang(point: Vector2, limit: float) -> float:
	var cell := _cell_of(point)
	if Airport.plane_network.is_paved(cell):
		return 0.0
	var radius := int(ceilf(limit / CELL)) + 1
	var best := INF
	var origin := Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var other := cell + Vector2i(dx, dy)
			if not Airport.plane_network.is_paved(other):
				continue
			var low := origin + Vector2(other) * CELL
			var nearest := Vector2(clampf(point.x, low.x, low.x + CELL), clampf(point.y, low.y, low.y + CELL))
			best = minf(best, point.distance_to(nearest))
	return best


# One ground pose: the fuselage middle must be on pavement; the nose, tail and both wingtips may only
# reach beyond it as far as a real plane's do. Returns the worst overhang over the four tips.
func _check_pose(label: String, position: Vector2, nose: Vector2, extent: float, stats: Dictionary) -> void:
	var clearance := _clearance(position, MIN_CENTRE_CLEARANCE_M + 2.0)
	stats["min_clearance"] = minf(stats.get("min_clearance", 99.0), clearance)
	check(clearance >= MIN_CENTRE_CLEARANCE_M, "%s: the fuselage middle %s is %.1f m inside the pavement (at least %.0f m)" % [label, position, clearance, MIN_CENTRE_CLEARANCE_M])
	var allowed := maxf(extent * 0.5 - TAXIWAY_HALF_M, 0.0) + CURVE_TOLERANCE_M
	var side := Vector2(-nose.y, nose.x)
	for tip in [position + nose * extent * 0.5, position - nose * extent * 0.5, position + side * extent * 0.5, position - side * extent * 0.5]:
		var over := _overhang(tip as Vector2, allowed + 4.0)
		stats["max_overhang"] = maxf(stats.get("max_overhang", 0.0), over)
		check(over <= allowed, "%s: a tip at %s is %.1f m beyond the pavement (allowed %.1f m)" % [label, tip, over, allowed])


func test_planes_stay_on_pavement_taxiing_in_and_out() -> void:
	ShowcaseAirport.build(0.0)
	var stats := {}
	var stands := _stands()
	check_eq(stands.size(), 3, "the showcase has three stands")
	for stand in stands:
		var route := Airport.plane_network.route_to_stand(stand)
		check(route != null and not route.from_fallback, "stand %d has an axis route" % stand.id)
		if route == null:
			continue
		var extent := TimetableSlot.WINGSPAN_M[TimetableSlot.PlaneClass.WIDE if stand.type.wide_body else TimetableSlot.PlaneClass.NARROW]
		var label := "stand %d" % stand.id
		# Taxi in: every 2 m of the way, nose along the line.
		var distance := 0.0
		while distance <= route.length:
			_check_pose(label + " in", route.position_at(distance), route.heading_at(distance), extent, stats)
			distance += 2.0
		# Parked.
		_check_pose(label + " parked", route.position_at(route.length), route.nose_direction(), extent, stats)
		# Taxi out: push-back, the turn and the taxi, every half second.
		var time := 0.0
		while time <= route.taxi_out_time:
			var driven := route.out_distance_at(time)
			_check_pose(label + " out", route.position_out(driven), route.nose_out(time, driven), extent, stats)
			time += 0.5
	print("INFO airside poses: the fuselage middle is at least %.1f m inside the pavement, the worst tip %.1f m beyond it" % [stats.get("min_clearance", 0.0), stats.get("max_overhang", 0.0)])


# The sharpest turn the plane may make: its nose swings at most this many radians per metre driven
# (a 12 m radius is 0.083; the arc is drawn in chords, so a little slack).
const MAX_TURN_PER_METRE: float = 0.12
## A heading change above this (degrees) while the plane stands still is a turn on the spot.
const STILL_TURN_DEG: float = 3.0


func _angle_between(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(absf(a.angle_to(b)))


func test_the_push_back_is_a_reverse_arc_onto_the_taxiway() -> void:
	ShowcaseAirport.build(0.0)
	for stand in _stands():
		var route := Airport.plane_network.route_to_stand(stand)
		var gate := _gate_of(stand)
		check(route != null and gate != null, "stand %d has a route and a gate" % stand.id)
		if route == null or gate == null:
			continue
		var label := "stand %d" % stand.id
		var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
		var origin := Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
		var rect := Rect2(origin + Vector2(stand.origin_cell) * CELL, Vector2(size) * CELL)
		var towards_gate := (Vector2(gate.origin_cell) + Vector2(gate.get_rect().size) * 0.5 - Vector2(stand.origin_cell) - Vector2(size) * 0.5).normalized()
		var nose := route.nose_direction()
		check(nose.dot(towards_gate) > 0.5, "%s: parked nose-in, the nose points towards the gate" % label)
		check(not route.from_fallback and route.blend_length == 0.0, "%s: a real push-back arc, no blending turn" % label)
		check(route.heading_at(route.length - 1.0).dot(nose) > 0.999 and route.heading_at(route.length - 20.0).dot(nose) > 0.99,
			"%s: the last 20 m are straight along the axis" % label)
		check(route.pushback_length > maxf(rect.size.x * absf(nose.x), rect.size.y * absf(nose.y)) * 0.5,
			"%s: pushed back beyond the stand's back edge (%.0f m)" % [label, route.pushback_length])
		check(PlaneRoute.PUSHBACK_HOLD >= 3.0, "the tug needs a few seconds to disconnect")
		# Straight out of the stand first: the first 10 m go back along the axis.
		var middle := route.position_out(0.0)
		var early := route.position_out(10.0) - middle
		check(absf(early.cross(nose)) < 0.01 and early.dot(nose) < 0.0, "%s: straight back out of the stand first" % label)
		# Walk the whole way out every tenth of a second.
		var last_pos := middle
		var last_nose := route.nose_out(0.0, 0.0)
		var swept := 0.0
		var time := 0.1
		var still_turns := 0
		var worst_rate := 0.0
		var window_moved := 0.0
		var window_nose := last_nose
		var arc_turned := 0.0
		while time <= route.taxi_out_time:
			var driven := route.out_distance_at(time)
			var here := route.position_out(driven)
			var facing := route.nose_out(time, driven)
			var moved := here.distance_to(last_pos)
			var turned := _angle_between(last_nose, facing)
			if moved < 0.001 and turned > STILL_TURN_DEG:
				still_turns += 1
			# The turn rate is measured over 3 m of travel (the arc is drawn in chords of a few degrees).
			window_moved += moved
			if window_moved >= 3.0:
				worst_rate = maxf(worst_rate, deg_to_rad(_angle_between(window_nose, facing)) / window_moved)
				window_moved = 0.0
				window_nose = facing
			if time < route.pushback_time:
				arc_turned += turned
				# Tail first: it moves opposite to where the nose points.
				if moved > 0.01:
					check((here - last_pos).normalized().dot(facing) < -0.95, "%s: backwards while pushed (t=%.1f)" % [label, time])
				check(not rect.has_point(here) or here.distance_to(middle) < route.pushback_length, "%s: stays on its path" % label)
			last_pos = here
			last_nose = facing
			time += 0.1
		check_eq(still_turns, 0, "%s: the heading never changes while the plane stands still" % label)
		check(worst_rate <= MAX_TURN_PER_METRE, "%s: sharpest turn %.3f rad per metre (at most %.2f)" % [label, worst_rate, MAX_TURN_PER_METRE])
		check(arc_turned > 10.0, "%s: the push-back really curves (%.0f degrees)" % [label, arc_turned])
		# At the end of the push-back the nose already points the way the plane taxis.
		var end_nose := route.nose_out(route.pushback_time, route.pushback_length)
		var taxi_direction := route.heading_out(route.pushback_length + 2.0)
		check(_angle_between(end_nose, taxi_direction) <= 5.0, "%s: ends with the nose in the taxi direction (%.1f degrees off)" % [label, _angle_between(end_nose, taxi_direction)])
		# Then it waits (nothing moves), then rolls forward with the nose along the line.
		var held := route.out_distance_at(route.pushback_time + PlaneRoute.PUSHBACK_HOLD * 0.5)
		check_eq(held, route.pushback_length, "%s: stands still for the tug to disconnect" % label)
		var after := route.pushback_time + PlaneRoute.PUSHBACK_HOLD + 3.0
		var driven_after := route.out_distance_at(after)
		check(route.nose_out(after, driven_after).dot(route.heading_out(driven_after)) > 0.999, "%s: forward on the taxiway" % label)
		check(route.out_distance_at(route.taxi_out_time) >= route.out_length - 0.5, "%s: the way out ends at the runway" % label)


func test_a_plane_on_screen_follows_the_same_poses() -> void:
	await start_game()
	ShowcaseAirport.build(0.0)
	var layer := main.get_node("Planes") as PlaneLayer
	var flight: Flight = first_flight(0, 1500.0)
	check(flight != null, "a flight")
	if flight == null:
		return
	var route := Airport.schedule.route_of(flight)
	var departs := flight.departs_at()
	while Airport.sim_time < departs - 2.0:
		Airport.step(Airport.SIM_STEP)
	var parked := layer._pose(flight, departs - 1.0) as Transform3D
	var nose_parked := Vector2(-parked.basis.z.x, -parked.basis.z.z)
	check(nose_parked.dot(route.nose_direction()) > 0.999, "parked with the route's nose direction")
	var time := 0.0
	var still_turns := 0
	var last := nose_parked
	var last_at := Vector2(parked.origin.x, parked.origin.z)
	while time < route.taxi_out_time:
		var pose := layer._pose(flight, departs + time) as Transform3D
		var nose := Vector2(-pose.basis.z.x, -pose.basis.z.z)
		var at := Vector2(pose.origin.x, pose.origin.z)
		if at.distance_to(last_at) < 0.001 and _angle_between(nose, last) > STILL_TURN_DEG:
			still_turns += 1
		last = nose
		last_at = at
		time += 0.1
	check_eq(still_turns, 0, "the drawn plane never turns while standing still")


# --- A taxiway must be wide enough ---

func test_a_taxiway_thinner_than_12_cells_does_not_count() -> void:
	build_basic_terminal()
	Airport.add_starting_runway()
	Airport.place_building(type_of(&"gate"), at(Vector2i(40, 34)), 0)
	var stand_cell := at(Vector2i(32, 39))
	Airport.place_building(type_of(&"aircraft_stand"), stand_cell, 0)
	var stand_type := type_of(&"aircraft_stand")
	for width in [2, 6, 11]:
		Airport.paint_taxiway(cells(at(Vector2i(36, 62)), Vector2i(width, 19)), true)
		check_eq(Airport.connection_problem(stand_type, stand_cell, 0), "No taxiway", "%d cells wide: no way to the runway" % width)
		check(Airport.plane_network.route_to_stand(Airport.stand_behind(Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)[0])) == null, "%d cells wide: no route" % width)
		Airport.paint_taxiway(cells(at(Vector2i(36, 62)), Vector2i(width, 19)), false)
	Airport.paint_taxiway(cells(at(Vector2i(36, 62)), Vector2i(12, 19)), true)
	check_eq(Airport.connection_problem(stand_type, stand_cell, 0), "", "12 cells (24 m): a way to the runway")
	var stand := Airport.stand_behind(Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)[0])
	var route := Airport.plane_network.route_to_stand(stand)
	check(route != null and not route.from_fallback, "and a route")
	# A thin spur beside a wide taxiway is not part of the network.
	Airport.paint_taxiway(cells(at(Vector2i(52, 70)), Vector2i(2, 8)), true)
	check(not Airport.plane_network.is_paved(at(Vector2i(52, 70))) or Airport.plane_network.area_of(at(Vector2i(52, 70))) < 0, "a 2 cell spur is not paved for planes")


# --- The first landing ---

func test_a_fresh_airport_sees_its_first_landing_within_a_minute() -> void:
	var landings: Array[float] = []
	for run in 2:
		ShowcaseAirport.build(0.0)
		var started := Airport.sim_time
		var first := -1.0
		for i in int(120.0 / Airport.SIM_STEP):
			Airport.step(Airport.SIM_STEP)
			if Airport.schedule.flights.any(func(f: Flight) -> bool: return f.phase == Flight.Phase.ARRIVING or f.phase == Flight.Phase.AT_STAND):
				first = Airport.sim_time - started
				break
		check(first >= 0.0 and first <= 60.0, "the first plane is on its way after %.1f s (at most 60 s)" % first)
		landings.append(first)
	print("INFO first plane on its way %.1f s after the start" % landings[0])
	check_eq(landings[0], landings[1], "and it is the same every time")


func test_only_the_first_gate_of_a_fresh_airport_gets_an_opening_flight() -> void:
	ShowcaseAirport.build(0.0)
	Airport.step(Airport.SIM_STEP)
	var openings := Airport.schedule.flights.filter(func(f: Flight) -> bool: return not Airport.timetable.slots.any(func(s: TimetableSlot) -> bool: return s.gate == f.gate and absf(s.departure_time - f.departure_time) < 0.01))
	check_eq(openings.size(), 1, "one opening flight, for the first gate")
	# The grid is untouched: every slot is on its gate's grid and a turnaround after the last departure of its gate.
	sim_seconds(1500.0)
	for gate in Airport.usable_gates():
		var times: Array[float] = []
		for flight in Airport.schedule.flights:
			if flight.gate == gate:
				times.append(flight.departure_time)
		for slot in Airport.timetable.slots:
			if slot.gate == gate:
				times.append(slot.departure_time)
		times.sort()
		for i in range(1, times.size()):
			check(times[i] - times[i - 1] >= Timetable.period_real() - 0.01 or absf(times[i] - times[i - 1]) < 0.01, "gate %d: departures a turnaround apart" % gate.id)


func test_the_opening_flight_happens_once_per_fresh_airport() -> void:
	ShowcaseAirport.build(0.0)
	Airport.step(Airport.SIM_STEP)
	var first := Airport.schedule.flights.size()
	check(first >= 1, "the fresh airport has its opening flight")
	# Every flight and slot cancelled (and the planner's memory of the grid gone): no second opening.
	Airport.schedule.flights.clear()
	Airport.timetable.slots.clear()
	Airport.timetable._next.clear()
	var before := Airport.sim_time
	for i in int(30.0 / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
	var early := Airport.schedule.flights.filter(func(f: Flight) -> bool: return f.departure_time < before + Timetable.period_real() * 0.2)
	check_eq(early.size(), 0, "no second opening flight after everything was cancelled")
