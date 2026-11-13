class_name PassengerFlow
extends RefCounted
## The passenger simulation (design doc §8.4, §8.5): arrivals for flights, walking, queues,
## service and boarding. Pure data: Airport calls tick() at a fixed rate and on_layout_changed()
## after layout changes. The flights themselves are planned by `schedule`.

## Walking speed in meters per second when a passenger has no type (realistic: about 1.3).
const WALK_SPEED: float = 1.3
## Largest personal sideways offset in meters (must stay below half a cell).
const MAX_OFFSET: float = 0.6
## Distance between passengers standing in a queue, in meters.
const QUEUE_SPACING: float = 0.8
## Seconds between attempts of a stuck passenger to find a way.
const RETRY_INTERVAL: float = 1.0
## Shops and cafés (design doc §8.6): passengers go only with at least this much time to spare
## before boarding opens, and then with this probability.
const SHOPPING_MIN_SPARE: float = 45.0
## Before security, passengers are less likely to sit in a landside café (share of their shop chance).
## (How likely a visit is before each step, and the time kept free after it, live in data/journeys/.)
## Arriving passengers without a checked bag still take this long to walk through baggage claim.
const PASS_THROUGH_TIME: float = 3.0
## Customers leave a shop this long before boarding opens at the latest ("final call").
const FINAL_CALL: float = 15.0
## Satisfaction (design doc §8.10): mood points lost per second in a queue beyond the type's
## patience, per second waiting for a bag beyond BAG_PATIENCE, per meter walked beyond
## WALK_TOLERANCE, and per second without a way to go on.
const QUEUE_PENALTY: float = 0.5
const BAG_PATIENCE: float = 60.0
const BAG_PENALTY: float = 0.3
const WALK_TOLERANCE: float = 150.0
const WALK_PENALTY: float = 0.1
const STUCK_PENALTY: float = 1.0
## The manager standing at a station (design doc §15.1): staff need this share of their usual
## time, and waiting costs this share of the usual mood (someone keeps the queue informed).
const PRESENCE_TIME_FACTOR: float = 0.9
const PRESENCE_CALM: float = 0.5
## Mood gained by a visit to a shop or café.
const SHOP_BONUS: float = 5.0
## Unhappy customers spend less: spending at mood 0 and at mood 100 (share of the normal amount).
const SPEND_AT_WORST: float = 0.5
const SPEND_AT_BEST: float = 1.1
## Car park, lounge and fast track (design doc §11.8).
const CAR_SHARE: float = 0.35
const PARKING_FEE: float = 8.0
const LOUNGE_CHANCE: float = 0.8
const LOUNGE_BONUS: float = 10.0
const FAST_TRACK_FEE: float = 5.0
## Roles of buildings that get a Station (queues, customers or statistics).
const STATION_ROLES: Array[BuildingType.Role] = [Role.CHECK_IN, Role.SECURITY, Role.TRANSFER_SECURITY, Role.GATE,
	Role.SHOP, Role.LOUNGE, Role.BAGGAGE_CLAIM, Role.CAR_PARK]
## How many clothing colors the visuals offer.
const COLOR_COUNT: int = 6
## Safety limit, so a layout where passengers can't leave doesn't fill up endlessly.
const MAX_PASSENGERS: int = 600
## The airport this part of the simulation works for; set by the Airport autoload.
var world: AirportWorld

## The limit in use (the device benchmark raises it, see scripts/dev/benchmark.gd).
var max_passengers: int = MAX_PASSENGERS

const Role := BuildingType.Role
## The journeys (tech architecture §5): the order of stations lives in these data files.
const DEPARTURE: JourneyRecipe = preload("res://data/journeys/departure.tres")
const ARRIVAL: JourneyRecipe = preload("res://data/journeys/arrival.tres")
const TRANSFER: JourneyRecipe = preload("res://data/journeys/transfer.tres")

var passengers: Array[Passenger] = []
var schedule: FlightSchedule = FlightSchedule.new()
## Simulation clock in seconds since the airport started (flights are timed against it).
var time: float = 0.0
## Passengers whose plane has left, and passengers who were too late for their flight.
var departed_count: int = 0
var missed_count: int = 0
## Arriving passengers who have left the airport (design doc §8.8).
var arrived_count: int = 0
## Transfer passengers who boarded their connecting flight (design doc §8.9).
var transferred_count: int = 0
## True while a working transfer security lets the airport sell connections.
var transfers_possible: bool = false
## Tests only: if 0 or more, replaces every route's transfer share.
var transfer_share_override: float = -1.0
## How happy passengers leave the airport (design doc §8.10).
var satisfaction: Satisfaction = Satisfaction.new()
## What is missing for a complete route, or "" if passengers can flow.
var route_problem: String = ""

var _network: WalkwayNetwork = WalkwayNetwork.new()
var _stations: Dictionary[Building, Station] = {}
# Role -> its stations, in the order of `_stations`; rebuilt whenever a station is added or removed.
# Planning a walk looks only at stations of the goal's kind instead of scanning all of them.
var _stations_by_role: Dictionary[int, Array] = {}
# Set when a passenger leaves (GONE), so the list is only cleaned up when needed.
var _someone_gone: bool = false
var _route_entrances: Array[Building] = []
# Car parks connected to the passenger route (design doc §11.8).
var _route_car_parks: Array[Building] = []
var _usable_gates: Array[Building] = []
var _usable_cargo_terminals: Array[Building] = []
var _sample_timer: float = 0.0
## Dice. Airport replaces them with its shared, seeded dice (tech_architecture.md §3).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func status_text() -> String:
	if not route_problem.is_empty():
		return "No passenger route yet: " + route_problem
	return "Passengers: %d    Departed: %d    Arrived: %d    Missed: %d" % [passengers.size(), departed_count, arrived_count, missed_count]


## The next departures, one line each: number, gate, status, time to departure.
func departures_text(max_lines: int = 4) -> String:
	var phase_names := {
		Flight.Phase.SCHEDULED: "Scheduled", Flight.Phase.ARRIVING: "Plane arriving",
		Flight.Phase.AT_STAND: "At stand", Flight.Phase.BOARDING: "Boarding",
		Flight.Phase.DEPARTING: "Departed",
	}
	var lines: PackedStringArray = []
	if schedule.flights.is_empty() and world.curfew_at():
		lines.append("Night curfew: no flights until %02d:00" % int(Clock.CURFEW_END))
	for flight in schedule.upcoming().slice(0, max_lines):
		var seconds := maxi(ceili(flight.departs_at() - time), 0)
		var status: String = phase_names[flight.phase]
		if flight.delay > 0.0 and flight.phase == Flight.Phase.BOARDING:
			status = "Delayed"
		var where := "Cargo" if flight.cargo else "Gate %d" % gate_number(flight.gate)
		lines.append("%s   %s   %s   %s   %d:%02d" % [
			flight.number, where, "Freighter" if flight.cargo else flight.route, status, seconds / 60, seconds % 60])
	return "\n".join(lines)


## The station of a building (check-in, security, gate), or null.
func station_for(building: Building) -> Station:
	return _stations.get(building)


## Every station in a stable order: check-ins, security, gates, each in the order they were built.
func stations() -> Array[Station]:
	var result: Array[Station] = []
	for role in [Role.CHECK_IN, Role.SECURITY, Role.TRANSFER_SECURITY, Role.GATE, Role.SHOP, Role.LOUNGE, Role.BAGGAGE_CLAIM, Role.CAR_PARK]:
		for building in world.buildings:
			if building.type.role == role and _stations.has(building):
				result.append(_stations[building])
	return result


## "Check-in 2", or just "Security" when there is only one of a kind.
func station_label(building: Building) -> String:
	var same_kind := world.buildings.filter(func(b: Building) -> bool: return b.type == building.type)
	if same_kind.size() == 1:
		return building.type.display_name
	return "%s %d" % [building.type.display_name, same_kind.find(building) + 1]


## The check-in or security with the longest average wait (at least `min_wait` seconds), or null.
func bottleneck(min_wait: float = 5.0) -> Station:
	var worst: Station = null
	var worst_wait := min_wait
	for station: Station in _stations.values():
		if station.role() in [Role.GATE, Role.SHOP, Role.LOUNGE, Role.BAGGAGE_CLAIM, Role.CAR_PARK]:
			continue  # waiting there is part of the visit, not a queue
		var wait := station.average_wait(time)
		if wait >= worst_wait:
			worst_wait = wait
			worst = station
	return worst


## Gates are numbered in the order they were built, starting at 1.
func gate_number(gate: Building) -> int:
	var number := 0
	for building in world.buildings:
		if building.type.role == Role.GATE:
			number += 1
			if building == gate:
				return number
	return 0


## Gates that can have flights right now: a complete passenger route exists, and the gate has a
## walkway in front and a stand behind.
## Cached: recalculated with the route after layout and staff changes (asked several times per step).
func usable_gates() -> Array[Building]:
	return _usable_gates


func _find_usable_gates() -> Array[Building]:
	var gates: Array[Building] = []
	if not route_problem.is_empty():
		return gates
	for station: Station in _stations.values():
		if station.role() == Role.GATE and _is_usable_gate(station):
			gates.append(station.building)
	return gates


func _rebuild_station_index() -> void:
	_stations_by_role.clear()
	for station: Station in _stations.values():
		var role := int(station.role())
		if not _stations_by_role.has(role):
			_stations_by_role[role] = []
		(_stations_by_role[role] as Array).append(station)


func on_layout_changed() -> void:
	_network.rebuild(world.grid)
	for building in world.buildings:
		if not _stations.has(building) and building.type.role in STATION_ROLES:
			_stations[building] = Station.new(building)
	for station: Station in _stations.values():
		# Baggage claim is used the other way round than security: in from airside (its back).
		var reversed := station.role() == Role.BAGGAGE_CLAIM
		station.entry_cells = _access_cells(station.building, not reversed)
		station.exit_cells = _access_cells(station.building, reversed)
	_rebuild_station_index()
	_update_route()
	# Walkways may have changed under people's feet: everyone on the move looks for a new way.
	for passenger in passengers:
		if passenger.state == Passenger.State.WALKING or passenger.state == Passenger.State.STUCK:
			_plan(passenger)


## Flights, passengers and queues as plain data for the save game (tech_architecture.md §13).
## Buildings are stored by permanent ID; a passenger's flight is an index into "flights".
## Not saved: the statistics windows of the stations (they refill within minutes).
func save_state() -> Dictionary:
	var referenced: Array[Flight] = []
	for passenger in passengers:
		if passenger.flight != null and not referenced.has(passenger.flight):
			referenced.append(passenger.flight)
	var schedule_data := schedule.save_state(referenced)
	var flight_index: Dictionary[Flight, int] = {}
	var all_flights: Array[Flight] = schedule.flights.duplicate()
	for flight in referenced:
		if not all_flights.has(flight):
			all_flights.append(flight)
	for i in all_flights.size():
		flight_index[all_flights[i]] = i
	var passenger_index: Dictionary[Passenger, int] = {}
	var records: Array[Dictionary] = []
	for passenger in passengers:
		passenger_index[passenger] = records.size()
		records.append({
			"state": int(passenger.state), "flight": flight_index.get(passenger.flight, -1),
			"type": String(passenger.type.id) if passenger.type != null else "",
			"arriving": passenger.is_arriving, "transfer": passenger.is_transfer,
			"by_car": passenger.by_car, "has_bag": passenger.has_bag, "bag_ready_at": passenger.bag_ready_at,
			"goal": int(passenger.goal), "target": passenger.target.id if passenger.target != null else 0,
			"position": passenger.position, "offset": passenger.offset,
			"path": passenger.path.slice(passenger.path_index),
			"color": passenger.color_index, "queued_since": passenger.queued_since,
			"visit_left": passenger.visit_left, "after_shop": int(_resume_role(passenger)),
			"leave_shop_by": passenger.leave_shop_by, "mood": passenger.mood,
			"walked": passenger.walked, "retry_in": passenger.retry_in,
		})
	var saved_stations: Array[Dictionary] = []
	for station: Station in _stations.values():
		var serving: Array = []
		for i in station.serving.size():
			serving.append([passenger_index[station.serving[i]], station.service_left[i]] \
				if station.serving[i] != null and passenger_index.has(station.serving[i]) else null)
		saved_stations.append({
			"building": station.building.id,
			"queue": station.queue.filter(func(p: Passenger) -> bool: return passenger_index.has(p)).map(func(p: Passenger) -> int: return passenger_index[p]),
			"serving": serving,
			"waiting": station.waiting.filter(func(p: Passenger) -> bool: return passenger_index.has(p)).map(func(p: Passenger) -> int: return passenger_index[p]),
		})
	return {
		"time": time, "sample_timer": _sample_timer, "departed": departed_count, "missed": missed_count,
		"arrived": arrived_count, "transferred": transferred_count,
		"schedule": schedule_data, "passengers": PassengerSave.encode(records, world.grid.size.x),
		"stations": saved_stations,
	}


## Restores from save_state() once the buildings are back (`by_id`: saved ID -> building).
## Anything that points at a building that is gone is dropped: a passenger can't stand at a
## station that no longer exists.
func load_state(data: Dictionary, by_id: Dictionary[int, Building]) -> void:
	time = float(data.get("time", 0.0))
	_sample_timer = float(data.get("sample_timer", 0.0))
	departed_count = int(data.get("departed", 0))
	missed_count = int(data.get("missed", 0))
	arrived_count = int(data.get("arrived", 0))
	transferred_count = int(data.get("transferred", 0))
	var flights := schedule.load_state(data.get("schedule", {}), by_id)
	# Save format 6 packs the passengers; an old list (not converted by SaveGame) is read as well.
	var saved: Variant = data.get("passengers", {})
	var width := world.grid.size.x
	var records: Array[Dictionary] = []
	if saved is Dictionary:
		records = PassengerSave.decode(saved)
		width = int((saved as Dictionary).get("grid_width", width))
	elif saved is Array:
		records = PassengerSave.from_v5(saved, world.grid.size, world.grid.cell_size)
	# Saved index -> loaded passenger (dropped ones are missing).
	var loaded: Dictionary[int, Passenger] = {}
	passengers.clear()
	for i in records.size():
		var entry: Dictionary = records[i]
		var flight: Flight = flights.get(int(entry["flight"]))
		if flight == null:
			continue
		var passenger := Passenger.new()
		passenger.flight = flight
		passenger.state = clampi(int(entry["state"]), 0, Passenger.State.STUCK) as Passenger.State
		passenger.type = FlightSchedule.type_by_id(StringName(entry["type"]))
		passenger.is_arriving = entry["arriving"]
		passenger.is_transfer = entry["transfer"]
		passenger.by_car = entry["by_car"]
		passenger.has_bag = entry["has_bag"]
		passenger.bag_ready_at = entry["bag_ready_at"]
		passenger.goal = int(entry["goal"]) as Role
		passenger.target = by_id.get(int(entry["target"]))
		passenger.position = entry["position"]
		# tick() sets this from the position at the start of every step anyway.
		passenger.previous_position = passenger.position
		passenger.offset = entry["offset"]
		# Only the way still ahead is saved; it starts again from its first cell.
		passenger.path = PassengerSave.remap_path(entry["path"], width, world.grid.size)
		passenger.path_index = 0
		passenger.color_index = int(entry["color"])
		passenger.queued_since = entry["queued_since"]
		passenger.visit_left = entry["visit_left"]
		passenger.leave_shop_by = entry["leave_shop_by"]
		_restore_journey(passenger, int(entry["after_shop"]) as Role)
		passenger.mood = entry["mood"]
		passenger.walked = entry["walked"]
		passenger.retry_in = entry["retry_in"]
		loaded[i] = passenger
		passengers.append(passenger)
	# Put the passengers back into their queues, counters and waiting rooms.
	var placed: Dictionary[Passenger, bool] = {}
	for entry: Dictionary in data.get("stations", []):
		var building: Building = by_id.get(int(entry.get("building", 0)))
		if building == null or not _stations.has(building):
			continue
		var station := _stations[building]
		station.sync_slots()
		for index in entry.get("queue", []):
			if loaded.has(int(index)):
				station.queue.append(loaded[int(index)])
				placed[loaded[int(index)]] = true
		var serving: Array = entry.get("serving", [])
		for i in mini(serving.size(), station.serving.size()):
			if serving[i] != null and loaded.has(int(serving[i][0])):
				station.serving[i] = loaded[int(serving[i][0])]
				station.service_left[i] = float(serving[i][1])
				placed[station.serving[i]] = true
		for index in entry.get("waiting", []):
			if loaded.has(int(index)):
				station.waiting.append(loaded[int(index)])
				placed[loaded[int(index)]] = true
	var lost: Array[Passenger] = []
	for passenger in passengers:
		match passenger.state:
			Passenger.State.QUEUING, Passenger.State.IN_SERVICE, Passenger.State.AT_GATE, \
					Passenger.State.IN_SHOP, Passenger.State.AT_BELT:
				if not placed.has(passenger):
					lost.append(passenger)  # their station is gone
			Passenger.State.WALKING:
				if passenger.target == null or not _stations.has(passenger.target) or passenger.path.is_empty():
					_plan(passenger)
	if not lost.is_empty():
		_remove(lost)


func tick(delta: float) -> void:
	time += delta
	for passenger in passengers:
		passenger.previous_position = passenger.position
	schedule.tick(time, delta, self)
	for station: Station in _stations.values():
		_tick_station(station, delta)
	_sample_timer += delta
	while _sample_timer >= 1.0:
		_sample_timer -= 1.0
		for station: Station in _stations.values():
			station.record_sample()
		satisfaction.tick_second()

	for passenger in passengers:
		match passenger.state:
			Passenger.State.WALKING:
				_walk(passenger, delta)
			Passenger.State.STUCK:
				_lose_mood(passenger, Satisfaction.NO_WAY, STUCK_PENALTY * delta)
				passenger.retry_in -= delta
				if passenger.retry_in <= 0.0:
					_plan(passenger)
	if _someone_gone:
		_someone_gone = false
		# Compact in place, keeping the order (the order decides who rolls the dice first).
		var kept := 0
		for passenger in passengers:
			if passenger.state != Passenger.State.GONE:
				passengers[kept] = passenger
				kept += 1
		passengers.resize(kept)


# --- Arrivals and departures (called by the schedule) ---

## A passenger of `type` for `flight` arrives at an entrance. Returns false if nobody can arrive.
func spawn_passenger(flight: Flight, type: PassengerType) -> bool:
	if not route_problem.is_empty() or _route_entrances.is_empty() or passengers.size() >= max_passengers:
		return false
	# Car travellers park for their trip, if there is a car park (design doc §11.8).
	var by_car := not _route_car_parks.is_empty() and rng.randf() < CAR_SHARE
	var cells: Array[Vector2i] = []
	if by_car:
		cells = _access_cells(_route_car_parks[rng.randi() % _route_car_parks.size()], true)
	else:
		cells = _access_cells(_route_entrances[rng.randi() % _route_entrances.size()], false)
	if cells.is_empty():
		return false
	var passenger := Passenger.new()
	passenger.flight = flight
	passenger.type = type
	passenger.offset = Vector3(rng.randf_range(-MAX_OFFSET, MAX_OFFSET), 0.0, rng.randf_range(-MAX_OFFSET, MAX_OFFSET))
	passenger.color_index = rng.randi() % COLOR_COUNT
	passenger.position = _cell_point(cells[rng.randi() % cells.size()], passenger)
	passenger.previous_position = passenger.position
	# Online check-in with hand luggage only: straight to security.
	passenger.recipe = DEPARTURE
	passenger.step = DEPARTURE.index_of(Role.SECURITY) if rng.randf() < type.skip_check_in_chance else 0
	passenger.goal = DEPARTURE.role_at(passenger.step)
	passengers.append(passenger)
	_plan(passenger)
	return true


## How many passengers of each type are in the airport right now ("Families" -> 12).
func count_by_type() -> Dictionary:
	var counts := {}
	for passenger in passengers:
		var name := passenger.type.display_name if passenger.type != null else "Other"
		counts[name] = counts.get(name, 0) + 1
	return counts


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
	for passenger in boarding:
		_finish_journey(passenger)
	flight.boarded += boarding.size()
	var transfers := boarding.filter(func(p: Passenger) -> bool: return p.is_transfer).size()
	transferred_count += transfers
	world.progression.transfers += transfers
	return boarding.size()


## True while passengers of departing `flight` are airside on their way to its gate, or waiting
## there to board: the flight holds its doors for them (design doc §11.7).
func is_anyone_coming(flight: Flight) -> bool:
	for passenger in passengers:
		if passenger.flight != flight or passenger.is_arriving:
			continue
		# On a step the flight waits for (also while on a detour back to it).
		if passenger.recipe == null:
			push_warning("A passenger without a journey recipe was found.")
		elif passenger.recipe.step_at(passenger.step).holds_flight:
			return true
	return false


## Re-checks the passenger route (and whether connections can be sold), e.g. after hiring.
func refresh_route() -> void:
	_update_route()


## How many transfer passengers are in the airport right now.
func transferring_count() -> int:
	return passengers.filter(func(p: Passenger) -> bool: return p.is_transfer).size()


## An arriving passenger of `type` leaves `flight`'s parked plane through the gate (design doc §8.8).
## Returns false if they can't get off right now (no walkway in front of the gate).
func deplane_passenger(flight: Flight, type: PassengerType) -> bool:
	var gate := _stations.get(flight.gate) as Station
	if gate == null or gate.entry_cells.is_empty():
		return false
	var passenger := Passenger.new()
	passenger.flight = flight
	passenger.type = type
	passenger.is_arriving = true
	passenger.has_bag = rng.randf() < type.checked_bag_chance
	passenger.by_car = rng.randf() < CAR_SHARE
	var parked_at := flight.departs_at() + flight.arrival_delay - (FlightSchedule.PLANE_ARRIVES - FlightSchedule.TAXI_TIME)
	passenger.bag_ready_at = parked_at + rng.randf_range(FlightSchedule.BAGS_FROM, FlightSchedule.BAGS_UNTIL)
	passenger.offset = Vector3(rng.randf_range(-MAX_OFFSET, MAX_OFFSET), 0.0, rng.randf_range(-MAX_OFFSET, MAX_OFFSET))
	passenger.color_index = rng.randi() % COLOR_COUNT
	passenger.position = _cell_point(gate.entry_cells[rng.randi() % gate.entry_cells.size()], passenger)
	passenger.previous_position = passenger.position
	passenger.recipe = ARRIVAL
	passenger.goal = ARRIVAL.role_at(0)
	# Some connect to another flight (design doc §8.9), if the airport can handle transfers.
	var connection := _connecting_flight(flight)
	if connection != null:
		passenger.is_arriving = false
		passenger.is_transfer = true
		passenger.flight = connection
		passenger.recipe = TRANSFER
		passenger.goal = TRANSFER.role_at(0)
	passengers.append(passenger)
	_plan(passenger)
	return true


# A connecting flight for a passenger coming off `inbound`, or null if they end their journey here.
func _connecting_flight(inbound: Flight) -> Flight:
	if not transfers_possible:
		return null
	var share: float = FlightSchedule.TRANSFER_SHARES.get(inbound.route, 0.0)
	if world.progression.tier == Progression.Tier.HUB:
		share *= Progression.HUB_TRANSFER_FACTOR
	if transfer_share_override >= 0.0:
		share = transfer_share_override
	if rng.randf() >= share:
		return null
	var options := schedule.flights.filter(func(f: Flight) -> bool:
		return f != inbound and not f.cargo and f.is_active() and f.departure_time >= time + FlightSchedule.MIN_CONNECTION)
	return options[rng.randi() % options.size()] if not options.is_empty() else null


## A building was demolished (design doc §7.6): its passengers look for another station of the
## same kind; shop customers carry on. Flights at a demolished gate or stand are cancelled by the
## schedule on its next step (the gate is no longer usable).
func remove_building(building: Building) -> void:
	var station := _stations.get(building) as Station
	if station == null:
		return
	_stations.erase(building)
	_rebuild_station_index()
	var displaced: Array[Passenger] = []
	displaced.append_array(station.queue)
	displaced.append_array(station.waiting)
	for passenger in station.serving:
		if passenger != null:
			displaced.append(passenger)
	for passenger in displaced:
		if passenger.state == Passenger.State.IN_SHOP:
			_end_detour(passenger)
		passenger.state = Passenger.State.WALKING
		# Step out of the building onto the nearest walkway before looking for a new way.
		if not station.entry_cells.is_empty():
			var door: Vector2i = _closest_cell_in_area(station.entry_cells, world.grid.world_to_cell(passenger.position), -1)
			passenger.position = _cell_point(door, passenger)
			passenger.previous_position = passenger.position
	# Everyone on their way to it, or just displaced, finds a new way after the layout update.
	for passenger in passengers:
		if passenger.target == building:
			passenger.target = null
			passenger.state = Passenger.State.WALKING


## Removes every departing passenger of `flight` still in the airport (doors closed or flight
## cancelled). Arriving passengers of that plane are already on their way out and stay.
## Missed passengers are counted. Returns how many were removed.
func remove_flight_passengers(flight: Flight, count_as_missed: bool) -> int:
	var leaving := passengers.filter(func(p: Passenger) -> bool: return p.flight == flight and not p.is_arriving)
	_remove(leaving)
	if count_as_missed:
		missed_count += leaving.size()
		for passenger: Passenger in leaving:
			# Missing the flight ruins the trip, whatever happened before.
			_lose_mood(passenger, Satisfaction.MISSED, passenger.mood)
			_finish_journey(passenger, Satisfaction.MISSED_WEIGHT)
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
	if _is_leaving(passenger):
		_plan_exit(passenger)
		return
	var cell := world.grid.world_to_cell(passenger.position)
	if not _network.is_walkable(cell):
		var nearest: Variant = _network.nearest_walkable(cell)
		if nearest == null:
			_set_stuck(passenger)
			return
		cell = nearest
	var area := _network.area_of(cell)

	var candidates: Array[Station] = []
	var candidate_cells: Array[Vector2i] = []
	for station: Station in _stations_by_role.get(int(passenger.goal), []):
		if passenger.goal == Role.GATE and station.building != passenger.flight.gate:
			continue
		if _in_detour(passenger) and not _has_room(station):
			continue
		var entry: Variant = _closest_cell_in_area(station.entry_cells, cell, area)
		if entry != null:
			candidates.append(station)
			candidate_cells.append(entry)
	if candidates.is_empty():
		if _in_detour(passenger):
			# No shop (or lounge) with room nearby: carry on instead.
			_end_detour(passenger)
			_plan(passenger)
			return
		_set_stuck(passenger)
		return

	var choice := 0
	if _in_detour(passenger):
		# Tastes differ: some want coffee, others duty free. Any place with room may be chosen.
		choice = rng.randi() % candidates.size()
	else:
		# Short queue and short walk both count, like real passengers judging a hall.
		# (For the gate there is only one candidate: the gate of their flight.)
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
	_set_path(passenger, cells)
	passenger.target = candidates[choice].building
	passenger.state = Passenger.State.WALKING


func _walk(passenger: Passenger, delta: float) -> void:
	var step := _speed(passenger) * delta
	var walked_before := passenger.walked
	passenger.walked += step
	# Long walks wear people out (design doc §8.10).
	var too_far := passenger.walked - maxf(walked_before, WALK_TOLERANCE)
	if too_far > 0.0:
		_lose_mood(passenger, Satisfaction.LONG_WALKS, too_far * WALK_PENALTY)
	while step > 0.0 and passenger.path_index < passenger.path.size():
		var waypoint := _waypoint(passenger, passenger.path_index)
		var to_target := waypoint - passenger.position
		var distance := to_target.length()
		if distance <= step:
			passenger.position = waypoint
			passenger.path_index += 1
			step -= distance
		else:
			passenger.position += to_target / distance * step
			step = 0.0
	if passenger.path_index >= passenger.path.size():
		_arrive(passenger)


func _arrive(passenger: Passenger) -> void:
	if _is_leaving(passenger):
		# Out of the airport: the arrival is complete (design doc §8.8).
		passenger.state = Passenger.State.GONE
		_someone_gone = true
		arrived_count += 1
		world.progression.passengers += 1
		if passenger.target != null and _stations.has(passenger.target):
			# Back from their trip: they pay for parking on the way out (design doc §11.8).
			world.economy.earn(PARKING_FEE, Economy.PARKING)
			_stations[passenger.target].record_income(time, PARKING_FEE)
		_finish_journey(passenger)
		world.economy.earn(Economy.ARRIVAL_FEE, Economy.ARRIVAL_FEES)
		return
	var station := _stations[passenger.target]
	if station.role() == Role.GATE:
		passenger.state = Passenger.State.AT_GATE
		station.waiting.append(passenger)
	elif station.role() == Role.BAGGAGE_CLAIM:
		passenger.state = Passenger.State.AT_BELT
		passenger.queued_since = time
		station.waiting.append(passenger)
	elif _in_detour(passenger):
		if time >= passenger.leave_shop_by:
			# The walk took too long: no time left for the visit, straight on.
			_end_detour(passenger)
			_plan(passenger)
			return
		passenger.state = Passenger.State.IN_SHOP
		var type := station.building.type
		passenger.visit_left = rng.randf_range(type.visit_seconds_min, type.visit_seconds_max)
		station.waiting.append(passenger)
	else:
		passenger.state = Passenger.State.QUEUING
		passenger.queued_since = time
		if station.building.fast_track and _is_business(passenger):
			# Fast track (design doc §11.8): business travellers go ahead of everyone else.
			var spot := 0
			while spot < station.queue.size() and _is_business(station.queue[spot]):
				spot += 1
			station.queue.insert(spot, passenger)
			world.economy.earn(FAST_TRACK_FEE, Economy.FAST_TRACK)
			station.record_income(time, FAST_TRACK_FEE)
		else:
			station.queue.append(passenger)


func _set_stuck(passenger: Passenger) -> void:
	passenger.state = Passenger.State.STUCK
	passenger.target = null
	passenger.retry_in = RETRY_INTERVAL


# --- Stations ---

func _tick_station(station: Station, delta: float) -> void:
	if station.role() == Role.GATE:
		return  # boarding is driven by the flight schedule
	if station.role() == Role.SHOP or station.role() == Role.LOUNGE:
		_tick_shop(station, delta)
		return
	if station.role() == Role.CAR_PARK:
		return  # people only walk through
	if station.role() == Role.BAGGAGE_CLAIM:
		_tick_baggage_claim(station)
		return

	station.sync_slots()
	if station.queue.is_empty() and station.serving.count(null) == station.serving.size():
		return  # an idle station has nothing to do (and nobody to look up)
	# One employee per counter (design doc §9.1): counter i is open only if employee i exists.
	var working := world.staff_working_at(station.building)
	var manager_here := world.is_manager_near(station.building)
	for i in station.serving.size():
		var served := station.serving[i]
		if served != null:
			station.service_left[i] -= delta
			# A security lane with no airside exit is blocked: passengers wait there until it opens.
			var blocked := station.role() == Role.SECURITY and station.exit_cells.is_empty()
			if station.service_left[i] <= 0.0 and not blocked:
				station.serving[i] = null
				if i < working.size():
					# Experience grows per station type (design doc §9).
					var role := station.role()
					working[i].served[role] = working[i].served.get(role, 0) + 1
				_finish_service(station, served)
		if station.serving[i] == null and not station.queue.is_empty() and i < working.size():
			var next: Passenger = station.queue.pop_front()
			next.state = Passenger.State.IN_SERVICE
			station.serving[i] = next
			station.record_wait(time, time - next.queued_since)
			var patience := next.type.queue_patience if next.type != null else 60.0
			_lose_mood(next, Satisfaction.LONG_QUEUES, (time - next.queued_since - patience) * QUEUE_PENALTY \
				* (PRESENCE_CALM if manager_here else 1.0))
			# Some passengers are quicker than others; experienced staff are faster.
			station.service_left[i] = station.building.service_time() * _type_factor(next, station) \
				* staff_time_factor(working[i], working, manager_here) * rng.randf_range(0.75, 1.25)

	# The counters' lane positions are the same for everyone in this step: work them out once.
	var lanes := _lane_count(station)
	station.lane_bases.resize(lanes)
	for lane in lanes:
		station.lane_bases[lane] = _lane_base(station, lane)
	for k in station.queue.size():
		var queued := station.queue[k]
		var spot := station.lane_bases[k % lanes] + station.outward * (0.3 + (k / lanes) * QUEUE_SPACING)
		if queued.position != spot:  # people already standing at their spot need no move
			_move_towards(queued, spot, delta)
	for i in station.serving.size():
		if station.serving[i] != null:
			_move_towards(station.serving[i], station.lane_bases[i % lanes] - station.outward * 0.5, delta)


func _finish_service(station: Station, passenger: Passenger) -> void:
	if passenger.recipe == null or passenger.recipe.is_last(passenger.step):
		return
	var done := passenger.recipe.step_at(passenger.step)
	var next := _next_step(passenger)
	if next.detour_before:
		_maybe_detour(passenger, next)
	if done.emerges_behind:
		# Through the security lane: appear behind the building.
		var exit: Vector2i = _closest_cell_in_area(station.exit_cells, world.grid.world_to_cell(passenger.position), -1)
		passenger.position = _cell_point(exit, passenger)
		passenger.previous_position = passenger.position
	_plan(passenger)


# Moves the passenger on to the next step of their journey and makes it their goal.
func _next_step(passenger: Passenger) -> JourneyStep:
	passenger.step = mini(passenger.step + 1, passenger.recipe.steps.size() - 1)
	passenger.goal = passenger.recipe.role_at(passenger.step)
	return passenger.recipe.step_at(passenger.step)


# Rebuilds recipe and step from the saved flags and goal. The saved "after_shop" is the role of the
# step a passenger on a detour returns to (the file format keeps it, so old saves still load).
func _restore_journey(passenger: Passenger, resume_role: Role) -> void:
	passenger.recipe = TRANSFER if passenger.is_transfer else (ARRIVAL if passenger.is_arriving else DEPARTURE)
	var role := resume_role if passenger.goal in [Role.SHOP, Role.LOUNGE] else passenger.goal
	passenger.step = maxi(passenger.recipe.index_of(role), 0)


# --- Detours (tech architecture §5): a visit before a step, then on with that step ---

# The role of the step the passenger is on (or returns to after a detour).
func _resume_role(passenger: Passenger) -> Role:
	return passenger.recipe.role_at(passenger.step) if passenger.recipe != null else passenger.goal


# On a detour: the goal is a visit, not the role of the current step.
func _in_detour(passenger: Passenger) -> bool:
	if passenger.recipe == null:
		push_warning("A passenger without a journey recipe was found.")
		return false
	return passenger.goal != passenger.recipe.role_at(passenger.step)


# Back to the step the detour came before.
func _end_detour(passenger: Passenger) -> void:
	passenger.goal = passenger.recipe.role_at(passenger.step)


# On the way out of the airport (the last step of an arrival).
func _is_leaving(passenger: Passenger) -> bool:
	return passenger.recipe != null and passenger.recipe.step_at(passenger.step).leaves_airport \
		and not _in_detour(passenger)


## How long `employee` needs compared to the standard time: experience (§9.1), a supervisor
## among `team` (§9.2) and the manager standing there (§15.1).
static func staff_time_factor(employee: Employee, team: Array[Employee], manager_here: bool) -> float:
	var factor := employee.time_factor()
	if manager_here:
		factor *= PRESENCE_TIME_FACTOR
	if not employee.is_supervisor and team.any(func(e: Employee) -> bool: return e.is_supervisor):
		factor *= Employee.SUPERVISOR_TEAM_FACTOR
	return factor


# --- Shops and cafés (design doc §8.6) ---

# With enough spare time (and some luck), the passenger visits a shop or café before `next`.
# The step's allowance is the time still needed after the visit (e.g. for security).
func _maybe_detour(passenger: Passenger, next: JourneyStep) -> void:
	var leave_by := passenger.flight.departure_time - FlightSchedule.BOARDING_OPENS - FINAL_CALL - next.detour_allowance
	if leave_by - time < SHOPPING_MIN_SPARE:
		return
	# Business travellers prefer the lounge airside (design doc §11.8).
	if next.detour_lounge and _is_business(passenger) and _has_lounge() and rng.randf() < LOUNGE_CHANCE:
		passenger.goal = Role.LOUNGE
		passenger.leave_shop_by = leave_by
		return
	if rng.randf() >= _shop_chance(passenger) * next.detour_chance_factor:
		return
	passenger.goal = Role.SHOP
	passenger.leave_shop_by = leave_by


# A shop has room if the customers inside plus those on their way fit in.
func _has_room(station: Station) -> bool:
	var coming := 0
	for passenger in passengers:
		if passenger.state == Passenger.State.WALKING and passenger.target == station.building:
			coming += 1
	return station.waiting.size() + coming < station.building.type.customer_capacity


func _tick_shop(station: Station, delta: float) -> void:
	var leaving: Array[Passenger] = []
	for customer in station.waiting:
		customer.visit_left -= delta
		# "Final call": leave in time for boarding, however long the visit was meant to be.
		if customer.visit_left <= 0.0 or time >= customer.leave_shop_by:
			leaving.append(customer)
	for customer in leaving:
		station.waiting.erase(customer)
		var type := station.building.type
		var spend_factor := customer.type.spend_factor if customer.type != null else 1.0
		# Stressed passengers spend less (design doc §8.10); the visit itself cheers them up.
		var mood_factor := lerpf(SPEND_AT_WORST, SPEND_AT_BEST, clampf(customer.mood, 0.0, 100.0) / 100.0)
		customer.mood = minf(customer.mood + (LOUNGE_BONUS if type.airport_run else SHOP_BONUS), 100.0)
		var income := rng.randf_range(type.spend_min, type.spend_max) * spend_factor * mood_factor * Economy.CONCESSION_SHARE
		if type.airport_run:
			income = type.spend_min  # a fixed price, all of it for the airport
		world.economy.earn(income, Economy.LOUNGE if type.airport_run else Economy.SHOPS)
		station.record_income(time, income)
		# Out of the front door and on to the gate.
		if not station.entry_cells.is_empty():
			var door: Vector2i = station.entry_cells[rng.randi() % station.entry_cells.size()]
			customer.position = _cell_point(door, customer)
			customer.previous_position = customer.position
		_end_detour(customer)
		_plan(customer)


# --- Arrivals (design doc §8.8) ---

# Passengers with their bag (or with hand luggage only) walk out through customs to the landside.
func _tick_baggage_claim(station: Station) -> void:
	var leaving: Array[Passenger] = []
	for passenger in station.waiting:
		var ready_at := passenger.queued_since + PASS_THROUGH_TIME
		if passenger.has_bag:
			ready_at = maxf(ready_at, passenger.bag_ready_at)
		if time >= ready_at and not station.exit_cells.is_empty():
			leaving.append(passenger)
	for passenger in leaving:
		station.waiting.erase(passenger)
		station.record_wait(time, time - passenger.queued_since)
		_lose_mood(passenger, Satisfaction.BAG_WAITS, (time - passenger.queued_since - BAG_PATIENCE) * BAG_PENALTY)
		var door: Vector2i = station.exit_cells[rng.randi() % station.exit_cells.size()]
		passenger.position = _cell_point(door, passenger)
		passenger.previous_position = passenger.position
		_next_step(passenger)
		_plan(passenger)


# Arriving passengers leave the airport through the nearest reachable entrance.
func _plan_exit(passenger: Passenger) -> void:
	var cell := world.grid.world_to_cell(passenger.position)
	if not _network.is_walkable(cell):
		var nearest: Variant = _network.nearest_walkable(cell)
		if nearest == null:
			_set_stuck(passenger)
			return
		cell = nearest
	var area := _network.area_of(cell)
	passenger.target = null
	var exit: Variant = null
	if passenger.by_car and passenger.recipe != null and passenger.recipe.step_at(passenger.step).exit_via_car_park:
		# Car travellers walk to their car (design doc §11.8), if a car park is reachable.
		var best_distance := INF
		for car_park in world.buildings:
			if car_park.type.role != Role.CAR_PARK:
				continue
			var door: Variant = _closest_cell_in_area(_access_cells(car_park, true), cell, area)
			if door != null and Vector2(door - cell).length() < best_distance:
				best_distance = Vector2(door - cell).length()
				exit = door
				passenger.target = car_park
	if exit == null:
		var exits: Array[Vector2i] = []
		for building in world.buildings:
			if building.type.role == Role.ENTRANCE:
				exits.append_array(_access_cells(building, false))
		exit = _closest_cell_in_area(exits, cell, area)
	if exit == null:
		_set_stuck(passenger)
		return
	var cells := _network.find_path(cell, exit)
	if cells.is_empty():
		_set_stuck(passenger)
		return
	_set_path(passenger, cells)
	passenger.state = Passenger.State.WALKING


# Queues form straight lines in front of the counters, one line per counter (see _tick_station).
func _lane_count(station: Station) -> int:
	return clampi(station.serving.size(), 1, maxi(station.entry_cells.size(), 1))


func _lane_base(station: Station, lane: int) -> Vector3:
	var cells := station.entry_cells
	if cells.is_empty():
		var type := station.building.type
		var size := Building.rotated_size(type.footprint, station.building.rotation_steps)
		return world.grid.block_center(station.building.origin_cell, size)
	var index := int((lane + 0.5) * cells.size() / _lane_count(station))
	return world.grid.cell_to_world(cells[index])


func _move_towards(passenger: Passenger, target: Vector3, delta: float) -> void:
	var to_target := target - passenger.position
	var step := _speed(passenger) * delta
	if to_target.length() <= step:
		passenger.position = target
	else:
		passenger.position += to_target.normalized() * step


# --- Satisfaction (design doc §8.10) ---

func _lose_mood(passenger: Passenger, reason: String, points: float) -> void:
	points = minf(points, passenger.mood)
	if points <= 0.0:
		return
	passenger.mood -= points
	satisfaction.complain(reason, points)


func _finish_journey(passenger: Passenger, weight: int = 1) -> void:
	satisfaction.record(passenger.type.display_name if passenger.type != null else "Other", passenger.mood, weight)


# --- Passenger types (design doc §8.7) ---

func _speed(passenger: Passenger) -> float:
	return passenger.type.walk_speed if passenger.type != null else WALK_SPEED


func _shop_chance(passenger: Passenger) -> float:
	return passenger.type.shop_chance if passenger.type != null else 0.6


# Families need longer at check-in (bags, children), business travellers are quicker.
func _is_business(passenger: Passenger) -> bool:
	return passenger.type != null and passenger.type.id == &"business"


func _has_lounge() -> bool:
	return _stations.values().any(func(s: Station) -> bool: return s.role() == Role.LOUNGE)


func _type_factor(passenger: Passenger, station: Station) -> float:
	if passenger.type == null:
		return 1.0
	match station.role():
		Role.CHECK_IN:
			return passenger.type.check_in_time_factor
		Role.SECURITY, Role.TRANSFER_SECURITY:
			return passenger.type.security_time_factor
	return 1.0


# --- Layout helpers ---

# Walkable cells along one side of a building that are in the zone that side needs.
func _access_cells(building: Building, front: bool) -> Array[Vector2i]:
	var type := building.type
	var side_zone := AirportGrid.Zone.LANDSIDE
	if type.zone_rule == BuildingType.ZoneRule.AIRSIDE:
		side_zone = AirportGrid.Zone.AIRSIDE
	elif type.zone_rule == BuildingType.ZoneRule.BORDER and not front:
		side_zone = AirportGrid.Zone.AIRSIDE
	elif type.zone_rule == BuildingType.ZoneRule.ANY:
		# A café serves the side it stands on.
		side_zone = world.grid.get_zone(building.origin_cell)
	var cells: Array[Vector2i] = []
	for cell in Building.outside_row(type.footprint, building.origin_cell, building.rotation_steps, front):
		if _network.is_walkable(cell) and world.grid.get_zone(cell) == side_zone:
			cells.append(cell)
	return cells


func _is_usable_gate(station: Station) -> bool:
	var building := station.building
	return world.connection_problem(building.type, building.origin_cell, building.rotation_steps).is_empty()


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


# Stores a found route in the passenger as cell indices.
func _set_path(passenger: Passenger, cells: Array[Vector2i]) -> void:
	passenger.path.resize(cells.size())
	var width := world.grid.size.x
	for i in cells.size():
		passenger.path[i] = cells[i].y * width + cells[i].x
	passenger.path_index = 0


func _waypoint(passenger: Passenger, index: int) -> Vector3:
	var width := world.grid.size.x
	var packed := passenger.path[index]
	return _cell_point(Vector2i(packed % width, packed / width), passenger)


func _cell_point(cell: Vector2i, passenger: Passenger) -> Vector3:
	return world.grid.cell_to_world(cell) + passenger.offset


func _update_route() -> void:
	_check_route()
	_usable_gates = _find_usable_gates()
	# Cargo doesn't need the passenger route (design doc §10.3): a connected stand and handlers.
	_usable_cargo_terminals.clear()
	for building in world.buildings:
		if building.type.role == Role.CARGO_TERMINAL and not world.staff_at(building).is_empty() \
				and world.connection_problem(building.type, building.origin_cell, building.rotation_steps).is_empty():
			_usable_cargo_terminals.append(building)


## Cargo terminals that can have flights right now (cached like usable_gates()).
func usable_cargo_terminals() -> Array[Building]:
	return _usable_cargo_terminals


# Checks, step by step like a passenger, whether Entrance -> Check-in -> Security -> Gate works.
func _check_route() -> void:
	_route_entrances.clear()
	_route_car_parks.clear()
	transfers_possible = false
	var entrance_areas: Dictionary[int, bool] = {}
	var has_entrance := false
	for building in world.buildings:
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

	# Arriving passengers need a way out: gate -> baggage claim -> entrance (design doc §8.8).
	var claims := _stations.values().filter(func(s: Station) -> bool: return s.role() == Role.BAGGAGE_CLAIM)
	if claims.is_empty():
		route_problem = "build a baggage claim for arriving passengers."
		return
	var claim_works := claims.any(func(s: Station) -> bool:
		var from_gates := s.entry_cells.any(func(c: Vector2i) -> bool: return gate_areas.has(_network.area_of(c)))
		var to_exit := s.exit_cells.any(func(c: Vector2i) -> bool: return entrance_areas.has(_network.area_of(c)))
		return from_gates and to_exit)
	if not claim_works:
		route_problem = "connect a baggage claim: back to the gates' walkway, front to the entrance's walkway."
		return

	# Connections are sold only with a working transfer security: in from the gates' walkway,
	# out to it again, and someone to run it (design doc §8.9).
	transfers_possible = _stations.values().any(func(s: Station) -> bool:
		return s.role() == Role.TRANSFER_SECURITY \
			and not world.staff_at(s.building).is_empty() \
			and s.entry_cells.any(func(c: Vector2i) -> bool: return gate_areas.has(_network.area_of(c))) \
			and s.exit_cells.any(func(c: Vector2i) -> bool: return gate_areas.has(_network.area_of(c))))

	route_problem = ""
	for building in world.buildings:
		if building.type.role == Role.ENTRANCE:
			if _access_cells(building, false).any(func(c: Vector2i) -> bool: return good_areas.has(_network.area_of(c))):
				_route_entrances.append(building)
		elif building.type.role == Role.CAR_PARK:
			if _access_cells(building, true).any(func(c: Vector2i) -> bool: return good_areas.has(_network.area_of(c))):
				_route_car_parks.append(building)


func _station_areas(role: BuildingType.Role, front: bool) -> Array[int]:
	var areas: Array[int] = []
	for station: Station in _stations.values():
		if station.role() == role:
			for cell in (station.entry_cells if front else station.exit_cells):
				areas.append(_network.area_of(cell))
	return areas
