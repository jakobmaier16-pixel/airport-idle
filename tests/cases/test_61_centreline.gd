extends TestCase
## The centreline graph and smooth ground routes (scripts/simulation/centreline_graph.gd,
## plane_route.gd; design doc §7.5a, step 7b). Built and tested, not yet used for timing.

const CELL_SIZE: float = 2.0
## No zig-zag: a turn in the opposite direction to the one before it, between two short segments.
const SHORT_SEGMENT_M: float = 8.0


# --- A hand-made airport: a runway, a 12 cell wide taxiway in an L shape and stands ---

class Layout extends RefCounted:
	var grid: AirportGrid
	var buildings: Array[Building] = []
	var network: PlaneNetwork = PlaneNetwork.new()
	var next_id: int = 1

	func _init(size: Vector2i) -> void:
		grid = AirportGrid.new(size, 2.0)

	func add(type_id: StringName, origin: Vector2i, rotation: int = 0) -> Building:
		var building := Building.new(Airport.CATALOG.find(type_id), origin, rotation)
		building.id = next_id
		next_id += 1
		buildings.append(building)
		var size := Building.rotated_size(building.type.footprint, rotation)
		for y in size.y:
			for x in size.x:
				grid.set_content(origin + Vector2i(x, y), building)
		return building

	func paint(origin: Vector2i, size: Vector2i, on: bool = true) -> void:
		for y in size.y:
			for x in size.x:
				grid.set_taxiway(origin + Vector2i(x, y), on)

	func rebuild() -> void:
		network.rebuild(grid, buildings)


# The runway on rows 100-122, a 12 wide vertical taxiway down from it, a 12 wide horizontal one,
# a stand on its far end and one below it.
func _l_layout() -> Layout:
	var layout := Layout.new(Vector2i(1200, 400))
	layout.add(&"runway", Vector2i(100, 100))
	layout.paint(Vector2i(300, 123), Vector2i(12, 80))
	layout.paint(Vector2i(300, 200), Vector2i(200, 12))
	layout.add(&"aircraft_stand", Vector2i(500, 195))
	layout.add(&"aircraft_stand", Vector2i(400, 212))
	layout.rebuild()
	return layout


func _stands(layout: Layout) -> Array[Building]:
	var result: Array[Building] = []
	for building in layout.buildings:
		if building.type.role == BuildingType.Role.AIRCRAFT_STAND:
			result.append(building)
	return result


func _turn_sign(a: Vector2, b: Vector2, c: Vector2) -> float:
	return signf((b - a).cross(c - b))


# Counts zig-zags: two consecutive turns in opposite directions where the segment between them (and
# one next to it) is short.
func _zigzags(route: PlaneRoute) -> int:
	var count := 0
	var points := route.points
	var last_sign := 0.0
	var last_short := false
	for i in range(1, points.size() - 1):
		var turn := (points[i] - points[i - 1]).normalized().cross((points[i + 1] - points[i]).normalized())
		if absf(turn) < 0.02:
			continue
		var sign := signf(turn)
		var short := points[i].distance_to(points[i - 1]) < SHORT_SEGMENT_M
		if last_sign != 0.0 and sign != last_sign and short and last_short:
			count += 1
		last_sign = sign
		last_short = short
	return count


func test_straight_taxiway_has_its_centreline_in_the_middle() -> void:
	var layout := _l_layout()
	var graph := layout.network.centreline()
	var origin := Vector2(layout.grid.origin.x, layout.grid.origin.z)
	# Axis nodes on the horizontal arm (x 330..470, away from the bend and the stands): row 206.
	var checked := 0
	for id in graph.axis_ids():
		var point := graph.point_of(id)
		if point.x > 330.0 and point.x < 390.0 and point.y > 195.0 and point.y < 215.0:
			checked += 1
			check(absf(point.y - 206.0) <= 1.0, "axis node at %s is within 1 cell of the middle (206)" % [point])
	check(checked > 20, "the horizontal arm has axis nodes (%d)" % checked)
	# And the vertical arm (x 300..311, middle 306).
	checked = 0
	for id in graph.axis_ids():
		var point := graph.point_of(id)
		if point.y > 130.0 and point.y < 190.0 and point.x > 295.0 and point.x < 316.0:
			checked += 1
			check(absf(point.x - 306.0) <= 1.0, "axis node at %s is within 1 cell of the middle (306)" % [point])
	check(checked > 15, "the vertical arm has axis nodes (%d)" % checked)
	# The route runs along it too.
	var route := layout.network.route_to_stand(_stands(layout)[0])
	check(route != null and not route.from_fallback, "the first stand has an axis route")
	for point in route.points:
		var cell := (point - origin) / CELL_SIZE
		if cell.x > 335.0 and cell.x < 390.0 and cell.y > 190.0 and cell.y < 215.0:
			check(absf(cell.y - 206.0) <= 1.0, "route point %s stays on the middle line" % [cell])


func test_every_connected_stand_has_a_smooth_route() -> void:
	var layout := _l_layout()
	var lonely := layout.add(&"aircraft_stand", Vector2i(700, 300))
	layout.rebuild()
	for stand in _stands(layout):
		var route := layout.network.route_to_stand(stand)
		if stand == lonely:
			check(route == null, "a stand without a taxiway has no route")
			continue
		check(route != null, "stand at %s has a route" % [stand.origin_cell])
		if route == null:
			continue
		check(not route.from_fallback, "stand at %s uses the axis graph" % [stand.origin_cell])
		check_eq(_zigzags(route), 0, "no zig-zag in the route to %s" % [stand.origin_cell])
		check(route.length > 0.0, "route has a length")
		var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
		var origin := Vector2(layout.grid.origin.x, layout.grid.origin.z)
		var middle := (Vector2(stand.origin_cell) + Vector2(size) * 0.5) * CELL_SIZE + origin
		check(route.points[route.points.size() - 1].distance_to(middle) < 0.01, "the route ends in the stand's middle")
		check(route.length >= route.points[0].distance_to(middle) - 0.01, "route is not shorter than the straight line")
		# Never off the pavement.
		for point in route.points:
			check(layout.network.centreline().is_paved_point((point - origin) / CELL_SIZE), "route point %s is paved" % [point])
		# It starts on the runway.
		var start := (route.points[0] - origin) / CELL_SIZE
		check(Rect2(100, 100, 1000, 23).has_point(start), "the route starts on the runway (%s)" % [start])


func test_route_sampling_by_distance() -> void:
	var layout := _l_layout()
	var route := layout.network.route_to_stand(_stands(layout)[0])
	check_eq(route.position_at(0.0), route.points[0], "distance 0 is the start")
	check(route.position_at(route.length).distance_to(route.points[route.points.size() - 1]) < 0.01, "full length is the end")
	check_eq(route.position_at(-5.0), route.points[0], "clamped before the start")
	var d := 0.0
	var previous := route.position_at(0.0)
	while d < route.length:
		d += 7.3
		var here := route.position_at(d)
		check(here.distance_to(previous) <= 7.3 + 0.01, "steps of 7.3 m move at most 7.3 m")
		check(absf(route.heading_at(d).length() - 1.0) < 0.001, "heading is a unit vector")
		previous = here
	check(route.position_out(0.0).distance_to(route.points[route.points.size() - 1]) < 0.01, "taxi out starts at the stand")
	check(route.heading_out(1.0).dot(route.heading_at(route.length - 1.0)) < -0.99, "taxi out faces backwards along the line")


func test_routes_are_cached_until_the_paved_layout_changes() -> void:
	var layout := _l_layout()
	var network := layout.network
	var stand := _stands(layout)[0]
	var route := network.route_to_stand(stand)
	var rebuilds := network.rebuild_count
	# A change that paves nothing (a walkway on land): the network and its routes stay as they are.
	for x in 10:
		layout.grid.set_walkway(Vector2i(20 + x, 20), true)
	layout.rebuild()
	check_eq(network.rebuild_count, rebuilds, "no rebuild for an unpaved change")
	check(network.route_to_stand(stand) == route, "same cached route object")
	# A paved change drops the cache.
	layout.paint(Vector2i(600, 100), Vector2i(12, 12))
	layout.rebuild()
	check_eq(network.rebuild_count, rebuilds + 1, "one rebuild for a paved change")
	var again := network.route_to_stand(stand)
	check(again != route, "a new route after a paved change")
	check_eq(again.length, route.length, "which is the same line, the layout around it did not change")
	# Cutting the taxiway cuts the route.
	layout.paint(Vector2i(300, 123), Vector2i(12, 80), false)
	layout.rebuild()
	check(network.route_to_stand(stand) == null, "no route after the taxiway is cut")


func test_building_the_graph_is_deterministic() -> void:
	var first := _l_layout()
	var second := _l_layout()
	for stand_index in 2:
		var a := first.network.route_to_stand(_stands(first)[stand_index])
		var b := second.network.route_to_stand(_stands(second)[stand_index])
		check_eq(a.points, b.points, "the same route twice")
	check_eq(first.network.centreline().axis_ids(), second.network.centreline().axis_ids(), "the same axis twice")


func test_showcase_routes_follow_the_four_way_paths() -> void:
	ShowcaseAirport.build(0.0)
	var network := Airport.plane_network
	var stands := 0
	for building in Airport.buildings:
		if building.type.role != BuildingType.Role.AIRCRAFT_STAND:
			continue
		stands += 1
		var cells := network.path_to_stand(building)
		var route := network.route_to_stand(building)
		check(route != null, "every showcase stand has a route")
		if route == null:
			continue
		check(not route.from_fallback, "stand at %s: axis route, no fallback" % [building.origin_cell])
		var origin := Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
		for point in route.points:
			check(network.centreline().is_paved_point((point - origin) / CELL_SIZE), "route point %s is paved" % [point])
		check_eq(_zigzags(route), 0, "no zig-zag at %s" % [building.origin_cell])
		var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
		var middle := (Vector2(building.origin_cell) + Vector2(size) * 0.5) * CELL_SIZE + Vector2(Airport.grid.origin.x, Airport.grid.origin.z)
		check(route.length >= route.points[0].distance_to(middle) - 0.01, "not shorter than the straight line")
		# The 4-way path starts at the runway's edge, the route on its middle line: add half a runway width.
		var four_way := (cells.size() - 1) * CELL_SIZE + 23.0
		check(route.length <= 1.3 * four_way, "route %.0f m <= 1.3 x the 4-way path %.0f m at %s" % [route.length, four_way, building.origin_cell])
	check(stands >= 3, "the showcase has stands")
	print("INFO showcase centreline: rebuild %.1f ms (graph %.1f ms), %d axis nodes" % [network.last_rebuild_ms, network.last_centreline_ms, network.centreline().axis_count()])


func test_big_airport_rebuild_time() -> void:
	# A big apron: a 1,000 cell runway, a 12 wide parallel taxiway, ten links and 20 stands.
	var layout := Layout.new(Vector2i(2200, 1600))
	layout.add(&"runway", Vector2i(400, 300))
	layout.paint(Vector2i(300, 400), Vector2i(1500, 12))
	for i in 10:
		layout.paint(Vector2i(400 + i * 140, 323), Vector2i(12, 80))
	for i in 20:
		layout.add(&"aircraft_stand", Vector2i(330 + i * 70, 412))
	var started := Time.get_ticks_usec()
	layout.rebuild()
	var total := (Time.get_ticks_usec() - started) / 1000.0
	var network := layout.network
	print("INFO big airport centreline: rebuild %.0f ms (graph %.0f ms), %d paved cells, %d axis nodes" % [total, network.last_centreline_ms, network.paved_count(), network.centreline().axis_count()])
	var routed := 0
	started = Time.get_ticks_usec()
	for stand in _stands(layout):
		if network.route_to_stand(stand) != null:
			routed += 1
	print("INFO big airport: %d routes in %.0f ms" % [routed, (Time.get_ticks_usec() - started) / 1000.0])
	check_eq(routed, 20, "every stand has a route")
	check(total < 4000.0, "rebuild stays bounded (%.0f ms)" % total)
