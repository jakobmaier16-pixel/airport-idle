extends Node
## Root of the airport simulation, registered as the autoload "Airport".
## The simulation is pure data: it runs all the time, for the whole airport, independent of
## what is on screen (see "Performance architecture" in CLAUDE.md).
## Visuals listen to its signals and never change simulation data directly.

signal building_placed(building: Building)
## An upgrade started or finished (design doc §7.8).
signal building_upgraded(building: Building)
## The bank sold buildings to cover the debt (design doc §11.6). `sold` names them.
signal restructured(sold: PackedStringArray)
## Someone was hired or dismissed at `building` (design doc §9.1).
signal staff_changed(building: Building)
## A building was demolished (design doc §7.6). Sent before layout_changed.
signal building_removed(building: Building)
signal zones_changed
signal walkways_changed
## Anything about the layout changed (buildings, zones, walkways). Used for saving and connection hints.
signal layout_changed

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
}
## Fictional names for new employees.
const FIRST_NAMES: Array[String] = [
	"Anna", "Luca", "Mia", "Noah", "Lea", "Elias", "Sara", "Jonas", "Emma", "Felix", "Nina", "Paul",
	"Lena", "David", "Clara", "Tim", "Sofia", "Ben", "Ida", "Max", "Yara", "Omar", "Leni", "Malik",
]
## The simulation advances in fixed steps of this many seconds (10 per second): cheap and
## independent of the frame rate. Visuals move smoothly between steps using `sim_alpha`.
const SIM_STEP: float = 0.1
## Most steps caught up in one frame, so a slow frame can't snowball.
const MAX_STEPS_PER_FRAME: int = 5

var grid: AirportGrid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
var buildings: Array[Building] = []
var passenger_flow: PassengerFlow = PassengerFlow.new()
var economy: Economy = Economy.new()
## Signed airlines and their offers (design doc §10.1). Kept for the whole game (reset, not
## replaced), so the HUD's signal connections stay valid.
var airlines: Airlines = Airlines.new()
## Star rating from satisfaction and punctuality (design doc §11.7).
var reputation: Reputation = Reputation.new()
## Everyone working at the airport (design doc §9.1).
var staff: Array[Employee] = []
## Where the manager stands (design doc §15.1). Gameplay state, not a visual: it decides which
## stations can be managed and where the manager's presence helps. Far away while nobody walks.
var manager_position: Vector3 = NOBODY_THERE
## How far the current frame is between the last and the next simulation step (0..1).
var sim_alpha: float = 0.0

var _sim_time: float = 0.0
# While loading a save, layout_changed is sent once at the end instead of for every building.
var _loading: bool = false
# Running costs of everything built, in euros per minute (recalculated when the layout changes).
var _running_cost_per_minute: float = 0.0

# Cells whose zone a placed building depends on (cell -> required Zone). They can't be repainted.
var _zone_locks: Dictionary[Vector2i, int] = {}


func _ready() -> void:
	layout_changed.connect(_on_layout_changed)
	_on_layout_changed()


func _process(delta: float) -> void:
	_sim_time += delta
	var steps := 0
	while _sim_time >= SIM_STEP and steps < MAX_STEPS_PER_FRAME:
		step(SIM_STEP)
		_sim_time -= SIM_STEP
		steps += 1
	_sim_time = minf(_sim_time, SIM_STEP)
	sim_alpha = _sim_time / SIM_STEP


## Advances the whole simulation by one step: passengers, flights and money.
func step(delta: float) -> void:
	passenger_flow.tick(delta)
	economy.tick(delta, _running_cost_per_minute)
	reputation.tick(delta)
	airlines.tick(delta, stars(), not passenger_flow.usable_gates().is_empty())
	_check_loan(delta)
	for building in buildings:
		if building.is_upgrading():
			building.upgrade_seconds_left -= delta
			if building.upgrade_seconds_left <= 0.0:
				_finish_upgrade(building)


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
	employee.name = "%s %s." % [FIRST_NAMES[randi() % FIRST_NAMES.size()], char(65 + randi() % 26)]
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


## Hires staff until every counter / lane of `building` is staffed.
func staff_fully(building: Building) -> void:
	while hire(building) != null:
		pass


## Why a building can't go here, as a short hint for the player, or "" if it can.
## `check_money` is false when restoring a save (the building was paid for back then).
func check_placement(type: BuildingType, origin_cell: Vector2i, rotation_steps: int, check_money: bool = true) -> String:
	for cell in Building.footprint_cells(type.footprint, origin_cell, rotation_steps):
		if not grid.is_inside(cell):
			return "Outside the map"
		if not grid.is_empty(cell):
			return "Space is taken"
	var requirements := Building.zone_requirements(type, origin_cell, rotation_steps)
	for cell in requirements:
		if not grid.is_inside(cell) or grid.get_zone(cell) != requirements[cell]:
			return _zone_hint(type)
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
	for cell in building.get_cells():
		grid.set_content(cell, building)
	var requirements := Building.zone_requirements(type, origin_cell, rotation_steps)
	for cell in requirements:
		_zone_locks[cell] = requirements[cell]
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
	# Rebuild the zone locks from the buildings that are left.
	_zone_locks.clear()
	for remaining in buildings:
		var requirements := Building.zone_requirements(remaining.type, remaining.origin_cell, remaining.rotation_steps)
		for cell in requirements:
			_zone_locks[cell] = requirements[cell]
	passenger_flow.remove_building(building)
	building_removed.emit(building)
	layout_changed.emit()
	return true


## Paints `cells` with `zone`. Cells a building depends on keep their zone.
## Returns how many cells were blocked that way, so the player can be told.
func paint_zone(cells: Array[Vector2i], zone: AirportGrid.Zone) -> int:
	var blocked := 0
	var changed := false
	for cell in cells:
		if not grid.is_inside(cell) or grid.get_zone(cell) == zone:
			continue
		if _zone_locks.has(cell) and _zone_locks[cell] != zone:
			blocked += 1
			continue
		grid.set_zone(cell, zone)
		changed = true
	if changed:
		zones_changed.emit()
		layout_changed.emit()
	return blocked


## Adds (or removes) walkway floor on `cells`. Works under buildings too (desks inside a hall).
## New walkway costs money per cell; removing it is free (no refund, design doc §11.5).
## Returns "" if it worked, or a hint why nothing was painted.
func paint_walkway(cells: Array[Vector2i], walkway: bool) -> String:
	var changing: Array[Vector2i] = []
	for cell in cells:
		if grid.is_inside(cell) and grid.is_walkway(cell) != walkway:
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
		if access == BuildingType.Access.STAND and not row.any(_is_aircraft_stand):
			return "Needs an aircraft stand %s" % side
	return ""


## Removes everything: buildings and zones. Visuals must be rebuilt afterwards (reload the scene).
func reset() -> void:
	grid = AirportGrid.new(MAP_SIZE_CELLS, CELL_SIZE)
	buildings.clear()
	_zone_locks.clear()
	staff.clear()
	passenger_flow = PassengerFlow.new()
	economy = Economy.new()
	reputation = Reputation.new()
	airlines.reset()
	manager_position = NOBODY_THERE
	_on_layout_changed()


## The whole airport as plain data, for the save game.
func save_state() -> Dictionary:
	var saved_buildings: Array[Dictionary] = []
	for building in buildings:
		saved_buildings.append({
			"type": String(building.type.id),
			"cell": [building.origin_cell.x, building.origin_cell.y],
			"rotation": building.rotation_steps,
			"level": building.level,
			"upgrade_left": building.upgrade_seconds_left,
		})
	var saved_staff: Array[Dictionary] = []
	for employee in staff:
		saved_staff.append({
			"name": employee.name,
			"building": buildings.find(employee.workplace),
			"served": employee.served,
		})
	return {
		"staff": saved_staff,
		"map_size": [grid.size.x, grid.size.y],
		"zones": Marshalls.raw_to_base64(grid.get_zone_data()),
		"walkways": Marshalls.raw_to_base64(grid.get_walkway_data()),
		"money": economy.balance,
		"over_limit": economy.over_limit_seconds,
		"satisfaction": passenger_flow.satisfaction.save_state(),
		"reputation": reputation.save_state(),
		"airlines": airlines.save_state(),
		"buildings": saved_buildings,
	}


## Restores an airport from save_state() data. Buildings go through the normal placement rules,
## so a save from an older version (e.g. different sizes) can't create an invalid airport;
## buildings that no longer fit are skipped. Returns how many were skipped.
func load_state(data: Dictionary) -> int:
	reset()
	# JSON stores every number as a float, hence the explicit conversion.
	var saved_size: Array = data.get("map_size", [])
	if saved_size.size() == 2 and Vector2i(int(saved_size[0]), int(saved_size[1])) == grid.size:
		grid.set_zone_data(Marshalls.base64_to_raw(data.get("zones", "")))
		grid.set_walkway_data(Marshalls.base64_to_raw(data.get("walkways", "")))
	var skipped := 0
	_loading = true
	# Saved building index -> loaded building (null if it was skipped).
	var by_saved_index: Array[Building] = []
	for entry: Dictionary in data.get("buildings", []):
		var type := CATALOG.find(StringName(entry.get("type", "")))
		var cell: Array = entry.get("cell", [0, 0])
		var origin := Vector2i(int(cell[0]), int(cell[1]))
		var building := place_building(type, origin, int(entry.get("rotation", 0)), false) if type != null else null
		by_saved_index.append(building)
		if building == null:
			skipped += 1
			continue
		building.level = clampi(int(entry.get("level", 1)), 1, type.upgrades.size() + 1)
		building.upgrade_seconds_left = float(entry.get("upgrade_left", 0.0)) if building.next_upgrade() != null else 0.0
	_loading = false
	if data.has("staff"):
		for entry: Dictionary in data["staff"]:
			var index := int(entry.get("building", -1))
			var workplace: Building = by_saved_index[index] if index >= 0 and index < by_saved_index.size() else null
			if workplace == null or not needs_staff(workplace):
				continue
			var employee := Employee.new()
			employee.name = str(entry.get("name", "Employee"))
			employee.workplace = workplace
			employee.salary_per_minute = SALARIES[workplace.type.role]
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
	passenger_flow.satisfaction.load_state(data.get("satisfaction", {}))
	reputation.load_state(data.get("reputation", {}))
	airlines.load_state(data.get("airlines", {}))
	zones_changed.emit()
	walkways_changed.emit()
	layout_changed.emit()
	return skipped


## The aircraft stand behind a gate (its STAND side), or null.
func stand_behind(gate: Building) -> Building:
	for cell in Building.outside_row(gate.type.footprint, gate.origin_cell, gate.rotation_steps, false):
		if _is_aircraft_stand(cell):
			return grid.get_content(cell) as Building
	return null


func _on_layout_changed() -> void:
	passenger_flow.on_layout_changed()
	_update_running_cost()


func _update_running_cost() -> void:
	var cost := 0.0
	for building in buildings:
		cost += building.running_cost_per_minute()
	for employee in staff:
		cost += employee.salary_per_minute
	var walkway_cells := 0
	for value in grid.get_walkway_data():
		walkway_cells += value
	_running_cost_per_minute = cost + walkway_cells * Economy.WALKWAY_RUNNING_COST_PER_CELL


func _is_aircraft_stand(cell: Vector2i) -> bool:
	if not grid.is_inside(cell) or grid.is_empty(cell):
		return false
	return (grid.get_content(cell) as Building).type.role == BuildingType.Role.AIRCRAFT_STAND


func _zone_hint(type: BuildingType) -> String:
	match type.zone_rule:
		BuildingType.ZoneRule.AIRSIDE:
			return "Must be built on airside"
		BuildingType.ZoneRule.BORDER:
			return "Front must face landside, back must face airside"
		_:
			return "Must be built on landside"
