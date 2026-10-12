class_name BuildingLayer
extends Node3D
## Visual layer for buildings: creates a 3D placeholder for every building in the simulation.
## It only reads simulation data and never changes it.

const FRONT_COLOR: Color = Color(0.15, 0.17, 0.2)

# One material per building type, shared by all buildings of that type (fewer draw-state changes).
var _materials: Dictionary[BuildingType, StandardMaterial3D] = {}
var _front_material: StandardMaterial3D


func _ready() -> void:
	_front_material = StandardMaterial3D.new()
	_front_material.albedo_color = FRONT_COLOR
	for building in Airport.buildings:
		_add_visual(building)
	Airport.building_placed.connect(_add_visual)


func _add_visual(building: Building) -> void:
	var cell_size := Airport.grid.cell_size
	var visual := BuildingVisual.new()
	visual.setup(building.type, cell_size, _material_for(building.type), _front_material)
	visual.place_on_grid(Airport.grid, building.type.footprint, building.origin_cell, building.rotation_steps)
	visual.add_collision(building.type, cell_size)
	add_child(visual)


func _material_for(type: BuildingType) -> StandardMaterial3D:
	if not _materials.has(type):
		var material := StandardMaterial3D.new()
		material.albedo_color = type.color
		_materials[type] = material
	return _materials[type]
