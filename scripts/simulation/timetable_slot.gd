class_name TimetableSlot
extends RefCounted
## One planned departure in the daily timetable (tech_architecture.md §6). Pure data.
## A slot is a promise of demand: FlightSchedule turns it into a Flight when its arrivals window
## opens, or drops it when no gate fits.

## The kind of plane a slot needs; the gate's stand decides what fits (stand_behind).
enum PlaneClass { NARROW, WIDE, CARGO }
## Wingspan in metres of each class (data for the stand rule: a stand must be at least this wide).
## Freighters are narrow-body size (A321F / 737F class).
const WINGSPAN_M: Dictionary[PlaneClass, float] = {PlaneClass.NARROW: 37.0, PlaneClass.WIDE: 65.0, PlaneClass.CARGO: 37.0}
enum State { PENDING, FILLED, DROPPED }

## Departure time in simulation seconds (AirportWorld.sim_time, real seconds for now).
var departure_time: float = 0.0
## The game day it belongs to (Clock.day()).
var day: int = 1
var plane_class: PlaneClass = PlaneClass.NARROW
## Route type (sets the season's demand, design doc §12.2).
var route: String = "Holiday"
var state: State = State.PENDING
## Filled in when the slot becomes a flight: the airline's code ("" until then) and flight number.
var airline_code: String = ""
var flight_number: String = ""


## Size order of the classes (0 = narrow-body size), compared with `BuildingType.stand_class`.
static func size_rank(plane_class: PlaneClass) -> int:
	return 1 if WINGSPAN_M[plane_class] > WINGSPAN_M[PlaneClass.NARROW] else 0


func to_dict() -> Dictionary:
	return {
		"time": departure_time, "day": day, "class": int(plane_class), "route": route,
		"state": int(state), "airline": airline_code, "number": flight_number,
	}


static func from_dict(entry: Dictionary) -> TimetableSlot:
	var slot := TimetableSlot.new()
	slot.departure_time = float(entry.get("time", 0.0))
	slot.day = int(entry.get("day", 1))
	slot.plane_class = clampi(int(entry.get("class", 0)), 0, PlaneClass.CARGO) as PlaneClass
	slot.route = str(entry.get("route", "Holiday"))
	slot.state = clampi(int(entry.get("state", 0)), 0, State.DROPPED) as State
	slot.airline_code = str(entry.get("airline", ""))
	slot.flight_number = str(entry.get("number", ""))
	return slot
