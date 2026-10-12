class_name FlightSchedule
extends RefCounted
## Plans and runs flights (design doc §8.5): one departure after another at every usable gate.
## Pure data. PassengerFlow owns it and passes itself into tick() (no stored back reference,
## so the two never keep each other alive).

## Seconds between two departures at the same gate.
const INTERVAL: float = 180.0
## A newly usable gate's first departure is this far in the future.
const FIRST_DEPARTURE_DELAY: float = 210.0
## Gates that become usable at the same moment are spread out by this much.
const GATE_STAGGER: float = 45.0
## Passengers for a flight arrive at the entrance between these times before departure.
const ARRIVALS_START: float = 200.0
const ARRIVALS_END: float = 100.0
## The plane starts taxiing onto the stand this long before departure.
const PLANE_ARRIVES: float = 130.0
## Seconds to taxi onto the stand, and to push back after departure.
const TAXI_TIME: float = 15.0
const BOARDING_OPENS: float = 90.0
## Passengers per second walking from the gate onto the plane.
const BOARDING_RATE: float = 1.0
const SEATS: int = 180
const BOOKED_MIN: int = 12
const BOOKED_MAX: int = 20
## Fictional airline code (design doc §18: no real airlines).
const AIRLINE_CODE: String = "AX"

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
	_last_planned[gate] = departure_time
	flights.append(flight)


func _advance(flight: Flight, now: float, delta: float, flow: PassengerFlow) -> void:
	var time_left := flight.departure_time - now

	# Passengers arrive at the entrance spread over the arrival window.
	var arrived_share := clampf((ARRIVALS_START - time_left) / (ARRIVALS_START - ARRIVALS_END), 0.0, 1.0)
	while flight.spawned < roundi(flight.booked * arrived_share):
		if not flow.spawn_passenger(flight):
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
