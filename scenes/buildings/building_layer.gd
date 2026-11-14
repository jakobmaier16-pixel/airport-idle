class_name BuildingLayer
extends Node3D
## Visual layer for buildings: creates a 3D placeholder for every building in the simulation,
## plus a floating hint above buildings that aren't connected yet (design doc §7.1b) or are
## being upgraded (§7.8).
## It only reads simulation data and never changes it.

const FRONT_COLOR: Color = Color(0.15, 0.17, 0.2)
const HINT_COLOR: Color = Color(1.0, 0.45, 0.4)
const UPGRADE_COLOR: Color = Color(1.0, 0.75, 0.25)
const MANAGER_COLOR: Color = Color(0.5, 1.0, 0.55)
## Metadata key on collision bodies: the Building they belong to (used to find tapped buildings).
const BUILDING_META: StringName = &"building"
## Hint size on screen (Label3D.pixel_size with fixed_size: share of the screen height per font pixel).
const HINT_PIXEL_SIZE: float = 0.0008
## How far above the roof the "not connected" hint floats, in meters.
const HINT_HEIGHT: float = 1.5

# One material per building type, shared by all buildings of that type (fewer draw-state changes).
var _materials: Dictionary[BuildingType, StandardMaterial3D] = {}
var _front_material: StandardMaterial3D
## Draws the landside pieces (roads, sidewalks, props, ...); set in the main scene.
@export var landside: LandsideLayer
var _hints: Dictionary[Building, Label3D] = {}
var _visuals: Dictionary[Building, BuildingVisual] = {}
# Connection problem per building, recalculated when the layout changes.
var _problems: Dictionary[Building, String] = {}


func _ready() -> void:
	_front_material = StandardMaterial3D.new()
	_front_material.albedo_color = FRONT_COLOR
	for building in Airport.buildings:
		_add_visual(building)
	Airport.building_placed.connect(_add_visual)
	Airport.building_removed.connect(_remove_visual)
	Airport.layout_changed.connect(_update_hints)
	_update_hints()


func _add_visual(building: Building) -> void:
	var cell_size := Airport.grid.cell_size
	if building.type.model != null:
		_add_piece(building)
		return
	var visual := BuildingVisual.new()
	visual.setup(building.type, cell_size, _material_for(building.type), _front_material,
			true, Building.ground_surface_of(building.type) == 0)
	visual.place_on_grid(Airport.grid, building.type.footprint, building.origin_cell, building.rotation_steps)
	if building.type.is_solid:
		visual.add_collision(building.type, cell_size).set_meta(BUILDING_META, building)
	add_child(visual)
	_visuals[building] = visual

	var hint := Label3D.new()
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Always readable, even behind other buildings.
	hint.no_depth_test = true
	# The same size on screen however close the camera is: in the manager view the camera can be
	# right next to a building, and a world-sized label would cover the screen.
	hint.fixed_size = true
	hint.font_size = 48
	hint.pixel_size = HINT_PIXEL_SIZE
	hint.outline_size = 12
	hint.modulate = HINT_COLOR
	hint.position.y = building.type.height + HINT_HEIGHT
	hint.visible = false
	visual.add_child(hint)
	_hints[building] = hint


# A landside piece is drawn by the LandsideLayer. Only solid ones (fence, hedge, tree, shelter) get
# an empty node with the collision box, so the manager cannot walk through them.
func _add_piece(building: Building) -> void:
	landside.add_building(building)
	if building.type.is_solid:
		var holder := BuildingVisual.new()
		holder.place_on_grid(Airport.grid, building.type.footprint, building.origin_cell, building.rotation_steps)
		holder.add_collision(building.type, Airport.grid.cell_size).set_meta(BUILDING_META, building)
		add_child(holder)
		_visuals[building] = holder


func _remove_visual(building: Building) -> void:
	if building.type.model != null:
		landside.remove_building(building)
	if _visuals.has(building):
		_visuals[building].queue_free()
		_visuals.erase(building)
	_hints.erase(building)
	_problems.erase(building)


## How many buildings are drawn (used by tests).
func visual_count() -> int:
	return _visuals.size()


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
		elif Airport.needs_staff(building) and Airport.is_manager_near(building):
			# The manager's presence helps (design doc §15.1). Shown on the facade, not above the
			# roof: the manager stands right in front, so a roof label would sit under the HUD.
			hint.text = "Manager here · +10 %"
			hint.modulate = MANAGER_COLOR
			hint.position.y = building.type.height * 0.5
		if hint.text != "Manager here · +10 %":
			hint.position.y = building.type.height + HINT_HEIGHT
		hint.visible = not problem.is_empty() or building.is_upgrading() \
			or (Airport.needs_staff(building) and (Airport.staff_at(building).is_empty() or Airport.is_manager_near(building)))


func _update_hints() -> void:
	for building in _hints:
		_problems[building] = Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps)


func _material_for(type: BuildingType) -> StandardMaterial3D:
	if not _materials.has(type):
		var material := StandardMaterial3D.new()
		material.albedo_color = type.color
		_materials[type] = material
	return _materials[type]
