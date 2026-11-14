class_name Flight
extends RefCounted
## One scheduled departure at a gate. Pure data.

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
## The class of the plane (it fits the stand behind the gate).
var plane_class: TimetableSlot.PlaneClass = TimetableSlot.PlaneClass.NARROW
var gate: Building
var stand: Building
## Scheduled time (AirportWorld.sim_time) when the doors close.
var departure_time: float
## Seconds the flight is late in total (knock-on delays and a busy runway).
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


## When the doors actually close (or closed): the scheduled time plus any delay.
func departs_at() -> float:
	return departure_time + delay


func is_active() -> bool:
	return phase != Phase.DEPARTED and phase != Phase.CANCELLED
