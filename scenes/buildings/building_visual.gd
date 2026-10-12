class_name BuildingVisual
extends Node3D
## Placeholder 3D look of one building: a box, plus a dark strip on the roof along the front side
## so the rotation is visible from both cameras. Used for placed buildings and for the preview.

## Depth of the front strip in meters.
const FRONT_STRIP_DEPTH: float = 0.5
const FRONT_STRIP_THICKNESS: float = 0.05


## Builds the meshes. Call once, right after creating the node.
func setup(type: BuildingType, cell_size: float, body_material: Material, front_material: Material,
		cast_shadows: bool = true) -> void:
	var size := Vector3(type.footprint.x * cell_size, type.height, type.footprint.y * cell_size)

	var body_mesh := BoxMesh.new()
	body_mesh.size = size
	body_mesh.material = body_material
	_add_mesh(body_mesh, Vector3(0.0, size.y * 0.5, 0.0), cast_shadows)

	# The front is the -Z side of the unrotated building (design doc §7.1a).
	var front_mesh := BoxMesh.new()
	front_mesh.size = Vector3(size.x, FRONT_STRIP_THICKNESS, FRONT_STRIP_DEPTH)
	front_mesh.material = front_material
	_add_mesh(front_mesh, Vector3(0.0, size.y, -size.z * 0.5 + FRONT_STRIP_DEPTH * 0.5), false)


## Moves and rotates the visual to match a footprint on the grid.
func place_on_grid(grid: AirportGrid, footprint: Vector2i, origin_cell: Vector2i, rotation_steps: int) -> void:
	position = grid.block_center(origin_cell, Building.rotated_size(footprint, rotation_steps))
	# Godot rotates counter-clockwise (seen from above) for positive angles; our steps are clockwise.
	rotation.y = -rotation_steps * PI * 0.5


## Makes the building solid, so the manager can't walk through it.
func add_collision(type: BuildingType, cell_size: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(type.footprint.x * cell_size, type.height, type.footprint.y * cell_size)
	shape.shape = box
	shape.position.y = type.height * 0.5
	body.add_child(shape)
	add_child(body)


func _add_mesh(mesh: Mesh, offset: Vector3, cast_shadows: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	if not cast_shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
