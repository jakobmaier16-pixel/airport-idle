class_name Timetable
extends RefCounted
## The fixed timetable (tech_architecture.md §6): every usable gate with its stand gets one
## turnaround every TURNAROUND_SECONDS simulation seconds. No dice: the times follow from the
## gate's permanent ID alone, so the same airport always flies the same pattern.
## A narrow stand gets narrow planes, a wide stand wide planes. FlightSchedule turns the slots into
## Flights. All times are simulation seconds (AirportWorld.sim_time); there is no time of day
## (docs/removed_features.md). Pure data; the brain owns it and steps it.

## Seconds between two departures at one gate: the one number the whole pattern is made of.
## The plane also needs its taxi both ways inside it.
const TURNAROUND_SECONDS: float = 360.0
## Gates are shifted against each other by this many seconds per gate ID (modulo the
## turnaround), so their planes do not all arrive at once.
const STAGGER_SECONDS: float = 68.0
## Slots are planned this many turnarounds ahead (and at least one beyond the first possible one).
const PLAN_TURNAROUNDS: int = 2
## A fresh airport opens with one flight, off the grid: the plane of one gate touches down this
## many seconds after the start, so the first landing happens within the first minute instead of
## after the grid's first slot. The grid slot after it keeps its time (unless it would be less
## than a turnaround later: it is skipped), so the rest of the pattern is unchanged.
const OPENING_LANDING_DELAY: float = 20.0
## Done slots are kept this long (seconds) for the departures board.
const KEEP_SECONDS: float = 5760.0

var world: AirportWorld
var slots: Array[TimetableSlot] = []
# Per gate ID: the time (sim seconds) of the next departure that is not planned yet.
var _next: Dictionary[int, float] = {}
# True once the airport has planned anything: the opening flight happens once per fresh airport, never
# again after all flights got cancelled or a gate was rebuilt.
var _opened: bool = false


## The time (sim seconds) of the first departure of `gate_id` at or after `time`.
static func next_departure_at_or_after(gate_id: int, time: float) -> float:
	var phase := fmod(gate_id * STAGGER_SECONDS, TURNAROUND_SECONDS)
	return phase + ceilf((time - phase) / TURNAROUND_SECONDS) * TURNAROUND_SECONDS


func clear() -> void:
	slots.clear()
	_next.clear()
	_opened = false


func tick() -> void:
	var now := world.sim_time
	var usable := world.usable_gates()
	# A gate that stopped working loses its planned turnarounds (and starts again from now later).
	if _next.size() > 0 or not slots.is_empty():
		slots = slots.filter(func(s: TimetableSlot) -> bool:
			return s.state != TimetableSlot.State.PENDING or usable.has(s.gate))
		for gate_id in _next.keys():
			if not usable.any(func(g: Building) -> bool: return g.id == gate_id):
				_next.erase(gate_id)
	var earliest := now + world.schedule.first_departure_delay()
	var horizon := now + maxf(PLAN_TURNAROUNDS * TURNAROUND_SECONDS, earliest - now + TURNAROUND_SECONDS)
	var added := false
	# Only a fresh airport opens with a flight: nothing is planned or flying yet. It goes to the gate
	# whose first grid slot is the latest (the one that would wait longest), ties to the first gate.
	var opening_gate: Building = null
	if not _opened and slots.is_empty() and _next.is_empty() and world.schedule.flights.is_empty():
		var latest := -INF
		for gate in usable:
			if world.stand_behind(gate) != null:
				var first_slot := next_departure_at_or_after(gate.id, earliest)
				if first_slot > latest:
					latest = first_slot
					opening_gate = gate
	for gate in usable:
		var stand := world.stand_behind(gate)
		if stand == null:
			continue
		var plane_class := TimetableSlot.PlaneClass.WIDE if stand.type.wide_body else TimetableSlot.PlaneClass.NARROW
		var first_grid := earliest
		if gate == opening_gate:
			# The grid slot after the opening flight keeps its place, unless it would be less than a
			# turnaround after it: then it is skipped.
			var grid_first := next_departure_at_or_after(gate.id, earliest)
			var opening := now + FlightSchedule.lead_of(world.plane_network.route_to_stand(stand)) \
				+ FlightSchedule.APPROACH_TIME + OPENING_LANDING_DELAY
			if opening < grid_first:
				world.schedule.add_opening_flight(gate, opening, plane_class)
				if grid_first < opening + TURNAROUND_SECONDS:
					first_grid = grid_first + TURNAROUND_SECONDS
		var next: float = _next.get(gate.id, next_departure_at_or_after(gate.id, first_grid))
		while next <= maxf(horizon, first_grid + TURNAROUND_SECONDS):
			var slot := TimetableSlot.new()
			slot.gate = gate
			slot.plane_class = plane_class
			slot.departure_time = next
			slots.append(slot)
			added = true
			next += TURNAROUND_SECONDS
		_next[gate.id] = next
	if added or opening_gate != null:
		_opened = true
	if added:
		slots.sort_custom(_by_time)
	# Slots are sorted by departure: only when the oldest one has expired is there anything to prune.
	var limit := now - KEEP_SECONDS
	if not slots.is_empty() and slots[0].departure_time <= limit:
		var expired := 0
		while expired < slots.size() and slots[expired].departure_time <= limit:
			expired += 1
		slots = slots.slice(expired)


## The slots still waiting for their flight, in departure order.
func pending() -> Array[TimetableSlot]:
	return slots.filter(func(s: TimetableSlot) -> bool: return s.state == TimetableSlot.State.PENDING)


func save_state() -> Dictionary:
	var saved: Array = []
	for slot in slots:
		saved.append(slot.to_dict())
	var next: Array = []
	for gate_id in _next:
		next.append([gate_id, _next[gate_id]])
	return {"slots": saved, "next": next}


## Restores from save_state(). Without data nothing is planned yet: the next tick plans it.
func load_state(data: Dictionary, by_id: Dictionary[int, Building] = {}) -> void:
	clear()
	for entry: Dictionary in data.get("slots", []):
		var slot := TimetableSlot.from_dict(entry, by_id)
		if slot != null:
			slots.append(slot)
	for pair: Array in data.get("next", []):
		if by_id.has(int(pair[0])):
			_next[int(pair[0])] = float(pair[1])
	slots.sort_custom(_by_time)


static func _by_time(a: TimetableSlot, b: TimetableSlot) -> bool:
	return a.departure_time < b.departure_time
