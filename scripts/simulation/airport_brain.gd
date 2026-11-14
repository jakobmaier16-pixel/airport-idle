class_name AirportWorld
extends RefCounted
## The brain (tech_architecture.md §3): the whole airport simulation as one self-contained object.
## It is pure data: no nodes, no scene tree, no globals, so a test can create a fresh one in a
## split second. The autoload "Airport" (airport_host.gd) owns one and drives it with `step()`.
## Visuals listen to its signals (re-emitted by the host) and never change its data directly.

signal building_placed(building: Building)
## The bank sold buildings to cover the debt (design doc §11.6). `sold` names them.
signal restructured(sold: PackedStringArray)
## The land the airport owns changed (a new tier, design doc §14.1).
signal land_changed
## A building was demolished (design doc §7.6). Sent before layout_changed.
signal building_removed(building: Building)
signal zones_changed
signal walkways_changed
## Anything about the layout changed (buildings, zones, walkways). Used for saving and connection hints.
signal layout_changed
## Re-sent from the parts that make them, so a listener connects to the brain once, even when a
## part (the flight schedule) is replaced on a reset.
signal tier_reached(tier: Progression.Tier)
signal offer_arrived(offer: AirlineOffer)
signal airline_unhappy(airline: Airline)
signal airline_left(airline: Airline)
signal plane_arriving(flight: Flight)

## Grid cell size in meters. Terminal and landside are near-realistic at this scale; airside is
## scaled down (design doc §7.1). Change it only here: the ground and all tools derive from it.
const CELL_SIZE: float = 2.0
## Map size in cells: 2,200 x 1,600 cells = 4.4 x 3.2 km (design doc §16, real scale).
const MAP_SIZE_CELLS: Vector2i = Vector2i(2200, 1600)
## Every building type in the game.
const CATALOG: BuildingCatalog = preload("res://data/buildings/catalog.tres")
## The simulation advances in fixed steps of this many seconds (10 per second): cheap and
## independent of the frame rate. Visuals move smoothly between steps using `sim_alpha`.
const SIM_STEP: float = 0.1

var grid: AirportGrid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
## The map size this brain was made with (tests make bigger ones); `reset()` keeps it.
var map_size: Vector2i = MAP_SIZE_CELLS
var buildings: Array[Building] = []
## Turns the timetable's slots into flights and runs them (design doc §8.5). Replaced on a reset.
var schedule: FlightSchedule = FlightSchedule.new()
## Where planes can move: taxiways, stands, runways (design doc §7.5a).
var plane_network: PlaneNetwork = PlaneNetwork.new()
## Zones computed from the layout (tech_architecture.md §4): written into `grid` after every layout change.
var zone_map: ZoneMap = ZoneMap.new()
## Named areas (connected walkways per zone), derived after the zones; never saved.
var area_map: AreaMap = AreaMap.new()
var economy: Economy = Economy.new()
## Signed airlines and their offers (design doc §10.1). Kept for the whole game (reset, not
## replaced), so the HUD's signal connections stay valid.
var airlines: Airlines = Airlines.new()
## Time of day (design doc §12.1). Reset, not replaced.
var clock: Clock = Clock.new()
## The day's planned flights (tech_architecture.md §6); FlightSchedule turns them into flights.
var timetable: Timetable = Timetable.new()
## Market demand for flights; grows with stars and punctuality (scripts/simulation/demand.gd).
var demand: Demand = Demand.new()
## "Getting started" goals (design doc §6.1).
var goals: Goals = Goals.new()
## Airport tiers and lifetime passenger counts (design doc §14.1). Reset, not replaced.
var progression: Progression = Progression.new()
## Star rating from punctuality (design doc §11.7).
var reputation: Reputation = Reputation.new()
## Where the manager stands. Far away while nobody walks.
var manager_position: Vector3 = NOBODY_THERE
## Where the manager looks (first person, design doc §15), saved with the position.
var manager_yaw: float = 0.0
## The manager's place from the save game ({"x", "z", "yaw"}), or empty: then they start at the entrance.
var saved_manager: Dictionary = {}
## The airport's dice (tech_architecture.md §3). Every random choice of the simulation comes from
## here, so the same seed and the same player actions give exactly the same game. Shared with
## FlightSchedule and Airlines; saved with the game.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The number the dice started from, for replaying a game (e.g. a failing test).
var game_seed: int = 0

# While loading a save, layout_changed is sent once at the end instead of for every building.
var _loading: bool = false
# Running costs of everything built, in euros per minute (recalculated when the layout changes).
var _running_cost_per_minute: float = 0.0
# Gates and cargo terminals that can have flights right now (see usable_gates()); recalculated with the layout.
var _usable_gates: Array[Building] = []
var _usable_cargo_terminals: Array[Building] = []


func _init(size_in_cells: Vector2i = MAP_SIZE_CELLS) -> void:
	map_size = size_in_cells
	grid = AirportGrid.new(map_size, CELL_SIZE)
	# The very first dice come from the clock; every later new game takes its seed from them.
	var first := RandomNumberGenerator.new()
	first.randomize()
	reseed(first.randi())
	layout_changed.connect(_on_layout_changed)
	progression.tier_reached.connect(_on_tier_reached)
	progression.tier_reached.connect(tier_reached.emit)
	airlines.offer_arrived.connect(offer_arrived.emit)
	airlines.airline_unhappy.connect(airline_unhappy.emit)
	airlines.airline_left.connect(airline_left.emit)
	schedule.plane_arriving.connect(plane_arriving.emit)
	_on_layout_changed()


## Starts the dice from `new_seed`: the same seed and the same player actions give the same game.
func reseed(new_seed: int) -> void:
	game_seed = new_seed
	rng.seed = new_seed
	_share_rng()


# Every part of the simulation rolls the same dice.
func _share_rng() -> void:
	schedule.world = self
	goals.world = self
	timetable.world = self
	schedule.rng = rng
	airlines.rng = rng


## Breaks the reference cycles so the brain can be freed (RefCounted objects that point at each
## other are never freed otherwise): the parts' `world` fields point back at the brain, and
## the brain listens to some of its own parts. Call it before dropping a brain; it is unusable after.
func dispose() -> void:
	if layout_changed.is_connected(_on_layout_changed):
		layout_changed.disconnect(_on_layout_changed)
	if progression.tier_reached.is_connected(_on_tier_reached):
		progression.tier_reached.disconnect(_on_tier_reached)
	if progression.tier_reached.is_connected(tier_reached.emit):
		progression.tier_reached.disconnect(tier_reached.emit)
	if airlines.offer_arrived.is_connected(offer_arrived.emit):
		airlines.offer_arrived.disconnect(offer_arrived.emit)
	if airlines.airline_unhappy.is_connected(airline_unhappy.emit):
		airlines.airline_unhappy.disconnect(airline_unhappy.emit)
	if airlines.airline_left.is_connected(airline_left.emit):
		airlines.airline_left.disconnect(airline_left.emit)
	if schedule.plane_arriving.is_connected(plane_arriving.emit):
		schedule.plane_arriving.disconnect(plane_arriving.emit)
	schedule.world = null
	goals.world = null
	timetable.world = null


## Seconds since the airport started (flights are timed against it). Not a clock of its own: it
## is `Clock.elapsed` in real seconds (tech_architecture.md §3, one clock).
var sim_time: float:
	get:
		return clock.real_elapsed


## Advances the whole simulation by one step: the timetable, flights and money.
func step(delta: float) -> void:
	clock.tick(delta)
	demand.tick(clock.day(), progression.tier, stars(), reputation.on_time_rate)
	timetable.tick()
	schedule.tick(sim_time, delta)
	economy.tick(delta, _running_cost_per_minute, 0.0)
	reputation.tick(delta)
	# Airlines don't count flights as owed during the curfew (design doc §12.4).
	var operating := (not _usable_gates.is_empty() or not _usable_cargo_terminals.is_empty()) \
		and not curfew_at() and not curfew_at(FlightSchedule.ARRIVALS_START)  # slots are planned that far ahead
	airlines.tick(delta, stars(), operating, progression.tier, has_cargo_terminal())
	progression.check(stars())
	_check_loan(delta)


# --- Airport tiers (design doc §14.1) ---

## The name of the area at a walkway cell ("Check-in Hall", "Gates", ...), "" outside any area.
func area_name(cell: Vector2i) -> String:
	return area_map.area_name(cell)


## All areas as {"name", "zone", "cells"}.
func areas() -> Array:
	return area_map.areas()


## True if the airport owns `cell` (land can be built on and painted).
func owns_cell(cell: Vector2i) -> bool:
	return progression.owned_land(grid.size).has_point(cell)


func _on_tier_reached(tier: Progression.Tier) -> void:
	land_changed.emit()
	match tier:
		Progression.Tier.NATIONAL:
			airlines.offer_from(&"norvane")
		Progression.Tier.INTERNATIONAL:
			airlines.offer_from(&"orynth")
		Progression.Tier.HUB:
			airlines.offer_from(&"corvista")


## manager_position while there is no manager (e.g. simulation-only tests).
const NOBODY_THERE: Vector3 = Vector3(1.0e9, 0.0, 1.0e9)


# --- Airline deals (design doc §10.1): player commands from the Airlines panel ---

func propose_airline_deal(offer: AirlineOffer, fee: float, flights: int, tone: AirlineType.Tone) -> Airlines.Answer:
	return airlines.propose(offer, fee, flights, tone, stars())


func accept_airline_counter(offer: AirlineOffer) -> Airline:
	return airlines.accept_counter(offer)


func decline_airline_offer(offer: AirlineOffer) -> void:
	airlines.decline(offer)


func end_airline_deal(airline: Airline) -> void:
	airlines.end_deal(airline)


# --- Bank loan and restructuring (design doc §11.6) ---

## Stars taken off the rating by a restructuring (fades, see Reputation).
const RESTRUCTURE_PENALTY_STARS: float = 1.0


## What everything built is worth: the build prices.
func airport_value() -> float:
	var value := 0.0
	for building in buildings:
		value += building.type.build_cost
	return value


## How much the bank lends right now.
func credit_limit() -> float:
	return Economy.credit_limit(airport_value())


## Seconds until the bank restructures, or -1 while the debt is within the limit.
func restructure_in() -> float:
	if economy.over_limit_seconds <= 0.0:
		return -1.0
	return maxf(Economy.RESTRUCTURE_AFTER - economy.over_limit_seconds, 0.0)


func _check_loan(delta: float) -> void:
	if economy.debt() <= 0.0 or economy.debt() <= credit_limit():
		economy.over_limit_seconds = 0.0
		return
	economy.over_limit_seconds += delta
	if economy.over_limit_seconds >= Economy.RESTRUCTURE_AFTER:
		restructure()


## The bank sells buildings (at the demolish refund) until the debt is covered, and writes off
## whatever is still missing. It never sells the last building of a kind the airport needs. The airport's reputation suffers. Returns the names of what was sold.
func restructure() -> PackedStringArray:
	var sold: PackedStringArray = []
	while economy.balance < 0.0:
		var building := _next_to_sell()
		if building == null:
			break
		sold.append(building.type.display_name)
		demolish(building)
	economy.balance = maxf(economy.balance, 0.0)
	economy.over_limit_seconds = 0.0
	reputation.penalty += RESTRUCTURE_PENALTY_STARS
	restructured.emit(sold)
	return sold


# Buildings without a role first, then second (third, ...) buildings of a kind; newest first.
func _next_to_sell() -> Building:
	for i in range(buildings.size() - 1, -1, -1):
		var role := buildings[i].type.role
		if role == BuildingType.Role.NONE:
			return buildings[i]
		for j in i:
			if buildings[j].type.role == role:
				return buildings[i]
	return null


## True if no plane may land or take off `real_seconds_ahead` from now (night curfew, §12.4).
## A Hub airport flies all night.
func curfew_at(real_seconds_ahead: float = 0.0) -> bool:
	return progression.tier < Progression.Tier.HUB and Clock.is_curfew_hour(clock.hour_at(real_seconds_ahead))


## The current season (design doc §12.2); it only drives demand.
func season() -> Seasons.Season:
	return Seasons.season_of(clock.day())


## True if a cargo terminal exists: cargo airlines make offers (design doc §10.3).
func has_cargo_terminal() -> bool:
	return buildings.any(func(b: Building) -> bool: return b.type.role == BuildingType.Role.CARGO_TERMINAL)


## The airport's star rating, 1.0 to 5.0 (design doc §11.7).
func stars() -> float:
	return reputation.stars()


## Running costs of everything built, in euros per minute.
func running_cost_per_minute() -> float:
	return _running_cost_per_minute


## Why a building can't go here, as a short hint for the player, or "" if it can.
## `check_money` is false when restoring a save (the building was paid for back then, and
## land and tier rules applied when it was built).
func check_placement(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, check_money: bool = true) -> String:
	for cell in Building.footprint_cells(type.footprint, origin_cell, rotation_steps):
		if not grid.is_inside(cell):
			return "Outside the map"
		if not grid.is_empty(cell):
			return "Space is taken"
		if check_money and not owns_cell(cell):
			return "Not your land yet (%s airport)" % progression.name_of(Progression.Tier.NATIONAL)
	if check_money and type.unlocked_at > progression.tier:
		return "Unlocked at %s airport" % progression.name_of(type.unlocked_at as Progression.Tier)
	# Zones are computed from the layout, so only border buildings (security) need room: a free row
	# on both sides, where the landside and airside walkways go.
	if type.zone_rule == BuildingType.ZoneRule.BORDER:
		for front in [true, false]:
			for cell in Building.outside_row(type.footprint, origin_cell, rotation_steps, front):
				if not grid.is_inside(cell) or not grid.is_empty(cell):
					return "Needs a free row in front and behind"
	var gate_problem := _one_gate_per_stand_problem(type, origin_cell, rotation_steps)
	if not gate_problem.is_empty():
		return gate_problem
	if check_money and not economy.can_afford(type.build_cost):
		return "Not enough money (%s)" % Economy.format(type.build_cost)
	return ""


# One stand serves exactly one gate (design doc §10.2): a plane parks at the stand its gate's
# back row touches, so two gates on one stand would fight for it, and a gate touching two stands
# would not know which one is its own. Gates and cargo terminals (back side = STAND) both count.
# The rule is checked when either side is placed, so no order of building can break it.
func _one_gate_per_stand_problem(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> String:
	if type.back_access == BuildingType.Access.STAND:
		var row := Building.outside_row(type.footprint, origin_cell, rotation_steps, false)
		var stands: Dictionary[Building, bool] = {}
		for cell in row:
			if _is_aircraft_stand(cell):
				stands[grid.get_content(cell) as Building] = true
		if stands.size() > 1:
			return "A gate must face one stand only"
		for stand in stands:
			if not _gates_touching(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps)).is_empty():
				return "This stand already has a gate"
	elif type.role == BuildingType.Role.AIRCRAFT_STAND:
		var gates := _gates_touching(origin_cell, Building.rotated_size(type.footprint, rotation_steps))
		if gates.size() > 1:
			return "A stand serves one gate: two gates would reach it"
		for gate in gates:
			if stand_behind(gate) != null:
				return "That gate already has a stand"
	return ""


# The gates (stand-side buildings) whose back row touches the stand rectangle at `origin` x `size`.
func _gates_touching(origin: Vector2i, size: Vector2i) -> Array[Building]:
	var rect := Rect2i(origin, size)
	var result: Array[Building] = []
	for building in buildings:
		if building.type.back_access != BuildingType.Access.STAND:
			continue
		for cell in Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false):
			if rect.has_point(cell):
				result.append(building)
				break
	return result


func can_place(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, check_money: bool = true) -> bool:
	return check_placement(type, origin_cell, rotation_steps, check_money).is_empty()


## Places a building if the spot is allowed and pays for it. Returns the new building, or null.
## `pay` is false when restoring a save (the building was paid for back then).
func place_building(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, pay: bool = true) -> Building:
	if not can_place(type, origin_cell, rotation_steps, pay):
		return null
	if pay:
		economy.pay_construction(type.build_cost)
	var building := Building.new(type, origin_cell, rotation_steps)
	building.id = _next_building_id
	_next_building_id += 1
	for cell in building.get_cells():
		grid.set_content(cell, building)
	buildings.append(building)
	var surface := Building.ground_surface_of(type)
	if surface != 0:
		grid.set_surface_rect(building.get_rect(), surface)
	building_placed.emit(building)
	if not _loading:
		layout_changed.emit()
	return building


## Share of the build price refunded when demolishing (design doc §7.6).
const DEMOLISH_REFUND_SHARE: float = 0.5


## What demolishing `building` would refund.
func demolish_refund(building: Building) -> float:
	return building.type.build_cost * DEMOLISH_REFUND_SHARE


## Demolishes `building`, also during operation (design doc §7.6): refunds half the build price,
## and frees the cells it needed. Flights at it are cancelled by the schedule's next step.
func demolish(building: Building) -> bool:
	if not buildings.has(building):
		return false
	economy.refund(demolish_refund(building))
	for cell in building.get_cells():
		grid.set_content(cell, null)
	buildings.erase(building)
	if Building.ground_surface_of(building.type) != 0:
		grid.set_surface_rect(building.get_rect(), 0)
	building_removed.emit(building)
	layout_changed.emit()
	return true


## Adds (or removes) walkway floor on `cells`. Works under buildings too (desks inside a hall).
## New walkway costs money per cell; removing it is free (no refund, design doc §11.5).
## Returns "" if it worked, or a hint why nothing was painted.
func paint_walkway(cells: Array[Vector2i], walkway: bool) -> String:
	var changing: Array[Vector2i] = []
	for cell in cells:
		# Walkway and taxiway never share a cell: people don't cross the planes' way.
		if grid.is_inside(cell) and grid.is_walkway(cell) != walkway and owns_cell(cell) and not grid.is_taxiway(cell):
			changing.append(cell)
	if changing.is_empty():
		return ""
	if walkway:
		var cost := changing.size() * Economy.WALKWAY_COST_PER_CELL
		if not economy.can_afford(cost):
			return "Not enough money (%s for %d cells)" % [Economy.format(cost), changing.size()]
		economy.pay_construction(cost)
	for cell in changing:
		grid.set_walkway(cell, walkway)
	walkways_changed.emit()
	layout_changed.emit()
	return ""


## Adds (or removes) taxiway on `cells` (design doc §7.5a): airside only, never on walkway.
## Returns "" if it worked, or a hint why nothing was painted.
func paint_taxiway(cells: Array[Vector2i], taxiway: bool) -> String:
	var changing := _taxiway_changes(cells, taxiway)
	if changing.is_empty():
		return ""
	if taxiway:
		var cost := changing.size() * Economy.TAXIWAY_COST_PER_CELL
		if not economy.can_afford(cost):
			return "Not enough money (%s for %d cells)" % [Economy.format(cost), changing.size()]
		economy.pay_construction(cost)
	for cell in changing:
		grid.set_taxiway(cell, taxiway)
	walkways_changed.emit()
	layout_changed.emit()
	return ""


## What `paint_taxiway(cells, true)` would charge, and how many cells it would really change
## (the build view shows it while the player drags the brush).
func taxiway_cost(cells: Array[Vector2i], taxiway: bool) -> float:
	if not taxiway:
		return 0.0
	return _taxiway_changes(cells, true).size() * Economy.TAXIWAY_COST_PER_CELL


func _taxiway_changes(cells: Array[Vector2i], taxiway: bool) -> Array[Vector2i]:
	var changing: Array[Vector2i] = []
	for cell in cells:
		if not grid.is_inside(cell) or grid.is_taxiway(cell) == taxiway or not owns_cell(cell):
			continue
		if taxiway and grid.is_walkway(cell):
			continue
		changing.append(cell)
	return changing


## What a building at this spot still needs to be connected, as a short hint, or "" if nothing.
## Unconnected buildings are allowed (build first, connect after; design doc §7.1b).
func connection_problem(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> String:
	for front in [true, false]:
		var access: BuildingType.Access = type.front_access if front else type.back_access
		if access == BuildingType.Access.NONE:
			continue
		var side := "in front" if front else "behind"
		var row := Building.outside_row(type.footprint, origin_cell, rotation_steps, front)
		if access == BuildingType.Access.WALKWAY and not row.any(grid.is_walkable):
			return "Needs a walkway %s" % side
		# Airside buildings can be placed anywhere; they work once the walk from the entrance
		# through security reaches them (the zone map marks those walkways airside).
		if access == BuildingType.Access.WALKWAY and type.zone_rule == BuildingType.ZoneRule.AIRSIDE \
				and not row.any(func(c: Vector2i) -> bool: return grid.is_walkable(c) and grid.get_zone(c) == AirportGrid.Zone.AIRSIDE):
			return "Not connected: build security and a walkway behind it to reach the airside"
		if access == BuildingType.Access.STAND and not row.any(_is_aircraft_stand):
			return "Needs an aircraft stand %s" % side
		if access == BuildingType.Access.STAND:
			var stand := grid.get_content(row.filter(_is_aircraft_stand)[0]) as Building
			if not _stand_reaches_runway(stand.type, stand.origin_cell, stand.rotation_steps):
				return "Its stand needs a taxiway to a runway"
	# Stands need a taxiway (or a runway right beside them) leading to a runway (§7.5a).
	if type.role == BuildingType.Role.AIRCRAFT_STAND and not _stand_reaches_runway(type, origin_cell, rotation_steps):
		return "Needs a taxiway to a runway"
	return ""


## Removes everything: buildings and zones, and lays the starting runway (unless `with_runway` is
## false, e.g. while loading a save that has its own). Visuals must be rebuilt afterwards (reload
## the scene). The new game's dice start from `new_seed`, or (if negative) from a seed the current
## dice roll, so a seeded test stays repeatable even when it starts a new game.
func reset(with_runway: bool = true, new_seed: int = -1) -> void:
	grid = AirportGrid.new(map_size, CELL_SIZE)
	buildings.clear()
	_next_building_id = 1
	zone_map.recompute(grid, buildings)
	area_map.recompute(grid, buildings)
	schedule = FlightSchedule.new()
	schedule.plane_arriving.connect(plane_arriving.emit)
	reseed(new_seed if new_seed >= 0 else int(rng.randi()))
	economy = Economy.new()
	reputation = Reputation.new()
	airlines.reset()
	progression.reset()
	goals.hidden = false
	clock.reset()
	timetable.clear()
	demand.reset()
	land_changed.emit()
	manager_position = NOBODY_THERE
	saved_manager = {}
	if with_runway:
		add_starting_runway()
	_on_layout_changed()


# The ID the next placed building gets. Never reused, so an ID always means one building.
var _next_building_id: int = 1
## After load_state(): money refunded for buildings that could not be restored, and their names.
var load_refund: float = 0.0
var load_refunded: PackedStringArray = PackedStringArray()


## The whole airport as plain data, for the save game.
func save_state() -> Dictionary:
	var saved_buildings: Array[Dictionary] = []
	for building in buildings:
		saved_buildings.append({
			"id": building.id,
			"type": String(building.type.id),
			"cost": building.type.build_cost,
			"cell": [building.origin_cell.x, building.origin_cell.y],
			"rotation": building.rotation_steps,
		})
	return {
		"next_building_id": _next_building_id,
		"map_size": [grid.size.x, grid.size.y],
		"walkways": GridSave.encode(grid, AirportGrid.WALKWAY_BIT),
		"taxiways": GridSave.encode(grid, AirportGrid.TAXIWAY_BIT),
		"money": economy.balance,
		"over_limit": economy.over_limit_seconds,
		"average_profit": economy.average_profit_per_minute,
		"reputation": reputation.save_state(),
		"airlines": airlines.save_state(),
		"progression": progression.save_state(),
		"goals_hidden": goals.hidden,
		"clock": clock.game_seconds,
		"clock_elapsed": clock.elapsed,
		"timetable": timetable.save_state(),
		"demand": demand.save_state(),
		"schedule": schedule.save_state(),
		"manager": {"x": manager_position.x, "z": manager_position.z, "yaw": manager_yaw} if manager_position != NOBODY_THERE else {},
		# As text: JSON keeps numbers as decimals, which can't hold a 64-bit dice state exactly.
		"seed": str(game_seed),
		"rng_state": str(rng.state),
		"buildings": saved_buildings,
	}


## Restores an airport from save_state() data. Buildings go through the normal placement rules,
## so a save from an older version (e.g. different sizes) can't create an invalid airport;
## buildings that no longer fit are skipped. Returns how many were skipped.
func load_state(data: Dictionary) -> int:
	reset(false)
	# The dice continue exactly where they were (saves from before seeds keep the fresh dice).
	if data.has("rng_state"):
		game_seed = str(data.get("seed", "0")).to_int()
		rng.seed = game_seed
		rng.state = str(data["rng_state"]).to_int()
	# A save from a map of another size is placed in the middle of this one (see _load_layers).
	var saved_size := _saved_map_size(data)
	var shift := cell_shift_from(saved_size)
	_load_layers(data, saved_size, shift)
	progression.load_state(data.get("progression", {}))
	goals.hidden = bool(data.get("goals_hidden", false))
	if not data.has("clock_elapsed"):
		push_warning("Saved airport has no clock_elapsed: the clock starts at zero.")
	clock.load_state(float(data.get("clock_elapsed", 0.0)), float(data.get("clock", Clock.START_HOUR * 3600.0)))
	timetable.load_state(data.get("timetable", {}))
	demand.load_state(data.get("demand", {}))
	demand.last_day = maxi(demand.last_day, 1) if data.has("demand") else clock.day()
	saved_manager = data.get("manager", {})
	land_changed.emit()
	var skipped := 0
	_loading = true
	# Saved building ID -> loaded building (skipped buildings are missing).
	var by_saved_id: Dictionary[int, Building] = {}
	load_refund = 0.0
	load_refunded = PackedStringArray()
	var highest_id := 0
	for entry: Dictionary in data.get("buildings", []):
		var type := CATALOG.find(StringName(entry.get("type", "")))
		var cell: Array = entry.get("cell", [0, 0])
		var origin := Vector2i(int(cell[0]), int(cell[1])) + shift
		var building := place_building(type, origin, int(entry.get("rotation", 0)), false) if type != null else null
		if building == null:
			skipped += 1
			# Nothing is lost silently: the price is paid back (half of it if the type is still
			# known, like demolishing; the saved price if the type is gone).
			var refund := type.build_cost * DEMOLISH_REFUND_SHARE if type != null else float(entry.get("cost", 0.0)) * DEMOLISH_REFUND_SHARE
			load_refund += refund
			load_refunded.append(str(entry.get("type", "?")))
			continue
		var saved_id := int(entry.get("id", 0))
		if saved_id > 0 and not by_saved_id.has(saved_id):
			building.id = saved_id
			by_saved_id[saved_id] = building
			highest_id = maxi(highest_id, saved_id)
	_loading = false
	# Buildings without a saved ID (hand-made data) get fresh ones above every saved ID.
	_next_building_id = maxi(int(data.get("next_building_id", 1)), highest_id + 1)
	for building in buildings:
		if not by_saved_id.has(building.id) or by_saved_id[building.id] != building:
			building.id = _next_building_id
			_next_building_id += 1
			by_saved_id[building.id] = building
	# Saves from before runways existed (design doc §7.5a) get the starting runway.
	if not buildings.any(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY):
		_loading = true
		for displaced in add_starting_runway():
			skipped += 1
			load_refund += displaced.type.build_cost
			load_refunded.append(String(displaced.type.id))
		_loading = false
	economy.balance = float(data.get("money", Economy.STARTING_MONEY))
	economy.over_limit_seconds = float(data.get("over_limit", 0.0))
	economy.average_profit_per_minute = float(data.get("average_profit", 0.0))
	if load_refund > 0.0:
		economy.refund(load_refund)
	reputation.load_state(data.get("reputation", {}))
	airlines.load_state(data.get("airlines", {}))
	walkways_changed.emit()
	# Also recomputes the zones, after buildings and walkways are all in place.
	layout_changed.emit()
	# Flights on their way (saves before version 3 have none), after the layout so the plane
	# network exists. Saves before 2026-11-14 kept the schedule inside the passenger flow ("flow").
	var saved_schedule: Variant = data.get("schedule", (data.get("flow", {}) as Dictionary).get("schedule", {}) if data.get("flow") is Dictionary else {})
	schedule.load_state(saved_schedule if saved_schedule is Dictionary else {}, by_saved_id)
	return skipped


## How many cells a map of `saved_size` is moved to sit in the middle of this one: (new - old) / 2,
## rounded towards zero. The grid is centred on the world origin, so with an even difference every
## world position (metres) stays the same; with an odd one everything moves by half a cell.
func cell_shift_from(saved_size: Vector2i) -> Vector2i:
	# This map's size is even (AirportGrid asserts it) and so is every size this game saves, so the
	# shift is a whole number of cells and world positions never move by half a cell.
	if saved_size.x % 2 != 0 or saved_size.y % 2 != 0:
		push_warning("Saved map size %s is odd: the save moves by half a cell." % saved_size)
	return (grid.size - saved_size) / 2


# The map size of a save (the old 64 x 64 map if the save doesn't say: every save made before
# the map size was stored came from it).
func _saved_map_size(data: Dictionary) -> Vector2i:
	var saved: Variant = data.get("map_size", [])
	if saved is Array and (saved as Array).size() == 2 and int(saved[0]) > 0 and int(saved[1]) > 0:
		return Vector2i(int(saved[0]), int(saved[1]))
	return MapAnchor.REFERENCE_SIZE


# Walkways and taxiways of a save (chunk lists, GridSave), moved by `shift` cells. Cells that don't
# fit on this map are skipped with a warning. Only the used chunks are visited, never the whole map.
func _load_layers(data: Dictionary, saved_size: Vector2i, shift: Vector2i) -> void:
	var skipped := 0
	for layer: Array in [["walkways", AirportGrid.WALKWAY_BIT], ["taxiways", AirportGrid.TAXIWAY_BIT]]:
		var saved: Variant = data.get(layer[0], [])
		if saved is String:
			# A dense layer (format 8 and below) that SaveGame didn't convert.
			saved = GridSave.from_dense(Marshalls.base64_to_raw(saved), saved_size)
		if not saved is Array:
			continue
		for cell in GridSave.cells_of(saved):
			var target := cell + shift
			if not grid.is_inside(target):
				skipped += 1
			elif layer[1] == AirportGrid.WALKWAY_BIT:
				grid.set_walkway(target, true)
			else:
				grid.set_taxiway(target, true)
	if skipped > 0:
		push_warning("%d saved walkway or taxiway cells do not fit on this map and were skipped." % skipped)


## The aircraft stand behind a gate (its STAND side), or null.
func stand_behind(gate: Building) -> Building:
	for cell in Building.outside_row(gate.type.footprint, gate.origin_cell, gate.rotation_steps, false):
		if _is_aircraft_stand(cell):
			return grid.get_content(cell) as Building
	return null


# While a batch is open (begin_batch / end_batch), layout changes only note that work is due.
var _batch_depth: int = 0
var _batch_pending: bool = false


## Several layout changes in one go (the showcase, tools): the zones, networks and stations are
## worked out once at `end_batch()` instead of after every building. Batches nest.
func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(_batch_depth - 1, 0)
	if _batch_depth == 0 and _batch_pending:
		_batch_pending = false
		_on_layout_changed()


func _on_layout_changed() -> void:
	if _batch_depth > 0:
		_batch_pending = true
		return
	# Zones first: everything below (walkway areas, stations) reads them.
	zone_map.recompute(grid, buildings)
	area_map.recompute(grid, buildings)
	zones_changed.emit()
	plane_network.rebuild(grid, buildings)
	_update_usable()
	_update_running_cost()


# Gates and cargo terminals that can have flights: connected on every side they need (a walkway in
# front on the right zone side, a stand behind that leads to a runway).
func _update_usable() -> void:
	_usable_gates.clear()
	_usable_cargo_terminals.clear()
	for building in buildings:
		var role := building.type.role
		if (role == BuildingType.Role.GATE or role == BuildingType.Role.CARGO_TERMINAL) \
				and connection_problem(building.type, building.origin_cell, building.rotation_steps).is_empty():
			(_usable_gates if role == BuildingType.Role.GATE else _usable_cargo_terminals).append(building)


## Gates that can have flights right now. Cached: recalculated after layout changes (asked often).
func usable_gates() -> Array[Building]:
	return _usable_gates


## Cargo terminals that can have flights right now (cached like usable_gates()).
func usable_cargo_terminals() -> Array[Building]:
	return _usable_cargo_terminals


## Gates are numbered in the order they were built, starting at 1 (0 for a building that is no gate).
func gate_number(gate: Building) -> int:
	var number := 0
	for building in buildings:
		if building.type.role == BuildingType.Role.GATE:
			number += 1
			if building == gate:
				return number
	return 0


## One line about the airport's state for the HUD (both views).
func status_text() -> String:
	if _usable_gates.is_empty() and _usable_cargo_terminals.is_empty():
		return "No gate in use yet: connect a gate to a walkway, a stand and a taxiway to the runway."
	return "Flights departed: %d" % reputation.departures


func _update_running_cost() -> void:
	var cost := 0.0
	for building in buildings:
		cost += building.running_cost_per_minute()
	var walkway_cells := grid.count_flag(AirportGrid.WALKWAY_BIT)
	var taxiway_cells := grid.count_flag(AirportGrid.TAXIWAY_BIT)
	_running_cost_per_minute = cost + walkway_cells * Economy.WALKWAY_RUNNING_COST_PER_CELL \
		+ taxiway_cells * Economy.TAXIWAY_RUNNING_COST_PER_CELL


# True if a plane can get from a runway to the stand: a taxiway or runway touches one of its sides
# and leads to a runway.
func _stand_reaches_runway(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> bool:
	var ring: Array[Vector2i] = []
	for front in [true, false]:
		ring.append_array(Building.outside_row(type.footprint, origin_cell, rotation_steps, front))
	# The two other sides: the same rows for the footprint turned by a quarter.
	var size := Building.rotated_size(type.footprint, rotation_steps)
	for y in size.y:
		ring.append(origin_cell + Vector2i(-1, y))
		ring.append(origin_cell + Vector2i(size.x, y))
	for x in size.x:
		ring.append(origin_cell + Vector2i(x, -1))
		ring.append(origin_cell + Vector2i(x, size.y))
	var paved := ring.filter(func(c: Vector2i) -> bool:
		return plane_network.is_paved(c) and grid.get_content(c) == null or plane_network.runway_at(c) != null)
	return plane_network.reaches_runway(paved)


## The runway every new airport starts with (design doc §7.5a): 1,000 x 23 cells (2 km), centred
## on the map's middle line, as an offset in cells from the map centre to the runway's origin cell.
## It lies in the south part of the starting land (rows 49 to 71 below the middle; the land ends at 200),
## leaving room above it for stands, a parallel taxiway and the terminal.
const DEFAULT_RUNWAY_ORIGIN: Vector2i = Vector2i(-500, 49)


## Where the manager starts (first person, design doc §15): where they were when the game was
## saved, or just inside the first entrance looking into the terminal, or the middle of the map.
## Returns [position, yaw].
func manager_start() -> Array:
	if saved_manager.has("x"):
		return [Vector3(float(saved_manager["x"]), 0.0, float(saved_manager["z"])), float(saved_manager.get("yaw", 0.0))]
	for building in buildings:
		if building.type.role == BuildingType.Role.ENTRANCE:
			var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
			var center := grid.block_center(building.origin_cell, size)
			var door := Vector3.ZERO
			var row := Building.outside_row(building.type.footprint, building.origin_cell, building.rotation_steps, false)
			for cell in row:
				door += grid.cell_to_world(cell)
			door /= row.size()
			var inward := (door - center).normalized()
			return [door + inward * grid.cell_size * 2.0, atan2(-inward.x, -inward.z)]
	return [Vector3.ZERO, 0.0]


## Lays the runway a new airport starts with, on airside (design doc §7.5a), at the default spot or,
## if a building stands there (a migrated save), at the nearest free spot inside the owned land:
## first moved up and down, then sideways. If there is none, the buildings in the default band are
## removed to make room. Returns those removed buildings: the caller pays their full price back and
## tells the player. Never fails silently.
func add_starting_runway() -> Array[Building]:
	var type := CATALOG.find(&"runway")
	var removed: Array[Building] = []
	if buildings.any(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY):
		return removed
	var home := MapAnchor.centre_of(grid.size) + DEFAULT_RUNWAY_ORIGIN
	var spot: Variant = _free_runway_spot(type, home)
	if spot == null:
		# Nothing is free: the runway goes to the default spot (kept inside the land) and what stands there leaves.
		var land := progression.owned_land(grid.size)
		spot = Vector2i(clampi(home.x, land.position.x, maxi(land.end.x - type.footprint.x, land.position.x)),
			clampi(home.y, land.position.y, maxi(land.end.y - type.footprint.y, land.position.y)))
		var band := Rect2i(spot, type.footprint)
		for building in buildings.duplicate():
			if Rect2i(building.origin_cell, Building.rotated_size(building.type.footprint, building.rotation_steps)).intersects(band):
				for cell in building.get_cells():
					grid.set_content(cell, null)
				buildings.erase(building)
				building_removed.emit(building)
				removed.append(building)
	if place_building(type, spot, 0, false) == null:
		push_warning("The starting runway could not be placed at %s." % [spot])
	return removed


# The nearest origin to `home` where a runway fits inside the owned land without touching a building,
# or null. Rows first (up and down), then columns in steps of 50 cells.
func _free_runway_spot(type: BuildingType, home: Vector2i) -> Variant:
	var land := progression.owned_land(grid.size)
	var rects: Array[Rect2i] = []
	for building in buildings:
		rects.append(Rect2i(building.origin_cell, Building.rotated_size(building.type.footprint, building.rotation_steps)))
	for dx in [0, -50, 50, -100, 100, -150, 150, -200, 200]:
		for step in range(0, land.size.y + 1):
			for dy in ([0] if step == 0 else [step, -step]):
				var rect := Rect2i(home + Vector2i(dx, dy), type.footprint)
				if land.encloses(rect) and not rects.any(func(r: Rect2i) -> bool: return r.intersects(rect)):
					return rect.position
	return null


func _is_aircraft_stand(cell: Vector2i) -> bool:
	if not grid.is_inside(cell) or grid.is_empty(cell):
		return false
	return (grid.get_content(cell) as Building).type.role == BuildingType.Role.AIRCRAFT_STAND
