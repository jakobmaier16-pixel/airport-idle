class_name Timetable
extends RefCounted
## The fixed timetable (tech_architecture.md §6): every usable gate with its stand gets one
## turnaround every TURNAROUND_MINUTES game minutes, all day and night. No dice: the times follow
## from the gate's permanent ID alone, so the same airport always flies the same pattern.
## A narrow stand gets narrow planes, a wide stand wide planes. FlightSchedule turns the slots into
## Flights. Pure data; the brain owns it and steps it.

## Game minutes between two departures at one gate: the one number the whole pattern is made of.
## A real turnaround is 45 to 60 minutes; the plane also needs its taxi both ways inside it.
const TURNAROUND_MINUTES: float = 90.0
## Gates are shifted against each other by this many game minutes per gate ID (modulo the
## turnaround), so their planes do not all arrive at once.
const STAGGER_MINUTES: float = 17.0
## Slots are planned this many turnarounds ahead (and at least one beyond the first possible one).
const PLAN_TURNAROUNDS: int = 2
## Done slots are kept this long (real seconds, one game day) for the departures board.
const KEEP_SECONDS: float = 5760.0

var world: AirportWorld
var slots: Array[TimetableSlot] = []
# Per gate ID: the game time (seconds) of the next departure that is not planned yet.
var _next: Dictionary[int, float] = {}
# Game time minus the clock's running time: changes only when something jumps the time of day.
var _offset: float = 0.0


## Seconds between two departures at one gate, in game seconds.
static func period_game() -> float:
	return TURNAROUND_MINUTES * 60.0


## The same in real seconds (what the simulation times are in).
static func period_real() -> float:
	return period_game() / Clock.GAME_PER_REAL


## The game time (seconds since midnight of day 1) of the first departure of `gate_id` at or after `game_time`.
static func next_departure_at_or_after(gate_id: int, game_time: float) -> float:
	var phase := fmod(gate_id * STAGGER_MINUTES, TURNAROUND_MINUTES) * 60.0
	var period := period_game()
	return phase + ceilf((game_time - phase) / period) * period


func clear() -> void:
	slots.clear()
	_next.clear()
	_offset = world.clock.game_seconds - world.clock.elapsed if world != null else 0.0


func tick() -> void:
	var clock := world.clock
	var offset := clock.game_seconds - clock.elapsed
	if absf(offset - _offset) > 1.0:
		# The time of day was jumped (tests, dev tools): planned slots no longer match it.
		slots = slots.filter(func(s: TimetableSlot) -> bool: return s.state != TimetableSlot.State.PENDING)
		_next.clear()
		_offset = offset
	var now := world.sim_time
	var usable := world.usable_gates()
	# A gate that stopped working loses its planned turnarounds (and starts again from now later).
	if _next.size() > 0 or not slots.is_empty():
		slots = slots.filter(func(s: TimetableSlot) -> bool:
			return s.state != TimetableSlot.State.PENDING or usable.has(s.gate))
		for gate_id in _next.keys():
			if not usable.any(func(g: Building) -> bool: return g.id == gate_id):
				_next.erase(gate_id)
	var game_now := clock.game_seconds
	var earliest := game_now + world.schedule.first_departure_delay() * Clock.GAME_PER_REAL
	var horizon := game_now + maxf(PLAN_TURNAROUNDS * period_game(), earliest - game_now + period_game())
	var added := false
	for gate in usable:
		var stand := world.stand_behind(gate)
		if stand == null:
			continue
		var plane_class := TimetableSlot.PlaneClass.WIDE if stand.type.wide_body else TimetableSlot.PlaneClass.NARROW
		var next: float = _next.get(gate.id, next_departure_at_or_after(gate.id, earliest))
		while next <= horizon:
			var slot := TimetableSlot.new()
			slot.gate = gate
			slot.plane_class = plane_class
			slot.departure_time = now + (next - game_now) / Clock.GAME_PER_REAL
			slots.append(slot)
			added = true
			next += period_game()
		_next[gate.id] = next
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
