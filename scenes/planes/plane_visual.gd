class_name PlaneVisual
extends Node3D
## Placeholder low-poly narrow-body plane built from simple shapes, scaled down like the airside
## (design doc §7.1, §8.5). The nose points to -Z. Replace with a Blender model later.
## It is solid: a moving physics body (AnimatableBody3D) keeps the manager from walking through it.

const LENGTH: float = 21.0
const FUSELAGE_RADIUS: float = 1.4
const WINGSPAN: float = 21.0
const BODY_COLOR: Color = Color(0.95, 0.96, 0.97)
## Freighters are grey (design doc §10.3).
const CARGO_BODY_COLOR: Color = Color(0.68, 0.7, 0.72)
## Tail color without an airline; with one, the airline's color (design doc §10.1).
const TAIL_COLOR: Color = Color(0.1, 0.45, 0.65)
const ENGINE_COLOR: Color = Color(0.55, 0.57, 0.6)
## Wide-body planes are this much bigger in every direction (fits a 16 × 16 cell stand).
const WIDE_BODY_SIZE: float = 1.4

## Set before the plane enters the tree.
var tail_color: Color = TAIL_COLOR
## A freighter: grey body. Set before the plane enters the tree.
var cargo: bool = false
## 1 for narrow-body planes; WIDE_BODY_SIZE for long-haul (design doc §10.2).
var size_factor: float = 1.0

var _body: AnimatableBody3D

# Shared by every plane, so many planes don't mean many materials.
static var _body_material: StandardMaterial3D
static var _cargo_body_material: StandardMaterial3D
# One tail material per airline color.
static var _tail_materials: Dictionary[Color, StandardMaterial3D] = {}
static var _engine_material: StandardMaterial3D


func _ready() -> void:
	if _body_material == null:
		_body_material = _material(BODY_COLOR)
		_cargo_body_material = _material(CARGO_BODY_COLOR)
		_engine_material = _material(ENGINE_COLOR)
	var body_material := _cargo_body_material if cargo else _body_material
	if not _tail_materials.has(tail_color):
		_tail_materials[tail_color] = _material(tail_color)
	# Every size is multiplied by k, so a wide-body plane is the same model, just bigger. (Scaling
	# the node instead would scale the collision shapes too, which physics engines handle badly.)
	var k := size_factor
	var length := LENGTH * k
	var radius := FUSELAGE_RADIUS * k
	var body_height := radius + 1.0 * k
	_body = AnimatableBody3D.new()
	# The plane is moved from _process (PlaneLayer), not by the physics engine.
	_body.sync_to_physics = false
	add_child(_body)

	# Fuselage: a capsule lying along the Z axis.
	var fuselage := CapsuleMesh.new()
	fuselage.radius = radius
	fuselage.height = length
	fuselage.radial_segments = 12
	fuselage.rings = 2
	_add(fuselage, body_material, Vector3(0.0, body_height, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
	var fuselage_shape := CapsuleShape3D.new()
	fuselage_shape.radius = radius
	fuselage_shape.height = length
	_add_collision(fuselage_shape, Vector3(0.0, body_height, 0.0), Vector3(PI * 0.5, 0.0, 0.0))

	var wings := BoxMesh.new()
	wings.size = Vector3(WINGSPAN, 0.3, 3.2) * k
	_add(wings, body_material, Vector3(0.0, body_height - 0.6 * k, 0.5 * k), Vector3.ZERO)
	# One box covers the wings and the engines below them, from the ground up.
	var wing_shape := BoxShape3D.new()
	wing_shape.size = Vector3(WINGSPAN * k, body_height - 0.45 * k, 3.2 * k)
	_add_collision(wing_shape, Vector3(0.0, (body_height - 0.45 * k) * 0.5, 0.5 * k), Vector3.ZERO)

	# Wide-body planes have four engines.
	var engine_offsets: Array[float] = [-3.8, 3.8]
	if k > 1.0:
		engine_offsets = [-6.0, -3.6, 3.6, 6.0]
	for side in engine_offsets:
		var engine := CylinderMesh.new()
		engine.top_radius = 0.6 * k
		engine.bottom_radius = 0.6 * k
		engine.height = 2.4 * k
		engine.radial_segments = 10
		_add(engine, _engine_material, Vector3(side * k, body_height - 1.3 * k, -0.4 * k), Vector3(PI * 0.5, 0.0, 0.0))

	var fin := BoxMesh.new()
	fin.size = Vector3(0.3, 3.0, 2.6) * k
	_add(fin, _tail_materials[tail_color], Vector3(0.0, body_height + 2.2 * k, length * 0.5 - 1.6 * k), Vector3.ZERO)

	var stabilizer := BoxMesh.new()
	stabilizer.size = Vector3(7.0, 0.25, 1.8) * k
	_add(stabilizer, body_material, Vector3(0.0, body_height + 0.4 * k, length * 0.5 - 1.4 * k), Vector3.ZERO)
	var tail_shape := BoxShape3D.new()
	tail_shape.size = Vector3(7.0 * k, body_height + 0.5 * k, 1.8 * k)
	_add_collision(tail_shape, Vector3(0.0, (body_height + 0.5 * k) * 0.5, length * 0.5 - 1.4 * k), Vector3.ZERO)


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
