class_name PassengerFlow
extends RefCounted
## The passenger simulation (design doc §8.4, §8.5): arrivals for flights, walking, queues,
## service and boarding. Pure data: Airport calls tick() at a fixed rate and on_layout_changed()
## after layout changes. The flights themselves are planned by `schedule`.

## Walking speed in meters per second (realistic: about 1.3).
const WALK_SPEED: float = 1.3
## Largest personal sideways offset in meters (must stay below half a cell).
const MAX_OFFSET: float = 0.6
## Distance between passengers standing in a queue, in meters.
const QUEUE_SPACING: float = 0.8
## Seconds between attempts of a stuck passenger to find a way.
const RETRY_INTERVAL: float = 1.0
## How many clothing colors the visuals offer.
const COLOR_COUNT: int = 6
## Safety limit, so a layout where passengers can't leave doesn't fill up endlessly.
const MAX_PASSENGERS: int = 600

const Role := BuildingType.Role

var passengers: Array[Passenger] = []
var schedule: FlightSchedule = FlightSchedule.new()
## Simulation clock in seconds since the airport started (flights are timed against it).
var time: float = 0.0
## Passengers whose plane has left, and passengers who were too late for their flight.
var departed_count: int = 0
var missed_count: int = 0
## What is missing for a complete route, or "" if passengers can flow.
var route_problem: String = ""

var _network: WalkwayNetwork = WalkwayNetwork.new()
var _stations: Dictionary[Building, Station] = {}
var _route_entrances: Array[Building] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func status_text() -> String:
	if not route_problem.is_empty():
		return "No passenger route yet: " + route_problem
	return "Passengers: %d    Departed: %d    Missed: %d" % [passengers.size(), departed_count, missed_count]


## The next departures, one line each: number, gate, status, time to departure.
func departures_text(max_lines: int = 4) -> String:
	var phase_names := {
		Flight.Phase.SCHEDULED: "Scheduled", Flight.Phase.ARRIVING: "Plane arriving",
		Flight.Phase.AT_STAND: "At stand", Flight.Phase.BOARDING: "Boarding",
		Flight.Phase.DEPARTING: "Departed",
	}
	var lines: PackedStringArray = []
	for flight in schedule.upcoming().slice(0, max_lines):
		var seconds := maxi(ceili(flight.departure_time - time), 0)
		lines.append("%s   Gate %d   %s   %d:%02d" % [
			flight.number, gate_number(flight.gate), phase_names[flight.phase], seconds / 60, seconds % 60])
	return "\n".join(lines)


## The station of a building (check-in, security, gate), or null.
func station_for(building: Building) -> Station:
	return _stations.get(building)


## Gates are numbered in the order they were built, starting at 1.
func gate_number(gate: Building) -> int:
	var number := 0
	for building in Airport.buildings:
		if building.type.role == Role.GATE:
			number += 1
			if building == gate:
				return number
	return 0


## Gates that can have flights right now: a complete passenger route exists, and the gate has a
## walkway in front and a stand behind.
func usable_gates() -> Array[Building]:
	var gates: Array[Building] = []
	if not route_problem.is_empty():
		return gates
	for station: Station in _stations.values():
		if station.role() == Role.GATE and _is_usable_gate(station):
			gates.append(station.building)
	return gates


func on_layout_changed() -> void:
	_network.rebuild(Airport.grid)
	for building in Airport.buildings:
		if not _stations.has(building) and building.type.role in [Role.CHECK_IN, Role.SECURITY, Role.GATE]:
			_stations[building] = Station.new(building)
	for station: Station in _stations.values():
		station.entry_cells = _access_cells(station.building, true)
		station.exit_cells = _access_cells(station.building, false)
	_update_route()
	# Walkways may have changed under people's feet: everyone on the move looks for a new way.
	for passenger in passengers:
		if passenger.state == Passenger.State.WALKING or passenger.state == Passenger.State.STUCK:
			_plan(passenger)


func tick(delta: float) -> void:
	time += delta
	for passenger in passengers:
		passenger.previous_position = passenger.position
	schedule.tick(time, delta, self)
	for station: Station in _stations.values():
		_tick_station(station, delta)

	for passenger in passengers:
		match passenger.state:
			Passenger.State.WALKING:
				_walk(passenger, delta)
			Passenger.State.STUCK:
				passenger.retry_in -= delta
				if passenger.retry_in <= 0.0:
					_plan(passenger)


# --- Arrivals and departures (called by the schedule) ---

## A passenger for `flight` arrives at an entrance. Returns false if nobody can arrive right now.
func spawn_passenger(flight: Flight) -> bool:
	if not route_problem.is_empty() or _route_entrances.is_empty() or passengers.size() >= MAX_PASSENGERS:
		return false
	var entrance := _route_entrances[_rng.randi() % _route_entrances.size()]
	var cells := _access_cells(entrance, false)
	if cells.is_empty():
		return false
	var passenger := Passenger.new()
	passenger.flight = flight
	passenger.offset = Vector3(_rng.randf_range(-MAX_OFFSET, MAX_OFFSET), 0.0, _rng.randf_range(-MAX_OFFSET, MAX_OFFSET))
	passenger.color_index = _rng.randi() % COLOR_COUNT
	passenger.position = _cell_point(cells[_rng.randi() % cells.size()], passenger)
	passenger.previous_position = passenger.position
	passenger.goal = Role.CHECK_IN
	passengers.append(passenger)
	_plan(passenger)
	return true


## Lets up to `max_count` passengers of `flight` walk from the gate onto the plane.
## Returns how many boarded.
func board(flight: Flight, max_count: int) -> int:
	if max_count <= 0 or not _stations.has(flight.gate):
		return 0
	var station := _stations[flight.gate]
	var boarding: Array[Passenger] = []
	for passenger in station.waiting:
		if passenger.flight == flight and boarding.size() < max_count:
			boarding.append(passenger)
	if boarding.is_empty():
		return 0
	_remove(boarding)
	flight.boarded += boarding.size()
	return boarding.size()


## Removes every passenger of `flight` still in the airport (doors closed or flight cancelled).
## Missed passengers are counted. Returns how many were removed.
func remove_flight_passengers(flight: Flight, count_as_missed: bool) -> int:
	var leaving := passengers.filter(func(p: Passenger) -> bool: return p.flight == flight)
	_remove(leaving)
	if count_as_missed:
		missed_count += leaving.size()
	return leaving.size()


# Takes passengers out of the airport, including any queue, counter or gate they are at.
func _remove(leaving: Array) -> void:
	var gone: Dictionary[Passenger, bool] = {}
	for passenger: Passenger in leaving:
		gone[passenger] = true
	var still_here := func(p: Passenger) -> bool: return not gone.has(p)
	passengers = passengers.filter(still_here)
	for station: Station in _stations.values():
		station.queue = station.queue.filter(still_here)
		station.waiting = station.waiting.filter(still_here)
		for i in station.serving.size():
			if gone.has(station.serving[i]):
				station.serving[i] = null


# --- Choosing a station and walking there ---

func _plan(passenger: Passenger) -> void:
	passenger.target = null
	var cell := Airport.grid.world_to_cell(passenger.position)
	if not _network.is_walkable(cell):
		var nearest: Variant = _network.nearest_walkable(cell)
		if nearest == null:
			_set_stuck(passenger)
			return
		cell = nearest
	var area := _network.area_of(cell)

	var candidates: Array[Station] = []
	var candidate_cells: Array[Vector2i] = []
	for station: Station in _stations.values():
		if station.role() != passenger.goal:
			continue
		if passenger.goal == Role.GATE and station.building != passenger.flight.gate:
			continue
		var entry: Variant = _closest_cell_in_area(station.entry_cells, cell, area)
		if entry != null:
			candidates.append(station)
			candidate_cells.append(entry)
	if candidates.is_empty():
		_set_stuck(passenger)
		return

	# Short queue and short walk both count, like real passengers judging a hall.
	# (For the gate there is only one candidate: the gate of their flight.)
	var choice := 0
	var best_score := INF
	for i in candidates.size():
		var score := candidates[i].busyness() * 3.0 + Vector2(candidate_cells[i] - cell).length() / 4.0
		if score < best_score:
			best_score = score
			choice = i

	var cells := _network.find_path(cell, candidate_cells[choice])
	if cells.is_empty():
		_set_stuck(passenger)
		return
	passenger.path = PackedVector3Array()
	for path_cell in cells:
		passenger.path.append(_cell_point(path_cell, passenger))
	passenger.path_index = 0
	passenger.target = candidates[choice].building
	passenger.state = Passenger.State.WALKING


func _walk(passenger: Passenger, delta: float) -> void:
	var step := WALK_SPEED * delta
	while step > 0.0 and passenger.path_index < passenger.path.size():
		var to_target := passenger.path[passenger.path_index] - passenger.position
		var distance := to_target.length()
		if distance <= step:
			passenger.position = passenger.path[passenger.path_index]
			passenger.path_index += 1
			step -= distance
		else:
			passenger.position += to_target / distance * step
			step = 0.0
	if passenger.path_index >= passenger.path.size():
		_arrive(passenger)


func _arrive(passenger: Passenger) -> void:
	var station := _stations[passenger.target]
	if station.role() == Role.GATE:
		passenger.state = Passenger.State.AT_GATE
		station.waiting.append(passenger)
	else:
		passenger.state = Passenger.State.QUEUING
		station.queue.append(passenger)


func _set_stuck(passenger: Passenger) -> void:
	passenger.state = Passenger.State.STUCK
	passenger.target = null
	passenger.retry_in = RETRY_INTERVAL


# --- Stations ---

func _tick_station(station: Station, delta: float) -> void:
	if station.role() == Role.GATE:
		return  # boarding is driven by the flight schedule

	station.sync_slots()
	for i in station.serving.size():
		var served := station.serving[i]
		if served != null:
			station.service_left[i] -= delta
			# A security lane with no airside exit is blocked: passengers wait there until it opens.
			var blocked := station.role() == Role.SECURITY and station.exit_cells.is_empty()
			if station.service_left[i] <= 0.0 and not blocked:
				station.serving[i] = null
				_finish_service(station, served)
		if station.serving[i] == null and not station.queue.is_empty():
			var next: Passenger = station.queue.pop_front()
			next.state = Passenger.State.IN_SERVICE
			station.serving[i] = next
			# Some passengers are quicker than others.
			station.service_left[i] = station.building.service_time() * _rng.randf_range(0.75, 1.25)

	for k in station.queue.size():
		_move_towards(station.queue[k], _queue_spot(station, k), delta)
	for i in station.serving.size():
		if station.serving[i] != null:
			_move_towards(station.serving[i], _desk_spot(station, i), delta)


func _finish_service(station: Station, passenger: Passenger) -> void:
	match station.role():
		Role.CHECK_IN:
			passenger.goal = Role.SECURITY
			_plan(passenger)
		Role.SECURITY:
			passenger.goal = Role.GATE
			# Through the security lane to the airside: appear behind the building.
			var exit: Vector2i = _closest_cell_in_area(station.exit_cells, Airport.grid.world_to_cell(passenger.position), -1)
			passenger.position = _cell_point(exit, passenger)
			passenger.previous_position = passenger.position
			_plan(passenger)


# Queues form straight lines in front of the counters, one line per counter.
func _queue_spot(station: Station, index: int) -> Vector3:
	var lanes := _lane_count(station)
	return _lane_base(station, index % lanes) + station.outward * (0.3 + (index / lanes) * QUEUE_SPACING)


func _desk_spot(station: Station, slot: int) -> Vector3:
	return _lane_base(station, slot % _lane_count(station)) - station.outward * 0.5


func _lane_count(station: Station) -> int:
	return clampi(station.serving.size(), 1, maxi(station.entry_cells.size(), 1))


func _lane_base(station: Station, lane: int) -> Vector3:
	var cells := station.entry_cells
	if cells.is_empty():
		var type := station.building.type
		var size := Building.rotated_size(type.footprint, station.building.rotation_steps)
		return Airport.grid.block_center(station.building.origin_cell, size)
	var index := int((lane + 0.5) * cells.size() / _lane_count(station))
	return Airport.grid.cell_to_world(cells[index])


func _move_towards(passenger: Passenger, target: Vector3, delta: float) -> void:
	var to_target := target - passenger.position
	var step := WALK_SPEED * delta
	if to_target.length() <= step:
		passenger.position = target
	else:
		passenger.position += to_target.normalized() * step


# --- Layout helpers ---

# Walkable cells along one side of a building that are in the zone that side needs.
func _access_cells(building: Building, front: bool) -> Array[Vector2i]:
	var type := building.type
	var side_zone := AirportGrid.Zone.LANDSIDE
	if type.zone_rule == BuildingType.ZoneRule.AIRSIDE:
		side_zone = AirportGrid.Zone.AIRSIDE
	elif type.zone_rule == BuildingType.ZoneRule.BORDER and not front:
		side_zone = AirportGrid.Zone.AIRSIDE
	var cells: Array[Vector2i] = []
	for cell in Building.outside_row(type.footprint, building.origin_cell, building.rotation_steps, front):
		if _network.is_walkable(cell) and Airport.grid.get_zone(cell) == side_zone:
			cells.append(cell)
	return cells


func _is_usable_gate(station: Station) -> bool:
	var building := station.building
	return Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps).is_empty()


# The cell in `cells` closest to `from`, only counting cells in `area` (-1 = any area).
func _closest_cell_in_area(cells: Array[Vector2i], from: Vector2i, area: int) -> Variant:
	var best: Variant = null
	var best_distance := INF
	for cell in cells:
		if area >= 0 and _network.area_of(cell) != area:
			continue
		var distance := Vector2(cell - from).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


func _cell_point(cell: Vector2i, passenger: Passenger) -> Vector3:
	return Airport.grid.cell_to_world(cell) + passenger.offset


# Checks, step by step like a passenger, whether Entrance -> Check-in -> Security -> Gate works.
func _update_route() -> void:
	_route_entrances.clear()
	var entrance_areas: Dictionary[int, bool] = {}
	var has_entrance := false
	for building in Airport.buildings:
		if building.type.role == Role.ENTRANCE:
			has_entrance = true
			for cell in _access_cells(building, false):
				entrance_areas[_network.area_of(cell)] = true
	if not has_entrance:
		route_problem = "build an entrance."
		return
	if entrance_areas.is_empty():
		route_problem = "connect the entrance's back to a walkway."
		return

	var check_in_areas := _station_areas(Role.CHECK_IN, true).filter(func(a: int) -> bool: return entrance_areas.has(a))
	if check_in_areas.is_empty():
		route_problem = "connect a check-in (front) to the entrance's walkway."
		return

	var gate_areas: Array[int] = []
	for station: Station in _stations.values():
		if station.role() == Role.GATE and _is_usable_gate(station):
			for cell in station.entry_cells:
				gate_areas.append(_network.area_of(cell))

	var good_areas: Dictionary[int, bool] = {}
	var security_reached := false
	for station: Station in _stations.values():
		if station.role() != Role.SECURITY:
			continue
		var front_areas := station.entry_cells.map(func(c: Vector2i) -> int: return _network.area_of(c))
		var reached := front_areas.filter(func(a: int) -> bool: return check_in_areas.has(a))
		if reached.is_empty():
			continue
		security_reached = true
		if station.exit_cells.any(func(c: Vector2i) -> bool: return gate_areas.has(_network.area_of(c))):
			for area: int in reached:
				good_areas[area] = true
	if not security_reached:
		route_problem = "connect security's front to the check-in walkway."
		return
	if good_areas.is_empty():
		route_problem = "connect a gate (with a stand behind it) to security's airside walkway."
		return

	route_problem = ""
	for building in Airport.buildings:
		if building.type.role == Role.ENTRANCE:
			if _access_cells(building, false).any(func(c: Vector2i) -> bool: return good_areas.has(_network.area_of(c))):
				_route_entrances.append(building)


func _station_areas(role: BuildingType.Role, front: bool) -> Array[int]:
	var areas: Array[int] = []
	for station: Station in _stations.values():
		if station.role() == role:
			for cell in (station.entry_cells if front else station.exit_cells):
				areas.append(_network.area_of(cell))
	return areas
