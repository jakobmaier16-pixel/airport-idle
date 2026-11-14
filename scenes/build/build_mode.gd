class_name BuildMode
extends Node3D
## Build view logic with two tools:
## - PLACE (design doc §7.1a): move the preview by dragging it (snaps cell by cell) or by tapping
##   the map, rotate it, then place or cancel.
## - PAINT (design doc §7.1b, §7.2): drag a rectangle (or tap a cell) to lay walkway floor or
##   taxiway, or remove it. Zones are not painted: they follow from the layout (design doc §8.1).
## - DEMOLISH (design doc §7.6): tap a building to select it, confirm to demolish it.
## With no tool active, tapping a cell highlights it.

enum Tool { NONE, PLACE, PAINT, DEMOLISH }
## The hint while a valid preview has nothing missing. Any other hint on a valid preview is
## information (what the building still needs), not an error; the HUD shows it in another colour.
const DRAG_HINT: String = "Drag the building to move it"

enum PaintKind { WALKWAY, REMOVE_WALKWAY, TAXIWAY }

## Emitted whenever the tool, its validity or its hint changes (so the HUD can update).
## can_confirm: PLACE = the spot is allowed; PAINT = always true; DEMOLISH = a building is selected.
signal tool_changed(tool: Tool, can_confirm: bool, hint: String)

## The camera used to find which cell was tapped.
@export var camera: BuildCamera
@export var valid_color: Color = Color(0.3, 0.9, 0.4, 0.55)
@export var invalid_color: Color = Color(0.95, 0.3, 0.25, 0.55)
@export var walkway_paint_color: Color = Color(0.95, 0.9, 0.7, 0.55)
@export var remove_paint_color: Color = Color(0.95, 0.3, 0.25, 0.45)
@export var taxiway_paint_color: Color = Color(0.15, 0.15, 0.17, 0.6)
@export var demolish_color: Color = Color(0.95, 0.2, 0.15, 0.5)
## A drag that starts this many cells around the preview still grabs it (fingers are wide).
@export var grab_margin_cells: int = 1

## Only reacts to taps while the build view is open. Leaving the build view ends the current tool.
var active: bool = false:
	set(value):
		active = value
		if not active:
			cancel_tool()
		_update_highlight()

var has_selection: bool = false
var selected_cell: Vector2i = Vector2i.ZERO

var _tool: Tool = Tool.NONE

# PLACE tool
var _placing_type: BuildingType = null
var _placing_rotation: int = 0
var _placing_origin: Vector2i = Vector2i.ZERO
# While the preview is being dragged: ground point under the finger minus the footprint corner,
# so the spot the player grabbed stays under the finger.
var _dragging_preview: bool = false
var _grab_offset: Vector3 = Vector3.ZERO
var _preview: BuildingVisual = null
var _preview_material: StandardMaterial3D
var _preview_front_material: StandardMaterial3D

# PAINT tool
var _paint_kind: PaintKind = PaintKind.WALKWAY
var _painting_drag: bool = false
var _paint_start_cell: Vector2i = Vector2i.ZERO
var _paint_rect: Rect2i = Rect2i()
# Taxiway: a rectangle from the start cell to the finger whose short side is BRUSH_CELLS (12 cells =
# 24 m, the width planes need); what the preview shows is exactly what is painted on release.
# Remove uses the older brush (a stamp that locks to one axis once the drag has moved AXIS_LOCK_CELLS)
# when the drag starts on taxiway.
const BRUSH_CELLS: int = 12
const AXIS_LOCK_CELLS: int = 3
## The long axis of a taxiway rectangle only switches when the finger is this many cells further along
## the other axis, so the rectangle does not flip near the diagonal.
const AXIS_SWITCH_CELLS: int = 6
var _brush_drag: bool = false
var _brush_axis: int = -1  # -1 not locked yet, 0 = x, 1 = y
var _taxiway_drag: bool = false
var _taxiway_axis: int = 0  # the long axis of the taxiway rectangle: 0 = x, 1 = y
var _paint_preview: MeshInstance3D
var _paint_material: StandardMaterial3D

# DEMOLISH tool: the selected building, shown with the paint preview box in red.
var _demolish_target: Building = null

@onready var _highlight: MeshInstance3D = $CellHighlight


func _ready() -> void:
	(_highlight.mesh as PlaneMesh).size = Vector2.ONE * Airport.grid.cell_size
	_highlight.visible = false
	_preview_material = _make_transparent_material(valid_color)
	_preview_front_material = _make_transparent_material(Color(0.1, 0.1, 0.1, 0.6))

	_paint_material = _make_transparent_material(walkway_paint_color)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.material = _paint_material
	_paint_preview = MeshInstance3D.new()
	_paint_preview.mesh = plane
	_paint_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_paint_preview.visible = false
	add_child(_paint_preview)

	TouchGestures.tapped.connect(_on_tapped)
	TouchGestures.drag_started.connect(_on_drag_started)
	TouchGestures.dragged.connect(_on_dragged)
	TouchGestures.drag_ended.connect(_on_drag_ended)
	TouchGestures.drag_cancelled.connect(_on_drag_cancelled)


func is_placing() -> bool:
	return _tool == Tool.PLACE


# --- Tools (called from the HUD via main.gd) ---

func start_placement(type: BuildingType) -> void:
	cancel_tool()
	_tool = Tool.PLACE
	_placing_type = type
	_placing_rotation = 0
	_preview = BuildingVisual.new()
	_preview.setup(type, Airport.grid.cell_size, _preview_material, _preview_front_material, false)
	# Slightly larger than the real building, so it doesn't flicker where it overlaps one.
	_preview.scale = Vector3.ONE * 1.02
	add_child(_preview)
	# Start in the middle of what the camera currently shows.
	var view_center := Vector3(camera.position.x, 0.0, camera.position.z)
	_center_preview_on(Airport.grid.world_to_cell(view_center))
	_update_highlight()


func start_painting(kind: PaintKind) -> void:
	cancel_tool()
	_tool = Tool.PAINT
	_paint_kind = kind
	_paint_material.albedo_color = _paint_color()
	_update_highlight()
	_emit_paint_hint("")


func start_demolish() -> void:
	cancel_tool()
	_tool = Tool.DEMOLISH
	_demolish_target = null
	_paint_material.albedo_color = demolish_color
	_update_highlight()
	tool_changed.emit(Tool.DEMOLISH, false, "Tap a building to demolish it")


## Demolishes the selected building; the tool stays open for the next one.
func confirm_demolish() -> void:
	if _tool != Tool.DEMOLISH or _demolish_target == null:
		return
	var type_name := _demolish_target.type.display_name
	Airport.demolish(_demolish_target)
	_demolish_target = null
	_paint_preview.visible = false
	tool_changed.emit(Tool.DEMOLISH, false, "%s demolished" % type_name)


func rotate_placement() -> void:
	if not is_placing():
		return
	# Turn around the footprint's center cell, so the building stays where it was.
	var center := _placing_origin + (_current_size() - Vector2i.ONE) / 2
	_placing_rotation = (_placing_rotation + 1) % 4
	_center_preview_on(center)


func confirm_placement() -> void:
	if is_placing() and Airport.place_building(_placing_type, _placing_origin, _placing_rotation) != null:
		_end_tool()


## Ends the current tool (Cancel while placing, Done while painting).
func cancel_tool() -> void:
	if _tool != Tool.NONE:
		_end_tool()


func select_cell(cell: Vector2i) -> void:
	has_selection = true
	selected_cell = cell
	# Slightly above the ground so it doesn't flicker against the ground surface.
	_highlight.position = Airport.grid.cell_to_world(cell) + Vector3(0.0, 0.02, 0.0)
	_update_highlight()


# --- Touch input ---

func _on_tapped(screen_position: Vector2) -> void:
	if not active or not camera:
		return
	var cell: Variant = _cell_at_screen_position(screen_position)
	if cell == null:
		return
	match _tool:
		Tool.NONE:
			select_cell(cell)
		Tool.PLACE:
			# Tapping the preview itself does nothing, so a missed grab doesn't shift it.
			if not _footprint_contains(cell, 0):
				_center_preview_on(cell)
		Tool.PAINT:
			if _paint_kind == PaintKind.TAXIWAY:
				# A tap lays nothing: a taxiway is always dragged out, so a stray touch never paints.
				_emit_paint_hint("")
			elif _uses_brush(cell):
				_emit_paint_hint(_apply_paint(_rect_cells(_brush_rect(cell, cell, -1))))
			else:
				var single: Array[Vector2i] = [cell]
				_emit_paint_hint(_paint_or_refuse(single, Rect2i(cell, Vector2i.ONE)))
		Tool.DEMOLISH:
			_select_for_demolish(cell)


func _on_drag_started(start_position: Vector2, touch_position: Vector2) -> void:
	if not active:
		return
	match _tool:
		Tool.PLACE:
			_try_grab_preview(start_position, touch_position)
		Tool.PAINT:
			var start_point: Variant = _ground_point(start_position)
			if start_point == null:
				return
			_painting_drag = true
			# One finger paints; two fingers still move the camera.
			camera.pan_enabled = false
			_paint_start_cell = _clamp_to_map(Airport.grid.world_to_cell(start_point))
			_taxiway_drag = _paint_kind == PaintKind.TAXIWAY
			_taxiway_axis = 0
			_brush_drag = not _taxiway_drag and _uses_brush(_paint_start_cell)
			_brush_axis = -1
			_update_paint_rect(touch_position)
			_paint_preview.visible = true


func _on_dragged(touch_position: Vector2, _relative: Vector2) -> void:
	if _dragging_preview:
		_drag_preview_to(touch_position)
	elif _painting_drag:
		_update_paint_rect(touch_position)


func _on_drag_ended(_touch_position: Vector2) -> void:
	_stop_dragging_preview()
	if _painting_drag:
		var cells := _rect_cells(_paint_rect)
		var rect := _paint_rect
		_stop_painting_drag()
		_emit_paint_hint(_paint_or_refuse(cells, rect))


# A second finger turned the drag into a pinch: keep the preview where it is, drop the rectangle.
func _on_drag_cancelled() -> void:
	_stop_dragging_preview()
	_stop_painting_drag()


# --- PLACE tool helpers ---

func _try_grab_preview(start_position: Vector2, touch_position: Vector2) -> void:
	var start_point: Variant = _ground_point(start_position)
	if start_point == null:
		return
	if not _footprint_contains(Airport.grid.world_to_cell(start_point), grab_margin_cells):
		return
	_dragging_preview = true
	# This drag moves the building, not the camera.
	camera.pan_enabled = false
	_grab_offset = (start_point as Vector3) - _origin_corner_world()
	_drag_preview_to(touch_position)


func _drag_preview_to(screen_position: Vector2) -> void:
	var point: Variant = _ground_point(screen_position)
	if point == null:
		return
	var grid := Airport.grid
	var corner := (point as Vector3) - _grab_offset - grid.origin
	# Round to the nearest cell corner, so the building snaps cell by cell.
	_set_preview_origin(Vector2i(roundi(corner.x / grid.cell_size), roundi(corner.z / grid.cell_size)))


func _stop_dragging_preview() -> void:
	if _dragging_preview:
		_dragging_preview = false
		camera.pan_enabled = true


func _center_preview_on(center_cell: Vector2i) -> void:
	_set_preview_origin(center_cell - (_current_size() - Vector2i.ONE) / 2)


func _set_preview_origin(origin_cell: Vector2i) -> void:
	var grid := Airport.grid
	# Keep the whole footprint on the map, so the preview never hangs over the edge.
	_placing_origin = origin_cell.clamp(Vector2i.ZERO, grid.size - _current_size())
	_preview.place_on_grid(grid, _placing_type.footprint, _placing_origin, _placing_rotation)
	var problem := Airport.check_placement(_placing_type, _placing_origin, _placing_rotation)
	var can_place := problem.is_empty()
	_preview_material.albedo_color = valid_color if can_place else invalid_color
	var hint := problem
	if can_place:
		# Unconnected is allowed (connect it later), but say what's missing.
		var missing := Airport.connection_hint(_placing_type, _placing_origin, _placing_rotation)
		hint = DRAG_HINT if missing.is_empty() else missing
	tool_changed.emit(Tool.PLACE, can_place, hint)


func _current_size() -> Vector2i:
	return Building.rotated_size(_placing_type.footprint, _placing_rotation)


# True if `cell` is inside the preview's footprint, grown by `margin` cells on every side.
func _footprint_contains(cell: Vector2i, margin: int) -> bool:
	return Rect2i(_placing_origin, _current_size()).grow(margin).has_point(cell)


func _origin_corner_world() -> Vector3:
	var grid := Airport.grid
	return grid.origin + Vector3(_placing_origin.x * grid.cell_size, 0.0, _placing_origin.y * grid.cell_size)


# --- DEMOLISH tool helpers ---

func _select_for_demolish(cell: Vector2i) -> void:
	var grid := Airport.grid
	if grid.is_empty(cell):
		_demolish_target = null
		_paint_preview.visible = false
		tool_changed.emit(Tool.DEMOLISH, false, "Tap a building to demolish it")
		return
	_demolish_target = grid.get_content(cell) as Building
	var size := Building.rotated_size(_demolish_target.type.footprint, _demolish_target.rotation_steps)
	# Cover the whole building with the red box (a little above its roof).
	_paint_preview.position = grid.block_center(_demolish_target.origin_cell, size) + Vector3(0.0, _demolish_target.type.height + 0.1, 0.0)
	_paint_preview.scale = Vector3(size.x * grid.cell_size, 1.0, size.y * grid.cell_size)
	_paint_preview.visible = true
	tool_changed.emit(Tool.DEMOLISH, true, "Demolish %s" % _demolish_target.type.display_name)


# --- PAINT tool helpers ---

func _update_paint_rect(screen_position: Vector2) -> void:
	var point: Variant = _ground_point(screen_position)
	if point == null:
		return
	var end_cell := _clamp_to_map(Airport.grid.world_to_cell(point))
	if _taxiway_drag:
		_paint_rect = _taxiway_rect(_paint_start_cell, end_cell)
		_show_paint_rect()
		return
	if _brush_drag:
		_paint_rect = _brush_rect(_paint_start_cell, end_cell, _lock_axis(end_cell))
		_show_paint_rect()
		return
	var top_left := Vector2i(mini(_paint_start_cell.x, end_cell.x), mini(_paint_start_cell.y, end_cell.y))
	var bottom_right := Vector2i(maxi(_paint_start_cell.x, end_cell.x), maxi(_paint_start_cell.y, end_cell.y))
	_paint_rect = Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)
	_show_paint_rect()


func _show_paint_rect() -> void:
	var grid := Airport.grid
	# Red where the paint would be refused (it goes over a building), like a building that cannot be placed.
	if _paint_kind != PaintKind.REMOVE_WALKWAY:
		_paint_material.albedo_color = invalid_color if _building_in(_paint_rect) != null else _paint_color()
	_paint_preview.position = grid.block_center(_paint_rect.position, _paint_rect.size) + Vector3(0.0, 0.03, 0.0)
	_paint_preview.scale = Vector3(_paint_rect.size.x * grid.cell_size, 1.0, _paint_rect.size.y * grid.cell_size)


func _uses_brush(cell: Vector2i) -> bool:
	return _paint_kind == PaintKind.REMOVE_WALKWAY and Airport.grid.is_taxiway(cell)


func _paint_color() -> Color:
	match _paint_kind:
		PaintKind.WALKWAY:
			return walkway_paint_color
		PaintKind.REMOVE_WALKWAY:
			return remove_paint_color
	return taxiway_paint_color


# The taxiway rectangle of a drag from `start` to `end`: it runs along the long axis from the start
# cell to the finger (at least BRUSH_CELLS long, extending towards the finger) and is BRUSH_CELLS wide
# across it, centred on the start cell. Cut off at the edge of the map.
func _taxiway_rect(start: Vector2i, end: Vector2i) -> Rect2i:
	var delta := end - start
	var along := [absi(delta.x), absi(delta.y)]
	if _taxiway_axis == 0 and along[1] >= along[0] + AXIS_SWITCH_CELLS:
		_taxiway_axis = 1
	elif _taxiway_axis == 1 and along[0] >= along[1] + AXIS_SWITCH_CELLS:
		_taxiway_axis = 0
	var long_delta := delta.x if _taxiway_axis == 0 else delta.y
	var length := maxi(absi(long_delta) + 1, BRUSH_CELLS)
	var first := start.x if _taxiway_axis == 0 else start.y
	var low := first - length + 1 if long_delta < 0 else first
	var across := (start.y if _taxiway_axis == 0 else start.x) - BRUSH_CELLS / 2
	var rect := Rect2i(Vector2i(low, across), Vector2i(length, BRUSH_CELLS)) if _taxiway_axis == 0 \
		else Rect2i(Vector2i(across, low), Vector2i(BRUSH_CELLS, length))
	return rect.intersection(Rect2i(Vector2i.ZERO, Airport.grid.size))


# The first building (any kind: also roads, curb, fence, car park ...) standing in `rect`, or null.
func _building_in(rect: Rect2i) -> Building:
	for building in Airport.buildings:
		if building.get_rect().intersects(rect):
			return building
	return null


# Paints unless a taxiway or walkway would go over a building: then nothing is painted and the player
# is told. Remove is never refused.
func _paint_or_refuse(cells: Array[Vector2i], rect: Rect2i) -> String:
	if _paint_kind != PaintKind.REMOVE_WALKWAY and _building_in(rect) != null:
		return "Can't build %s over a building" % ("a taxiway" if _paint_kind == PaintKind.TAXIWAY else "a walkway")
	return _apply_paint(cells)


# Locks to the axis of the bigger movement once the drag is AXIS_LOCK_CELLS away from the start.
func _lock_axis(end_cell: Vector2i) -> int:
	if _brush_axis < 0:
		var delta := (end_cell - _paint_start_cell).abs()
		if maxi(delta.x, delta.y) >= AXIS_LOCK_CELLS:
			_brush_axis = 0 if delta.x >= delta.y else 1
	return _brush_axis


# The cells covered by a stamp centred on `start` that slid to `end` along `axis` (-1: not moved).
func _brush_rect(start: Vector2i, end: Vector2i, axis: int) -> Rect2i:
	var low := Vector2i(start.x - BRUSH_CELLS / 2, start.y - BRUSH_CELLS / 2)
	var high := low + Vector2i(BRUSH_CELLS, BRUSH_CELLS)
	if axis == 0:
		low.x = mini(low.x, end.x - BRUSH_CELLS / 2)
		high.x = maxi(high.x, end.x - BRUSH_CELLS / 2 + BRUSH_CELLS)
	elif axis == 1:
		low.y = mini(low.y, end.y - BRUSH_CELLS / 2)
		high.y = maxi(high.y, end.y - BRUSH_CELLS / 2 + BRUSH_CELLS)
	var size := Airport.grid.size
	low = low.clamp(Vector2i.ZERO, size)
	high = high.clamp(Vector2i.ZERO, size)
	return Rect2i(low, high - low)


func _rect_cells(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y))
	return cells


func _stop_painting_drag() -> void:
	if _painting_drag:
		_painting_drag = false
		_brush_drag = false
		_taxiway_drag = false
		_paint_preview.visible = false
		camera.pan_enabled = true


# Applies the current paint kind. Returns "" if everything worked, or a hint for the player.
func _apply_paint(cells: Array[Vector2i]) -> String:
	match _paint_kind:
		PaintKind.WALKWAY:
			return Airport.paint_walkway(cells, true)
		PaintKind.REMOVE_WALKWAY:
			# Remove clears walkways and taxiways alike.
			Airport.paint_taxiway(cells, false)
			return Airport.paint_walkway(cells, false)
		PaintKind.TAXIWAY:
			return Airport.paint_taxiway(cells, true)
	return ""


# Shows `problem` if there is one, otherwise how to use the current paint tool.
func _emit_paint_hint(problem: String) -> void:
	var actions: Array[String] = ["lay walkway", "remove walkway or taxiway", "lay a 12 cell wide taxiway from stands to the runway"]
	var hint := problem
	if hint.is_empty():
		hint = "Drag to %s. Two fingers: move and zoom." % actions[_paint_kind]
	tool_changed.emit(Tool.PAINT, true, hint)


# --- Shared helpers ---

func _end_tool() -> void:
	_stop_dragging_preview()
	_stop_painting_drag()
	_demolish_target = null
	if _paint_preview != null:
		_paint_preview.visible = false
	_tool = Tool.NONE
	_placing_type = null
	if _preview:
		_preview.queue_free()
		_preview = null
	_update_highlight()
	tool_changed.emit(Tool.NONE, false, "")


func _clamp_to_map(cell: Vector2i) -> Vector2i:
	return cell.clamp(Vector2i.ZERO, Airport.grid.size - Vector2i.ONE)


# Returns the grid cell under a screen position, or null if it's off the map.
func _cell_at_screen_position(screen_position: Vector2) -> Variant:
	var point: Variant = _ground_point(screen_position)
	if point == null:
		return null
	var cell := Airport.grid.world_to_cell(point as Vector3)
	return cell if Airport.grid.is_inside(cell) else null


# Returns the point on the ground (y = 0) under a screen position, or null if there is none.
func _ground_point(screen_position: Vector2) -> Variant:
	# Shoot a ray from the camera through the pixel and see where it hits the ground.
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	return Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)


func _update_highlight() -> void:
	if is_node_ready():
		_highlight.visible = active and has_selection and _tool == Tool.NONE


func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
