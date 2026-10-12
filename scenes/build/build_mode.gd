class_name BuildMode
extends Node3D
## Build view logic (design doc §7.1a): pick a building type, then move the preview by dragging it
## (snaps cell by cell) or by tapping the map, rotate it, then place or cancel.
## Without an active placement, tapping a cell highlights it.

## Emitted whenever placement starts, ends, or the preview moves (so the HUD can update its buttons).
signal placement_changed(is_placing: bool, can_place: bool)

## The camera used to find which cell was tapped.
@export var camera: BuildCamera
@export var valid_color: Color = Color(0.3, 0.9, 0.4, 0.55)
@export var invalid_color: Color = Color(0.95, 0.3, 0.25, 0.55)
## A drag that starts this many cells around the preview still grabs it (fingers are wide).
@export var grab_margin_cells: int = 1

## Only reacts to taps while the build view is open. Leaving the build view cancels a placement.
var active: bool = false:
	set(value):
		active = value
		if not active:
			cancel_placement()
		_update_highlight()

var has_selection: bool = false
var selected_cell: Vector2i = Vector2i.ZERO

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

@onready var _highlight: MeshInstance3D = $CellHighlight


func _ready() -> void:
	(_highlight.mesh as PlaneMesh).size = Vector2.ONE * Airport.grid.cell_size
	_highlight.visible = false
	_preview_material = _make_transparent_material(valid_color)
	_preview_front_material = _make_transparent_material(Color(0.1, 0.1, 0.1, 0.6))
	TouchGestures.tapped.connect(_on_tapped)
	TouchGestures.drag_started.connect(_on_drag_started)
	TouchGestures.dragged.connect(_on_dragged)
	TouchGestures.drag_ended.connect(_on_drag_ended)


func is_placing() -> bool:
	return _placing_type != null


func start_placement(type: BuildingType) -> void:
	cancel_placement()
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


func rotate_placement() -> void:
	if not is_placing():
		return
	# Turn around the footprint's center cell, so the building stays where it was.
	var center := _placing_origin + (_current_size() - Vector2i.ONE) / 2
	_placing_rotation = (_placing_rotation + 1) % 4
	_center_preview_on(center)


func confirm_placement() -> void:
	if not is_placing():
		return
	if Airport.place_building(_placing_type, _placing_origin, _placing_rotation) != null:
		_end_placement()


func cancel_placement() -> void:
	if is_placing():
		_end_placement()


func select_cell(cell: Vector2i) -> void:
	has_selection = true
	selected_cell = cell
	# Slightly above the ground so it doesn't flicker against the ground surface.
	_highlight.position = Airport.grid.cell_to_world(cell) + Vector3(0.0, 0.02, 0.0)
	_update_highlight()


func _on_tapped(screen_position: Vector2) -> void:
	if not active or not camera:
		return
	var cell: Variant = _cell_at_screen_position(screen_position)
	if cell == null:
		return
	if not is_placing():
		select_cell(cell)
	elif not _footprint_contains(cell, 0):
		# Tapping the preview itself does nothing, so a missed grab doesn't shift it.
		_center_preview_on(cell)


func _on_drag_started(start_position: Vector2, touch_position: Vector2) -> void:
	if not active or not is_placing():
		return
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


func _on_dragged(touch_position: Vector2, _relative: Vector2) -> void:
	if _dragging_preview:
		_drag_preview_to(touch_position)


func _on_drag_ended(_touch_position: Vector2) -> void:
	_stop_dragging_preview()


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
	var size := _current_size()
	# Keep the whole footprint on the map, so the preview never hangs over the edge.
	var clamped := origin_cell.clamp(Vector2i.ZERO, grid.size - size)
	_placing_origin = clamped
	_preview.place_on_grid(grid, _placing_type.footprint, _placing_origin, _placing_rotation)
	var can_place := Airport.can_place(_placing_type, _placing_origin, _placing_rotation)
	_preview_material.albedo_color = valid_color if can_place else invalid_color
	placement_changed.emit(true, can_place)


func _current_size() -> Vector2i:
	return Building.rotated_size(_placing_type.footprint, _placing_rotation)


# True if `cell` is inside the preview's footprint, grown by `margin` cells on every side.
func _footprint_contains(cell: Vector2i, margin: int) -> bool:
	var rect := Rect2i(_placing_origin, _current_size()).grow(margin)
	return rect.has_point(cell)


func _origin_corner_world() -> Vector3:
	var grid := Airport.grid
	return grid.origin + Vector3(_placing_origin.x * grid.cell_size, 0.0, _placing_origin.y * grid.cell_size)


func _end_placement() -> void:
	_stop_dragging_preview()
	_placing_type = null
	if _preview:
		_preview.queue_free()
		_preview = null
	_update_highlight()
	placement_changed.emit(false, false)


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
		_highlight.visible = active and has_selection and not is_placing()


func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
