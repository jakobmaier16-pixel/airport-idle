class_name Flight
extends RefCounted
## One scheduled departure at a gate (design doc §8.5). Pure data.

enum Phase {
	SCHEDULED, ## No plane yet.
	ARRIVING, ## The plane is landing and taxiing onto the stand.
	AT_STAND, ## The plane is parked.
	BOARDING, ## The last stretch before the doors close (the plane is still parked).
	DEPARTING, ## Doors closed; the plane pushes back.
	DEPARTED, ## Gone.
	CANCELLED, ## The gate stopped being usable.
}

var number: String
## The airline flying it (design doc §10.1), or null (tests only).
var airline: Airline = null
## A wide-body (long-haul) plane (design doc §10.2).
var wide_body: bool = false
## A freighter (design doc §10.3): `tonnes` of freight to unload and load.
var cargo: bool = false
var tonnes: float = 0.0
var tonnes_handled: float = 0.0
## What the airline pays: per tonne for freighters (it was per passenger, see docs/removed_features.md).
var fee_per_passenger: float = Economy.PASSENGER_FEE
## Route type, e.g. "Holiday" (sets the season's demand, design doc §12.2).
var route: String = ""
var gate: Building
var stand: Building
## Scheduled time (AirportWorld.sim_time) when the doors close.
var departure_time: float
## Seconds the flight is late in total (knock-on delays and a busy runway, design doc §11.7).
var delay: float = 0.0
## Seconds the plane landed late without delaying the departure: the time at the stand absorbs it
## (turnaround buffer, design doc §7.5a).
var arrival_delay: float = 0.0
## Runway slots booked for landing and take-off (design doc §7.5a).
var landing_booked: bool = false
var takeoff_booked: bool = false
## When the take-off run starts (after taxiing out and any wait at the runway); -1 until booked.
var takeoff_at: float = -1.0
var phase: Phase = Phase.SCHEDULED
## Fractional passengers allowed through the door so far (boarding happens at a fixed rate).
var boarding_credit: float = 0.0


## When the doors actually close (or closed): the scheduled time plus any delay.
func departs_at() -> float:
	return departure_time + delay


## The part of the delay the airport is responsible for (all of it, now that nothing else delays flights).
func airport_delay() -> float:
	return delay


func is_active() -> bool:
	return phase != Phase.DEPARTED and phase != Phase.CANCELLED
