class_name BuildMode
extends Node3D
## Build view logic: turns taps on the screen into grid cells. For now, tapping a cell highlights it.
## Placing and rotating buildings will live here later.

signal cell_selected(cell: Vector2i)

## The camera used to find which cell was tapped.
@export var camera: BuildCamera

## Only reacts to taps while the build view is open. The highlight is hidden otherwise.
var active: bool = false:
	set(value):
		active = value
		if is_node_ready():
			_highlight.visible = active and has_selection

var has_selection: bool = false
var selected_cell: Vector2i = Vector2i.ZERO

@onready var _highlight: MeshInstance3D = $CellHighlight


func _ready() -> void:
	(_highlight.mesh as PlaneMesh).size = Vector2.ONE * Airport.grid.cell_size
	_highlight.visible = false
	TouchGestures.tapped.connect(_on_tapped)


func select_cell(cell: Vector2i) -> void:
	has_selection = true
	selected_cell = cell
	# Slightly above the ground so it doesn't flicker against the ground surface.
	_highlight.position = Airport.grid.cell_to_world(cell) + Vector3(0.0, 0.02, 0.0)
	_highlight.visible = active
	cell_selected.emit(cell)


func _on_tapped(screen_position: Vector2) -> void:
	if not active or not camera:
		return
	# Shoot a ray from the camera through the tapped pixel and see where it hits the ground.
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
	if hit == null:
		return
	var cell := Airport.grid.world_to_cell(hit as Vector3)
	if Airport.grid.is_inside(cell):
		select_cell(cell)
