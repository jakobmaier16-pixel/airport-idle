class_name FlightSchedule
extends RefCounted
## Plans and runs flights (design doc §8.5): one departure after another at every usable gate.
## Pure data. PassengerFlow owns it and passes itself into tick() (no stored back reference,
## so the two never keep each other alive).

## Seconds between two departures at the same gate.
const INTERVAL: float = 180.0
## A newly usable gate's first departure is this far in the future (after the arrival window).
const FIRST_DEPARTURE_DELAY: float = 270.0
## Gates that become usable at the same moment are spread out by this much.
const GATE_STAGGER: float = 60.0
## The earliest any passenger type arrives before departure (see data/passengers/); the next
## flight at a gate is planned this long before it departs.
const ARRIVALS_START: float = 260.0
## The plane starts taxiing onto the stand this long before departure.
const PLANE_ARRIVES: float = 130.0
## A flight waits at most this long for passengers who are already airside (checked-in bags would
## otherwise have to be unloaded). Fits before the next plane arrives at the same stand.
const MAX_HOLD: float = 30.0
## The airport this part of the simulation works for; set by the Airport autoload.
var world: AirportWorld

## Every landing and take-off occupies a runway this long (design doc §7.5a). A variable, so
## tests can make runways the bottleneck.
var runway_seconds: float = RUNWAY_SECONDS
const RUNWAY_SECONDS: float = 20.0
## Freight per cargo flight (unloaded and loaded), and how long a freighter waits for unfinished
## loading (design doc §10.3).
const CARGO_TONNES_MIN: float = 30.0
const CARGO_TONNES_MAX: float = 50.0
const CARGO_MAX_HOLD: float = 60.0
## A plane may land this many seconds late without delaying its departure (design doc §7.5a).
const TURNAROUND_BUFFER: float = 20.0
## Seconds to taxi onto the stand, and to push back after departure.
const TAXI_TIME: float = 15.0
const BOARDING_OPENS: float = 90.0
## Passengers per second walking from the gate onto the plane.
const BOARDING_RATE: float = 1.0
## Arriving passengers per second leaving the parked plane through the gate (design doc §8.8).
const DEPLANE_RATE: float = 1.0
## Bags come off the belt between these times after the plane has parked.
const BAGS_FROM: float = 30.0
const BAGS_UNTIL: float = 90.0
const SEATS: int = 180
const BOOKED_MIN: int = 12
const BOOKED_MAX: int = 20
## Flight numbers without an airline (tests only).
const NO_AIRLINE_CODE: String = "XX"
## Passenger types (design doc §8.7).
const FAMILY: PassengerType = preload("res://data/passengers/family.tres")
const LOW_COST: PassengerType = preload("res://data/passengers/low_cost.tres")
const BUSINESS: PassengerType = preload("res://data/passengers/business.tres")
## Share of a route's arriving passengers who connect to another flight (design doc §8.9).
const TRANSFER_SHARES: Dictionary = {"Holiday": 0.1, "Low-cost": 0.05, "Business": 0.25, "Long-haul": 0.3}
## A connecting flight must depart at least this long after the transfer passenger deplanes.
const MIN_CONNECTION: float = 150.0
## Route types and their passenger mix: [families, low-cost, business] shares.
const ROUTES: Dictionary = {
	"Holiday": [0.7, 0.2, 0.1],
	"Low-cost": [0.15, 0.8, 0.05],
	"Business": [0.1, 0.3, 0.6],
	"Long-haul": [0.35, 0.15, 0.5],
}
## Wide-body (long-haul) planes carry this many times the passengers, and deplane through two
## doors (design doc §10.2).
const WIDE_BODY_FACTOR: float = 2.0
const WIDE_BODY_DEPLANE_RATE: float = 2.0

## A plane starts its final approach (the visuals may celebrate a new airline's first landing).
signal plane_arriving(flight: Flight)

## Every flight that hasn't departed yet. A gate can have two: the one at the stand and the
## next one, whose passengers are already arriving (like at a real airport).
var flights: Array[Flight] = []

# Simulation time from which each runway is free again.
var _runway_free_at: Dictionary[Building, float] = {}
## Every runway booking (runway, start time), for tests.
var runway_bookings: Array = []

# Departure time of the latest flight planned at each gate.
var _last_planned: Dictionary[Building, float] = {}
var _next_number: int = 101
## Dice. Airport replaces them with its shared, seeded dice (tech_architecture.md §3).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func tick(now: float, delta: float, flow: PassengerFlow) -> void:
	var usable := flow.usable_gates() + flow.usable_cargo_terminals()
	for flight in flights:
		if not usable.has(flight.gate):
			flight.phase = Flight.Phase.CANCELLED
			flow.remove_flight_passengers(flight, false)
			_last_planned.erase(flight.gate)
	flights = flights.filter(func(f: Flight) -> bool: return f.is_active())

	# Plan ahead: each gate always has its next flight planned before its passengers must arrive.
	var new_gates := 0
	# Gates opening together share the 3-minute slot evenly, so their runway movements interleave.
	var opening := usable.filter(func(g: Building) -> bool: return not _last_planned.has(g)).size()
	var stagger := minf(GATE_STAGGER, INTERVAL / maxi(opening, 1))
	for gate in usable:
		if not _last_planned.has(gate):
			_plan_slot(gate, now + FIRST_DEPARTURE_DELAY + new_gates * stagger)
			new_gates += 1
		# The next slot is planned exactly when its passengers have to start arriving.
		while _last_planned[gate] + INTERVAL - now <= ARRIVALS_START:
			_plan_slot(gate, _last_planned[gate] + INTERVAL)

	for flight in flights:
		_advance(flight, now, delta, flow)
	flights = flights.filter(func(f: Flight) -> bool: return f.is_active())


## The flights in departure order, for the departures board.
func upcoming() -> Array[Flight]:
	var sorted := flights.duplicate()
	sorted.sort_custom(func(a: Flight, b: Flight) -> bool: return a.departure_time < b.departure_time)
	return sorted


# A gate's turnaround slot: the airline owed the most flights gets it; with no demand it stays empty.
func _plan_slot(gate: Building, departure_time: float) -> void:
	# Night curfew (design doc §12.4): no landing or take-off in the quiet hours.
	var now := world.passenger_flow.time
	if world.curfew_at(departure_time - now) or world.curfew_at(departure_time - PLANE_ARRIVES - now):
		_last_planned[gate] = departure_time
		return
	var stand := world.stand_behind(gate)
	var cargo := gate.type.role == BuildingType.Role.CARGO_TERMINAL
	var airline := world.airlines.next_airline(stand != null and stand.type.wide_body, cargo)
	if airline != null:
		_schedule(gate, departure_time, airline)
	else:
		_last_planned[gate] = departure_time


func _schedule(gate: Building, departure_time: float, airline: Airline = null) -> void:
	var flight := Flight.new()
	flight.airline = airline
	flight.number = "%s %d" % [airline.type.code if airline != null else NO_AIRLINE_CODE, _next_number]
	_next_number += 1
	flight.gate = gate
	flight.stand = world.stand_behind(gate)
	# The airline's route type sets the passenger mix (design doc §10.1); random without one.
	flight.route = airline.type.route if airline != null else ROUTES.keys()[rng.randi() % ROUTES.size()]
	flight.wide_body = airline != null and airline.type.wide_body
	flight.departure_time = departure_time
	if airline != null and airline.type.cargo:
		# A freighter (design doc §10.3): freight instead of passengers.
		flight.cargo = true
		flight.tonnes = rng.randf_range(CARGO_TONNES_MIN, CARGO_TONNES_MAX)
		flight.fee_per_passenger = airline.fee  # per tonne
		_last_planned[gate] = departure_time
		flights.append(flight)
		return
	var size_factor := WIDE_BODY_FACTOR if flight.wide_body else 1.0
	flight.seats = roundi(SEATS * size_factor)
	# Busy mornings and evenings, quiet nights (design doc §12.1), holiday peaks in summer (§12.2).
	size_factor *= Clock.demand_factor(world.clock.hour_at(departure_time - world.passenger_flow.time))
	size_factor *= Weather.demand_factor(flight.route, world.season())
	flight.booked = roundi(_passenger_count() * size_factor)
	flight.departure_time = departure_time
	if airline != null:
		flight.fee_per_passenger = airline.fee
	_plan_arrivals(flight)
	# The inbound leg: the same plane brings passengers before it takes new ones (turnaround).
	var mix := PackedFloat32Array(ROUTES[flight.route])
	var types: Array[PassengerType] = [FAMILY, LOW_COST, BUSINESS]
	for i in roundi(_passenger_count() * size_factor):
		flight.inbound_types.append(types[rng.rand_weighted(mix)])
	_last_planned[gate] = departure_time
	flights.append(flight)


# Passengers on one leg: a well-rated airport attracts more of them (design doc §11.7).
func _passenger_count() -> int:
	return roundi(rng.randi_range(BOOKED_MIN, BOOKED_MAX) * world.reputation.demand_factor(world.stars()))


# Decides type and arrival time of every booked passenger, from the route's mix.
func _plan_arrivals(flight: Flight) -> void:
	var mix: Array = ROUTES[flight.route]
	var types: Array[PassengerType] = [FAMILY, LOW_COST, BUSINESS]
	var arrivals: Array = []
	for i in flight.booked:
		var type := types[rng.rand_weighted(PackedFloat32Array(mix))]
		var before := rng.randf_range(type.arrives_until, type.arrives_from)
		arrivals.append([flight.departure_time - before, type])
	arrivals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for arrival: Array in arrivals:
		flight.arrival_times.append(arrival[0])
		flight.arrival_types.append(arrival[1])


func _advance(flight: Flight, now: float, delta: float, flow: PassengerFlow) -> void:
	# Weather and knock-on holds (design doc §12.2): time stands still for this flight.
	var hold := _hold_reason(flight, now)
	if hold == Hold.AIRPORT and flight.arrival_delay < TURNAROUND_BUFFER:
		# Landing a little late: the time at the stand absorbs it, the departure stays on time.
		flight.arrival_delay += delta
	elif hold != Hold.NONE:
		flight.delay += delta
		if hold == Hold.WEATHER:
			flight.weather_delay += delta
	var time_left := flight.departs_at() - now
	# Arrival phases run late by the absorbed arrival delay.
	var arrival_left := time_left + flight.arrival_delay
	var ramp_open := not world.weather.ramp_closed()

	# Passengers arrive at the entrance at their planned times.
	while flight.spawned < flight.booked and flight.arrival_times[flight.spawned] <= now:
		if not flow.spawn_passenger(flight, flight.arrival_types[flight.spawned]):
			break
		flight.spawned += 1

	var phase := Flight.Phase.SCHEDULED
	if time_left <= -TAXI_TIME:
		phase = Flight.Phase.DEPARTED
	elif time_left <= 0.0:
		phase = Flight.Phase.DEPARTING
	elif time_left <= BOARDING_OPENS:
		phase = Flight.Phase.BOARDING
	elif arrival_left <= PLANE_ARRIVES - TAXI_TIME:
		phase = Flight.Phase.AT_STAND
	elif arrival_left <= PLANE_ARRIVES:
		phase = Flight.Phase.ARRIVING

	if not ramp_open:
		pass  # lightning: nobody on the apron
	elif phase == Flight.Phase.AT_STAND or (phase == Flight.Phase.BOARDING and flight.deplaned < flight.inbound_types.size()):
		# Arriving passengers leave the plane first; whoever is left when boarding opens leaves at once.
		flight.deplane_credit += (WIDE_BODY_DEPLANE_RATE if flight.wide_body else DEPLANE_RATE) * delta
		if phase == Flight.Phase.BOARDING:
			flight.deplane_credit = flight.inbound_types.size()
		while flight.deplane_credit >= 1.0 and flight.deplaned < flight.inbound_types.size():
			if not flow.deplane_passenger(flight, flight.inbound_types[flight.deplaned]):
				break
			flight.deplaned += 1
			flight.deplane_credit -= 1.0
	if flight.cargo and ramp_open and (phase == Flight.Phase.AT_STAND or phase == Flight.Phase.BOARDING):
		flight.tonnes_handled = minf(flight.tonnes_handled + _handling_rate(flight.gate) * delta, flight.tonnes)
	if phase >= Flight.Phase.DEPARTING and flight.phase == Flight.Phase.BOARDING and flight.cargo \
			and flight.tonnes_handled < flight.tonnes and flight.airport_delay() < CARGO_MAX_HOLD:
		# The freight isn't loaded yet: the freighter waits (the airport's delay).
		flight.delay += delta
		phase = Flight.Phase.BOARDING
	if phase == Flight.Phase.BOARDING and ramp_open:
		flight.boarding_credit += BOARDING_RATE * delta
		var boarded := flow.board(flight, floori(flight.boarding_credit))
		flight.boarding_credit -= boarded
		# Unused capacity doesn't pile up while nobody is waiting.
		flight.boarding_credit = minf(flight.boarding_credit, 1.0)
	if phase >= Flight.Phase.DEPARTING and flight.phase == Flight.Phase.BOARDING \
			and flight.airport_delay() < MAX_HOLD and flow.is_anyone_coming(flight):
		# Hold the doors for passengers who are airside or still boarding: a delay (design doc §11.7).
		flight.delay += delta
		phase = Flight.Phase.BOARDING
	if phase >= Flight.Phase.DEPARTING and flight.phase == Flight.Phase.BOARDING:
		# Snow: de-icing before pushback (design doc §12.2), a weather delay.
		var deicing := world.weather.deicing_seconds(world.has_deicing_pad())
		if flight.deiced < deicing:
			flight.deiced += delta
			flight.delay += delta
			flight.weather_delay += delta
			phase = Flight.Phase.BOARDING
	if phase >= Flight.Phase.DEPARTING and flight.phase < Flight.Phase.DEPARTING and not flight.takeoff_booked:
		# The take-off slot (design doc §7.5a): the plane pushes back on time and, if the runway is
		# busy, waits at the holding point. Punctuality counts the push-back, as in real statistics.
		_book_runway(flight, now, true)
		flight.takeoff_booked = true
	if phase >= Flight.Phase.DEPARTING and flight.phase < Flight.Phase.DEPARTING:
		# Only delays the airport caused count (design doc §12.2).
		world.reputation.record_departure(flight.airport_delay())
		# Doors close: whoever isn't on board has missed the flight.
		flight.missed = flow.remove_flight_passengers(flight, true)
		flow.departed_count += flight.boarded
		world.progression.passengers += flight.boarded
		if flight.cargo:
			# Paid per tonne handled (design doc §10.3); the handlers gain experience.
			world.economy.earn(flight.tonnes_handled * flight.fee_per_passenger + Economy.FLIGHT_FEE, Economy.CARGO)
			var handlers := world.staff_working_at(flight.gate)
			for handler in handlers:
				var role := BuildingType.Role.CARGO_TERMINAL
				handler.served[role] = handler.served.get(role, 0) + roundi(flight.tonnes_handled / handlers.size())
		else:
			# The airline pays per passenger (as agreed in its deal) and per flight (design doc §11.5).
			world.economy.earn(flight.boarded * flight.fee_per_passenger + Economy.FLIGHT_FEE)
		var missed_share := float(flight.missed) / maxi(flight.booked, 1)
		world.airlines.record_flight(flight.airline, flight.airport_delay() > Reputation.ON_TIME_LIMIT, missed_share)
	if phase == Flight.Phase.ARRIVING and flight.phase == Flight.Phase.SCHEDULED:
		plane_arriving.emit(flight)
	flight.phase = phase


enum Hold { NONE, WEATHER, AIRPORT }

## Tonnes per second one cargo handler moves (design doc §10.3); experience makes them faster.
const HANDLER_RATE: float = 0.25


func _handling_rate(terminal: Building) -> float:
	var rate := 0.0
	for handler in world.staff_working_at(terminal):
		rate += HANDLER_RATE / handler.time_factor()
	return rate


# Books the runway `flight` uses for `runway_seconds`, from now. False if it is busy, unless
# `queue` is set: then the booking starts when the runway is free again.
func _book_runway(flight: Flight, now: float, queue: bool = false) -> bool:
	var runway := _runway_for(flight)
	if runway == null:
		return true  # no runway known (tests without one): nothing to wait for
	var free_at: float = _runway_free_at.get(runway, -INF)
	if free_at > now and not queue:
		return false
	var start := maxf(now, free_at)
	_runway_free_at[runway] = start + runway_seconds
	runway_bookings.append([runway, start])
	return true


# The runway at the start of the planes' way to `flight`'s stand.
func _runway_for(flight: Flight) -> Building:
	if flight.stand == null:
		return null
	var path := world.plane_network.path_to_stand(flight.stand)
	return world.plane_network.runway_at(path[0]) if not path.is_empty() else null


# Why `flight` must wait this step (design doc §12.2): weather (no landing, no ground work), or
# its stand is still taken by the previous plane at the same gate (knock-on delay; weather if
# that plane was held by weather).
func _hold_reason(flight: Flight, now: float) -> Hold:
	var arrival_left := flight.departs_at() - now + flight.arrival_delay
	var weather := world.weather
	if flight.phase == Flight.Phase.SCHEDULED and arrival_left <= PLANE_ARRIVES:
		if weather.landing_closed():
			return Hold.WEATHER
		for other in flights:
			if other != flight and other.gate == flight.gate and other.is_active() \
					and other.departure_time < flight.departure_time and other.phase != Flight.Phase.SCHEDULED:
				return Hold.WEATHER if other.weather_delay > 0.0 else Hold.AIRPORT
		# A landing slot on the runway (design doc §7.5a).
		if not flight.landing_booked:
			if not _book_runway(flight, now):
				return Hold.AIRPORT
			flight.landing_booked = true
	elif flight.phase >= Flight.Phase.ARRIVING and weather.ramp_closed():
		return Hold.WEATHER
	return Hold.NONE
