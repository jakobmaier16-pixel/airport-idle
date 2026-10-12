class_name BuildingLayer
extends Node3D
## Visual layer for buildings: creates a 3D placeholder for every building in the simulation,
## plus a floating hint above buildings that aren't connected yet (design doc §7.1b) or are
## being upgraded (§7.8).
## It only reads simulation data and never changes it.

const FRONT_COLOR: Color = Color(0.15, 0.17, 0.2)
const HINT_COLOR: Color = Color(1.0, 0.45, 0.4)
const UPGRADE_COLOR: Color = Color(1.0, 0.75, 0.25)
## Metadata key on collision bodies: the Building they belong to (used to find tapped buildings).
const BUILDING_META: StringName = &"building"
## How far above the roof the "not connected" hint floats, in meters.
const HINT_HEIGHT: float = 1.5

# One material per building type, shared by all buildings of that type (fewer draw-state changes).
var _materials: Dictionary[BuildingType, StandardMaterial3D] = {}
var _front_material: StandardMaterial3D
var _hints: Dictionary[Building, Label3D] = {}
# Connection problem per building, recalculated when the layout changes.
var _problems: Dictionary[Building, String] = {}


func _ready() -> void:
	_front_material = StandardMaterial3D.new()
	_front_material.albedo_color = FRONT_COLOR
	for building in Airport.buildings:
		_add_visual(building)
	Airport.building_placed.connect(_add_visual)
	Airport.layout_changed.connect(_update_hints)
	_update_hints()


func _add_visual(building: Building) -> void:
	var cell_size := Airport.grid.cell_size
	var visual := BuildingVisual.new()
	visual.setup(building.type, cell_size, _material_for(building.type), _front_material)
	visual.place_on_grid(Airport.grid, building.type.footprint, building.origin_cell, building.rotation_steps)
	if building.type.is_solid:
		visual.add_collision(building.type, cell_size).set_meta(BUILDING_META, building)
	add_child(visual)

	var hint := Label3D.new()
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Always readable, even behind other buildings.
	hint.no_depth_test = true
	hint.font_size = 48
	hint.pixel_size = 0.03
	hint.outline_size = 12
	hint.modulate = HINT_COLOR
	hint.position.y = building.type.height + HINT_HEIGHT
	hint.visible = false
	visual.add_child(hint)
	_hints[building] = hint


func _process(_delta: float) -> void:
	# Upgrade countdowns change every frame; connection problems only when the layout changes.
	for building in _hints:
		var hint := _hints[building]
		var problem: String = _problems.get(building, "")
		if not problem.is_empty():
			hint.text = problem
			hint.modulate = HINT_COLOR
		elif Airport.needs_staff(building) and Airport.staff_at(building).is_empty():
			hint.text = "Needs staff"
			hint.modulate = HINT_COLOR
		elif building.is_upgrading():
			var seconds := ceili(building.upgrade_seconds_left)
			hint.text = "Upgrading… %d:%02d" % [seconds / 60, seconds % 60]
			hint.modulate = UPGRADE_COLOR
		hint.visible = not problem.is_empty() or building.is_upgrading() \
			or (Airport.needs_staff(building) and Airport.staff_at(building).is_empty())


func _update_hints() -> void:
	for building in _hints:
		_problems[building] = Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps)


func _material_for(type: BuildingType) -> StandardMaterial3D:
	if not _materials.has(type):
		var material := StandardMaterial3D.new()
		material.albedo_color = type.color
		_materials[type] = material
	return _materials[type]
