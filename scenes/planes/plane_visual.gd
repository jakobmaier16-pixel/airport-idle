class_name PlaneVisual
extends Node3D
## Placeholder low-poly narrow-body plane built from simple shapes, scaled down like the airside
## (design doc §7.1, §8.5). The nose points to -Z. Replace with a Blender model later.
## It is solid: a moving physics body (AnimatableBody3D) keeps the manager from walking through it.

const LENGTH: float = 21.0
const FUSELAGE_RADIUS: float = 1.4
const WINGSPAN: float = 21.0
## Fictional airline colors (design doc §18).
const BODY_COLOR: Color = Color(0.95, 0.96, 0.97)
const TAIL_COLOR: Color = Color(0.1, 0.45, 0.65)
const ENGINE_COLOR: Color = Color(0.55, 0.57, 0.6)

var _body: AnimatableBody3D

# Shared by every plane, so many planes don't mean many materials.
static var _body_material: StandardMaterial3D
static var _tail_material: StandardMaterial3D
static var _engine_material: StandardMaterial3D


func _ready() -> void:
	if _body_material == null:
		_body_material = _material(BODY_COLOR)
		_tail_material = _material(TAIL_COLOR)
		_engine_material = _material(ENGINE_COLOR)
	var body_height := FUSELAGE_RADIUS + 1.0
	_body = AnimatableBody3D.new()
	# The plane is moved from _process (PlaneLayer), not by the physics engine.
	_body.sync_to_physics = false
	add_child(_body)

	# Fuselage: a capsule lying along the Z axis.
	var fuselage := CapsuleMesh.new()
	fuselage.radius = FUSELAGE_RADIUS
	fuselage.height = LENGTH
	fuselage.radial_segments = 12
	fuselage.rings = 2
	_add(fuselage, _body_material, Vector3(0.0, body_height, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
	var fuselage_shape := CapsuleShape3D.new()
	fuselage_shape.radius = FUSELAGE_RADIUS
	fuselage_shape.height = LENGTH
	_add_collision(fuselage_shape, Vector3(0.0, body_height, 0.0), Vector3(PI * 0.5, 0.0, 0.0))

	var wings := BoxMesh.new()
	wings.size = Vector3(WINGSPAN, 0.3, 3.2)
	_add(wings, _body_material, Vector3(0.0, body_height - 0.6, 0.5), Vector3.ZERO)
	# One box covers the wings and the engines below them, from the ground up.
	var wing_shape := BoxShape3D.new()
	wing_shape.size = Vector3(WINGSPAN, body_height - 0.45, 3.2)
	_add_collision(wing_shape, Vector3(0.0, (body_height - 0.45) * 0.5, 0.5), Vector3.ZERO)

	for side in [-1.0, 1.0]:
		var engine := CylinderMesh.new()
		engine.top_radius = 0.6
		engine.bottom_radius = 0.6
		engine.height = 2.4
		engine.radial_segments = 10
		_add(engine, _engine_material, Vector3(side * 3.8, body_height - 1.3, -0.4), Vector3(PI * 0.5, 0.0, 0.0))

	var fin := BoxMesh.new()
	fin.size = Vector3(0.3, 3.0, 2.6)
	_add(fin, _tail_material, Vector3(0.0, body_height + 2.2, LENGTH * 0.5 - 1.6), Vector3.ZERO)

	var stabilizer := BoxMesh.new()
	stabilizer.size = Vector3(7.0, 0.25, 1.8)
	_add(stabilizer, _body_material, Vector3(0.0, body_height + 0.4, LENGTH * 0.5 - 1.4), Vector3.ZERO)
	var tail_shape := BoxShape3D.new()
	tail_shape.size = Vector3(7.0, body_height + 0.5, 1.8)
	_add_collision(tail_shape, Vector3(0.0, (body_height + 0.5) * 0.5, LENGTH * 0.5 - 1.4), Vector3.ZERO)


func _add(mesh: Mesh, material: Material, offset: Vector3, rotation_radians: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.rotation = rotation_radians
	add_child(instance)


func _add_collision(shape: Shape3D, offset: Vector3, rotation_radians: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = offset
	collision.rotation = rotation_radians
	_body.add_child(collision)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
