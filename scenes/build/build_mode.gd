class_name BuildMode
extends Node3D
## Build view logic (design doc §7.1a): pick a building type, tap the map to move the preview,
## rotate it, then place or cancel. Without an active placement, tapping a cell highlights it.

## Emitted whenever placement starts, ends, or the preview moves (so the HUD can update its buttons).
signal placement_changed(is_placing: bool, can_place: bool)

## The camera used to find which cell was tapped.
@export var camera: BuildCamera
## Building types offered in the build menu.
@export var building_types: Array[BuildingType] = []
@export var valid_color: Color = Color(0.3, 0.9, 0.4, 0.55)
@export var invalid_color: Color = Color(0.95, 0.3, 0.25, 0.55)

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
# The cell the player tapped; the footprint is centered on it (as far as the map edge allows).
var _placing_center_cell: Vector2i = Vector2i.ZERO
var _placing_origin: Vector2i = Vector2i.ZERO
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
	_move_preview(Airport.grid.world_to_cell(view_center))
	_update_highlight()


func rotate_placement() -> void:
	if not is_placing():
		return
	_placing_rotation = (_placing_rotation + 1) % 4
	_move_preview(_placing_center_cell)


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
	if is_placing():
		_move_preview(cell)
	else:
		select_cell(cell)


func _move_preview(center_cell: Vector2i) -> void:
	_placing_center_cell = center_cell
	var grid := Airport.grid
	var size := Building.rotated_size(_placing_type.footprint, _placing_rotation)
	# Keep the whole footprint on the map, so the preview never hangs over the edge.
	_placing_origin = (center_cell - (size - Vector2i.ONE) / 2).clamp(Vector2i.ZERO, grid.size - size)
	_preview.place_on_grid(grid, _placing_type.footprint, _placing_origin, _placing_rotation)
	var can_place := Airport.can_place(_placing_type, _placing_origin, _placing_rotation)
	_preview_material.albedo_color = valid_color if can_place else invalid_color
	placement_changed.emit(true, can_place)


func _end_placement() -> void:
	_placing_type = null
	if _preview:
		_preview.queue_free()
		_preview = null
	_update_highlight()
	placement_changed.emit(false, false)


# Returns the grid cell under a screen position, or null if it's off the map.
func _cell_at_screen_position(screen_position: Vector2) -> Variant:
	# Shoot a ray from the camera through the tapped pixel and see where it hits the ground.
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
	if hit == null:
		return null
	var cell := Airport.grid.world_to_cell(hit as Vector3)
	return cell if Airport.grid.is_inside(cell) else null


func _update_highlight() -> void:
	if is_node_ready():
		_highlight.visible = active and has_selection and not is_placing()


func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
