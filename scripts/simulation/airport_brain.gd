class_name AirportWorld
extends RefCounted
## The brain (tech_architecture.md §3): the whole airport simulation as one self-contained object.
## It is pure data: no nodes, no scene tree, no globals, so a test can create a fresh one in a
## split second. The autoload "Airport" (airport_host.gd) owns one and drives it with `step()`.
## Visuals listen to its signals (re-emitted by the host) and never change its data directly.

signal building_placed(building: Building)
## An upgrade started or finished (design doc §7.8).
signal building_upgraded(building: Building)
## An unattended bag closed `building` (design doc §12.3).
## The bank sold buildings to cover the debt (design doc §11.6). `sold` names them.
signal restructured(sold: PackedStringArray)
## Someone was hired or dismissed at `building` (design doc §9.1).
signal staff_changed(building: Building)
## The land the airport owns changed (a new tier, design doc §14.1).
signal land_changed
## A building was demolished (design doc §7.6). Sent before layout_changed.
signal building_removed(building: Building)
signal zones_changed
signal walkways_changed
## Anything about the layout changed (buildings, zones, walkways). Used for saving and connection hints.
signal layout_changed
## Re-sent from the parts that make them, so a listener connects to the brain once, even when a
## part (the passenger flow) is replaced on a reset.
signal tier_reached(tier: Progression.Tier)
signal offer_arrived(offer: AirlineOffer)
signal airline_unhappy(airline: Airline)
signal airline_left(airline: Airline)
signal plane_arriving(flight: Flight)

## Grid cell size in meters. Terminal and landside are near-realistic at this scale; airside is
## scaled down (design doc §7.1). Change it only here: the ground and all tools derive from it.
const CELL_SIZE: float = 2.0
## Map size in cells: 64 x 64 cells = 128 x 128 m (design doc §7.1).
const MAP_SIZE_CELLS: Vector2i = Vector2i(64, 64)
## Every building type in the game.
const CATALOG: BuildingCatalog = preload("res://data/buildings/catalog.tres")
## Salary per minute for the stations that need staff (design doc §9.1).
const SALARIES: Dictionary = {
	BuildingType.Role.CHECK_IN: 8.0,
	BuildingType.Role.SECURITY: 10.0,
	BuildingType.Role.TRANSFER_SECURITY: 10.0,
	BuildingType.Role.CARGO_TERMINAL: 9.0,
}
## Fictional names for new employees.
const FIRST_NAMES: Array[String] = [
	"Anna", "Luca", "Mia", "Noah", "Lea", "Elias", "Sara", "Jonas", "Emma", "Felix", "Nina", "Paul",
	"Lena", "David", "Clara", "Tim", "Sofia", "Ben", "Ida", "Max", "Yara", "Omar", "Leni", "Malik",
]
## The simulation advances in fixed steps of this many seconds (10 per second): cheap and
## independent of the frame rate. Visuals move smoothly between steps using `sim_alpha`.
const SIM_STEP: float = 0.1

var grid: AirportGrid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
var buildings: Array[Building] = []
var passenger_flow: PassengerFlow = PassengerFlow.new()
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
## Star rating from satisfaction and punctuality (design doc §11.7).
var reputation: Reputation = Reputation.new()
## Everyone working at the airport (design doc §9.1).
var staff: Array[Employee] = []
## Where the manager stands (design doc §15.1). Gameplay state, not a visual: it decides which
## stations can be managed and where the manager's presence helps. Far away while nobody walks.
var manager_position: Vector3 = NOBODY_THERE
## Where the manager looks (first person, design doc §15), saved with the position.
var manager_yaw: float = 0.0
## The manager's place from the save game ({"x", "z", "yaw"}), or empty: then they start at the entrance.
var saved_manager: Dictionary = {}
## The airport's dice (tech_architecture.md §3). Every random choice of the simulation comes from
## here, so the same seed and the same player actions give exactly the same game. Shared with
## PassengerFlow, FlightSchedule and Airlines; saved with the game.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The number the dice started from, for replaying a game (e.g. a failing test).
var game_seed: int = 0

# While loading a save, layout_changed is sent once at the end instead of for every building.
var _loading: bool = false
# Running costs of everything built plus salaries, in euros per minute (recalculated when the
# layout or the staff changes), and the salaries alone.
var _running_cost_per_minute: float = 0.0
var _salaries_per_minute: float = 0.0


func _init() -> void:
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
	passenger_flow.schedule.plane_arriving.connect(plane_arriving.emit)
	_on_layout_changed()


## Starts the dice from `new_seed`: the same seed and the same player actions give the same game.
func reseed(new_seed: int) -> void:
	game_seed = new_seed
	rng.seed = new_seed
	_share_rng()


# Every part of the simulation rolls the same dice.
func _share_rng() -> void:
	passenger_flow.rng = rng
	passenger_flow.world = self
	passenger_flow.schedule.world = self
	goals.world = self
	timetable.world = self
	passenger_flow.schedule.rng = rng
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
	if passenger_flow.schedule.plane_arriving.is_connected(plane_arriving.emit):
		passenger_flow.schedule.plane_arriving.disconnect(plane_arriving.emit)
	passenger_flow.world = null
	passenger_flow.schedule.world = null
	goals.world = null
	timetable.world = null


## Advances the whole simulation by one step: passengers, flights and money.
func step(delta: float) -> void:
	clock.tick(delta)
	demand.tick(clock.day(), progression.tier, stars(), reputation.on_time_rate)
	timetable.tick()
	passenger_flow.tick(delta)
	economy.tick(delta, _running_cost_per_minute - _salaries_per_minute, _salaries_per_minute)
	reputation.tick(delta)
	# Airlines don't count flights as owed during the curfew (design doc §12.4).
	var operating := (not passenger_flow.usable_gates().is_empty() or not passenger_flow.usable_cargo_terminals().is_empty()) \
		and not curfew_at() and not curfew_at(FlightSchedule.ARRIVALS_START)  # slots are planned that far ahead
	airlines.tick(delta, stars(), operating, progression.tier, has_cargo_terminal())
	progression.check(stars())
	_check_loan(delta)
	for employee in staff:
		if employee.is_training():
			employee.training_left -= delta
			if not employee.is_training():
				var role := employee.workplace.type.role
				employee.served[role] = employee.served.get(role, 0) + Employee.TRAINING_EXPERIENCE
	for building in buildings:
		if building.is_upgrading():
			building.upgrade_seconds_left -= delta
			if building.upgrade_seconds_left <= 0.0:
				_finish_upgrade(building)


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


# --- Manager on the spot (design doc §15.1) ---

## Hiring, dismissing and upgrading need the manager within this many meters of the building.
const MANAGE_DISTANCE: float = 10.0
## Within this many meters the manager's presence helps: staff work faster, queues stay calmer.
const PRESENCE_DISTANCE: float = 6.0
## manager_position while there is no manager (e.g. simulation-only tests).
const NOBODY_THERE: Vector3 = Vector3(1.0e9, 0.0, 1.0e9)


## Meters from `point` to the nearest edge of `building` (0 inside it), on the ground.
func distance_to_building(building: Building, point: Vector3) -> float:
	var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
	var center := grid.block_center(building.origin_cell, size)
	var half := Vector2(size) * grid.cell_size * 0.5
	var outside := Vector2(maxf(absf(point.x - center.x) - half.x, 0.0), maxf(absf(point.z - center.z) - half.y, 0.0))
	return outside.length()


## Why the manager can't manage `building` from where they stand, or "" if they can.
func manage_problem(building: Building) -> String:
	var distance := distance_to_building(building, manager_position)
	if distance <= MANAGE_DISTANCE:
		return ""
	if distance > 1000.0:
		return "Walk here to manage"
	return "Walk closer to manage (%d m away)" % ceili(distance)


## True while the manager stands right at `building`.
func is_manager_near(building: Building) -> bool:
	return distance_to_building(building, manager_position) <= PRESENCE_DISTANCE


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
## The bank sells these first, newest first: they make money but passengers can do without them.
const OPTIONAL_ROLES: Array[BuildingType.Role] = [BuildingType.Role.SHOP, BuildingType.Role.TRANSFER_SECURITY]


## What everything built is worth: build prices plus the upgrades paid for.
func airport_value() -> float:
	var value := 0.0
	for building in buildings:
		value += building.type.build_cost
		for i in building.level - 1:
			value += building.type.upgrades[i].cost
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
## whatever is still missing. It never sells the last building of a kind the passenger route
## needs. The airport's reputation suffers. Returns the names of what was sold.
func restructure() -> PackedStringArray:
	var sold: PackedStringArray = []
	while economy.balance < 0.0:
		var building := _next_to_sell()
		if building == null:
			break
		sold.append(passenger_flow.station_label(building) if passenger_flow.station_for(building) != null else building.type.display_name)
		demolish(building)
	economy.balance = maxf(economy.balance, 0.0)
	economy.over_limit_seconds = 0.0
	reputation.penalty += RESTRUCTURE_PENALTY_STARS
	restructured.emit(sold)
	return sold


# Optional buildings first, then second (third, ...) buildings of a kind; newest first.
func _next_to_sell() -> Building:
	for i in range(buildings.size() - 1, -1, -1):
		if buildings[i].type.role in OPTIONAL_ROLES:
			return buildings[i]
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
	return reputation.stars(passenger_flow.satisfaction.average)


## Why `building` can't be upgraded right now, as a short hint, or "" if it can.
func upgrade_problem(building: Building) -> String:
	if building.type.upgrades.is_empty():
		return "No upgrades for this building yet"
	if building.is_upgrading():
		return "Upgrade in progress"
	var upgrade := building.next_upgrade()
	if upgrade == null:
		return "Fully upgraded"
	if not economy.can_afford(upgrade.cost):
		return "Not enough money (%s)" % Economy.format(upgrade.cost)
	return ""


## Pays for and starts the next upgrade. Small upgrades finish at once, big ones take time.
func start_upgrade(building: Building) -> bool:
	if not upgrade_problem(building).is_empty():
		return false
	var upgrade := building.next_upgrade()
	economy.pay_construction(upgrade.cost)
	if upgrade.build_seconds <= 0.0:
		_finish_upgrade(building)
	else:
		building.upgrade_seconds_left = upgrade.build_seconds
		building_upgraded.emit(building)
	return true


func _finish_upgrade(building: Building) -> void:
	building.upgrade_seconds_left = 0.0
	building.level += 1
	_update_running_cost()
	building_upgraded.emit(building)


## A fast track lane for security (design doc §11.8): a one-off price.
const FAST_TRACK_COST: float = 5000.0


## Why `building` can't get a fast track right now, or "" if it can.
func fast_track_problem(building: Building) -> String:
	if building.type.role != BuildingType.Role.SECURITY:
		return "Only for security"
	if building.fast_track:
		return "Has a fast track"
	if not economy.can_afford(FAST_TRACK_COST):
		return "Not enough money (%s)" % Economy.format(FAST_TRACK_COST)
	return ""


func buy_fast_track(building: Building) -> bool:
	if not fast_track_problem(building).is_empty():
		return false
	economy.pay_construction(FAST_TRACK_COST)
	building.fast_track = true
	building_upgraded.emit(building)
	return true


## Running costs of everything built plus salaries, in euros per minute.
func running_cost_per_minute() -> float:
	return _running_cost_per_minute


# --- Staff (design doc §9.1) ---

## True for stations that need one employee per counter / lane.
func needs_staff(building: Building) -> bool:
	return SALARIES.has(building.type.role)


## Employees working at `building`, in the order they were hired (employee i runs counter i).
func staff_at(building: Building) -> Array[Employee]:
	var result: Array[Employee] = []
	for employee in staff:
		if employee.workplace == building:
			result.append(employee)
	return result


## Why nobody can be hired for `building` right now, or "" if someone can.
func hire_problem(building: Building) -> String:
	if not needs_staff(building):
		return "No staff needed here"
	if staff_at(building).size() >= building.service_slots():
		return "Every counter is staffed"
	return ""


## Hires a new employee for `building`. Returns them, or null if nobody can be hired there.
func hire(building: Building) -> Employee:
	if not hire_problem(building).is_empty():
		return null
	var employee := Employee.new()
	employee.name = "%s %s." % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], char(65 + rng.randi() % 26)]
	employee.workplace = building
	employee.salary_per_minute = SALARIES[building.type.role]
	staff.append(employee)
	_update_running_cost()
	# Staffing decides whether e.g. transfer security works (design doc §8.9).
	passenger_flow.refresh_route()
	staff_changed.emit(building)
	return employee


## Dismisses the most recently hired employee at `building`. Returns false if nobody works there.
func dismiss(building: Building) -> bool:
	var working := staff_at(building)
	if working.is_empty():
		return false
	staff.erase(working[-1])
	_update_running_cost()
	passenger_flow.refresh_route()
	staff_changed.emit(building)
	return true


## Staff at `building` who are at their counters right now (not in training). Counter i is run
## by the i-th of them.
func staff_working_at(building: Building) -> Array[Employee]:
	return staff_at(building).filter(func(e: Employee) -> bool: return not e.is_training())


## The employee at `building` who would go to training next (least experienced), or null.
func next_trainee(building: Building) -> Employee:
	var best: Employee = null
	for employee in staff_at(building):
		if not employee.is_expert() and (best == null or employee.experience() < best.experience()):
			best = employee
	return best


## Why nobody at `building` can be trained right now, or "" if someone can.
func train_problem(building: Building) -> String:
	if staff_at(building).is_empty():
		return "Nobody to train"
	if staff_at(building).any(func(e: Employee) -> bool: return e.is_training()):
		return "Training in progress"
	if next_trainee(building) == null:
		return "Everyone is an expert"
	if not economy.can_afford(Employee.TRAINING_COST):
		return "Not enough money (%s)" % Economy.format(Employee.TRAINING_COST)
	return ""


## Sends the least experienced employee at `building` to training (design doc §9.2).
func train(building: Building) -> Employee:
	if not train_problem(building).is_empty():
		return null
	var trainee := next_trainee(building)
	economy.pay_construction(Employee.TRAINING_COST)
	trainee.training_left = Employee.TRAINING_SECONDS
	staff_changed.emit(building)
	return trainee


## Why nobody at `building` can be promoted right now, or "" if someone can.
func promote_problem(building: Building) -> String:
	var working := staff_at(building)
	if working.any(func(e: Employee) -> bool: return e.is_supervisor):
		return "Has a supervisor"
	if not working.any(func(e: Employee) -> bool: return e.is_expert()):
		return "Needs an expert"
	return ""


## Promotes the most experienced expert at `building` to supervisor (design doc §9.2).
func promote(building: Building) -> Employee:
	if not promote_problem(building).is_empty():
		return null
	var best: Employee = null
	for employee in staff_at(building):
		if employee.is_expert() and (best == null or employee.experience() > best.experience()):
			best = employee
	best.is_supervisor = true
	best.salary_per_minute += Employee.SUPERVISOR_RAISE
	_update_running_cost()
	staff_changed.emit(building)
	return best


## Hires staff until every counter / lane of `building` is staffed.
func staff_fully(building: Building) -> void:
	while hire(building) != null:
		pass


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
	if check_money and not economy.can_afford(type.build_cost):
		return "Not enough money (%s)" % Economy.format(type.build_cost)
	return ""


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
## dismisses its staff, sends its passengers elsewhere and frees the cells it needed.
func demolish(building: Building) -> bool:
	if not buildings.has(building):
		return false
	economy.refund(demolish_refund(building))
	staff = staff.filter(func(e: Employee) -> bool: return e.workplace != building)
	for cell in building.get_cells():
		grid.set_content(cell, null)
	buildings.erase(building)
	passenger_flow.remove_building(building)
	building_removed.emit(building)
	layout_changed.emit()
	return true


## Adds (or removes) walkway floor on `cells`. Works under buildings too (desks inside a hall).
## New walkway costs money per cell; removing it is free (no refund, design doc §11.5).
## Returns "" if it worked, or a hint why nothing was painted.
func paint_walkway(cells: Array[Vector2i], walkway: bool) -> String:
	var changing: Array[Vector2i] = []
	for cell in cells:
		# Walkway and taxiway never share a cell: passengers don't cross the planes' way.
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
	var changing: Array[Vector2i] = []
	for cell in cells:
		if not grid.is_inside(cell) or grid.is_taxiway(cell) == taxiway or not owns_cell(cell):
			continue
		if taxiway and grid.is_walkway(cell):
			continue
		changing.append(cell)
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
	grid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
	buildings.clear()
	_next_building_id = 1
	zone_map.recompute(grid, buildings)
	area_map.recompute(grid, buildings)
	staff.clear()
	passenger_flow = PassengerFlow.new()
	passenger_flow.schedule.plane_arriving.connect(plane_arriving.emit)
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
			"level": building.level,
			"upgrade_left": building.upgrade_seconds_left,
			"fast_track": building.fast_track,
		})
	var saved_staff: Array[Dictionary] = []
	for employee in staff:
		saved_staff.append({
			"name": employee.name,
			"building_id": employee.workplace.id,
			"served": employee.served,
			"training_left": employee.training_left,
			"supervisor": employee.is_supervisor,
		})
	return {
		"staff": saved_staff,
		"next_building_id": _next_building_id,
		"map_size": [grid.size.x, grid.size.y],
		"walkways": Marshalls.raw_to_base64(grid.get_walkway_data()),
		"taxiways": Marshalls.raw_to_base64(grid.get_taxiway_data()),
		"money": economy.balance,
		"over_limit": economy.over_limit_seconds,
		"average_profit": economy.average_profit_per_minute,
		"satisfaction": passenger_flow.satisfaction.save_state(),
		"reputation": reputation.save_state(),
		"airlines": airlines.save_state(),
		"progression": progression.save_state(),
		"goals_hidden": goals.hidden,
		"clock": clock.game_seconds,
		"clock_elapsed": clock.elapsed,
		"timetable": timetable.save_state(),
		"demand": demand.save_state(),
		"flow": passenger_flow.save_state(),
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
	# JSON stores every number as a float, hence the explicit conversion.
	var saved_size: Array = data.get("map_size", [])
	if saved_size.size() == 2 and Vector2i(int(saved_size[0]), int(saved_size[1])) == grid.size:
		grid.set_walkway_data(Marshalls.base64_to_raw(data.get("walkways", "")))
		grid.set_taxiway_data(Marshalls.base64_to_raw(data.get("taxiways", "")))
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
		var origin := Vector2i(int(cell[0]), int(cell[1]))
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
		building.level = clampi(int(entry.get("level", 1)), 1, type.upgrades.size() + 1)
		building.upgrade_seconds_left = float(entry.get("upgrade_left", 0.0)) if building.next_upgrade() != null else 0.0
		building.fast_track = bool(entry.get("fast_track", false))
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
		add_starting_runway()
		_loading = false
	if data.has("staff"):
		for entry: Dictionary in data["staff"]:
			var workplace: Building = by_saved_id.get(int(entry.get("building_id", 0)))
			if workplace == null or not needs_staff(workplace):
				continue
			var employee := Employee.new()
			employee.name = str(entry.get("name", "Employee"))
			employee.workplace = workplace
			employee.salary_per_minute = SALARIES[workplace.type.role]
			employee.training_left = float(entry.get("training_left", 0.0))
			employee.is_supervisor = bool(entry.get("supervisor", false))
			if employee.is_supervisor:
				employee.salary_per_minute += Employee.SUPERVISOR_RAISE
			var served: Dictionary = entry.get("served", {})
			for role in served:
				employee.served[int(role)] = int(served[role])
			staff.append(employee)
	else:
		# Saves from before staff existed: every counter gets an employee, so nothing stops working.
		for building in buildings:
			if needs_staff(building):
				staff_fully(building)
	economy.balance = float(data.get("money", Economy.STARTING_MONEY))
	economy.over_limit_seconds = float(data.get("over_limit", 0.0))
	economy.average_profit_per_minute = float(data.get("average_profit", 0.0))
	if load_refund > 0.0:
		economy.refund(load_refund)
	passenger_flow.satisfaction.load_state(data.get("satisfaction", {}))
	reputation.load_state(data.get("reputation", {}))
	airlines.load_state(data.get("airlines", {}))
	walkways_changed.emit()
	# Also recomputes the zones, after buildings and walkways are all in place.
	layout_changed.emit()
	# Flights and passengers on their way (saves before version 3 have none), after the layout
	# so the stations exist.
	if data.has("flow"):
		passenger_flow.load_state(data["flow"], by_saved_id)
	return skipped


## The aircraft stand behind a gate (its STAND side), or null.
func stand_behind(gate: Building) -> Building:
	for cell in Building.outside_row(gate.type.footprint, gate.origin_cell, gate.rotation_steps, false):
		if _is_aircraft_stand(cell):
			return grid.get_content(cell) as Building
	return null


func _on_layout_changed() -> void:
	# Zones first: everything below (walkway areas, stations) reads them.
	zone_map.recompute(grid, buildings)
	area_map.recompute(grid, buildings)
	zones_changed.emit()
	plane_network.rebuild(grid, buildings)
	passenger_flow.on_layout_changed()
	_update_running_cost()


func _update_running_cost() -> void:
	var cost := 0.0
	for building in buildings:
		cost += building.running_cost_per_minute()
	_salaries_per_minute = 0.0
	for employee in staff:
		_salaries_per_minute += employee.salary_per_minute
	cost += _salaries_per_minute
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


## The runway every new airport starts with (design doc §7.5a): along the south edge.
const DEFAULT_RUNWAY_ORIGIN: Vector2i = Vector2i(6, 57)


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


## Lays the runway a new airport starts with, on airside (design doc §7.5a).
func add_starting_runway() -> void:
	var type := CATALOG.find(&"runway")
	place_building(type, DEFAULT_RUNWAY_ORIGIN, 0, false)


func _is_aircraft_stand(cell: Vector2i) -> bool:
	if not grid.is_inside(cell) or grid.is_empty(cell):
		return false
	return (grid.get_content(cell) as Building).type.role == BuildingType.Role.AIRCRAFT_STAND
