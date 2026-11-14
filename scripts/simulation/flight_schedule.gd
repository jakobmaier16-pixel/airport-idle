class_name FlightSchedule
extends RefCounted
## Turns the timetable's slots into flights and runs them (design doc §8.5).
## Pure data. The brain owns it and drives it with tick().

## The least time between two departures at the same gate (a turnaround).
const INTERVAL: float = 180.0
## Slots are only planned this far ahead of now (just after their arrivals window opens), or
## further if the longest planned taxi needs it (see first_departure_delay).
const FIRST_DEPARTURE_DELAY: float = 270.0
## A slot becomes a flight this long before it departs (or earlier: see fill_window).
const ARRIVALS_START: float = 260.0
## A plane stands at its stand this long before it departs (from parking to the doors closing).
const STAND_DWELL: float = 115.0
## Ground time to and from the stand when no route is known (tests without a runway): the old
## fixed taxi time.
const FALLBACK_TAXI_TIME: float = 15.0
## The final approach (seen, but not on the runway yet) and the climb-out after lift-off (seen,
## but already gone from the runway), in seconds.
const APPROACH_TIME: float = 6.0
const CLIMB_TIME: float = 6.0
## A plane that has waited this long at the holding point goes before landings (design doc §7.5a):
## no new landing is booked until it has taken off. Without it landings (booked 6 s ahead) always
## beat take-offs (which need a free runway right now) and the holding point can starve (the
## longest wait was 140 s on the showcase day). Not shorter, because a landing that waits is a
## late departure, while a take-off that waits is not (punctuality counts the push-back).
const HOLDING_PRIORITY_AFTER: float = 80.0
## The airport this part of the simulation works for; set by the Airport autoload.
var world: AirportWorld

## A landing or take-off occupies the runway for its roll plus this clear margin (design doc §7.5a).
## A variable, so tests can make runways the bottleneck.
var runway_margin: float = RUNWAY_CLEAR_MARGIN
const RUNWAY_CLEAR_MARGIN: float = 10.0
## Freight per cargo flight (unloaded and loaded), and how long a freighter waits for unfinished
## loading (design doc §10.3).
const CARGO_TONNES_MIN: float = 30.0
const CARGO_TONNES_MAX: float = 50.0
const CARGO_MAX_HOLD: float = 60.0
## A plane may land this many seconds late without delaying its departure (design doc §7.5a).
const TURNAROUND_BUFFER: float = 20.0
## The last stretch before the doors close (the BOARDING phase).
const BOARDING_OPENS: float = 90.0

## A plane starts its final approach (the visuals may celebrate a new airline's first landing).
signal plane_arriving(flight: Flight)

## Every flight that hasn't departed yet. A gate can have two: the one at the stand and the
## next one, whose plane is already on its way (like at a real airport).
var flights: Array[Flight] = []

# Simulation time from which each runway is free again.
var _runway_free_at: Dictionary[Building, float] = {}
## Every runway booking (runway, start time, end time), for tests.
var runway_bookings: Array = []

# Departure time of the latest flight planned at each gate.
var _last_planned: Dictionary[Building, float] = {}
var _next_number: int = 101
# True while a plane has waited long enough at the holding point to go before landings (set per tick).
var _takeoff_priority: bool = false
## Dice. Airport replaces them with its shared, seeded dice (tech_architecture.md §3).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func tick(now: float, delta: float) -> void:
	var usable := world.usable_gates() + world.usable_cargo_terminals()
	for flight in flights:
		if not usable.has(flight.gate):
			flight.phase = Flight.Phase.CANCELLED
			_last_planned.erase(flight.gate)
	flights = flights.filter(func(f: Flight) -> bool: return f.is_active())

	# The timetable's slots become flights when their planes have to start arriving.
	for slot in world.timetable.slots:
		if slot.state == TimetableSlot.State.PENDING and slot.departure_time - now <= fill_window():
			_fill_slot(slot, usable, now)

	_takeoff_priority = false
	for flight in flights:
		if not flight.takeoff_booked and flight.phase == Flight.Phase.DEPARTING:
			var route := route_of(flight)
			if route != null and route.runway != null \
					and now >= flight.departs_at() + taxi_out_of(route) + HOLDING_PRIORITY_AFTER:
				_takeoff_priority = true
				break
	for flight in flights:
		_advance(flight, now, delta)
	flights = flights.filter(func(f: Flight) -> bool: return f.is_active())


## A slot becomes a flight this long before it departs: early enough for the plane with the
## longest planned taxi to touch down in time.
func fill_window() -> float:
	return maxf(ARRIVALS_START, longest_lead() + APPROACH_TIME + 5.0)


## Slots are only planned further ahead than this (so no flight is made too late for its plane).
func first_departure_delay() -> float:
	return maxf(FIRST_DEPARTURE_DELAY, fill_window() + 10.0)


## The longest time any plane needs between touchdown and the doors closing, over all stands.
func longest_lead() -> float:
	var network := world.plane_network
	return maxf(network.longest_arrival(), FALLBACK_TAXI_TIME) + STAND_DWELL


## The longest time from a departure's push-back to the plane being off the ground.
func longest_departure_run() -> float:
	return maxf(world.plane_network.longest_departure(), FALLBACK_TAXI_TIME) + CLIMB_TIME


## The route of `flight`'s stand, or null if it has none (tests without a runway).
func route_of(flight: Flight) -> PlaneRoute:
	return world.plane_network.route_to_stand(flight.stand) if flight.stand != null else null


## Seconds from the plane touching down to the doors closing: landing roll, taxi in and the time
## at the stand. This is what the timetable plans a flight's arrival by.
static func lead_of(route: PlaneRoute) -> float:
	if route == null:
		return FALLBACK_TAXI_TIME + STAND_DWELL
	return route.roll_in_time + route.taxi_in_time + STAND_DWELL


## Seconds from push-back to the take-off run starting (the taxi out).
static func taxi_out_of(route: PlaneRoute) -> float:
	return FALLBACK_TAXI_TIME if route == null else route.taxi_out_time


static func roll_out_of(route: PlaneRoute) -> float:
	return 0.0 if route == null else route.roll_out_time


## How long the plane of `flight` blocks the runway when it lands (`landing`) or takes off: the
## roll plus a clear margin.
func occupancy(flight: Flight, landing: bool) -> float:
	var route := route_of(flight)
	var roll := 0.0
	if route != null:
		roll = route.roll_in_time if landing else route.roll_out_time
	return roll + runway_margin


## The flights in departure order, for the departures board.
func upcoming() -> Array[Flight]:
	var sorted := flights.duplicate()
	sorted.sort_custom(func(a: Flight, b: Flight) -> bool: return a.departure_time < b.departure_time)
	return sorted


## The next departures, one line each: number, gate, status, time to departure.
func departures_text(max_lines: int = 4) -> String:
	var phase_names := {
		Flight.Phase.SCHEDULED: "Scheduled", Flight.Phase.ARRIVING: "Plane arriving",
		Flight.Phase.AT_STAND: "At stand", Flight.Phase.BOARDING: "Boarding",
		Flight.Phase.DEPARTING: "Departed",
	}
	var lines: PackedStringArray = []
	if flights.is_empty() and world.curfew_at():
		lines.append("Night curfew: no flights until %02d:00" % int(Clock.CURFEW_END))
	for flight in upcoming().slice(0, max_lines):
		var seconds := maxi(ceili(flight.departs_at() - world.sim_time), 0)
		var status: String = phase_names[flight.phase]
		if flight.delay > 0.0 and flight.phase == Flight.Phase.BOARDING:
			status = "Delayed"
		var where := "Cargo" if flight.cargo else "Gate %d" % world.gate_number(flight.gate)
		lines.append("%s   %s   %s   %s   %d:%02d" % [
			flight.number, where, "Freighter" if flight.cargo else flight.route, status, seconds / 60, seconds % 60])
	return "\n".join(lines)


## The schedule as plain data for the save game (tech_architecture.md §13). Buildings are stored
## by their permanent ID.
func save_state() -> Dictionary:
	var saved: Array[Dictionary] = []
	for flight in flights:
		saved.append(_save_flight(flight))
	var planned: Array = []
	for gate in _last_planned:
		planned.append([gate.id, _last_planned[gate]])
	var runways: Array = []
	for runway in _runway_free_at:
		runways.append([runway.id, _runway_free_at[runway]])
	return {"flights": saved, "next_number": _next_number, "last_planned": planned, "runway_free_at": runways}


## Restores from save_state(). Flights whose gate is gone are left out. Entries of old saves that
## were only kept for their passengers ("scheduled": false) are dropped.
func load_state(data: Dictionary, by_id: Dictionary[int, Building]) -> void:
	flights.clear()
	_last_planned.clear()
	_runway_free_at.clear()
	_next_number = int(data.get("next_number", _next_number))
	for entry: Dictionary in data.get("flights", []):
		var gate: Building = by_id.get(int(entry.get("gate", 0)))
		if gate == null or not bool(entry.get("scheduled", true)):
			continue
		flights.append(_load_flight(entry, gate, by_id))
	for pair: Array in data.get("last_planned", []):
		if by_id.has(int(pair[0])):
			_last_planned[by_id[int(pair[0])]] = float(pair[1])
	for pair: Array in data.get("runway_free_at", []):
		if by_id.has(int(pair[0])):
			_runway_free_at[by_id[int(pair[0])]] = float(pair[1])


func _save_flight(flight: Flight) -> Dictionary:
	return {
		"number": flight.number,
		"airline": String(flight.airline.type.id) if flight.airline != null else "",
		"wide_body": flight.wide_body, "cargo": flight.cargo,
		"tonnes": flight.tonnes, "tonnes_handled": flight.tonnes_handled, "fee": flight.fee_per_passenger,
		"route": flight.route, "gate": flight.gate.id, "stand": flight.stand.id if flight.stand != null else 0,
		"departure_time": flight.departure_time, "delay": flight.delay, "arrival_delay": flight.arrival_delay,
		"landing_booked": flight.landing_booked, "takeoff_booked": flight.takeoff_booked,
		"takeoff_at": flight.takeoff_at, "phase": int(flight.phase),
	}


func _load_flight(entry: Dictionary, gate: Building, by_id: Dictionary[int, Building]) -> Flight:
	var flight := Flight.new()
	flight.number = str(entry.get("number", ""))
	var airline_id := StringName(entry.get("airline", ""))
	for airline in world.airlines.signed:
		if airline.type.id == airline_id:
			flight.airline = airline
	flight.wide_body = bool(entry.get("wide_body", false))
	flight.cargo = bool(entry.get("cargo", false))
	flight.tonnes = float(entry.get("tonnes", 0.0))
	flight.tonnes_handled = float(entry.get("tonnes_handled", 0.0))
	flight.fee_per_passenger = float(entry.get("fee", Economy.PASSENGER_FEE))
	flight.route = str(entry.get("route", ""))
	flight.gate = gate
	flight.stand = by_id.get(int(entry.get("stand", 0)), world.stand_behind(gate))
	flight.departure_time = float(entry.get("departure_time", 0.0))
	flight.delay = float(entry.get("delay", 0.0))
	flight.arrival_delay = float(entry.get("arrival_delay", 0.0))
	flight.landing_booked = bool(entry.get("landing_booked", false))
	flight.takeoff_booked = bool(entry.get("takeoff_booked", false))
	# Saves from before real taxi times have no start: the run starts when the plane reaches the runway.
	flight.takeoff_at = float(entry.get("takeoff_at", -1.0))
	if flight.takeoff_booked and flight.takeoff_at < 0.0:
		flight.takeoff_at = flight.departs_at() + taxi_out_of(route_of(flight))
	flight.phase = clampi(int(entry.get("phase", 0)), 0, Flight.Phase.CANCELLED) as Flight.Phase
	return flight


# Turns a slot into a flight at a gate that fits it, or drops the slot (no gate, no airline).
func _fill_slot(slot: TimetableSlot, usable: Array[Building], now: float) -> void:
	slot.state = TimetableSlot.State.DROPPED
	# Night curfew (design doc §12.4): no landing or take-off in the quiet hours.
	if world.timetable.in_curfew(slot.departure_time):
		return
	var gate := _gate_for(slot, usable, now)
	if gate == null:
		return
	# Signed deals fill their quotas first; without a deal the default airline flies the narrow-bodies.
	var airline := world.airlines.claim_for_slot(slot.plane_class, slot.route)
	var type: AirlineType = airline.type if airline != null else null
	if type == null:
		if slot.plane_class != TimetableSlot.PlaneClass.NARROW:
			return
		type = Timetable.default_airline()
	slot.state = TimetableSlot.State.FILLED
	var flight := _schedule(gate, slot.departure_time, type, airline)
	slot.airline_code = type.code
	slot.flight_number = flight.number


# The gate that takes `slot`: free for a turnaround before it, and the one with the shortest planned
# route (close stands are worth more), ties by id. Wide-body slots need a wide-body stand
# (stand_behind decides what fits), so narrow-body slots keep off those gates while another one is free.
# A stand whose plane would have to land before `now` (a far stand built mid-day while this slot
# was already planned) is skipped: the plane could not touch down in time.
func _gate_for(slot: TimetableSlot, usable: Array[Building], now: float = -INF) -> Building:
	var best: Building = null
	var best_wide := false
	var best_time := INF
	for gate in usable:
		if (gate.type.role == BuildingType.Role.CARGO_TERMINAL) != (slot.plane_class == TimetableSlot.PlaneClass.CARGO):
			continue
		var stand := world.stand_behind(gate)
		var wide_stand := stand != null and stand.type.wide_body
		# The stand's class decides (BuildingType.fits): a wide stand takes narrow planes too, a
		# narrow one never takes a wide-body plane.
		if stand != null and not stand.type.fits(slot.plane_class):
			continue
		if stand == null and slot.plane_class == TimetableSlot.PlaneClass.WIDE:
			continue
		var last: float = _last_planned.get(gate, -INF)
		if last + INTERVAL > slot.departure_time:
			continue
		if wide_stand and slot.plane_class == TimetableSlot.PlaneClass.NARROW and _wide_slot_near(slot):
			continue  # a wide-body slot needs this gate right about now
		var route := world.plane_network.route_to_stand(stand) if stand != null else null
		if route != null and slot.departure_time - now < lead_of(route) + APPROACH_TIME:
			continue
		var planned := 2.0 * FALLBACK_TAXI_TIME if route == null else route.taxi_in_time + route.taxi_out_time
		var better := best == null or (best_wide and not wide_stand) or (best_wide == wide_stand \
				and (planned < best_time - 0.001 or (absf(planned - best_time) <= 0.001 and gate.id < best.id)))
		if better:
			best = gate
			best_wide = wide_stand
			best_time = planned
	return best


# Makes the flight (tests call it directly; no type means the default airline).
# True if a wide-body slot still waits for its flight within a turnaround of `slot`.
func _wide_slot_near(slot: TimetableSlot) -> bool:
	for other in world.timetable.slots:
		if other.plane_class == TimetableSlot.PlaneClass.WIDE and other.state == TimetableSlot.State.PENDING \
				and absf(other.departure_time - slot.departure_time) < INTERVAL:
			return true
	return false


func _schedule(gate: Building, departure_time: float, type: AirlineType = null, airline: Airline = null) -> Flight:
	if type == null:
		type = Timetable.default_airline()
	var flight := Flight.new()
	flight.airline = airline
	flight.number = "%s %d" % [type.code, _next_number]
	_next_number += 1
	flight.gate = gate
	flight.stand = world.stand_behind(gate)
	# The airline's route type (it sets the season's demand, design doc §12.2).
	flight.route = type.route
	flight.wide_body = type.wide_body
	flight.departure_time = departure_time
	if type.cargo:
		# A freighter (design doc §10.3): freight to unload and load.
		flight.cargo = true
		flight.tonnes = rng.randf_range(CARGO_TONNES_MIN, CARGO_TONNES_MAX)
		flight.fee_per_passenger = airline.fee  # per tonne
		_last_planned[gate] = departure_time
		flights.append(flight)
		return flight
	flight.fee_per_passenger = airline.fee if airline != null else type.expected_fee
	_last_planned[gate] = departure_time
	flights.append(flight)
	return flight


func _advance(flight: Flight, now: float, delta: float) -> void:
	# Knock-on holds: time stands still for this flight.
	var hold := _hold_reason(flight, now)
	if hold == Hold.AIRPORT and flight.arrival_delay < TURNAROUND_BUFFER:
		# Landing a little late: the time at the stand absorbs it, the departure stays on time.
		flight.arrival_delay += delta
	elif hold != Hold.NONE:
		flight.delay += delta
	var time_left := flight.departs_at() - now
	# Arrival phases run late by the absorbed arrival delay.
	var arrival_left := time_left + flight.arrival_delay
	var route := route_of(flight)
	var taxi_out := taxi_out_of(route)

	# The take-off run starts when the plane reaches the runway (it waits there until the runway is free).
	if not flight.takeoff_booked and time_left <= 0.0 and now >= flight.departs_at() + taxi_out:
		_try_takeoff(flight, now)

	var phase := Flight.Phase.SCHEDULED
	if flight.takeoff_booked and now >= flight.takeoff_at + roll_out_of(route) + CLIMB_TIME:
		phase = Flight.Phase.DEPARTED
	elif time_left <= 0.0:
		phase = Flight.Phase.DEPARTING
	elif time_left <= BOARDING_OPENS:
		phase = Flight.Phase.BOARDING
	elif arrival_left <= STAND_DWELL:
		phase = Flight.Phase.AT_STAND
	elif arrival_left <= lead_of(route) + APPROACH_TIME:
		phase = Flight.Phase.ARRIVING
	# A plane never goes back a phase (a changed route moves the times, not the story).
	phase = maxi(phase, flight.phase) as Flight.Phase if flight.phase != Flight.Phase.CANCELLED else phase

	if flight.cargo and (phase == Flight.Phase.AT_STAND or phase == Flight.Phase.BOARDING):
		flight.tonnes_handled = minf(flight.tonnes_handled + _handling_rate(flight.gate) * delta, flight.tonnes)
	if phase >= Flight.Phase.DEPARTING and flight.phase == Flight.Phase.BOARDING and flight.cargo \
			and flight.tonnes_handled < flight.tonnes and flight.airport_delay() < CARGO_MAX_HOLD:
		# The freight isn't loaded yet: the freighter waits (the airport's delay).
		flight.delay += delta
		phase = Flight.Phase.BOARDING
	if phase >= Flight.Phase.DEPARTING and flight.phase < Flight.Phase.DEPARTING:
		world.reputation.record_departure(flight.airport_delay())
		if flight.cargo:
			# Paid per tonne handled (design doc §10.3).
			world.economy.earn(flight.tonnes_handled * flight.fee_per_passenger + Economy.FLIGHT_FEE, Economy.CARGO)
		else:
			# The airline pays per flight (design doc §11.5).
			world.economy.earn(Economy.FLIGHT_FEE)
		world.airlines.record_flight(flight.airline, flight.airport_delay() > Reputation.ON_TIME_LIMIT)
	if phase == Flight.Phase.ARRIVING and flight.phase == Flight.Phase.SCHEDULED:
		plane_arriving.emit(flight)
	flight.phase = phase


enum Hold { NONE, AIRPORT }

## Tonnes per second a cargo terminal moves (design doc §10.3): four handler places at 0.25 t/s
## each, as when every place was staffed (staff were removed 2026-11-14).
const HANDLING_RATE: float = 1.0


func _handling_rate(_terminal: Building) -> float:
	return HANDLING_RATE


# Books `runway` for a movement that starts at `start` and lasts `duration`. False if the runway is
# still busy then: nobody reserves the runway for later than their own movement, so a plane that
# waits (at the holding point or in the air) never blocks the planes that are ready.
func _book_runway(runway: Building, start: float, duration: float) -> bool:
	if _runway_free_at.get(runway, -INF) > start:
		return false
	_runway_free_at[runway] = start + duration
	runway_bookings.append([runway, start, start + duration])
	return true


# The take-off run of `flight` (design doc §7.5a): the plane has pushed back and taxied to the
# runway, and waits at the holding point until the runway is free. Punctuality counts the push-back,
# as in real statistics.
func _try_takeoff(flight: Flight, now: float) -> void:
	var route := route_of(flight)
	if route != null and route.runway != null and not _book_runway(route.runway, now, occupancy(flight, false)):
		return
	flight.takeoff_booked = true
	flight.takeoff_at = now


# The runway `flight` lands on, or null (tests without one).
func _runway_for(flight: Flight) -> Building:
	var route := route_of(flight)
	return null if route == null else route.runway


# Why `flight` must wait this step: its stand is still taken by the previous plane at the same
# gate (knock-on delay) or the runway is busy.
func _hold_reason(flight: Flight, now: float) -> Hold:
	var arrival_left := flight.departs_at() - now + flight.arrival_delay
	var route := route_of(flight)
	var arrive_at := lead_of(route) + APPROACH_TIME
	if flight.phase == Flight.Phase.SCHEDULED and arrival_left <= arrive_at:
		# The plane reaches the stand this long after touchdown; the plane before it at the same gate
		# must have pushed back by then.
		var parks_in := APPROACH_TIME + FALLBACK_TAXI_TIME
		if route != null:
			parks_in = APPROACH_TIME + route.roll_in_time + route.taxi_in_time
		for other in flights:
			if other != flight and other.gate == flight.gate and other.is_active() \
					and other.departure_time < flight.departure_time and other.phase < Flight.Phase.DEPARTING \
					and other.departs_at() > now + parks_in:
				return Hold.AIRPORT
		# A landing slot on the runway: the roll starts after the approach (design doc §7.5a).
		if not flight.landing_booked:
			var runway := _runway_for(flight)
			if runway != null and (_takeoff_priority or not _book_runway(runway, now + APPROACH_TIME, occupancy(flight, true))):
				return Hold.AIRPORT
			flight.landing_booked = true
	return Hold.NONE
