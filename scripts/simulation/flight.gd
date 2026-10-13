class_name Flight
extends RefCounted
## One scheduled departure at a gate (design doc §8.5). Pure data.
## Passengers point to their flight; the flight never points to passengers (no reference cycles).

enum Phase {
	SCHEDULED, ## No plane yet; passengers may already be arriving.
	ARRIVING, ## The plane is taxiing onto the stand.
	AT_STAND, ## The plane is parked; boarding hasn't opened yet.
	BOARDING, ## Passengers walk from the gate onto the plane.
	DEPARTING, ## Doors closed; the plane pushes back.
	DEPARTED, ## Gone.
	CANCELLED, ## The gate stopped being usable.
}

var number: String
## The airline flying it (design doc §10.1), or null (tests only).
var airline: Airline = null
## A wide-body (long-haul) plane (design doc §10.2).
var wide_body: bool = false
## A VIP flies with this flight; the next passenger to arrive is them (design doc §14.2).
var vip_pending: bool = false
## A freighter (design doc §10.3): no passengers, `tonnes` of freight to unload and load.
var cargo: bool = false
var tonnes: float = 0.0
var tonnes_handled: float = 0.0
## What the airline pays per departing passenger.
var fee_per_passenger: float = Economy.PASSENGER_FEE
## Route type, e.g. "Holiday" (sets the passenger mix, design doc §8.7).
var route: String = ""
var gate: Building
var stand: Building
## Scheduled time (PassengerFlow.time) when the doors close.
var departure_time: float
## Seconds the flight is late in total: waiting for passengers who were already airside
## (design doc §11.7), weather and knock-on delays (§12.2).
var delay: float = 0.0
## Seconds the plane landed late without delaying the departure: the time at the stand absorbs it
## (turnaround buffer, design doc §7.5a).
var arrival_delay: float = 0.0
## The part of `delay` caused by weather (doesn't count against the airport).
var weather_delay: float = 0.0
## Seconds of de-icing done (snow, design doc §12.2).
var deiced: float = 0.0
## Runway slots booked for landing and take-off (design doc §7.5a).
var landing_booked: bool = false
var takeoff_booked: bool = false
var seats: int
var booked: int
## When each booked passenger arrives at the entrance (simulation time, ascending) and their type.
var arrival_times: PackedFloat32Array = PackedFloat32Array()
var arrival_types: Array[PassengerType] = []
## How many of them have arrived so far.
var spawned: int = 0
## Passengers on the inbound plane (design doc §8.8), and how many have deplaned so far.
var inbound_types: Array[PassengerType] = []
var deplaned: int = 0
var deplane_credit: float = 0.0
var boarded: int = 0
var missed: int = 0
var phase: Phase = Phase.SCHEDULED
## Fractional passengers allowed through the door so far (boarding happens at a fixed rate).
var boarding_credit: float = 0.0


## When the doors actually close (or closed): the scheduled time plus any delay.
func departs_at() -> float:
	return departure_time + delay


## The part of the delay the airport is responsible for.
func airport_delay() -> float:
	return delay - weather_delay


func is_active() -> bool:
	return phase != Phase.DEPARTED and phase != Phase.CANCELLED
