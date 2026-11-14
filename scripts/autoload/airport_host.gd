class_name AirportHost
extends Node
## The autoload "Airport": the Godot-facing shell around the simulation brain (airport_brain.gd).
## It owns the brain, advances it in fixed steps from `_process`, and forwards every property,
## method and signal, so scenes and tests keep writing `Airport.x`. All rules live in the brain.

signal building_placed(building: Building)
signal building_upgraded(building: Building)
signal restructured(sold: PackedStringArray)
signal staff_changed(building: Building)
signal land_changed
signal building_removed(building: Building)
signal zones_changed
signal walkways_changed
signal layout_changed
signal tier_reached(tier: Progression.Tier)
signal offer_arrived(offer: AirlineOffer)
signal airline_unhappy(airline: Airline)
signal airline_left(airline: Airline)
signal plane_arriving(flight: Flight)

## Most steps caught up in one frame, so a slow frame can't snowball.
const MAX_STEPS_PER_FRAME: int = 5
const CELL_SIZE: float = AirportWorld.CELL_SIZE
const MAP_SIZE_CELLS: Vector2i = AirportWorld.MAP_SIZE_CELLS
const CATALOG: BuildingCatalog = AirportWorld.CATALOG
const SALARIES: Dictionary = AirportWorld.SALARIES
const SIM_STEP: float = AirportWorld.SIM_STEP
const NOBODY_THERE: Vector3 = AirportWorld.NOBODY_THERE
const FAST_TRACK_COST: float = AirportWorld.FAST_TRACK_COST

## The simulation. Replaced by a fresh one on every `reset()`, so never keep it (or any part of it)
## in a variable across a reset: read it through `Airport` each time.
var brain: AirportWorld = AirportWorld.new()
## How far the current frame is between the last and the next simulation step (0..1).
var sim_alpha: float = 0.0
## How long each simulation step of the current frame took, in microseconds (for the device
## benchmark, scripts/dev/benchmark.gd). Refilled every frame.
var last_heartbeats_usec: PackedInt32Array = PackedInt32Array()
var _sim_time: float = 0.0


func _ready() -> void:
	_bind()


func _process(delta: float) -> void:
	_sim_time += delta
	var steps := 0
	last_heartbeats_usec.clear()
	while _sim_time >= AirportWorld.SIM_STEP and steps < MAX_STEPS_PER_FRAME:
		var started := Time.get_ticks_usec()
		brain.step(AirportWorld.SIM_STEP)
		last_heartbeats_usec.append(Time.get_ticks_usec() - started)
		_sim_time -= AirportWorld.SIM_STEP
		steps += 1
	_sim_time = minf(_sim_time, AirportWorld.SIM_STEP)
	sim_alpha = _sim_time / AirportWorld.SIM_STEP


# The brain is a RefCounted full of cross references: free them explicitly (see AirportWorld.dispose).
func _exit_tree() -> void:
	brain.dispose()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and brain != null:
		brain.dispose()


# The brain's signals are re-emitted here, so listeners connect once to `Airport` and stay valid
# when the brain is replaced. Called again for every new brain: it first disconnects the old one,
# so nothing is ever connected twice.
const SIGNALS: Array[StringName] = [
	&"building_placed", &"building_upgraded",
	&"restructured", &"staff_changed", &"land_changed", &"building_removed", &"zones_changed",
	&"walkways_changed", &"layout_changed", &"tier_reached", &"offer_arrived",
	&"airline_unhappy", &"airline_left", &"plane_arriving",
]
var _bound: AirportWorld = null


func _bind() -> void:
	if _bound != null:
		for name in SIGNALS:
			if _bound.is_connected(name, Signal(self, name).emit):
				_bound.disconnect(name, Signal(self, name).emit)
	_bound = brain
	for name in SIGNALS:
		brain.connect(name, Signal(self, name).emit)


# --- Forwards to the brain ---

var grid: AirportGrid:
	get:
		return brain.grid
	set(value):
		brain.grid = value

var buildings: Array[Building]:
	get:
		return brain.buildings
	set(value):
		brain.buildings = value

var passenger_flow: PassengerFlow:
	get:
		return brain.passenger_flow
	set(value):
		brain.passenger_flow = value

var plane_network: PlaneNetwork:
	get:
		return brain.plane_network
	set(value):
		brain.plane_network = value

var economy: Economy:
	get:
		return brain.economy
	set(value):
		brain.economy = value

var airlines: Airlines:
	get:
		return brain.airlines
	set(value):
		brain.airlines = value

var clock: Clock:
	get:
		return brain.clock
	set(value):
		brain.clock = value

var timetable: Timetable:
	get:
		return brain.timetable
	set(value):
		brain.timetable = value

var goals: Goals:
	get:
		return brain.goals
	set(value):
		brain.goals = value

var progression: Progression:
	get:
		return brain.progression
	set(value):
		brain.progression = value

var demand: Demand:
	get:
		return brain.demand
	set(value):
		brain.demand = value
var reputation: Reputation:
	get:
		return brain.reputation
	set(value):
		brain.reputation = value

var staff: Array[Employee]:
	get:
		return brain.staff
	set(value):
		brain.staff = value

var manager_position: Vector3:
	get:
		return brain.manager_position
	set(value):
		brain.manager_position = value

var manager_yaw: float:
	get:
		return brain.manager_yaw
	set(value):
		brain.manager_yaw = value

var saved_manager: Dictionary:
	get:
		return brain.saved_manager
	set(value):
		brain.saved_manager = value

## What the last load_state() refunded for buildings it could not restore, and their names.
var load_refund: float:
	get:
		return brain.load_refund

var load_refunded: PackedStringArray:
	get:
		return brain.load_refunded

var rng: RandomNumberGenerator:
	get:
		return brain.rng
	set(value):
		brain.rng = value

var game_seed: int:
	get:
		return brain.game_seed
	set(value):
		brain.game_seed = value

func reseed(new_seed: int) -> void:
	brain.reseed(new_seed)


func step(delta: float) -> void:
	brain.step(delta)


func area_name(cell: Vector2i) -> String:
	return brain.area_name(cell)


func areas() -> Array:
	return brain.areas()


func owns_cell(cell: Vector2i) -> bool:
	return brain.owns_cell(cell)


func distance_to_building(building: Building, point: Vector3) -> float:
	return brain.distance_to_building(building, point)


func manage_problem(building: Building) -> String:
	return brain.manage_problem(building)


func is_manager_near(building: Building) -> bool:
	return brain.is_manager_near(building)


func propose_airline_deal(offer: AirlineOffer, fee: float, flights: int, tone: AirlineType.Tone) -> Airlines.Answer:
	return brain.propose_airline_deal(offer, fee, flights, tone)


func accept_airline_counter(offer: AirlineOffer) -> Airline:
	return brain.accept_airline_counter(offer)


func decline_airline_offer(offer: AirlineOffer) -> void:
	brain.decline_airline_offer(offer)


func end_airline_deal(airline: Airline) -> void:
	brain.end_airline_deal(airline)


func airport_value() -> float:
	return brain.airport_value()


func credit_limit() -> float:
	return brain.credit_limit()


func restructure_in() -> float:
	return brain.restructure_in()


func restructure() -> PackedStringArray:
	return brain.restructure()


func curfew_at(real_seconds_ahead: float = 0.0) -> bool:
	return brain.curfew_at(real_seconds_ahead)


func season() -> Seasons.Season:
	return brain.season()


func has_cargo_terminal() -> bool:
	return brain.has_cargo_terminal()


func stars() -> float:
	return brain.stars()


func upgrade_problem(building: Building) -> String:
	return brain.upgrade_problem(building)


func start_upgrade(building: Building) -> bool:
	return brain.start_upgrade(building)


func fast_track_problem(building: Building) -> String:
	return brain.fast_track_problem(building)


func buy_fast_track(building: Building) -> bool:
	return brain.buy_fast_track(building)


func running_cost_per_minute() -> float:
	return brain.running_cost_per_minute()


func needs_staff(building: Building) -> bool:
	return brain.needs_staff(building)


func staff_at(building: Building) -> Array[Employee]:
	return brain.staff_at(building)


func hire_problem(building: Building) -> String:
	return brain.hire_problem(building)


func hire(building: Building) -> Employee:
	return brain.hire(building)


func dismiss(building: Building) -> bool:
	return brain.dismiss(building)


func staff_working_at(building: Building) -> Array[Employee]:
	return brain.staff_working_at(building)


func next_trainee(building: Building) -> Employee:
	return brain.next_trainee(building)


func train_problem(building: Building) -> String:
	return brain.train_problem(building)


func train(building: Building) -> Employee:
	return brain.train(building)


func promote_problem(building: Building) -> String:
	return brain.promote_problem(building)


func promote(building: Building) -> Employee:
	return brain.promote(building)


func staff_fully(building: Building) -> void:
	brain.staff_fully(building)


func check_placement(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, check_money: bool = true) -> String:
	return brain.check_placement(type, origin_cell, rotation_steps, check_money)


func can_place(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, check_money: bool = true) -> bool:
	return brain.can_place(type, origin_cell, rotation_steps, check_money)


func place_building(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, pay: bool = true) -> Building:
	return brain.place_building(type, origin_cell, rotation_steps, pay)


func demolish_refund(building: Building) -> float:
	return brain.demolish_refund(building)


func demolish(building: Building) -> bool:
	return brain.demolish(building)


func paint_walkway(cells: Array[Vector2i], walkway: bool) -> String:
	return brain.paint_walkway(cells, walkway)


func paint_taxiway(cells: Array[Vector2i], taxiway: bool) -> String:
	return brain.paint_taxiway(cells, taxiway)


func connection_problem(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> String:
	return brain.connection_problem(type, origin_cell, rotation_steps)


## `size_in_cells` is only for tests and tools that want a map of another size; the game always
## uses the default one (a zero size).
func reset(with_runway: bool = true, new_seed: int = -1, size_in_cells: Vector2i = Vector2i.ZERO) -> void:
	# A fresh brain instead of cleaning the old one: nothing can be left over.
	var next_seed := new_seed if new_seed >= 0 else int(brain.rng.randi())
	var old := brain
	brain = AirportWorld.new(size_in_cells if size_in_cells != Vector2i.ZERO else MAP_SIZE_CELLS)
	old.dispose()
	_bind()
	brain.reset(with_runway, next_seed)


func save_state() -> Dictionary:
	return brain.save_state()


func load_state(data: Dictionary) -> int:
	return brain.load_state(data)


func stand_behind(gate: Building) -> Building:
	return brain.stand_behind(gate)


func manager_start() -> Array:
	return brain.manager_start()


func begin_batch() -> void:
	brain.begin_batch()


func end_batch() -> void:
	brain.end_batch()


func add_starting_runway() -> void:
	brain.add_starting_runway()
