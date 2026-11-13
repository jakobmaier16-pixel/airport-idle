class_name Ground
extends StaticBody3D
## The flat ground of the map: one mesh, one draw call. Sizes itself to the airport grid; the shader
## reads the grid's flag layer from an R8 texture (GroundFlagTexture), so the visuals always match
## the simulation data. Unowned land is shaded from `Progression.owned_land` (a rectangle uniform;
## the grid's owned bit stays unused so its chunks stay sparse).

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _material: ShaderMaterial
# The whole flag layer as one R8 texture (1 texel per cell); the shader decodes the bits.
var _flags: GroundFlagTexture
var _flags_grid: AirportGrid


func _ready() -> void:
	var grid := Airport.grid
	var rect := grid.get_world_rect()
	position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)

	var plane := _mesh_instance.mesh as PlaneMesh
	plane.size = rect.size
	var box := _collision_shape.shape as BoxShape3D
	box.size = Vector3(rect.size.x, 1.0, rect.size.y)

	_material = plane.material as ShaderMaterial
	_material.set_shader_parameter(&"cell_size", grid.cell_size)
	_material.set_shader_parameter(&"grid_origin", Vector2(grid.origin.x, grid.origin.z))
	_material.set_shader_parameter(&"map_size", rect.size)

	_update_cells()
	_update_land()
	Airport.land_changed.connect(_update_land)
	Airport.zones_changed.connect(_update_cells)
	Airport.walkways_changed.connect(_update_cells)


## The flag texture (for tests).
func get_flag_texture() -> GroundFlagTexture:
	return _flags


# Shades land the airport doesn't own yet (design doc §14.1).
func _update_land() -> void:
	var grid := Airport.grid
	var land := Airport.progression.owned_land(grid.size)
	var corner := Vector2(grid.origin.x, grid.origin.z)
	var from := corner + Vector2(land.position) * grid.cell_size
	var to := corner + Vector2(land.end) * grid.cell_size
	_material.set_shader_parameter(&"owned_rect", Vector4(from.x, from.y, to.x, to.y))


# Brings the flag texture up to date: only chunks that changed since the last call are copied.
func _update_cells() -> void:
	var grid := Airport.grid
	if _flags == null or grid != _flags_grid:
		# First build, or a new grid (a loaded game): copy every allocated chunk once.
		_flags_grid = grid
		_flags = GroundFlagTexture.new(grid)
		_material.set_shader_parameter(&"flag_map", _flags.texture)
		return
	_flags.refresh()
