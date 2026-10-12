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
const GATE_STAGGER: float = 45.0
## The earliest any passenger type arrives before departure (see data/passengers/); the next
## flight at a gate is planned this long before it departs.
const ARRIVALS_START: float = 260.0
## The plane starts taxiing onto the stand this long before departure.
const PLANE_ARRIVES: float = 130.0
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
## Fictional airline code (design doc §18: no real airlines).
const AIRLINE_CODE: String = "AX"
## Passenger types (design doc §8.7).
const FAMILY: PassengerType = preload("res://data/passengers/family.tres")
const LOW_COST: PassengerType = preload("res://data/passengers/low_cost.tres")
const BUSINESS: PassengerType = preload("res://data/passengers/business.tres")
## Share of a route's arriving passengers who connect to another flight (design doc §8.9).
const TRANSFER_SHARES: Dictionary = {"Holiday": 0.1, "Low-cost": 0.05, "Business": 0.25}
## A connecting flight must depart at least this long after the transfer passenger deplanes.
const MIN_CONNECTION: float = 150.0
## Route types and their passenger mix: [families, low-cost, business] shares.
const ROUTES: Dictionary = {
	"Holiday": [0.7, 0.2, 0.1],
	"Low-cost": [0.15, 0.8, 0.05],
	"Business": [0.1, 0.3, 0.6],
}

## Every flight that hasn't departed yet. A gate can have two: the one at the stand and the
## next one, whose passengers are already arriving (like at a real airport).
var flights: Array[Flight] = []

# Departure time of the latest flight planned at each gate.
var _last_planned: Dictionary[Building, float] = {}
var _next_number: int = 101
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func tick(now: float, delta: float, flow: PassengerFlow) -> void:
	var usable := flow.usable_gates()
	for flight in flights:
		if not usable.has(flight.gate):
			flight.phase = Flight.Phase.CANCELLED
			flow.remove_flight_passengers(flight, false)
			_last_planned.erase(flight.gate)
	flights = flights.filter(func(f: Flight) -> bool: return f.is_active())

	# Plan ahead: each gate always has its next flight planned before its passengers must arrive.
	var new_gates := 0
	for gate in usable:
		if not _last_planned.has(gate):
			_schedule(gate, now + FIRST_DEPARTURE_DELAY + new_gates * GATE_STAGGER)
			new_gates += 1
		# The next flight is planned exactly when its passengers have to start arriving.
		while _last_planned[gate] + INTERVAL - now <= ARRIVALS_START:
			_schedule(gate, _last_planned[gate] + INTERVAL)

	for flight in flights:
		_advance(flight, now, delta, flow)
	flights = flights.filter(func(f: Flight) -> bool: return f.is_active())


## The flights in departure order, for the departures board.
func upcoming() -> Array[Flight]:
	var sorted := flights.duplicate()
	sorted.sort_custom(func(a: Flight, b: Flight) -> bool: return a.departure_time < b.departure_time)
	return sorted


func _schedule(gate: Building, departure_time: float) -> void:
	var flight := Flight.new()
	flight.number = "%s %d" % [AIRLINE_CODE, _next_number]
	_next_number += 1
	flight.gate = gate
	flight.stand = Airport.stand_behind(gate)
	flight.seats = SEATS
	flight.booked = _rng.randi_range(BOOKED_MIN, BOOKED_MAX)
	flight.departure_time = departure_time
	# Random route for now; later airlines and deals decide (design doc §10).
	flight.route = ROUTES.keys()[_rng.randi() % ROUTES.size()]
	_plan_arrivals(flight)
	# The inbound leg: the same plane brings passengers before it takes new ones (turnaround).
	var mix := PackedFloat32Array(ROUTES[flight.route])
	var types: Array[PassengerType] = [FAMILY, LOW_COST, BUSINESS]
	for i in _rng.randi_range(BOOKED_MIN, BOOKED_MAX):
		flight.inbound_types.append(types[_rng.rand_weighted(mix)])
	_last_planned[gate] = departure_time
	flights.append(flight)


# Decides type and arrival time of every booked passenger, from the route's mix.
func _plan_arrivals(flight: Flight) -> void:
	var mix: Array = ROUTES[flight.route]
	var types: Array[PassengerType] = [FAMILY, LOW_COST, BUSINESS]
	var arrivals: Array = []
	for i in flight.booked:
		var type := types[_rng.rand_weighted(PackedFloat32Array(mix))]
		var before := _rng.randf_range(type.arrives_until, type.arrives_from)
		arrivals.append([flight.departure_time - before, type])
	arrivals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for arrival: Array in arrivals:
		flight.arrival_times.append(arrival[0])
		flight.arrival_types.append(arrival[1])


func _advance(flight: Flight, now: float, delta: float, flow: PassengerFlow) -> void:
	var time_left := flight.departure_time - now

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
	elif time_left <= PLANE_ARRIVES - TAXI_TIME:
		phase = Flight.Phase.AT_STAND
	elif time_left <= PLANE_ARRIVES:
		phase = Flight.Phase.ARRIVING

	if phase == Flight.Phase.AT_STAND or (phase == Flight.Phase.BOARDING and flight.deplaned < flight.inbound_types.size()):
		# Arriving passengers leave the plane first; whoever is left when boarding opens leaves at once.
		flight.deplane_credit += DEPLANE_RATE * delta
		if phase == Flight.Phase.BOARDING:
			flight.deplane_credit = flight.inbound_types.size()
		while flight.deplane_credit >= 1.0 and flight.deplaned < flight.inbound_types.size():
			if not flow.deplane_passenger(flight, flight.inbound_types[flight.deplaned]):
				break
			flight.deplaned += 1
			flight.deplane_credit -= 1.0
	if phase == Flight.Phase.BOARDING:
		flight.boarding_credit += BOARDING_RATE * delta
		var boarded := flow.board(flight, floori(flight.boarding_credit))
		flight.boarding_credit -= boarded
		# Unused capacity doesn't pile up while nobody is waiting.
		flight.boarding_credit = minf(flight.boarding_credit, 1.0)
	if phase >= Flight.Phase.DEPARTING and flight.phase < Flight.Phase.DEPARTING:
		# Doors close: whoever isn't on board has missed the flight.
		flight.missed = flow.remove_flight_passengers(flight, true)
		flow.departed_count += flight.boarded
		# The airline pays per passenger and per flight (design doc §11.5).
		Airport.economy.earn(flight.boarded * Economy.PASSENGER_FEE + Economy.FLIGHT_FEE)
	flight.phase = phase
