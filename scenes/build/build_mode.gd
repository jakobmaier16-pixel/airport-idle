class_name BuildMode
extends Node3D
## Build view logic with two tools:
## - PLACE (design doc §7.1a): move the preview by dragging it (snaps cell by cell) or by tapping
##   the map, rotate it, then place or cancel.
## - PAINT (design doc §7.1b, §7.2): drag a rectangle (or tap a cell) to paint landside / airside,
##   lay walkway floor or remove it.
## With no tool active, tapping a cell highlights it.

enum Tool { NONE, PLACE, PAINT }
enum PaintKind { AIRSIDE, LANDSIDE, WALKWAY, REMOVE_WALKWAY }

## Emitted whenever the tool, its validity or its hint changes (so the HUD can update).
## can_confirm: PLACE = the spot is allowed; PAINT = always true.
signal tool_changed(tool: Tool, can_confirm: bool, hint: String)

## The camera used to find which cell was tapped.
@export var camera: BuildCamera
@export var valid_color: Color = Color(0.3, 0.9, 0.4, 0.55)
@export var invalid_color: Color = Color(0.95, 0.3, 0.25, 0.55)
@export var airside_paint_color: Color = Color(0.25, 0.35, 0.6, 0.45)
@export var landside_paint_color: Color = Color(0.35, 0.8, 0.35, 0.45)
@export var walkway_paint_color: Color = Color(0.95, 0.9, 0.7, 0.55)
@export var remove_paint_color: Color = Color(0.95, 0.3, 0.25, 0.45)
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
var _paint_kind: PaintKind = PaintKind.AIRSIDE
var _painting_drag: bool = false
var _paint_start_cell: Vector2i = Vector2i.ZERO
var _paint_rect: Rect2i = Rect2i()
var _paint_preview: MeshInstance3D
var _paint_material: StandardMaterial3D

@onready var _highlight: MeshInstance3D = $CellHighlight


func _ready() -> void:
	(_highlight.mesh as PlaneMesh).size = Vector2.ONE * Airport.grid.cell_size
	_highlight.visible = false
	_preview_material = _make_transparent_material(valid_color)
	_preview_front_material = _make_transparent_material(Color(0.1, 0.1, 0.1, 0.6))

	_paint_material = _make_transparent_material(airside_paint_color)
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
	var colors: Array[Color] = [airside_paint_color, landside_paint_color, walkway_paint_color, remove_paint_color]
	_paint_material.albedo_color = colors[kind]
	_update_highlight()
	_emit_paint_hint("")


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
			var single: Array[Vector2i] = [cell]
			_emit_paint_hint(_apply_paint(single))


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
		var cells: Array[Vector2i] = []
		for y in range(_paint_rect.position.y, _paint_rect.end.y):
			for x in range(_paint_rect.position.x, _paint_rect.end.x):
				cells.append(Vector2i(x, y))
		_stop_painting_drag()
		_emit_paint_hint(_apply_paint(cells))


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
		var missing := Airport.connection_problem(_placing_type, _placing_origin, _placing_rotation)
		hint = "Drag the building to move it" if missing.is_empty() else missing + " (can be added later)"
		hint += "  ·  " + Economy.format(_placing_type.build_cost)
	tool_changed.emit(Tool.PLACE, can_place, hint)


func _current_size() -> Vector2i:
	return Building.rotated_size(_placing_type.footprint, _placing_rotation)


# True if `cell` is inside the preview's footprint, grown by `margin` cells on every side.
func _footprint_contains(cell: Vector2i, margin: int) -> bool:
	return Rect2i(_placing_origin, _current_size()).grow(margin).has_point(cell)


func _origin_corner_world() -> Vector3:
	var grid := Airport.grid
	return grid.origin + Vector3(_placing_origin.x * grid.cell_size, 0.0, _placing_origin.y * grid.cell_size)


# --- PAINT tool helpers ---

func _update_paint_rect(screen_position: Vector2) -> void:
	var point: Variant = _ground_point(screen_position)
	if point == null:
		return
	var end_cell := _clamp_to_map(Airport.grid.world_to_cell(point))
	var top_left := Vector2i(mini(_paint_start_cell.x, end_cell.x), mini(_paint_start_cell.y, end_cell.y))
	var bottom_right := Vector2i(maxi(_paint_start_cell.x, end_cell.x), maxi(_paint_start_cell.y, end_cell.y))
	_paint_rect = Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)
	var grid := Airport.grid
	_paint_preview.position = grid.block_center(_paint_rect.position, _paint_rect.size) + Vector3(0.0, 0.03, 0.0)
	_paint_preview.scale = Vector3(_paint_rect.size.x * grid.cell_size, 1.0, _paint_rect.size.y * grid.cell_size)


func _stop_painting_drag() -> void:
	if _painting_drag:
		_painting_drag = false
		_paint_preview.visible = false
		camera.pan_enabled = true


# Applies the current paint kind. Returns "" if everything worked, or a hint for the player.
func _apply_paint(cells: Array[Vector2i]) -> String:
	var blocked := 0
	match _paint_kind:
		PaintKind.AIRSIDE:
			blocked = Airport.paint_zone(cells, AirportGrid.Zone.AIRSIDE)
		PaintKind.LANDSIDE:
			blocked = Airport.paint_zone(cells, AirportGrid.Zone.LANDSIDE)
		PaintKind.WALKWAY:
			return Airport.paint_walkway(cells, true)
		PaintKind.REMOVE_WALKWAY:
			return Airport.paint_walkway(cells, false)
	if blocked > 0:
		return "%d cells kept: a building needs their zone." % blocked
	return ""


# Shows `problem` if there is one, otherwise how to use the current paint tool.
func _emit_paint_hint(problem: String) -> void:
	var actions: Array[String] = ["paint airside", "paint landside", "lay walkway (%s per cell)" % Economy.format(Economy.WALKWAY_COST_PER_CELL), "remove walkway"]
	var hint := problem
	if hint.is_empty():
		hint = "Drag to %s. Two fingers: move and zoom." % actions[_paint_kind]
	tool_changed.emit(Tool.PAINT, true, hint)


# --- Shared helpers ---

func _end_tool() -> void:
	_stop_dragging_preview()
	_stop_painting_drag()
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
