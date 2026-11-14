class_name CentrelineGraph
extends RefCounted
## The middle lines of the paved airside (design doc §7.5a, step 7b). A 4-way cell path on a 12 cell
## wide taxiway is a staircase; this graph runs along the medial axis instead: the cells that are
## farthest from the pavement's edge. Built from the paved cell set in O(paved cells), only when
## PlaneNetwork's signature changes, and never per tick. Deterministic: no dice, ties by id.
##
## Works on 2 x 2 cell blocks (see MIN_CELLS_PER_BLOCK) to keep the cost down; the
## smoothing afterwards (string pull, corner rounding) checks the real cells again.

const BLOCK: int = 2
## A block counts as paved with this many of its 4 cells paved: a 2 cell wide taxiway on an odd row
## would vanish otherwise. The smoothing checks the real cells again.
const MIN_CELLS_PER_BLOCK: int = 2
## Chamfer 3-4 distance weights (straight, diagonal): distances come out in thirds of a block.
const STRAIGHT: int = 3
const DIAGONAL: int = 4
## How far (in blocks) a stand's lead-in node looks for the axis.
const LEAD_IN_RADIUS: int = 24
## Corner rounding radius in metres (design doc: about 30 m).
const CORNER_RADIUS_M: float = 30.0
const ARC_STEPS: int = 6
## A corner that turns less than this (radians) is left as it is.
const MIN_DEFLECTION: float = 0.05
## The corner before a stand's straight run is only rounded if it turns more than this (about 11 degrees):
## a smaller kink is invisible, and its tiny arc would only wobble the line.
const STAND_MIN_DEFLECTION: float = 0.2
const MIN_GAP: float = 4.0
## Room (cells) each side of a pulled-tight line; small, so a thin taxiway's wobble straightens out.
const PULL_ROOM: float = 4.2
## Cells of pavement kept free on every side of a rounded corner (a plane's middle stays 8 m inside).
const CURVE_ROOM: float = 4.1
## Node ids of stand lead-ins start here (AStar2D ids can't be negative); block ids are far smaller.
const LEAD_IN_BASE: int = 1 << 40

## Points are block centres in "cell corner" coordinates (cell i spans i .. i + 1); a lead-in node
## has the stand's middle. Stand lead-ins use ids LEAD_IN_BASE + stand.id, axis blocks their block id.
var astar: AStar2D = AStar2D.new()
var cell_width: int = 0
var cell_height: int = 0
var _block_width: int = 0
var _cells: Dictionary = {}
# Block clearance (chamfer units) by block id, for the axis blocks only.
var _clearance: Dictionary[int, int] = {}
# stand id -> lead-in node id (or absent when no axis is near)
var _lead_in: Dictionary[int, int] = {}
# Per runway building id: Array[int] node ids where a plane can leave / enter the runway.
var _exits: Dictionary[int, Array] = {}


func axis_count() -> int:
	return _clearance.size()


func has_lead_in(stand_id: int) -> bool:
	return _lead_in.has(stand_id)


## The node id of a stand's lead-in (only meaningful if `has_lead_in`).
func lead_in_of(stand_id: int) -> int:
	return LEAD_IN_BASE + stand_id


## Node ids on the axis (no lead-ins), ascending.
func axis_ids() -> PackedInt32Array:
	var ids := PackedInt32Array(_clearance.keys())
	ids.sort()
	return ids


func exits_of(runway_id: int) -> Array:
	return _exits.get(runway_id, [])


## Position (cell corner coordinates) of a node.
func point_of(id: int) -> Vector2:
	return astar.get_point_position(id)


## Builds the graph. `paved` has every paved cell id (y * width + x) as a key.
func build(paved: Dictionary, width: int, height: int, stands: Array[Building], runways: Array[Building]) -> void:
	_cells = paved
	cell_width = width
	cell_height = height
	_block_width = (width + BLOCK - 1) / BLOCK
	astar = AStar2D.new()
	_clearance = {}
	_lead_in = {}
	_exits = {}
	if paved.is_empty():
		return
	var ids := _paved_blocks()
	var index: Dictionary[int, int] = {}
	for i in ids.size():
		index[ids[i]] = i
	var dist := _distance_transform(ids, index)
	_pick_axis(ids, index, dist)
	_link_axis()
	for stand in stands:
		_add_lead_in(stand)
	for runway in runways:
		_find_exits(runway)


# Blocks whose four cells are all paved, ascending by id.
func _paved_blocks() -> PackedInt32Array:
	var counts: Dictionary[int, int] = {}
	for id: int in _cells:
		var block := (id / cell_width / BLOCK) * _block_width + (id % cell_width) / BLOCK
		counts[block] = counts.get(block, 0) + 1
	var result := PackedInt32Array()
	for block: int in counts:
		if counts[block] >= MIN_CELLS_PER_BLOCK:
			result.append(block)
	result.sort()
	return result


# Two-pass chamfer distance from the pavement's edge (outside counts as 0), in 1/3 blocks.
func _distance_transform(ids: PackedInt32Array, index: Dictionary[int, int]) -> PackedInt32Array:
	var bw := _block_width
	var dist := PackedInt32Array()
	dist.resize(ids.size())
	dist.fill(1 << 20)
	for i in ids.size():
		var id := ids[i]
		var x := id % bw
		var best := dist[i]
		best = mini(best, (dist[index[id - 1]] if x > 0 and index.has(id - 1) else 0) + STRAIGHT)
		best = mini(best, (dist[index[id - bw - 1]] if x > 0 and index.has(id - bw - 1) else 0) + DIAGONAL)
		best = mini(best, (dist[index[id - bw]] if index.has(id - bw) else 0) + STRAIGHT)
		best = mini(best, (dist[index[id - bw + 1]] if x < bw - 1 and index.has(id - bw + 1) else 0) + DIAGONAL)
		dist[i] = best
	for i in range(ids.size() - 1, -1, -1):
		var id := ids[i]
		var x := id % bw
		var best := dist[i]
		best = mini(best, (dist[index[id + 1]] if x < bw - 1 and index.has(id + 1) else 0) + STRAIGHT)
		best = mini(best, (dist[index[id + bw + 1]] if x < bw - 1 and index.has(id + bw + 1) else 0) + DIAGONAL)
		best = mini(best, (dist[index[id + bw]] if index.has(id + bw) else 0) + STRAIGHT)
		best = mini(best, (dist[index[id + bw - 1]] if x > 0 and index.has(id + bw - 1) else 0) + DIAGONAL)
		dist[i] = best
	return dist


# The ridge of the distance map: a block that is at least as far from the edge as the block before
# it and farther than the one after it, along any of the four directions. The "farther" on one side
# only makes a two-block-wide plateau give one line, not two.
func _pick_axis(ids: PackedInt32Array, index: Dictionary[int, int], dist: PackedInt32Array) -> void:
	var bw := _block_width
	var steps := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
	for i in ids.size():
		var id := ids[i]
		var x := id % bw
		var here := dist[i]
		for step: Vector2i in steps:
			var forward := id + step.y * bw + step.x
			var backward := id - step.y * bw - step.x
			var forward_ok := x + step.x >= 0 and x + step.x < bw
			var backward_ok := x - step.x >= 0 and x - step.x < bw
			var after := dist[index[forward]] if forward_ok and index.has(forward) else 0
			var before := dist[index[backward]] if backward_ok and index.has(backward) else 0
			if here >= before and here > after:
				_clearance[id] = here
				break
	for id: int in _clearance:
		astar.add_point(id, _block_centroid(id))


# The middle of the paved cells of a block: the block's centre when all four are paved, and the
# middle of the road when a thin taxiway only covers half of it.
func _block_centroid(block: int) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	var x0 := (block % _block_width) * BLOCK
	var y0 := (block / _block_width) * BLOCK
	for dy in BLOCK:
		for dx in BLOCK:
			if x0 + dx < cell_width and _cells.has((y0 + dy) * cell_width + x0 + dx):
				sum += Vector2(x0 + dx + 0.5, y0 + dy + 0.5)
				count += 1
	return sum / count


# Axis blocks next to each other (8 ways) are linked; a one-block gap in a thin line is bridged.
func _link_axis() -> void:
	var bw := _block_width
	var ordered := axis_ids()
	for id in ordered:
		var x := id % bw
		for step: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1)]:
			if x + step.x < 0 or x + step.x >= bw:
				continue
			var other := id + step.y * bw + step.x
			if _clearance.has(other):
				astar.connect_points(id, other, true)
	# Gaps: a dead end that has an axis block two steps away (but nothing closer) joins it.
	for id in ordered:
		if astar.get_point_connections(id).size() > 1:
			continue
		var x := id % bw
		var found := -1
		var found_distance := INF
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if maxi(absi(dx), absi(dy)) != 2 or x + dx < 0 or x + dx >= bw:
					continue
				var other := id + dy * bw + dx
				if _clearance.has(other) and not astar.are_points_connected(id, other):
					var d := point_of(id).distance_squared_to(point_of(other))
					if d < found_distance and segment_clear(point_of(id), point_of(other)):
						found = other
						found_distance = d
		if found >= 0:
			astar.connect_points(id, found, true)


# A stand's lead-in: its middle, joined to the nearest axis blocks (at most 3) it can see.
func _add_lead_in(stand: Building) -> void:
	var size := Building.rotated_size(stand.type.footprint, stand.rotation_steps)
	var middle := Vector2(stand.origin_cell) + Vector2(size) * 0.5
	var node := LEAD_IN_BASE + stand.id
	astar.add_point(node, middle)
	var centre_block := Vector2i(int(middle.x) / BLOCK, int(middle.y) / BLOCK)
	var linked := 0
	for radius in LEAD_IN_RADIUS + 1:
		var ring: Array[Vector3i] = []
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var bx := centre_block.x + dx
				var by := centre_block.y + dy
				if bx < 0 or by < 0 or bx >= _block_width:
					continue
				var block := by * _block_width + bx
				if _clearance.has(block):
					var offset := point_of(block) - middle
					ring.append(Vector3i(block, int(offset.length_squared() * 16.0), 0))
		ring.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for entry in ring:
			if linked < 3 and segment_clear(middle, point_of(entry.x)):
				astar.connect_points(node, entry.x, true)
				linked += 1
		# One ring further than the first hit still sees blocks that are really nearer.
		if linked > 0:
			break
	if linked > 0:
		_lead_in[stand.id] = node
	else:
		astar.remove_point(node)


# Where a plane can get on or off `runway`: the two ends of its middle line, and every middle line
# block where a taxiway's axis joins it.
func _find_exits(runway: Building) -> void:
	var size := Building.rotated_size(runway.type.footprint, runway.rotation_steps)
	var rect := Rect2(Vector2(runway.origin_cell), Vector2(size))
	var along_x := size.x >= size.y
	var middle := rect.get_center()
	var on_line: Array[int] = []
	for id in axis_ids():
		var point := point_of(id)
		if not rect.has_point(point):
			continue
		var offset := absf(point.y - middle.y) if along_x else absf(point.x - middle.x)
		if offset <= BLOCK:
			on_line.append(id)
	var exits: Array[int] = []
	if on_line.is_empty():
		_exits[runway.id] = exits
		return
	var first := on_line[0]
	var last := on_line[0]
	for id in on_line:
		var key := point_of(id).x if along_x else point_of(id).y
		var first_key := point_of(first).x if along_x else point_of(first).y
		var last_key := point_of(last).x if along_x else point_of(last).y
		if key < first_key or (key == first_key and id < first):
			first = id
		if key > last_key or (key == last_key and id < last):
			last = id
	exits.append(first)
	if last != first:
		exits.append(last)
	for id in on_line:
		if id in exits:
			continue
		for other in astar.get_point_connections(id):
			var point := astar.get_point_position(other)
			var offset := absf(point.y - middle.y) if along_x else absf(point.x - middle.x)
			if offset > BLOCK and not on_line.has(other):
				exits.append(id)
				break
	_exits[runway.id] = exits


# --- Paths ---

## The shortest axis path (node ids) between two nodes, or an empty array.
func node_path(from_node: int, to_node: int) -> PackedInt64Array:
	if not astar.has_point(from_node) or not astar.has_point(to_node):
		return PackedInt64Array()
	return astar.get_id_path(from_node, to_node)


## True if the point (cell corner coordinates) lies on a paved cell.
func is_paved_point(point: Vector2) -> bool:
	var x := floori(point.x)
	var y := floori(point.y)
	return x >= 0 and y >= 0 and x < cell_width and y < cell_height and _cells.has(y * cell_width + x)


## True if the straight line a-b stays on paved cells with `room` cells to spare on both sides.
func segment_clear(a: Vector2, b: Vector2, room: float = 0.9) -> bool:
	var span := b - a
	var length := span.length()
	var side := Vector2(-span.y, span.x) / length * room if length > 0.001 else Vector2.ZERO
	var steps := maxi(int(length / 0.5), 1)
	# is_paved_point written out three times: this is the hot loop of building the routes.
	var width := cell_width
	var height := cell_height
	for i in steps + 1:
		var p := a + span * (float(i) / steps)
		var x := floori(p.x)
		var y := floori(p.y)
		if x < 0 or y < 0 or x >= width or y >= height or not _cells.has(y * width + x):
			return false
		x = floori(p.x + side.x)
		y = floori(p.y + side.y)
		if x < 0 or y < 0 or x >= width or y >= height or not _cells.has(y * width + x):
			return false
		x = floori(p.x - side.x)
		y = floori(p.y - side.y)
		if x < 0 or y < 0 or x >= width or y >= height or not _cells.has(y * width + x):
			return false
	return true


## A smooth polyline in metres for the node path: string-pulled over paved cells, corners rounded.
## `points` are cell corner coordinates; `origin` and `cell_size` map them to world metres.
func smooth(points: PackedVector2Array, origin: Vector2, cell_size: float) -> PackedVector2Array:
	var pulled := _drop_close_points(_string_pull(points))
	var anchor := _anchor_of(pulled)
	var rounded := _round_corners(_relative(pulled, anchor), CORNER_RADIUS_M / cell_size, MIN_DEFLECTION, anchor)
	return _to_metres(rounded, anchor, origin, cell_size)


## Like `smooth`, for a route that ends with a straight run along a stand's axis. `points` runs from
## the runway exit to the push-back point B (its last point), `middle` is the stand's middle (cell
## corner coordinates). Returns two lines in metres: [0] the way in, exit to the stand's middle, with
## the corner at B rounded; [1] exit to B, whose last corner stays sharp: pushed back, the plane turns
## there, on the taxiway (see PlaneRoute).
func smooth_to_stand(points: PackedVector2Array, middle: Vector2, origin: Vector2, cell_size: float) -> Array[PackedVector2Array]:
	var pulled := _drop_close_points(_string_pull(points))
	var radius := CORNER_RADIUS_M / cell_size
	var anchor := _anchor_of(pulled)
	var relative := _relative(pulled, anchor)
	var way_out := _round_corners(relative, radius, MIN_DEFLECTION, anchor)
	var with_middle := relative.duplicate()
	with_middle.append(middle - anchor)
	var way_in := _round_corners(with_middle, radius, STAND_MIN_DEFLECTION, anchor)
	var result: Array[PackedVector2Array] = []
	result.append(_to_metres(way_in, anchor, origin, cell_size))
	result.append(_to_metres(way_out, anchor, origin, cell_size))
	return result


# The curves are computed relative to a whole-cell anchor near the line, so that their float values
# do not depend on how far from the map's corner they are (a map of another size gives the very same
# route, bit for bit: the behaviour hash relies on it).
func _anchor_of(line: PackedVector2Array) -> Vector2:
	return line[0].floor() if not line.is_empty() else Vector2.ZERO


func _relative(line: PackedVector2Array, anchor: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(line.size())
	for i in line.size():
		result[i] = line[i] - anchor
	return result


func _to_metres(line: PackedVector2Array, anchor: Vector2, origin: Vector2, cell_size: float) -> PackedVector2Array:
	var base := origin + anchor * cell_size
	var metres := PackedVector2Array()
	metres.resize(line.size())
	for i in line.size():
		metres[i] = base + line[i] * cell_size
	return metres


# Keeps only the points that are needed: from each kept point, the farthest later point that can
# be reached in a straight line over paved cells. Found by doubling and then halving the jump,
# so a long path costs a few line checks per kept point, not one per node.
func _string_pull(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.is_empty():
		return result
	var count := points.size()
	var current := 0
	result.append(points[0])
	while current < count - 1:
		var good := current + 1
		var jump := 2
		var bad := -1
		while current + jump < count:
			if segment_clear(points[current], points[current + jump], PULL_ROOM):
				good = current + jump
				jump *= 2
			else:
				bad = current + jump
				break
		if bad < 0 and good < count - 1:
			# The doubling ran past the end: try the last point itself.
			if segment_clear(points[current], points[count - 1], PULL_ROOM):
				good = count - 1
			else:
				bad = count - 1
		if bad >= 0:
			var low := good
			var high := bad
			while high - low > 1:
				var mid := (low + high) >> 1
				if segment_clear(points[current], points[mid], PULL_ROOM):
					low = mid
				else:
					high = mid
			good = low
		current = good
		result.append(points[current])
	return result


# A point less than MIN_GAP cells after the last kept one only wobbles the line (the axis of a thin
# taxiway or a stand is a few cells thick): skipped when the line can go straight on over it.
func _drop_close_points(line: PackedVector2Array) -> PackedVector2Array:
	if line.size() < 3:
		return line
	var result := PackedVector2Array()
	result.append(line[0])
	for i in range(1, line.size() - 1):
		var kept := result[result.size() - 1]
		if kept.distance_to(line[i]) < MIN_GAP and segment_clear(kept, line[i + 1], PULL_ROOM):
			continue
		result.append(line[i])
	result.append(line[line.size() - 1])
	return result


# True if `point` and the eight points `room` cells around it (a box) are on paved cells.
func has_room(point: Vector2, room: float, anchor: Vector2 = Vector2.ZERO) -> bool:
	for dy in [-room, 0.0, room]:
		for dx in [-room, 0.0, room]:
			if not is_paved_point(anchor + point + Vector2(dx, dy)):
				return false
	return true


# Cuts every corner with a quadratic curve, as wide as the pavement allows: the tangent length of a
# circle of `radius` (cell units), at most half of each neighbouring line, halved until the whole
# curve stays on paved cells.
func _round_corners(line: PackedVector2Array, radius: float, last_min_deflection: float = MIN_DEFLECTION, anchor: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	if line.size() < 3:
		return line
	var result := PackedVector2Array()
	result.append(line[0])
	for i in range(1, line.size() - 1):
		var corner := line[i]
		var to_prev := line[i - 1] - corner
		var to_next := line[i + 1] - corner
		var prev_length := to_prev.length()
		var next_length := to_next.length()
		if prev_length < 0.001 or next_length < 0.001:
			continue
		var dir_prev := to_prev / prev_length
		var dir_next := to_next / next_length
		# Deflection angle between the incoming and the outgoing direction.
		var deflection := PI - absf(dir_prev.angle_to(dir_next))
		if deflection < (last_min_deflection if i == line.size() - 2 else MIN_DEFLECTION):
			result.append(corner)
			continue
		var full_tangent := minf(radius * tan(deflection * 0.5), 0.5 * minf(prev_length, next_length))
		var done := false
		# As much room to the pavement's edge as there is; a tight junction gets a tighter curve
		# (down to the centre point only) rather than a sharp corner.
		for room in [CURVE_ROOM, 2.5, 0.0]:
			var tangent := full_tangent
			for attempt in 4:
				var start := corner + dir_prev * tangent
				var end := corner + dir_next * tangent
				var curve := PackedVector2Array()
				var ok := true
				for s in ARC_STEPS + 1:
					var t := float(s) / ARC_STEPS
					var p := start.lerp(corner, t).lerp(corner.lerp(end, t), t)
					if not has_room(p, room, anchor):
						ok = false
						break
					curve.append(p)
				if ok:
					result.append_array(curve)
					done = true
					break
				tangent *= 0.5
			if done:
				break
		if not done:
			result.append(corner)
	result.append(line[line.size() - 1])
	return result
