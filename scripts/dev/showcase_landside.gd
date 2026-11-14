class_name ShowcaseLandside
extends RefCounted
## The approved landside start layout (art/landside/landside_preview.py) as buildable pieces, for the
## showcase airport: country road, one-way loop, curb road with Kiss & Fly, zebra, bus bay and taxi
## rank, a fenced 128-bay car park with a barrier gate, sidewalks, signs, lights, bollards and trees.
##
## The preview is drawn in metres with the terminal on the north side (+Y). The showcase has its
## terminal south of the landside, so the layout is turned by 180 degrees (a rotation, no mirror):
## preview (x, y) metres -> world cell (ORIGIN_X - x / 2, ORIGIN_Z + y / 2). Door 1 of the preview
## (x = 44 m) ends up in front of the showcase entrance.
## Everything is decorative: pieces have no role, so they change nothing in the simulation.
##
## Differences from the preview, forced by the one-building-per-cell grid:
## - Fence, hedge, mast and tree rows sit one cell outside the car park instead of on its edge.
## - The car-park sidewalk is one cell (2 m) wide: the north fence takes the other cell.
## - A bollard is one per cell (2 m apart, was 1.5 m); props that stand on a sidewalk replace its tile.
## - The bus shelter stands beside the bus bay, not inside it (a cell holds one building).
## - Light masts, trees and signs inside walkway pieces are left out.

## Where the preview's origin is, in cells of the 64 x 64 reference map (see MapAnchor): the terminal
## face (y = 74 m) meets the showcase entrance at row 19, door 1 (x = 44 m) is in line with its middle.
const ORIGIN_X: int = 54
const ORIGIN_Z: int = -18

## Pieces that could not be placed, as "id at cell: reason". Empty when the layout is complete.
static var failures: PackedStringArray = PackedStringArray()
## How many pieces the layout placed.
static var placed: int = 0

static var _catalog: BuildingCatalog


## Places the whole layout. Call between Airport.begin_batch() and end_batch().
static func build() -> void:
	failures = PackedStringArray()
	placed = 0
	_paved_tile_removed.clear()
	_catalog = Airport.CATALOG
	_roads()
	_curb()
	_car_park()
	_props()
	_sidewalks()
	_trees()


# --- Placing -----------------------------------------------------------------------------------

# Rotation in preview degrees (counter-clockwise from above) -> rotation steps of the turned layout.
static func _steps(rot_deg: float) -> int:
	return posmod(-roundi((rot_deg + 180.0) / 90.0), 4)


# A piece whose footprint is centred on (cx, cy) metres of the preview.
static func _piece(id: StringName, cx: float, cy: float, rot_deg: float = 0.0) -> void:
	var type := _catalog.find(id)
	assert(type != null, "unknown landside piece %s" % id)
	var steps := _steps(rot_deg)
	var size := Building.rotated_size(type.footprint, steps)
	var origin := Vector2i(roundi(ORIGIN_X - cx / 2.0 - size.x / 2.0), roundi(ORIGIN_Z + cy / 2.0 - size.y / 2.0))
	_put(type, origin, steps)


# A one-cell piece on the cell (a, b) of the preview grid (a, b = metres / 2).
static func _cell(id: StringName, a: int, b: int, rot_deg: float = 0.0) -> void:
	_piece(id, a * 2.0 + 1.0, b * 2.0 + 1.0, rot_deg)


static func _put(type: BuildingType, reference_origin: Vector2i, steps: int) -> void:
	var origin := MapAnchor.cell(reference_origin, Airport.grid.size)
	var problem := Airport.check_placement(type, origin, steps)
	if not problem.is_empty():
		failures.append("%s at %s: %s" % [type.id, reference_origin, problem])
		return
	if Airport.place_building(type, origin, steps) != null:
		placed += 1


# --- Roads -------------------------------------------------------------------------------------

static func _roads() -> void:
	_piece(&"road_country_tjunction", 4, 8)  # loop entry (west)
	_piece(&"road_country_tjunction_giveway", 140, 8)  # loop exit (east)
	var xs: Array[int] = []
	for x in range(-36, -8, 8):
		xs.append(x)
	for x in range(20, 128, 8):
		xs.append(x)
	for x in range(156, 188, 8):
		xs.append(x)
	for x in xs:
		_piece(&"road_country_straight", x, 4)
	# West leg northbound, with the opening to the car park gate; east leg southbound.
	_piece(&"road_oneway_2lane_straight", 4, 20, 90)
	_piece(&"road_oneway_2lane_access", 4, 32, 90)
	_piece(&"road_oneway_2lane_arrows", 4, 44, 90)
	for y in [20, 28, 36, 44]:
		_piece(&"road_oneway_2lane_arrows" if y == 36 else &"road_oneway_2lane_straight", 140, y, -90)
	_piece(&"road_oneway_corner", 8, 56)
	_piece(&"road_oneway_corner", 136, 56, -90)


# --- Curb road along the terminal --------------------------------------------------------------

static func _curb() -> void:
	_piece(&"curb_dropoff_segment", 28, 65)
	_piece(&"zebra_crossing", 44, 62)
	_piece(&"curb_plain_segment_arrows", 52, 62)
	_piece(&"curb_plain_segment", 60, 62)
	_piece(&"curb_bus_bay", 76, 65)
	_piece(&"curb_plain_segment", 92, 62)
	_piece(&"curb_taxi_rank_4", 108, 62)
	_piece(&"curb_plain_segment_arrows", 124, 62)
	# The shelter stands on the terminal sidewalk just east of the bay (cells 44..46, row 35).
	for a in range(44, 47):
		_paved_tile_removed.append(Vector2i(a, 35))
	_piece(&"bus_shelter", 91.0, 71.0)


# --- Car park ----------------------------------------------------------------------------------

const WALK_X: int = 44
const MODULE_XS: Array[int] = [27, 37, 51, 61, 71, 81, 91, 101]
# Cells (preview grid) of the sidewalk that a prop takes over; no tile is placed there.
static var _paved_tile_removed: Array[Vector2i] = []


static func _car_park() -> void:
	for row_y in [28, 44]:
		for x in MODULE_XS:
			_piece(&"carpark_module", x, row_y)
		_piece(&"carpark_walkway_end" if row_y == 28 else &"carpark_walkway", WALK_X, row_y)
		_piece(&"carpark_end_aisle", 19, row_y)
		_piece(&"carpark_end_aisle", 109, row_y)
	_piece(&"carpark_barrier_gate", 12, 32)
	# Fence ring, one cell outside the car park. South (row 9), east (column 56), north (row 26), west (column 7).
	for a in range(8, 56):
		_cell(&"fence_panel_2m", a, 9)
	for b in range(10, 26):
		_cell(&"fence_panel_2m", 56, b, 90)
	for a in range(8, 56):
		if a == 21 or a == 22:
			continue  # the pedestrian gate
		if a == 23:
			continue  # the pay station
		_cell(&"fence_panel_2m", a, 26, 180)
	_piece(&"fence_gate_pedestrian", WALK_X, 53, 180)
	for b in [10, 11, 20, 21, 22, 23]:
		_cell(&"fence_panel_2m", 7, b, -90)
	for corner in [Vector2i(7, 9), Vector2i(56, 9), Vector2i(56, 26)]:
		_cell(&"fence_post", corner.x, corner.y)
	_cell(&"carpark_info_board", 6, 11, -90)  # faces drivers turning in
	_cell(&"sign_parking", 4, 8)  # the "P" sign before the access
	_paved_tile_removed.append(Vector2i(23, 26))
	_cell(&"pay_station", 23, 26, -90)  # beside the pedestrian exit
	for a in range(8, 56):
		_cell(&"hedge_2m", a, 8)  # outside the south fence
	for b in range(20, 24):
		_cell(&"hedge_2m", 6, b, 90)  # outside the north part of the west fence


# --- Street furniture --------------------------------------------------------------------------

static func _props() -> void:
	# Anti-ram bollards along the terminal curb (row 34): none at the zebra, the bus bay and the
	# Kiss & Fly pockets, which are pieces of their own.
	for a in range(0, 72):
		if a == 20 or (a >= 23 and a < 32) or (a >= 44 and a < 64):
			_paved_tile_removed.append(Vector2i(a, 34))
			_cell(&"bollard", a, 34)
	# Street lights on the car-park sidewalk, and masts outside the car park.
	for a in [12, 31, 48, 62]:
		_paved_tile_removed.append(Vector2i(a, 27))
		_cell(&"light_mast", a, 27)
	for a in [15, 32, 49]:
		_cell(&"light_mast", a, 7)
	_cell(&"light_mast", 57, 18)
	# Wayfinding beside door 1 / the zebra, and on the car-park side.
	_paved_tile_removed.append(Vector2i(23, 35))
	_cell(&"sign_wayfinding", 23, 35)
	_paved_tile_removed.append(Vector2i(20, 27))
	_cell(&"sign_wayfinding", 20, 27, 180)


# --- Sidewalks ---------------------------------------------------------------------------------

static func _sidewalks() -> void:
	# Tiles as cells (a, b) of the preview grid.
	var tiles: Dictionary[Vector2i, bool] = {}
	for a in range(8, 64):  # car-park sidewalk, row 27 (row 26 is the fence)
		tiles[Vector2i(a, 27)] = true
	for a in range(0, 72):  # terminal sidewalk, rows 34..36
		if (a >= 32 and a < 44) or (a >= 8 and a < 20):
			continue  # the bus bay and the Kiss & Fly pieces bring their own sidewalk
		for b in range(34, 37):
			tiles[Vector2i(a, b)] = true
	for a in list_range(0, 8) + list_range(64, 72):
		for b in [32, 33]:
			tiles[Vector2i(a, b)] = true  # above the loop road corners
	var lowered := [Vector2i(21, 27), Vector2i(22, 27)]  # one 4 m lowered piece, car-park side of the zebra
	var landing := [Vector2i(21, 34), Vector2i(22, 34)]  # tactile landing, terminal side
	# What counts as raised for the curb stones: tiles, the pieces' own sidewalks, the terminal, the fence.
	var raised: Dictionary[Vector2i, bool] = tiles.duplicate()
	for a in list_range(32, 44) + list_range(8, 20):
		for b in range(34, 37):
			raised[Vector2i(a, b)] = true
	for a in range(10, 62):
		raised[Vector2i(a, 37)] = true
	for a in range(8, 56):
		raised[Vector2i(a, 26)] = true
	for cell: Vector2i in lowered + landing:
		tiles.erase(cell)
	for cell in _paved_tile_removed:
		tiles.erase(cell)
	var cells: Array[Vector2i] = tiles.keys()
	cells.sort()
	for cell in cells:
		var open := ""
		# Sides in the order south, east, north, west (preview directions).
		for entry: Array in [["s", Vector2i(0, -1)], ["e", Vector2i(1, 0)], ["n", Vector2i(0, 1)], ["w", Vector2i(-1, 0)]]:
			if raised.has(cell + (entry[1] as Vector2i)):
				continue
			if entry[0] == "s" and cell.y == 34 and cell.x >= 8 and cell.x < 64:
				continue  # the curb pieces' raised strip continues here
			open += entry[0]
		match open:
			"":
				_cell(&"sidewalk_tile", cell.x, cell.y)
			"s":
				_cell(&"sidewalk_edge", cell.x, cell.y, 0)
			"e":
				_cell(&"sidewalk_edge", cell.x, cell.y, 90)
			"n":
				_cell(&"sidewalk_edge", cell.x, cell.y, 180)
			"w":
				_cell(&"sidewalk_edge", cell.x, cell.y, -90)
			"sw":
				_cell(&"sidewalk_corner", cell.x, cell.y, 0)
			"se":
				_cell(&"sidewalk_corner", cell.x, cell.y, 90)
			"en":
				_cell(&"sidewalk_corner", cell.x, cell.y, 180)
			"nw":
				_cell(&"sidewalk_corner", cell.x, cell.y, -90)
			_:
				_cell(&"sidewalk_tile", cell.x, cell.y)
	_piece(&"sidewalk_edge_lowered_4m", WALK_X, 55, 180)
	_piece(&"sidewalk_tactile_landing", WALK_X, 69)


static func list_range(from: int, to: int) -> Array[int]:
	var result: Array[int] = []
	for i in range(from, to):
		result.append(i)
	return result


# --- Trees -------------------------------------------------------------------------------------

static func _trees() -> void:
	for a in range(10, 56, 4):  # outside the south fence
		_cell(&"tree_deciduous", a, 6)
	for b in range(11, 25, 4):  # east of the car park
		_cell(&"tree_deciduous", 58, b)
	for b in range(9, 24, 4):  # loop road verges, outside
		_cell(&"tree_deciduous", -3, b)
		_cell(&"tree_deciduous", 74, b)
	for a in range(-15, 87, 6):  # country road, north verge
		if a > -6 and a < 10 or a > 62 and a < 78:
			continue
		_cell(&"tree_deciduous", a, 6)
