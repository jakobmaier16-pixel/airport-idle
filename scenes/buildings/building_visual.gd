class_name BuildingVisual
extends Node3D
## Placeholder 3D look of one building: a box, plus a dark strip on the roof along the front side
## so the rotation is visible from both cameras, and a few low-poly details per kind of building
## (jet bridges, stand markings, parked cars). Used for placed buildings and for the preview.

## Depth of the front strip in meters.
const FRONT_STRIP_DEPTH: float = 0.5
const FRONT_STRIP_THICKNESS: float = 0.05
const BRIDGE_COLOR: Color = Color(0.78, 0.8, 0.84)
const MARKING_COLOR: Color = Color(1.0, 0.82, 0.15)
const CAR_COLORS: Array[Color] = [Color(0.8, 0.15, 0.15), Color(0.15, 0.3, 0.7), Color(0.9, 0.9, 0.92),
	Color(0.15, 0.15, 0.17), Color(0.55, 0.57, 0.6), Color(0.2, 0.5, 0.3)]

# Shared by every building, so details don't multiply materials.
static var _bridge_material: StandardMaterial3D
static var _marking_material: StandardMaterial3D
static var _car_material: StandardMaterial3D


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
	_add_details(type, size, cast_shadows)


func _add_details(type: BuildingType, size: Vector3, cast_shadows: bool) -> void:
	if _bridge_material == null:
		_bridge_material = _flat_material(BRIDGE_COLOR)
		_marking_material = _flat_material(MARKING_COLOR)
		_car_material = StandardMaterial3D.new()
		_car_material.vertex_color_use_as_albedo = true
	match type.role:
		BuildingType.Role.GATE:
			# A jet bridge from the back wall out over the stand, beside the plane's nose (to its
			# front door). The back is the +Z side of the unrotated building.
			var bridge := BoxMesh.new()
			bridge.size = Vector3(2.0, 2.2, 4.0)
			bridge.material = _bridge_material
			_add_mesh(bridge, Vector3(3.0, 3.3, size.z * 0.5 + 2.0), cast_shadows)
			var leg := BoxMesh.new()
			leg.size = Vector3(0.4, 2.2, 0.4)
			leg.material = _bridge_material
			_add_mesh(leg, Vector3(3.0, 1.1, size.z * 0.5 + 3.4), cast_shadows)
		BuildingType.Role.AIRCRAFT_STAND:
			# Yellow lead-in line from the gate side to the middle, and a stop bar for the nose.
			var line := BoxMesh.new()
			line.size = Vector3(0.25, 0.02, size.z * 0.75)
			line.material = _marking_material
			_add_mesh(line, Vector3(0.0, size.y + 0.01, -size.z * 0.125), false)
			var stop_bar := BoxMesh.new()
			stop_bar.size = Vector3(3.0, 0.02, 0.3)
			stop_bar.material = _marking_material
			_add_mesh(stop_bar, Vector3(0.0, size.y + 0.01, -size.z * 0.5 + 1.2), false)
		BuildingType.Role.CAR_PARK:
			_add_cars(size)


# Rows of parked cars on the deck: one MultiMesh, so a full car park is a single draw call.
func _add_cars(size: Vector3) -> void:
	var car := BoxMesh.new()
	car.size = Vector3(1.8, 1.3, 4.0)
	car.material = _car_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = car
	var columns := int(size.x / 2.6)
	var rows := int(size.z / 5.5)
	multimesh.instance_count = columns * rows
	var index := 0
	for row in rows:
		for column in columns:
			var spot := Vector3((column + 0.5) * size.x / columns - size.x * 0.5, size.y + 0.65,
				(row + 0.5) * size.z / rows - size.z * 0.5)
			multimesh.set_instance_transform(index, Transform3D(Basis(), spot))
			# Not every spot is taken; a fixed pattern keeps it stable between frames.
			var taken := (column * 7 + row * 3) % 5 != 0
			var color := CAR_COLORS[(column * 5 + row * 2) % CAR_COLORS.size()] if taken else Color(0, 0, 0, 0)
			multimesh.set_instance_color(index, color)
			if not taken:
				multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), spot))
			index += 1
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


## Moves and rotates the visual to match a footprint on the grid.
func place_on_grid(grid: AirportGrid, footprint: Vector2i, origin_cell: Vector2i, rotation_steps: int) -> void:
	position = grid.block_center(origin_cell, Building.rotated_size(footprint, rotation_steps))
	# Godot rotates counter-clockwise (seen from above) for positive angles; our steps are clockwise.
	rotation.y = -rotation_steps * PI * 0.5


## Makes the building solid, so the manager can't walk through it. Returns the physics body.
func add_collision(type: BuildingType, cell_size: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(type.footprint.x * cell_size, type.height, type.footprint.y * cell_size)
	shape.shape = box
	shape.position.y = type.height * 0.5
	body.add_child(shape)
	add_child(body)
	return body


func _add_mesh(mesh: Mesh, offset: Vector3, cast_shadows: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	if not cast_shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
