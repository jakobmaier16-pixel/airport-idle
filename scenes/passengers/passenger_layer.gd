class_name PassengerLayer
extends Node3D
## Draws passengers near the camera as simple low-poly figures, all in one batch (MultiMesh:
## one draw call for every figure). Passengers away from the camera exist only as simulation data
## (performance rule in CLAUDE.md). Movement is smoothed between simulation steps.

## Most figures drawn at once.
const MAX_VISIBLE: int = 400
const FIGURE_HEIGHT: float = 1.65
const FIGURE_RADIUS: float = 0.22
## Used for passengers without a type.
const DEFAULT_COLOR: Color = Color(0.8, 0.8, 0.8)

## Manager view: figures are drawn within this distance (meters) of the point the camera looks at.
@export var manager_view_radius: float = 45.0

var _multimesh: MultiMesh


func _ready() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = FIGURE_RADIUS
	mesh.height = FIGURE_HEIGHT
	# Low-poly: few segments are plenty at this size and keep the vertex count small.
	mesh.radial_segments = 8
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh.material = material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = mesh
	_multimesh.instance_count = MAX_VISIBLE
	_multimesh.visible_instance_count = 0

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	# Hundreds of small shadows cost a lot on older iPhones and add little.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Positions are rewritten every frame and already smoothed with Airport.sim_alpha, so Godot's
	# physics interpolation must stay out (it would blend unrelated figures into stretched shapes).
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var area := _visible_area(camera)
	var center := Vector2(area.x, area.y)
	var radius_squared := area.z * area.z
	var alpha := Airport.sim_alpha
	var lift := Vector3(0.0, FIGURE_HEIGHT * 0.5, 0.0)

	var count := 0
	for passenger in Airport.passenger_flow.passengers:
		if passenger.state == Passenger.State.AT_GATE or passenger.state == Passenger.State.IN_SHOP:
			continue  # inside a building
		var figure_position := passenger.previous_position.lerp(passenger.position, alpha)
		if Vector2(figure_position.x, figure_position.z).distance_squared_to(center) > radius_squared:
			continue
		_multimesh.set_instance_transform(count, Transform3D(Basis.IDENTITY, figure_position + lift))
		_multimesh.set_instance_color(count, color_of(passenger))
		count += 1
		if count == MAX_VISIBLE:
			break
	_multimesh.visible_instance_count = count


## Figure color: one of the passenger type's colors (design doc §8.7).
static func color_of(passenger: Passenger) -> Color:
	if passenger.type == null or passenger.type.colors.is_empty():
		return DEFAULT_COLOR
	return passenger.type.colors[passenger.color_index % passenger.type.colors.size()]


# Ground area worth drawing: (center x, center z, radius) around what the camera shows.
func _visible_area(camera: Camera3D) -> Vector3:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Top-down build view: the screen shows `size` meters vertically.
		var viewport_size := get_viewport().get_visible_rect().size
		var half_diagonal := Vector2(camera.size * viewport_size.x / viewport_size.y, camera.size).length() * 0.5
		return Vector3(camera.global_position.x, camera.global_position.z, half_diagonal + 2.0)
	# Manager view: around the point in the middle of the screen.
	var forward := -camera.global_basis.z
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.global_position, forward)
	var focus: Vector3 = hit if hit != null else camera.global_position
	return Vector3(focus.x, focus.z, manager_view_radius)
