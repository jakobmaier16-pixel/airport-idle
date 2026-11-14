extends TestCase
## The airside of the showcase works like a real one: planes are pushed back along the stand's axis
## and turn on the taxiway (never at the stand), they stay on pavement, taxiways must be 12 cells
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


func test_the_push_back_goes_straight_back_and_turns_on_the_taxiway() -> void:
	ShowcaseAirport.build(0.0)
	for stand in _stands():
		var route := Airport.plane_network.route_to_stand(stand)
		var gate := _gate_of(stand)
		check(route != null and gate != null, "stand %d has a route and a gate" % stand.id)
		if route == null or gate == null:
			continue
		var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
		var origin := Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
		var rect := Rect2(origin + Vector2(stand.origin_cell) * CELL, Vector2(size) * CELL)
		var towards_gate := (Vector2(gate.origin_cell) + Vector2(gate.get_rect().size) * 0.5 - Vector2(stand.origin_cell) - Vector2(size) * 0.5).normalized()
		var nose := route.nose_direction()
		check(nose.dot(towards_gate) > 0.5, "stand %d: parked nose-in, the nose points towards the gate" % stand.id)
		check(route.heading_at(route.length - 1.0).dot(nose) > 0.999 and route.heading_at(route.length - 20.0).dot(nose) > 0.99,
			"stand %d: the last 20 m are straight along the axis" % stand.id)
		var middle := route.position_out(0.0)
		check(route.pushback_length > maxf(rect.size.x * absf(nose.x), rect.size.y * absf(nose.y)) * 0.5,
			"stand %d: pushed back beyond the stand's back edge (%.0f m)" % [stand.id, route.pushback_length])
		var turned := 0
		var time := 0.0
		var last_nose := nose
		while time <= route.taxi_out_time:
			var driven := route.out_distance_at(time)
			var here := route.position_out(driven)
			var facing := route.nose_out(time, driven)
			if time < route.pushback_time:
				check(facing.dot(nose) > 0.9999, "stand %d: the nose keeps the parked heading while pushed back (t=%.1f)" % [stand.id, time])
				# Straight back along the stand's axis.
				var along := (here - middle)
				check(absf(along.cross(nose)) < 0.01, "stand %d: pushed straight back along the axis (t=%.1f)" % [stand.id, time])
				check(along.dot(nose) <= 0.01, "stand %d: it moves backwards (t=%.1f)" % [stand.id, time])
			if facing.dot(last_nose) < 0.9999:
				turned += 1
				check(not rect.has_point(here), "stand %d: it never turns on the spot inside the stand (t=%.1f, %s)" % [stand.id, time, here])
			last_nose = facing
			time += 0.25
		# A full turn of the nose from the parked heading towards the taxiway takes time, at 20 degrees a second at most.
		check(route.turn_time <= 9.5, "stand %d: the turn takes %.1f s" % [stand.id, route.turn_time])
		check(turned > 0 or route.turn_time < 0.2, "stand %d: it turns on the taxiway" % stand.id)
		# After the turn the plane drives forward: the nose is the direction of travel.
		var driven := route.out_distance_at(route.pushback_time + route.turn_time + 3.0)
		check(route.nose_out(route.pushback_time + route.turn_time + 3.0, driven).dot(route.heading_out(driven)) > 0.999, "stand %d: forward on the taxiway" % stand.id)
		check(route.out_distance_at(route.taxi_out_time) >= route.out_length - 0.5, "stand %d: the way out ends at the runway" % stand.id)


func test_a_plane_on_screen_follows_the_same_poses() -> void:
	await start_game()
	ShowcaseAirport.build(0.0)
	var layer := main.get_node("Planes") as PlaneLayer
	var flight: Flight = first_flight(0, 1500.0)
	check(flight != null, "a flight")
	if flight == null:
		return
	var route := Airport.schedule.route_of(flight)
	# While pushed back the drawn plane keeps the parked heading, and never turns inside its stand.
	var departs := flight.departs_at()
	while Airport.sim_time < departs - 2.0:
		Airport.step(Airport.SIM_STEP)
	var origin := Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
	var stand := flight.stand
	var rect := Rect2(origin + Vector2(stand.origin_cell) * CELL, Vector2(Building.rotated_size(stand.type.footprint, stand.rotation_steps)) * CELL)
	var parked := layer._pose(flight, departs - 1.0) as Transform3D
	var nose_parked := Vector2(-parked.basis.z.x, -parked.basis.z.z)
	check(nose_parked.dot(route.nose_direction()) > 0.999, "parked with the route's nose direction")
	var time := 0.0
	var turned_inside := 0
	var last := nose_parked
	while time < route.taxi_out_time:
		var pose := layer._pose(flight, departs + time) as Transform3D
		var nose := Vector2(-pose.basis.z.x, -pose.basis.z.z)
		if nose.dot(last) < 0.9999 and rect.has_point(Vector2(pose.origin.x, pose.origin.z)):
			turned_inside += 1
		last = nose
		time += 0.25
	check_eq(turned_inside, 0, "the drawn plane never turns inside its stand")


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
		check_eq(Airport.connection_problem(stand_type, stand_cell, 0), "Needs a taxiway to a runway", "%d cells wide: no way to the runway" % width)
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
