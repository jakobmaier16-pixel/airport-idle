class_name Timetable
extends RefCounted
## The daily timetable (tech_architecture.md §6): every flight the airport could get on a game day,
## planned once, shortly before the day starts (and at the first start / load if missing).
## Flights per hour = Demand.value x Clock.DEMAND_BY_HOUR[hour]; none in curfew hours (a Hub flies
## all night). FlightSchedule turns slots into Flights. Pure data; the brain owns it and steps it.

const WIDE_FLIGHTS_PER_HOUR: float = 0.5
const CARGO_FLIGHTS_PER_HOUR: float = 0.5
## The next day's slots are made at this hour: ahead of the first arrivals window after midnight.
const GENERATE_HOUR: float = 22.0
## Done slots are kept this long (real seconds, one game day) for the departures board and stats.
const KEEP_SECONDS: float = 5760.0
## The default airline: fills narrow-body slots when no deal does (a regional carrier).
const DEFAULT_AIRLINE: StringName = &"velora"

var world: AirportWorld
var slots: Array[TimetableSlot] = []
## The game days whose slots exist.
var generated_days: Array[int] = []
# Game time minus the clock's running time: changes only when something jumps the time of day.
var _offset: float = 0.0


## The default airline's type (also what the departures use when no deal fills a slot).
static func default_airline() -> AirlineType:
	return Airlines.CATALOG.find(DEFAULT_AIRLINE)


func clear() -> void:
	slots.clear()
	generated_days.clear()
	_offset = world.clock.game_seconds - world.clock.elapsed if world != null else 0.0


func tick() -> void:
	var clock := world.clock
	var offset := clock.game_seconds - clock.elapsed
	if absf(offset - _offset) > 1.0:
		# The time of day was jumped (tests, dev tools): planned slots no longer match it.
		slots = slots.filter(func(s: TimetableSlot) -> bool: return s.state != TimetableSlot.State.PENDING)
		generated_days.clear()
		_offset = offset
	var day := clock.day()
	if not generated_days.has(day):
		generate_day(day)
	if clock.hour() >= GENERATE_HOUR and not generated_days.has(day + 1):
		generate_day(day + 1)
	# Slots are sorted by departure: only when the oldest one has expired is there anything to prune.
	var limit := world.passenger_flow.time - KEEP_SECONDS
	if not slots.is_empty() and slots[0].departure_time <= limit:
		var expired := 0
		while expired < slots.size() and slots[expired].departure_time <= limit:
			expired += 1
		slots = slots.slice(expired)
	# Only the recent days matter (a day is never planned twice); the list must not grow forever.
	while not generated_days.is_empty() and generated_days[0] < day - 2:
		generated_days.remove_at(0)


## Plans the slots of game day `day` that still lie ahead (a new airport opens at 06:00, so the
## hours before are skipped). Rolls only the shared dice.
func generate_day(day: int) -> void:
	generated_days.append(day)
	var now := world.passenger_flow.time
	var earliest := now + FlightSchedule.FIRST_DEPARTURE_DELAY
	var shares := _route_shares()
	var season := Seasons.season_of(day)
	var day_start := (day - 1) * 86400.0
	for hour in 24:
		var hour_start := day_start + hour * 3600.0
		var rate := Clock.DEMAND_BY_HOUR[hour]
		var wanted: Array[Array] = []  # [route, plane class] per slot of this hour
		for route: String in shares:
			_add_count(wanted, world.demand.value * rate * shares[route] * Seasons.demand_factor(route, season), route, TimetableSlot.PlaneClass.NARROW)
		_add_count(wanted, WIDE_FLIGHTS_PER_HOUR * rate, "Long-haul", TimetableSlot.PlaneClass.WIDE)
		_add_count(wanted, CARGO_FLIGHTS_PER_HOUR * rate, "Cargo", TimetableSlot.PlaneClass.CARGO)
		_shuffle(wanted)
		for i in wanted.size():
			# Spread over the hour instead of clumping: slot i gets the i-th part of it.
			var game_time := hour_start + (i + rng_range(0.15, 0.85)) / wanted.size() * 3600.0
			var departure := now + (game_time - world.clock.game_seconds) / Clock.GAME_PER_REAL
			if departure < earliest or _in_curfew(departure, now):
				continue
			var slot := TimetableSlot.new()
			slot.departure_time = departure
			slot.day = day
			slot.route = wanted[i][0]
			slot.plane_class = wanted[i][1]
			slot.seats = 0 if slot.plane_class == TimetableSlot.PlaneClass.CARGO \
				else roundi(FlightSchedule.SEATS * (FlightSchedule.WIDE_BODY_FACTOR if slot.plane_class == TimetableSlot.PlaneClass.WIDE else 1.0))
			slots.append(slot)
	slots.sort_custom(func(a: TimetableSlot, b: TimetableSlot) -> bool: return a.departure_time < b.departure_time)


## True if a plane may neither land nor take off for a slot at `departure` (the plane arrives
## before it leaves, so both ends count).
func in_curfew(departure: float) -> bool:
	return _in_curfew(departure, world.passenger_flow.time)


func _in_curfew(departure: float, now: float) -> bool:
	return world.curfew_at(departure - now) or world.curfew_at(departure - FlightSchedule.PLANE_ARRIVES - now)


## The slots still waiting for their flight, in departure order.
func pending() -> Array[TimetableSlot]:
	return slots.filter(func(s: TimetableSlot) -> bool: return s.state == TimetableSlot.State.PENDING)


## How many slots of game day `day` have this state.
func count(day: int, state: TimetableSlot.State) -> int:
	var total := 0
	for slot in slots:
		if slot.day == day and slot.state == state:
			total += 1
	return total


func save_state() -> Dictionary:
	var saved: Array = []
	for slot in slots:
		saved.append(slot.to_dict())
	return {"generated_days": generated_days.duplicate(), "slots": saved}


## Restores from save_state(). Without data nothing is planned yet: the next tick plans today.
func load_state(data: Dictionary) -> void:
	clear()
	for day in data.get("generated_days", []):
		generated_days.append(int(day))
	for entry: Dictionary in data.get("slots", []):
		slots.append(TimetableSlot.from_dict(entry))
	slots.sort_custom(func(a: TimetableSlot, b: TimetableSlot) -> bool: return a.departure_time < b.departure_time)


# The routes narrow-body slots fly and their shares: the signed airlines' routes weighted by their
# quotas, or the default airline's route when no deal exists.
func _route_shares() -> Dictionary:
	var weights: Dictionary = {}
	var total := 0.0
	for airline in world.airlines.signed:
		if airline.type.cargo or airline.type.wide_body:
			continue
		weights[airline.type.route] = weights.get(airline.type.route, 0.0) + airline.flights_per_hour
		total += airline.flights_per_hour
	if total <= 0.0:
		return {default_airline().route: 1.0}
	for route in weights:
		weights[route] /= total
	return weights


# `expected` slots on average: the whole part always, the fraction by chance.
func _add_count(wanted: Array[Array], expected: float, route: String, plane_class: TimetableSlot.PlaneClass) -> void:
	var n := floori(expected)
	if world.rng.randf() < expected - n:
		n += 1
	for i in n:
		wanted.append([route, plane_class])


func rng_range(low: float, high: float) -> float:
	return world.rng.randf_range(low, high)


# Fisher-Yates with the shared dice (Array.shuffle() would use the unseeded global ones).
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := world.rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
