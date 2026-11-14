class_name LandsideLayer
extends Node3D
## Draws the landside pieces (roads, curb, sidewalks, car park, props, trees) from their .glb models.
## Every piece is a MultiMesh instance, grouped by piece, part and map chunk, so a whole car park or a
## row of 90 fence panels costs a handful of draw calls. It only reads simulation data.
##
## A model holds `<piece>` (full detail), `<piece>_markings` (flat paint) and `<piece>_lodfar`
## (simple stand-in). The full detail is on render layer 3 (NEAR_LAYER) and the stand-in on layer 4
## (FAR_LAYER); the manager camera does not draw layer 4 and the build camera does not draw layer 3.
## Distance alone cannot tell the views apart: the build camera is orthographic, 40 m above the
## ground, however far it is zoomed out. In the manager view visibility ranges still apply: the full
## detail ends at LOD_FAR_M, where a second copy of the stand-in takes over, so roads do not stop in mid-air.
## - Paint never casts shadows; flat pieces (roads, sidewalks) don't either: nothing stands above them.
## - Fences fade out at about 60 m and have an alpha scissor + alpha-to-coverage mesh (no shimmering).
## - Pieces without a stand-in (bollards, masts, signs) are on the NEAR layer only: hidden in the build view.
## - Wear decals (oil, tyre marks, patches, grates) are scattered on a few pieces from the building's id.

## In the manager view the stand-in replaces the full model beyond this distance (metres).
const LOD_FAR_M: float = 120.0
## Render layers (1-based, as in Camera3D.set_cull_mask_value): full detail / stand-ins.
const NEAR_LAYER: int = 3
const FAR_LAYER: int = 4
## Fences fade out here (manager view); `FENCE_FADE_MARGIN_M` is the fade length.
const FENCE_END_M: float = 60.0
const FENCE_FADE_MARGIN_M: float = 10.0
## Pieces without a stand-in are drawn up to here (manager view only).
const SMALL_PROP_END_M: float = 80.0
## MultiMeshes are split by map area, so a visibility range works per area and not for the whole map.
const CHUNK_CELLS: int = 24
## Parts lower than this (metres) cast no shadow.
const FLAT_HEIGHT_M: float = 0.3
## Shared materials, by the name the model gives them (assets/materials/<name>.tres).
const MATERIAL_DIR: String = "res://assets/materials/"
const TREE_ID: StringName = &"tree_deciduous"

enum Kind { MAIN, MARKINGS, FAR }
## Metadata key on every MultiMesh node: the Kind of mesh it draws (used by tests).
const KIND_META: StringName = &"part_kind"

## One mesh of a model.
class Part extends RefCounted:
	var mesh: Mesh
	var kind: Kind
	var local: Transform3D
	var flat: bool

## The meshes of a model, loaded once per model.
static var _parts: Dictionary[PackedScene, Array] = {}
static var _materials: Dictionary[String, Material] = {}

# group key -> Group. A group is the MultiMesh of one mesh in one chunk.
var _groups: Dictionary[String, Group] = {}
var _dirty: Dictionary[String, bool] = {}
# The groups each building is in, to take it out again.
var _of_building: Dictionary[Building, Array] = {}

## One MultiMesh node: the transforms of every building (and decal) that uses this mesh in this chunk.
class Group extends RefCounted:
	var node: MultiMeshInstance3D
	var mesh: Mesh
	var use_colors: bool
	var transforms: Dictionary[Building, Array] = {}
	var colors: Dictionary[Building, Color] = {}


func _process(_delta: float) -> void:
	flush()


## Rebuilds the MultiMeshes of the groups that changed. Runs every frame; tests call it directly.
func flush() -> void:
	for key in _dirty:
		_rebuild(_groups[key], key)
	_dirty.clear()


## Draws `building` (a landside piece with a model).
func add_building(building: Building) -> void:
	if building.type.model == null or _of_building.has(building):
		return
	var keys: Array[String] = []
	var chunk := _chunk_of(building)
	var base := _transform_of(building)
	_add_model(building, building.type.model, building.type.id, chunk, base, keys)
	if building.type.paved_base:
		var tile := Airport.CATALOG.find(&"sidewalk_tile")
		for cell in building.get_cells():
			var at := Transform3D(Basis(), Airport.grid.cell_to_world(cell))
			_add_model(building, tile.model, &"paved_base", chunk, at, keys)
	_add_decals(building, chunk, base, keys)
	_of_building[building] = keys


## Stops drawing `building`.
func remove_building(building: Building) -> void:
	for key: String in _of_building.get(building, []):
		var group := _groups[key]
		group.transforms.erase(building)
		group.colors.erase(building)
		_dirty[key] = true
	_of_building.erase(building)


## The MultiMesh nodes (used by tests).
func multimesh_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for group in _groups.values():
		if group.node != null:
			result.append(group.node)
	return result


## The parts of a model with their materials in place (used by tests).
static func parts_of(model: PackedScene) -> Array:
	if not _parts.has(model):
		_parts[model] = _load_parts(model)
	return _parts[model]


# --- Building the groups -----------------------------------------------------------------------

func _chunk_of(building: Building) -> Vector2i:
	return Vector2i(floori(float(building.origin_cell.x) / CHUNK_CELLS), floori(float(building.origin_cell.y) / CHUNK_CELLS))


# Where the piece stands: its footprint centre, turned by the building's rotation (clockwise steps).
func _transform_of(building: Building) -> Transform3D:
	var center := Airport.grid.block_center(building.origin_cell, Building.rotated_size(building.type.footprint, building.rotation_steps))
	return Transform3D(Basis(Vector3.UP, -building.rotation_steps * PI * 0.5), center)


func _add_model(building: Building, model: PackedScene, id: StringName, chunk: Vector2i, base: Transform3D, keys: Array[String]) -> void:
	var parts := parts_of(model)
	var fence := String(id).begins_with("fence_")
	var has_far := parts.any(func(p: Part) -> bool: return p.kind == Kind.FAR)
	var is_tree := id == TREE_ID
	var placed := base
	var tint := Color.WHITE
	if is_tree:
		# Every tree is a little different: turn, size and shade come from its id, so they never change.
		var dice := RandomNumberGenerator.new()
		dice.seed = building.id * 7919 + 17
		var size := dice.randf_range(0.8, 1.2)
		var offset := Vector3(dice.randf_range(-0.6, 0.6), 0.0, dice.randf_range(-0.6, 0.6))
		var turn := Basis(Vector3.UP, dice.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(size, size * dice.randf_range(0.9, 1.1), size))
		placed = Transform3D(base.basis * turn, base.origin + offset)
		var shade := dice.randf_range(0.85, 1.05)
		tint = Color(shade, shade, shade)
	for part: Part in parts:
		var index := parts.find(part)
		# A stand-in is drawn twice: for the build camera (layer 4, always) and for the manager camera
		# (layer 3, beyond the full detail).
		for variant in (2 if part.kind == Kind.FAR else 1):
			var key := "%s|%d%s|%d,%d" % [id, index, "m" if variant == 1 else "", chunk.x, chunk.y]
			var group := _group(key, part.mesh, is_tree)
			group.transforms[building] = [placed * part.local]
			if is_tree:
				group.colors[building] = tint
			_configure(group, part, fence, has_far, variant == 1)
			_dirty[key] = true
			keys.append(key)


# Layers, visibility ranges and shadows of one group's node, by the kind of part.
# `for_manager` is the manager camera's copy of a stand-in.
func _configure(group: Group, part: Part, fence: bool, has_far: bool, for_manager: bool = false) -> void:
	var node := group.node
	node.set_meta(KIND_META, part.kind)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if part.kind == Kind.MAIN and not part.flat else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var near_end := FENCE_END_M if fence else (LOD_FAR_M if has_far else SMALL_PROP_END_M)
	if part.kind == Kind.FAR and not for_manager:
		node.layers = 1 << (FAR_LAYER - 1)
		return
	node.layers = 1 << (NEAR_LAYER - 1)
	if part.kind == Kind.FAR:
		node.visibility_range_begin = near_end
		return
	node.visibility_range_end = near_end
	if fence and part.kind == Kind.MAIN:
		node.visibility_range_end_margin = FENCE_FADE_MARGIN_M
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _group(key: String, mesh: Mesh, use_colors: bool) -> Group:
	if _groups.has(key):
		return _groups[key]
	var group := Group.new()
	group.mesh = mesh
	group.use_colors = use_colors
	group.node = MultiMeshInstance3D.new()
	group.node.name = key.replace("|", "_").replace(",", "_")
	group.node.multimesh = MultiMesh.new()
	group.node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	group.node.multimesh.use_colors = use_colors
	group.node.multimesh.mesh = mesh
	add_child(group.node)
	_groups[key] = group
	return group


func _rebuild(group: Group, key: String) -> void:
	var count := 0
	for list: Array in group.transforms.values():
		count += list.size()
	var multimesh := group.node.multimesh
	multimesh.instance_count = count
	group.node.visible = count > 0
	var index := 0
	for building: Building in group.transforms:
		for transform: Transform3D in group.transforms[building]:
			multimesh.set_instance_transform(index, transform)
			if group.use_colors:
				multimesh.set_instance_color(index, group.colors.get(building, Color.WHITE))
			index += 1


# --- Wear decals -------------------------------------------------------------------------------

# Decals per piece: [decal id, x, y (metres in the piece's frame, as in the Blender preview, y up), yaw in degrees].
# A few are only drawn for some pieces (by id), so the wear is not the same everywhere.
func _add_decals(building: Building, chunk: Vector2i, base: Transform3D, keys: Array[String]) -> void:
	var list: Array = []
	var dice := RandomNumberGenerator.new()
	dice.seed = building.id * 104729 + 3
	match building.type.id:
		&"carpark_module":
			for j in 4:
				for side in [-1.0, 1.0]:
					if dice.randf() < 0.35:
						list.append([&"decal_oil_stain", -3.75 + 2.5 * j + dice.randf_range(-0.2, 0.2), side * 5.3 + dice.randf_range(-0.3, 0.3), dice.randf_range(0.0, 360.0)])
			if building.id % 5 == 0:
				list.append([&"decal_patch", 1.0, 0.0, 0.0])
		&"carpark_barrier_gate":
			list.append([&"decal_tyre_marks", 1.5, -3.5, 0.0])
			list.append([&"decal_tyre_marks", -1.5, 3.5, 180.0])
		&"curb_dropoff_segment":
			list.append([&"decal_tyre_marks", 2.0, 0.6, 25.0])
			list.append([&"decal_patch", 5.0, -3.5, 0.0])
			for i in 3:
				list.append([&"decal_drain_grate", -7.4 + 8.0 * i, 4.41, 115.0])
		&"curb_plain_segment", &"curb_plain_segment_arrows":
			if building.id % 3 != 0:
				list.append([&"decal_drain_grate", 0.0, 5.2, 90.0])
			if building.id % 2 == 0:
				list.append([&"decal_drain_grate", 0.0, -5.7, 90.0])
		&"road_country_straight":
			if building.id % 9 == 0:
				list.append([&"decal_patch", 0.0, -2.0, 15.0])
	for entry: Array in list:
		var model: PackedScene = load("res://assets/models/landside/%s.glb" % entry[0])
		# Blender (x, y) is Godot (x, -y); a counter-clockwise yaw is a positive Godot rotation.
		var local := Transform3D(Basis(Vector3.UP, deg_to_rad(entry[3])), Vector3(entry[1], 0.0, -entry[2]))
		for part: Part in parts_of(model):
			var key := "%s|%d|%d,%d" % [entry[0], parts_of(model).find(part), chunk.x, chunk.y]
			var group := _group(key, part.mesh, false)
			group.node.set_meta(KIND_META, Kind.MARKINGS)
			group.node.layers = 1 << (NEAR_LAYER - 1)
			var list_of: Array = group.transforms.get(building, [])
			list_of.append(base * local * part.local)
			group.transforms[building] = list_of
			group.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.node.visibility_range_end = SMALL_PROP_END_M
			_dirty[key] = true
			if not keys.has(key):
				keys.append(key)


# --- Loading models ----------------------------------------------------------------------------

static func _load_parts(model: PackedScene) -> Array:
	var root := model.instantiate()
	var parts: Array = []
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		var instance := node as MeshInstance3D
		var part := Part.new()
		var name := String(instance.name)
		part.kind = Kind.MARKINGS if name.ends_with("_markings") else (Kind.FAR if name.ends_with("_lodfar") else Kind.MAIN)
		part.mesh = instance.mesh
		part.local = _relative_transform(instance, root)
		part.flat = instance.mesh.get_aabb().end.y < FLAT_HEIGHT_M
		for surface in part.mesh.get_surface_count():
			var material := part.mesh.surface_get_material(surface)
			if material != null:
				part.mesh.surface_set_material(surface, _shared_material(material.resource_name, part.kind))
		parts.append(part)
	root.free()
	return parts


# The model's own materials carry only a name; the real ones are in assets/materials. The paint
# atlas on the solid parts (fence mesh, barrier boom) is cut out with alpha scissor + alpha-to-coverage
# instead of blended, so thin wires stay smooth on the phone without sorting problems.
static func _shared_material(material_name: String, kind: Kind) -> Material:
	var wanted := material_name
	if material_name == "markings" and kind == Kind.MAIN:
		wanted = "markings_solid"
	if not _materials.has(wanted):
		_materials[wanted] = load("%s%s.tres" % [MATERIAL_DIR, wanted])
	return _materials[wanted]


static func _relative_transform(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D()
	var current: Node = node
	while current != root and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
