class_name Ground
extends StaticBody3D
## The flat ground of the map. Sizes itself to the airport grid, so the visuals always match
## the simulation data, whatever the cell size or map size.

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	var grid := Airport.grid
	var rect := grid.get_world_rect()
	position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)

	var plane := _mesh_instance.mesh as PlaneMesh
	plane.size = rect.size
	var box := _collision_shape.shape as BoxShape3D
	box.size = Vector3(rect.size.x, 1.0, rect.size.y)

	var material := plane.material as ShaderMaterial
	material.set_shader_parameter(&"cell_size", grid.cell_size)
	material.set_shader_parameter(&"grid_origin", Vector2(grid.origin.x, grid.origin.z))
