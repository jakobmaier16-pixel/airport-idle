class_name TimetableSlot
extends RefCounted
## One planned departure in the timetable (tech_architecture.md §6). Pure data.
## A slot is one turnaround at one gate: FlightSchedule turns it into a Flight when its arrivals
## window opens, or drops it when the plane could not make it in time.

## The kind of plane a slot needs; the gate's stand decides what fits.
enum PlaneClass { NARROW, WIDE }
## Wingspan in metres of each class (data for the stand rule: a stand must be at least this wide).
const WINGSPAN_M: Dictionary[PlaneClass, float] = {PlaneClass.NARROW: 37.0, PlaneClass.WIDE: 65.0}
enum State { PENDING, FILLED, DROPPED }

## Departure time in simulation seconds (AirportWorld.sim_time, real seconds).
var departure_time: float = 0.0
var plane_class: PlaneClass = PlaneClass.NARROW
## The gate it is planned for (the plane parks on the stand behind it).
var gate: Building = null
var state: State = State.PENDING
## Filled in when the slot becomes a flight ("" until then).
var flight_number: String = ""


## Size order of the classes (0 = narrow-body size), compared with `BuildingType.stand_class`.
static func size_rank(plane_class: PlaneClass) -> int:
	return 1 if WINGSPAN_M[plane_class] > WINGSPAN_M[PlaneClass.NARROW] else 0


func to_dict() -> Dictionary:
	return {
		"time": departure_time, "class": int(plane_class), "gate": gate.id if gate != null else 0,
		"state": int(state), "number": flight_number,
	}


## The slot of a saved entry, or null if its gate is gone.
static func from_dict(entry: Dictionary, by_id: Dictionary[int, Building]) -> TimetableSlot:
	var slot_gate: Building = by_id.get(int(entry.get("gate", 0)))
	if slot_gate == null:
		return null
	var slot := TimetableSlot.new()
	slot.gate = slot_gate
	slot.departure_time = float(entry.get("time", 0.0))
	slot.plane_class = clampi(int(entry.get("class", 0)), 0, PlaneClass.WIDE) as PlaneClass
	slot.state = clampi(int(entry.get("state", 0)), 0, State.DROPPED) as State
	slot.flight_number = str(entry.get("number", ""))
	return slot
