class_name AirportWorld
extends RefCounted
## The brain (tech_architecture.md §3): the whole airport simulation as one self-contained object.
## It is pure data: no nodes, no scene tree, no globals, so a test can create a fresh one in a
## split second. The autoload "Airport" (airport_host.gd) owns one and drives it with `step()`.
## Visuals listen to its signals (re-emitted by the host) and never change its data directly.

signal building_placed(building: Building)
## A building was demolished (design doc §7.6). Sent before layout_changed.
signal building_removed(building: Building)
signal zones_changed
signal walkways_changed
## Anything about the layout changed (buildings, zones, walkways). Used for saving and connection hints.
signal layout_changed
## Re-sent from the flight schedule, so a listener connects to the brain once, even when the
## schedule is replaced on a reset.
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
## Time of day (design doc §12.1). Reset, not replaced.
var clock: Clock = Clock.new()
## The fixed timetable (tech_architecture.md §6); FlightSchedule turns its slots into flights.
var timetable: Timetable = Timetable.new()
## Where the manager stands. Far away while nobody walks.
var manager_position: Vector3 = NOBODY_THERE
## Where the manager looks (first person, design doc §15), saved with the position.
var manager_yaw: float = 0.0
## The manager's place from the save game ({"x", "z", "yaw"}), or empty: then they start at the entrance.
var saved_manager: Dictionary = {}
## The airport's dice (tech_architecture.md §3). Every random choice of the simulation comes from
## here, so the same seed and the same player actions give exactly the same game. Nothing rolls
## it at the moment (the timetable is fixed), but the seed and its state stay in the save.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The number the dice started from, for replaying a game (e.g. a failing test).
var game_seed: int = 0

# While loading a save, layout_changed is sent once at the end instead of for every building.
var _loading: bool = false
# Gates that can have flights right now (see usable_gates()); recalculated with the layout.
var _usable_gates: Array[Building] = []


func _init(size_in_cells: Vector2i = MAP_SIZE_CELLS) -> void:
	map_size = size_in_cells
	grid = AirportGrid.new(map_size, CELL_SIZE)
	# The very first dice come from the clock; every later new game takes its seed from them.
	var first := RandomNumberGenerator.new()
	first.randomize()
	reseed(first.randi())
	layout_changed.connect(_on_layout_changed)
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
	timetable.world = self


## Breaks the reference cycles so the brain can be freed (RefCounted objects that point at each
## other are never freed otherwise): the parts' `world` fields point back at the brain, and
## the brain listens to some of its own parts. Call it before dropping a brain; it is unusable after.
func dispose() -> void:
	if layout_changed.is_connected(_on_layout_changed):
		layout_changed.disconnect(_on_layout_changed)
	if schedule.plane_arriving.is_connected(plane_arriving.emit):
		schedule.plane_arriving.disconnect(plane_arriving.emit)
	schedule.world = null
	timetable.world = null


## Seconds since the airport started (flights are timed against it). Not a clock of its own: it
## is `Clock.elapsed` in real seconds (tech_architecture.md §3, one clock).
var sim_time: float:
	get:
		return clock.real_elapsed


## Advances the whole simulation by one step: the clock, the timetable and the flights.
func step(delta: float) -> void:
	clock.tick(delta)
	timetable.tick()
	schedule.tick(sim_time, delta)


## The name of the area at a walkway cell ("Check-in Hall", "Gates", ...), "" outside any area.
func area_name(cell: Vector2i) -> String:
	return area_map.area_name(cell)


## All areas as {"name", "zone", "cells"}.
func areas() -> Array:
	return area_map.areas()


## manager_position while there is no manager (e.g. simulation-only tests).
const NOBODY_THERE: Vector3 = Vector3(1.0e9, 0.0, 1.0e9)


## Why a building can't go here, as a short hint for the player, or "" if it can. The whole map
## is buildable and building is free.
func check_placement(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> String:
	for cell in Building.footprint_cells(type.footprint, origin_cell, rotation_steps):
		if not grid.is_inside(cell):
			return "Outside the map"
		if not grid.is_empty(cell):
			return "Space is taken"
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
	return ""


# One stand serves exactly one gate (design doc §10.2): a plane parks at the stand its gate's
# back row touches, so two gates on one stand would fight for it, and a gate touching two stands
# would not know which one is its own. Every building whose back side is a STAND counts.
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


func can_place(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> bool:
	return check_placement(type, origin_cell, rotation_steps).is_empty()


## Places a building if the spot is allowed. Returns the new building, or null.
func place_building(type: BuildingType, origin_cell: Vector2i, rotation_steps: int) -> Building:
	if not can_place(type, origin_cell, rotation_steps):
		return null
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


## Demolishes `building`, also during operation (design doc §7.6), and frees the cells it needed.
## Flights at it are cancelled by the schedule's next step.
func demolish(building: Building) -> bool:
	if not buildings.has(building):
		return false
	for cell in building.get_cells():
		grid.set_content(cell, null)
	buildings.erase(building)
	if Building.ground_surface_of(building.type) != 0:
		grid.set_surface_rect(building.get_rect(), 0)
	building_removed.emit(building)
	layout_changed.emit()
	return true


## Adds (or removes) walkway floor on `cells`. Works under buildings too (desks inside a hall).
## Free to build and to remove.
## Returns "" if it worked, or a hint why nothing was painted.
func paint_walkway(cells: Array[Vector2i], walkway: bool) -> String:
	var changing: Array[Vector2i] = []
	for cell in cells:
		# Walkway and taxiway never share a cell: people don't cross the planes' way.
		if grid.is_inside(cell) and grid.is_walkway(cell) != walkway and not grid.is_taxiway(cell):
			changing.append(cell)
	if changing.is_empty():
		return ""
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
	for cell in changing:
		grid.set_taxiway(cell, taxiway)
	walkways_changed.emit()
	layout_changed.emit()
	return ""


func _taxiway_changes(cells: Array[Vector2i], taxiway: bool) -> Array[Vector2i]:
	var changing: Array[Vector2i] = []
	for cell in cells:
		if not grid.is_inside(cell) or grid.is_taxiway(cell) == taxiway:
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
	clock.reset()
	timetable.clear()
	manager_position = NOBODY_THERE
	saved_manager = {}
	if with_runway:
		add_starting_runway()
	_on_layout_changed()


# The ID the next placed building gets. Never reused, so an ID always means one building.
var _next_building_id: int = 1
## After load_state(): the names of buildings that could not be restored (their place was taken).
## Buildings of removed types are dropped silently and not listed.
var load_skipped: PackedStringArray = PackedStringArray()


## The whole airport as plain data, for the save game.
func save_state() -> Dictionary:
	var saved_buildings: Array[Dictionary] = []
	for building in buildings:
		saved_buildings.append({
			"id": building.id,
			"type": String(building.type.id),
			"cell": [building.origin_cell.x, building.origin_cell.y],
			"rotation": building.rotation_steps,
		})
	return {
		"next_building_id": _next_building_id,
		"map_size": [grid.size.x, grid.size.y],
		"walkways": GridSave.encode(grid, AirportGrid.WALKWAY_BIT),
		"taxiways": GridSave.encode(grid, AirportGrid.TAXIWAY_BIT),
		"clock": clock.game_seconds,
		"clock_elapsed": clock.elapsed,
		"timetable": timetable.save_state(),
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
	if not data.has("clock_elapsed"):
		push_warning("Saved airport has no clock_elapsed: the clock starts at zero.")
	clock.load_state(float(data.get("clock_elapsed", 0.0)), float(data.get("clock", Clock.START_HOUR * 3600.0)))
	saved_manager = data.get("manager", {})
	var skipped := 0
	_loading = true
	# Saved building ID -> loaded building (skipped buildings are missing).
	var by_saved_id: Dictionary[int, Building] = {}
	load_skipped = PackedStringArray()
	var highest_id := 0
	for entry: Dictionary in data.get("buildings", []):
		var type := CATALOG.find(StringName(entry.get("type", "")))
		var cell: Array = entry.get("cell", [0, 0])
		var origin := Vector2i(int(cell[0]), int(cell[1])) + shift
		if type == null:
			continue  # a removed building type (docs/removed_features.md): dropped silently
		var building := place_building(type, origin, int(entry.get("rotation", 0)))
		if building == null:
			skipped += 1
			load_skipped.append(str(entry.get("type", "?")))
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
			load_skipped.append(String(displaced.type.id))
		_loading = false
	walkways_changed.emit()
	# Also recomputes the zones, after buildings and walkways are all in place.
	layout_changed.emit()
	# The timetable and the flights on their way, after the layout so the plane network exists.
	var saved_timetable: Variant = data.get("timetable", {})
	timetable.load_state(saved_timetable if saved_timetable is Dictionary else {}, by_saved_id)
	var saved_schedule: Variant = data.get("schedule", {})
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


# Gates that can have flights: connected on every side they need (a walkway in front on the
# right zone side, a stand behind that leads to a runway).
func _update_usable() -> void:
	_usable_gates.clear()
	for building in buildings:
		if building.type.role == BuildingType.Role.GATE \
				and connection_problem(building.type, building.origin_cell, building.rotation_steps).is_empty():
			_usable_gates.append(building)


## Gates that can have flights right now. Cached: recalculated after layout changes (asked often).
func usable_gates() -> Array[Building]:
	return _usable_gates


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
	if _usable_gates.is_empty():
		return "No gate in use yet: connect a gate to a walkway, a stand and a taxiway to the runway."
	return "Flights departed: %d" % schedule.departures


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
## if a building stands there (a migrated save), at the nearest free spot on the map:
## first moved up and down, then sideways. If there is none, the buildings in the default band are
## removed to make room. Returns those removed buildings. Never fails silently.
func add_starting_runway() -> Array[Building]:
	var type := CATALOG.find(&"runway")
	var removed: Array[Building] = []
	if buildings.any(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY):
		return removed
	var home := MapAnchor.centre_of(grid.size) + DEFAULT_RUNWAY_ORIGIN
	var spot: Variant = _free_runway_spot(type, home)
	if spot == null:
		# Nothing is free: the runway goes to the default spot (kept inside the land) and what stands there leaves.
		var land := Rect2i(Vector2i.ZERO, grid.size)
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
	if place_building(type, spot, 0) == null:
		push_warning("The starting runway could not be placed at %s." % [spot])
	return removed


# The nearest origin to `home` where a runway fits on the map without touching a building,
# or null. Rows first (up and down), then columns in steps of 50 cells.
func _free_runway_spot(type: BuildingType, home: Vector2i) -> Variant:
	var land := Rect2i(Vector2i.ZERO, grid.size)
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
