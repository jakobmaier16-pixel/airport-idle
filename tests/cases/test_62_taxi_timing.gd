extends TestCase
## Taxiing at real scale (design doc §7.5a, step 7c): the speed model, the runway rolls, the
## timetable's planning by the real route, and planes drawn along it.

## The share of a day's departures that must leave on time on the showcase airport. Before real taxi
## times it was 100 %. With the fixed seed 91.7 % (5 of 60) are on time: at the evening peak the one
## runway is full (about 64 s per flight), and a plane that has to wait in the air for it, longer than
## the 20 s turnaround buffer absorbs, leaves late. Landings give way to a take-off that has waited
## 80 s at the holding point (HOLDING_PRIORITY_AFTER), which costs a few more of these (it was 96.7 %
## when take-offs could starve for up to 140 s). 90 % is what every airport starts with.
const MIN_ON_TIME: float = 0.9
## A flight that leaves more than this many seconds after its time is late.
const ON_TIME_LIMIT: float = 10.0
## The longest a plane may wait at the holding point for the runway (seconds): a landing booked
## ahead cannot starve it (HOLDING_PRIORITY_AFTER), so it only waits for what is on the runway and
## for the take-offs in front of it.
const MAX_HOLDING_WAIT: float = 120.0


# --- Speed model (TaxiProfile) ---

func _straight(length: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])


func test_taxi_time_is_length_over_speed_on_a_straight() -> void:
	for length in [800.0, 1500.0, 2500.0]:
		var line := _straight(length)
		var in_profile := TaxiProfile.build(line, TaxiProfile.TAXI_SPEED, 0.0)
		var out_profile := TaxiProfile.build(line, 0.0, TaxiProfile.TAXI_SPEED)
		var ideal: float = length / TaxiProfile.TAXI_SPEED
		check(absf(in_profile.duration - ideal) <= ideal * 0.05, "taxi in over %.0f m: %.1f s vs %.1f s" % [length, in_profile.duration, ideal])
		check(absf(out_profile.duration - ideal) <= ideal * 0.05, "taxi out over %.0f m: %.1f s vs %.1f s" % [length, out_profile.duration, ideal])
		check_eq(in_profile.length, length, "the profile knows the length")


func test_distance_and_time_are_inverse_and_monotone() -> void:
	# An S-bend of rounded corners, so every kind of segment (speed up, cruise, brake) is used.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(220, 5), Vector2(235, 20), Vector2(240, 40),
		Vector2(240, 300), Vector2(245, 320), Vector2(260, 335), Vector2(280, 340), Vector2(500, 340)])
	var profile := TaxiProfile.build(line, 0.0, 0.0)
	var last := -1.0
	var steps := 400
	for i in steps + 1:
		var time := profile.duration * i / steps
		var distance := profile.distance_at(time)
		check(distance >= last - 0.001, "distance never goes back (t=%.1f)" % time)
		last = distance
		check(absf(profile.time_at(distance) - time) < 0.05, "time_at(distance_at(t)) == t at %.1f s" % time)
	check_eq(profile.distance_at(0.0), 0.0, "starts at 0")
	check(absf(profile.distance_at(profile.duration) - profile.length) < 0.01, "ends at the full length")
	# Never faster than the taxi speed, nor an acceleration beyond the limits.
	var step := 0.25
	var previous := 0.0
	var previous_speed := 0.0
	for i in range(1, int(profile.duration / step)):
		var distance := profile.distance_at(i * step)
		var speed := (distance - previous) / step
		check(speed <= TaxiProfile.TAXI_SPEED + 0.05, "speed %.2f m/s is within the taxi speed (t=%.2f)" % [speed, i * step])
		check(absf(speed - previous_speed) / step <= TaxiProfile.BRAKE + 0.2, "no jerky change of speed at t=%.2f" % [i * step])
		previous = distance
		previous_speed = speed


func test_turns_are_slower_than_straights() -> void:
	var straight := TaxiProfile.build(_straight(600.0), 0.0, 0.0)
	# The same 600 m with a tight 90 degree bend in the middle (radius about 15 m).
	var bend := PackedVector2Array([Vector2(0, 0), Vector2(285, 0), Vector2(295, 3), Vector2(299, 8), Vector2(300, 15),
		Vector2(300, 315)])
	var bent := TaxiProfile.build(bend, 0.0, 0.0)
	check(bent.duration > straight.duration + 3.0, "a turn costs time: %.1f s vs %.1f s" % [bent.duration, straight.duration])
	# In the turn the plane is at turn speed, not at the taxi speed.
	var mid := bent.time_at(297.0)
	var speed := (bent.distance_at(mid + 0.1) - bent.distance_at(mid - 0.1)) / 0.2
	check(speed <= 4.0, "slow in the bend: %.1f m/s" % speed)


func test_runway_rolls() -> void:
	# Landing: from touchdown speed to taxi speed over the distance; take-off: from rest to lift-off.
	var roll := 800.0
	var time := TaxiProfile.landing_roll_time(roll)
	check(absf(time - roll / ((TaxiProfile.TOUCHDOWN_SPEED + TaxiProfile.TAXI_SPEED) * 0.5)) < 0.01, "average speed of a constant brake")
	check(absf(TaxiProfile.landing_roll_distance(time, roll) - roll) < 0.01, "the landing roll ends at the exit")
	check(TaxiProfile.landing_roll_distance(time * 0.5, roll) > roll * 0.5, "most of the roll is the fast part")
	var run := 1000.0
	var take_off := TaxiProfile.takeoff_roll_time(run)
	check(absf(take_off - 2.0 * run / TaxiProfile.LIFTOFF_SPEED) < 0.01, "constant acceleration to lift-off")
	check(absf(TaxiProfile.takeoff_roll_distance(take_off, run) - run) < 0.01, "lift-off at the end of the run")
	check(TaxiProfile.takeoff_roll_distance(take_off * 0.5, run) < run * 0.3, "slow at first")


# --- Routes: closer stands are quicker ---

class Layout extends RefCounted:
	var grid: AirportGrid
	var buildings: Array[Building] = []
	var network: PlaneNetwork = PlaneNetwork.new()
	var next_id: int = 1

	func _init(size: Vector2i) -> void:
		grid = AirportGrid.new(size, 2.0)

	func add(type_id: StringName, origin: Vector2i, rotation: int = 0) -> Building:
		var building := Building.new(Airport.CATALOG.find(type_id), origin, rotation)
		building.id = next_id
		next_id += 1
		buildings.append(building)
		var size := Building.rotated_size(building.type.footprint, rotation)
		for y in size.y:
			for x in size.x:
				grid.set_content(origin + Vector2i(x, y), building)
		return building

	func paint(origin: Vector2i, size: Vector2i, on: bool = true) -> void:
		for y in size.y:
			for x in size.x:
				grid.set_taxiway(origin + Vector2i(x, y), on)

	func rebuild() -> void:
		network.rebuild(grid, buildings)

	func stands() -> Array[Building]:
		var result: Array[Building] = []
		for building in buildings:
			if building.type.role == BuildingType.Role.AIRCRAFT_STAND:
				result.append(building)
		return result


# A runway, a taxiway running away from it and three stands at increasing distance from the exit.
func _stand_row() -> Layout:
	var layout := Layout.new(Vector2i(1200, 400))
	layout.add(&"runway", Vector2i(100, 100))
	layout.paint(Vector2i(500, 123), Vector2i(12, 80))
	layout.paint(Vector2i(500, 200), Vector2i(500, 12))
	layout.add(&"aircraft_stand", Vector2i(540, 212))
	layout.add(&"aircraft_stand", Vector2i(700, 212))
	layout.add(&"aircraft_stand", Vector2i(900, 212))
	layout.rebuild()
	return layout


func test_closer_stand_has_a_shorter_planned_time() -> void:
	var layout := _stand_row()
	var last_in := 0.0
	var last_out := 0.0
	var last_lead := 0.0
	for stand in layout.stands():
		var route := layout.network.route_to_stand(stand)
		check(route != null, "the stand has a route")
		if route == null:
			continue
		check(route.taxi_in_time > last_in, "taxi in grows with the distance: %.1f s" % route.taxi_in_time)
		check(route.taxi_out_time > last_out, "taxi out grows with the distance: %.1f s" % route.taxi_out_time)
		check(FlightSchedule.lead_of(route) > last_lead, "so does the plane's lead time: %.1f s" % FlightSchedule.lead_of(route))
		check(route.taxi_in_time >= route.length / TaxiProfile.TAXI_SPEED * 0.95, "not faster than the taxi speed")
		check(route.roll_in_time > 10.0 and route.roll_out_time > 10.0, "rolls on a 2 km runway take a while (%.1f s, %.1f s)" % [route.roll_in_time, route.roll_out_time])
		last_in = route.taxi_in_time
		last_out = route.taxi_out_time
		last_lead = FlightSchedule.lead_of(route)
	check(last_lead > FlightSchedule.STAND_DWELL + 100.0, "a far stand lands its plane much earlier (no cap): %.0f s before departure" % last_lead)
	check(layout.network.longest_arrival() >= last_in, "the network knows its longest arrival")
	check(layout.network.longest_departure() >= last_out, "and its longest departure")


func test_routes_are_made_by_the_rebuild_not_lazily() -> void:
	var layout := _stand_row()
	var built := layout.network.routes_built
	check_eq(built, 3, "one route per stand, made in the rebuild")
	for stand in layout.stands():
		layout.network.route_to_stand(stand)
	check_eq(layout.network.routes_built, built, "asking for a route makes none")
	check(layout.network.last_routes_ms <= layout.network.last_rebuild_ms, "the time of the routes is part of the rebuild")


# --- On the showcase airport ---

func test_planning_windows_cover_the_longest_taxi() -> void:
	ShowcaseAirport.build(0.0)
	var schedule := Airport.schedule
	check(schedule.fill_window() >= schedule.longest_lead() + FlightSchedule.APPROACH_TIME, "a flight exists before its plane has to land")
	check(schedule.fill_window() >= FlightSchedule.ARRIVALS_START, "and before its passengers arrive")
	check(schedule.first_departure_delay() > schedule.fill_window(), "slots are planned beyond that window")
	check(schedule.first_departure_delay() >= FlightSchedule.FIRST_DEPARTURE_DELAY, "never less than before")


func test_a_day_on_the_showcase() -> void:
	Airport.reseed(Benchmark.SEED)
	ShowcaseAirport.build(180.0)
	var schedule := Airport.schedule
	var built_before := Airport.plane_network.routes_built
	var checked: Dictionary[Flight, bool] = {}
	# Flights made during the warm-up were checked when they were made (they are older than the loop).
	for flight in schedule.flights:
		checked[flight] = true
	var late_creation := 0
	var late_departures := 0
	var backwards := 0
	var phases: Dictionary[Flight, int] = {}
	var waits: Dictionary[Flight, bool] = {}
	var max_wait := 0.0
	var steps := int(5760.0 / Airport.SIM_STEP)  # one game day
	for i in steps:
		Airport.step(Airport.SIM_STEP)
		var now := Airport.sim_time
		for flight in schedule.flights:
			if not checked.has(flight):
				checked[flight] = true
				# A flight is made before its plane has to touch down (a flight without a route, e.g. at a
				# stand that is not connected yet, has no real lead to check).
				var route := schedule.route_of(flight)
				if route != null and flight.departs_at() - now + flight.arrival_delay < FlightSchedule.lead_of(route):
					late_creation += 1
			if phases.has(flight) and int(flight.phase) < phases[flight]:
				backwards += 1
			if flight.phase >= Flight.Phase.DEPARTING and phases.get(flight, 0) < int(Flight.Phase.DEPARTING) and flight.delay > ON_TIME_LIMIT:
				late_departures += 1
			phases[flight] = int(flight.phase)
			if flight.takeoff_booked and not waits.has(flight):
				waits[flight] = true
				var route_out := schedule.route_of(flight)
				max_wait = maxf(max_wait, flight.takeoff_at - flight.departs_at() - FlightSchedule.taxi_out_of(route_out))
	check(waits.size() >= 40, "take-offs were measured (%d)" % waits.size())
	check(max_wait <= MAX_HOLDING_WAIT, "no plane waits long at the holding point: %.1f s (at most %.0f s)" % [max_wait, MAX_HOLDING_WAIT])
	print("INFO showcase day: longest holding point wait %.1f s" % max_wait)
	check_eq(Airport.plane_network.routes_built, built_before, "no route was built inside a simulation step")
	check_eq(late_creation, 0, "every flight existed before its touchdown")
	check_eq(backwards, 0, "phases only move forward")
	# The runway: one plane at a time, over the whole day.
	var bookings := schedule.runway_bookings
	check(bookings.size() >= 90, "landings and take-offs over a day: %d" % bookings.size())
	var overlaps := 0
	var movement := 0.0
	for i in range(1, bookings.size()):
		if bookings[i][1] < bookings[i - 1][2] - 0.001 and bookings[i][0] == bookings[i - 1][0]:
			overlaps += 1
	for booking: Array in bookings:
		movement += booking[2] - booking[1]
	check_eq(overlaps, 0, "the runway is never double occupied")
	check(movement / bookings.size() > 20.0, "a movement takes its roll and margin: %.0f s" % (movement / bookings.size()))
	var departures := schedule.departures
	var on_time := 1.0 - float(late_departures) / maxi(departures, 1)
	print("INFO showcase day: %d departures, %.1f %% on time, %d runway movements" % [departures, on_time * 100.0, bookings.size()])
	check(departures >= 40, "the day had flights (%d)" % departures)
	check(on_time >= MIN_ON_TIME, "on time: %.1f %% (at least %.0f %%)" % [on_time * 100.0, MIN_ON_TIME * 100.0])


func test_removing_the_taxiway_cancels_cleanly_and_laying_it_again_resumes() -> void:
	ShowcaseAirport.build(0.0)
	var schedule := Airport.schedule
	check(first_flight(0, 2400.0) != null, "a flight is planned")
	sim_seconds(60.0)
	# Cut the parallel taxiway while planes are about.
	Airport.paint_taxiway(cells(at(Vector2i(6, 79)), Vector2i(100, 2)), false)
	var stands := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.AIRCRAFT_STAND)
	for stand: Building in stands:
		check(Airport.plane_network.route_to_stand(stand) == null, "no route to stand %d" % stand.id)
	sim_seconds(30.0)
	check(not schedule.flights.any(func(f: Flight) -> bool: return f.is_active() and f.phase != Flight.Phase.SCHEDULED), "nothing flies to unreachable stands")
	check_eq(Airport.usable_gates().size(), 0, "no gate gets flights")
	var built := Airport.plane_network.routes_built
	sim_seconds(300.0)
	check_eq(Airport.plane_network.routes_built, built, "and the simulation makes no routes meanwhile")
	# Lay it again: routes come back and flights are planned again.
	Airport.paint_taxiway(cells(at(Vector2i(6, 79)), Vector2i(100, 2)), true)
	for stand: Building in stands:
		check(Airport.plane_network.route_to_stand(stand) != null, "route back to stand %d" % stand.id)
	check(first_flight(0, 3000.0) != null, "flights are planned again")


func test_no_route_is_built_inside_a_step_after_a_layout_change() -> void:
	ShowcaseAirport.build(0.0)
	var before := Airport.plane_network.routes_built
	Airport.paint_taxiway(cells(at(Vector2i(6, 76)), Vector2i(20, 2)), true)
	var after_change := Airport.plane_network.routes_built
	check(after_change > before, "a taxiway change rebuilds the routes at once (%d -> %d)" % [before, after_change])
	sim_seconds(600.0)
	check_eq(Airport.plane_network.routes_built, after_change, "ten minutes of simulation built none")


func test_rebuild_and_taxi_times_are_reported() -> void:
	ShowcaseAirport.build(0.0)
	var network := Airport.plane_network
	print("INFO showcase rebuild: %.1f ms in total, centreline %.1f ms, routes %.1f ms" % [
		network.last_rebuild_ms, network.last_centreline_ms, network.last_routes_ms])
	check(network.last_routes_ms <= network.last_rebuild_ms, "routes are inside the rebuild")
	for stand in Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.AIRCRAFT_STAND):
		var route := Airport.plane_network.route_to_stand(stand)
		if route == null:
			continue
		print("INFO showcase stand %d: route %.0f m, roll in %.0f s, taxi in %.0f s, taxi out %.0f s, take-off run %.0f s" % [
			stand.id, route.length, route.roll_in_time, route.taxi_in_time, route.taxi_out_time, route.roll_out_time])
		check(route.taxi_in_time > 5.0 and route.taxi_in_time < 600.0, "a sane taxi time")


# A big airport: two rows of stands along a 1,200 cell taxiway, all with routes.
func test_rebuild_time_of_a_big_airport() -> void:
	var layout := Layout.new(Vector2i(1600, 600))
	layout.add(&"runway", Vector2i(100, 100))
	layout.paint(Vector2i(500, 123), Vector2i(12, 80))
	layout.paint(Vector2i(300, 200), Vector2i(1200, 12))
	var count := 0
	for x in range(320, 1450, 45):
		layout.add(&"aircraft_stand", Vector2i(x, 212))
		layout.add(&"aircraft_stand", Vector2i(x, 177))
		count += 2
	layout.rebuild()
	var network := layout.network
	print("INFO big airport rebuild (%d stands, 1,200 cell taxiway): %.1f ms in total, centreline %.1f ms, routes %.1f ms" % [
		count, network.last_rebuild_ms, network.last_centreline_ms, network.last_routes_ms])
	check_eq(network.routes_built, count, "a route per stand")
	print("INFO longest arrival on the big airport: %.0f s" % network.longest_arrival())
	check(network.longest_arrival() > 100.0, "the far stands are far")


# --- Saving ---

func test_takeoff_start_is_saved() -> void:
	ShowcaseAirport.build(0.0)
	var schedule := Airport.schedule
	var flight: Flight = null
	for i in 20000:
		Airport.step(Airport.SIM_STEP)
		for candidate in schedule.flights:
			if candidate.takeoff_booked:
				flight = candidate
		if flight != null:
			break
	check(flight != null, "a plane started its take-off run")
	if flight == null:
		return
	var number := flight.number
	var at_time := flight.takeoff_at
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	var restored: Flight = null
	for candidate in Airport.schedule.flights:
		if candidate.number == number:
			restored = candidate
	check(restored != null and restored.takeoff_booked, "the flight is back, with its take-off booked")
	if restored != null:
		check(absf(restored.takeoff_at - at_time) < 0.01, "and it starts its run at the same time")


# --- Planes are drawn along the route ---

func test_plane_follows_its_route_at_taxi_speed() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var layer := main.get_node("Planes") as PlaneLayer
	var schedule := Airport.schedule
	var flight: Flight = null
	for i in 6000:
		Airport.step(Airport.SIM_STEP)
		for candidate in schedule.flights:
			var route := schedule.route_of(candidate)
			if candidate.phase == Flight.Phase.ARRIVING and route != null \
					and candidate.departs_at() - Airport.sim_time + candidate.arrival_delay < FlightSchedule.lead_of(route) - route.roll_in_time - 2.0:
				flight = candidate
		if flight != null:
			break
	check(flight != null, "a plane is taxiing in")
	if flight == null:
		return
	var route := schedule.route_of(flight)
	var now := Airport.sim_time
	var previous := (layer._pose(flight, now) as Transform3D).origin
	var moved := 0.0
	var fastest := 0.0
	var step := 0.5
	for i in int(route.taxi_in_time / step):
		now += step
		var pose := layer._pose(flight, now) as Transform3D
		var speed := pose.origin.distance_to(previous) / step
		fastest = maxf(fastest, speed)
		moved += pose.origin.distance_to(previous)
		previous = pose.origin
		var best := INF
		var p := Vector2(pose.origin.x, pose.origin.z)
		for k in range(route.points.size() - 1):
			var a := route.points[k]
			var b := route.points[k + 1]
			var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_to(a.lerp(b, t)))
		check(best < 1.0, "the plane is on its route (%.2f m off)" % best)
		check(pose.origin.y == 0.0, "on the ground")
	check(fastest <= TaxiProfile.TAXI_SPEED + 0.3, "never faster than the taxi speed: %.1f m/s" % fastest)
	check(moved > route.length * 0.3, "and it moved along the route (%.0f of %.0f m)" % [moved, route.length])


func test_planes_are_drawn_at_real_size() -> void:
	var narrow := Flight.new()
	var wide := Flight.new()
	wide.plane_class = TimetableSlot.PlaneClass.WIDE
	check(absf(PlaneVisual.size_for(narrow) * PlaneVisual.WINGSPAN - 37.0) < 0.01, "a narrow-body is 37 m across")
	check(absf(PlaneVisual.size_for(wide) * PlaneVisual.WINGSPAN - 65.0) < 0.01, "a wide-body is 65 m across")


# --- A far stand built in the middle of the day ---

# A gate and a wide stand far to the north-east of the showcase; the taxiway that links them is
# laid separately, so the stand has no route (and no flights) until then.
func _build_far_stand() -> void:
	var catalog := Airport.CATALOG
	Airport.begin_batch()
	Airport.paint_walkway(cells(at(Vector2i(88, 31)), Vector2i(20, 3)), true)
	Airport.place_building(catalog.find(&"gate"), at(Vector2i(100, 26)), 2)
	Airport.place_building(catalog.find(&"aircraft_stand"), at(Vector2i(98, 3)), 2)
	Airport.end_batch()


func _link_far_stand() -> void:
	# Up along the east side of everything, then down to the parallel taxiway.
	Airport.paint_taxiway(cells(at(Vector2i(108, 3)), Vector2i(2, 78)), true)
	Airport.paint_taxiway(cells(at(Vector2i(106, 3)), Vector2i(4, 4)), true)
	Airport.paint_taxiway(cells(at(Vector2i(106, 79)), Vector2i(4, 2)), true)


func test_a_far_stand_built_mid_day_still_gets_its_planes_down_in_time() -> void:
	Airport.reseed(Benchmark.SEED)
	ShowcaseAirport.build(0.0)
	var schedule := Airport.schedule
	sim_seconds(1500.0)
	_build_far_stand()
	var lead_before := schedule.longest_lead()
	_link_far_stand()
	var far := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE and b.origin_cell == at(Vector2i(100, 26)))
	check_eq(far.size(), 1, "the far gate was built")
	if far.is_empty():
		return
	var gate: Building = far[0]
	var route := Airport.plane_network.route_to_stand(Airport.stand_behind(gate))
	check(route != null, "the far stand has a route now")
	check(schedule.longest_lead() > lead_before + 5.0, "it needs a longer lead: %.0f s -> %.0f s" % [lead_before, schedule.longest_lead()])
	# A slot that is already planned, closer than the far plane's lead: its plane could not land in
	# time, so it must not become a flight.
	var now := Airport.sim_time
	var slot := TimetableSlot.new()
	slot.gate = gate
	slot.plane_class = TimetableSlot.PlaneClass.NARROW
	slot.departure_time = now + FlightSchedule.lead_of(route) + FlightSchedule.APPROACH_TIME - 5.0
	var gates := Airport.usable_gates()
	check(gates.has(gate), "the far gate is usable")
	schedule._fill_slot(slot, gates, now)
	check_eq(slot.state, TimetableSlot.State.DROPPED, "the far gate does not take a flight its plane cannot reach in time")
	check_eq(schedule.flights.filter(func(f: Flight) -> bool: return f.gate == gate).size(), 0, "and no flight was made")
	# Over the following hours every flight that is made still has its touchdown ahead of it.
	var late := 0
	var seen: Dictionary[Flight, bool] = {}
	for flight in schedule.flights:
		seen[flight] = true  # planned before the stand existed: their stands did not change
	var used_far := 0
	for i in int(2400.0 / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
		var t := Airport.sim_time
		for flight in schedule.flights:
			if seen.has(flight):
				continue
			seen[flight] = true
			var r := schedule.route_of(flight)
			if r != null and flight.departs_at() - t + flight.arrival_delay < FlightSchedule.lead_of(r):
				late += 1
			if flight.gate == gate:
				used_far += 1
	check_eq(late, 0, "no flight was made too late for its plane")
	check(seen.size() > 10, "flights kept coming (%d, %d at the far gate)" % [seen.size(), used_far])


func test_routes_of_stands_added_later_are_made_by_the_rebuild() -> void:
	ShowcaseAirport.build(0.0)
	_build_far_stand()
	_link_far_stand()
	var built := Airport.plane_network.routes_built
	for stand: Building in Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.AIRCRAFT_STAND):
		Airport.plane_network.route_to_stand(stand)
	check_eq(Airport.plane_network.routes_built, built, "every stand, the later ones too, already has its route")
	sim_seconds(900.0)
	check_eq(Airport.plane_network.routes_built, built, "and the simulation made none")
