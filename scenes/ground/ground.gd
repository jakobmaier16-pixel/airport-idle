class_name Ground
extends StaticBody3D
## The flat ground of the map. Sizes itself to the airport grid and shows zones and walkway floor,
## so the visuals always match the simulation data.

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _material: ShaderMaterial
# One pixel per cell (red = airside, green = walkway); the shader reads it to color the ground.
var _zone_image: Image
var _zone_texture: ImageTexture


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

	_zone_image = Image.create(grid.size.x, grid.size.y, false, Image.FORMAT_RG8)
	_zone_texture = ImageTexture.create_from_image(_zone_image)
	_material.set_shader_parameter(&"zone_map", _zone_texture)
	_update_cells()
	Airport.zones_changed.connect(_update_cells)
	Airport.walkways_changed.connect(_update_cells)


func _update_cells() -> void:
	var zones := Airport.grid.get_zone_data()
	var walkways := Airport.grid.get_walkway_data()
	# Two bytes per pixel (red, green). Values are 0 / 1; the texture needs 0 / 255 for "fully on".
	var data := PackedByteArray()
	data.resize(zones.size() * 2)
	for i in zones.size():
		data[i * 2] = zones[i] * 255
		data[i * 2 + 1] = walkways[i] * 255
	_zone_image.set_data(_zone_image.get_width(), _zone_image.get_height(), false, Image.FORMAT_RG8, data)
	_zone_texture.update(_zone_image)
