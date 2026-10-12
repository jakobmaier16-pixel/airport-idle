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
var gate: Building
var stand: Building
## Simulation time (PassengerFlow.time) when the doors close.
var departure_time: float
var seats: int
var booked: int
var spawned: int = 0
var boarded: int = 0
var missed: int = 0
var phase: Phase = Phase.SCHEDULED
## Fractional passengers allowed through the door so far (boarding happens at a fixed rate).
var boarding_credit: float = 0.0


func is_active() -> bool:
	return phase != Phase.DEPARTED and phase != Phase.CANCELLED
