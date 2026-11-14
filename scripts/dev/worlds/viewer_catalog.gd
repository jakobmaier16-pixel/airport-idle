class_name ViewerCatalog
extends RefCounted
## The asset viewer's catalog: every building type, the ground surfaces, the planes and the
## display-only items (data/viewer/display_items.tres), in a stable order with stable ids.
## tools/viewer_catalog.sh prints it numbered, so "No. 12" maps to an id for any commit.
## Also measures items (grid footprint, real model bounds) and says where the viewer puts them.

const DISPLAY_ITEMS: DisplayCatalog = preload("res://data/viewer/display_items.tres")

const CATEGORY_GROUND: String = "Ground"
const CATEGORY_PLANES: String = "Planes"

const GROUND_GRASS: StringName = &"ground_grass"
const GROUND_WALKWAY: StringName = &"ground_walkway"
const GROUND_TAXIWAY: StringName = &"ground_taxiway"
const PLANE_NARROW: StringName = &"plane_narrow"
const PLANE_WIDE: StringName = &"plane_wide"

## Ground patches in cells. A taxiway is 12 cells (24 m) wide, as in the game, and long enough to show
## its centreline and both edge lines. The walkway patch shows the paving. Grass is just a bare patch.
const WALKWAY_PATCH: Vector2i = Vector2i(10, 10)
const TAXIWAY_STRIP: Vector2i = Vector2i(60, 12)
const GRASS_PATCH: Vector2i = Vector2i(10, 10)


## The numbered catalog (number = index + 1). `display` is a parameter so tests can add items.
static func items(display: DisplayCatalog = DISPLAY_ITEMS) -> Array[ViewerItem]:
	var result: Array[ViewerItem] = []
	var types: Array[BuildingType] = Airport.CATALOG.types
	# Menu order: categories as they first appear; inside one, the sub-categories first (they are
	# buttons in the build menu), then the buildings that sit directly in the category.
	var categories: PackedStringArray = []
	for type in types:
		if not categories.has(type.category):
			categories.append(type.category)
	for category in categories:
		var subs: PackedStringArray = [""]
		for type in types:
			if type.category == category and not subs.has(type.sub_category):
				subs.append(type.sub_category)
		subs.remove_at(0)
		subs.append("")
		for sub in subs:
			for type in types:
				if type.category == category and type.sub_category == sub:
					result.append(_building_item(type))
	result.append(_ground_item(GROUND_GRASS, "Grass", ViewerItem.Surface.GRASS))
	result.append(_ground_item(GROUND_WALKWAY, "Walkway paving", ViewerItem.Surface.WALKWAY))
	result.append(_ground_item(GROUND_TAXIWAY, "Plane taxiway", ViewerItem.Surface.TAXIWAY))
	result.append(_plane_item(PLANE_NARROW, "Narrow-body plane", false))
	result.append(_plane_item(PLANE_WIDE, "Wide-body plane", true))
	for entry in display.items:
		var item := ViewerItem.new()
		item.id = entry.id
		item.display_name = entry.display_name
		item.category = entry.category
		item.kind = ViewerItem.Kind.DISPLAY
		item.display = entry
		result.append(item)
	return result


## The categories in the order of their first item.
static func categories(list: Array[ViewerItem]) -> PackedStringArray:
	var result: PackedStringArray = []
	for item in list:
		if not result.has(item.category):
			result.append(item.category)
	return result


## The label above the item: "12 / 61 · bollard · Bollard · Landside › Props" (number is 1-based).
static func label_of(list: Array[ViewerItem], index: int) -> String:
	var item := list[index]
	return "%d / %d · %s · %s · %s" % [index + 1, list.size(), item.id, item.display_name, item.category_path()]


# --- Where the viewer puts an item ---

## The size in cells of the area the item takes in the middle of the map.
static func cells_of(item: ViewerItem) -> Vector2i:
	match item.kind:
		ViewerItem.Kind.BUILDING:
			return item.building_type.footprint
		ViewerItem.Kind.GROUND:
			match item.surface:
				ViewerItem.Surface.WALKWAY:
					return WALKWAY_PATCH
				ViewerItem.Surface.TAXIWAY:
					return TAXIWAY_STRIP
				_:
					return GRASS_PATCH
	return Vector2i.ONE


## The first cell of that area, so the area is centred on the map's middle cell.
static func origin_cell_of(item: ViewerItem) -> Vector2i:
	return MapAnchor.centre_of(Airport.grid.size) - cells_of(item) / 2


## The middle of the item on the ground, in world metres.
static func anchor_of(item: ViewerItem) -> Vector3:
	return Airport.grid.block_center(origin_cell_of(item), cells_of(item))


## True if the item has a footprint on the grid (buildings and painted ground).
static func has_footprint(item: ViewerItem) -> bool:
	return item.kind == ViewerItem.Kind.BUILDING or (item.kind == ViewerItem.Kind.GROUND and item.surface != ViewerItem.Surface.GRASS)


## The footprint on the ground in metres, around the anchor (x = width, y = depth).
static func footprint_m(item: ViewerItem) -> Vector2:
	return Vector2(cells_of(item)) * Airport.CELL_SIZE


## The real size of the item's model: the bounds of what is drawn, around the anchor (y up from the
## ground). A building without a model is a placeholder box, a ground patch is its area.
## `host` is a node in the tree for items that need a temporary instance (planes, scenes).
static func model_aabb(item: ViewerItem, host: Node) -> AABB:
	match item.kind:
		ViewerItem.Kind.BUILDING:
			var type := item.building_type
			if type.model != null:
				return _model_bounds(type.model)
			var size := Vector3(type.footprint.x * Airport.CELL_SIZE, type.height, type.footprint.y * Airport.CELL_SIZE)
			return AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		ViewerItem.Kind.GROUND:
			var area := Vector2(cells_of(item)) * Airport.CELL_SIZE
			return AABB(Vector3(-area.x * 0.5, 0.0, -area.y * 0.5), Vector3(area.x, 0.02, area.y))
		ViewerItem.Kind.PLANE:
			var plane := make_plane(item)
			host.add_child(plane)
			var bounds := node_bounds(plane)
			host.remove_child(plane)
			plane.free()
			return bounds
		_:
			if item.display.scene != null:
				var node := item.display.scene.instantiate() as Node3D
				host.add_child(node)
				var bounds := node_bounds(node)
				host.remove_child(node)
				node.free()
				return bounds
			var swatch := item.display.swatch_size
			return AABB(Vector3(-swatch.x * 0.5, 0.0, -swatch.z * 0.5), swatch)


## What the camera frames: the model and, for items on the grid, the footprint too.
static func frame_aabb(item: ViewerItem, host: Node) -> AABB:
	var bounds := model_aabb(item, host)
	if has_footprint(item):
		var area := footprint_m(item)
		bounds = bounds.merge(AABB(Vector3(-area.x * 0.5, 0.0, -area.y * 0.5), Vector3(area.x, 0.02, area.y)))
	return bounds


## The size line under the label: footprint and real model size.
static func size_text(item: ViewerItem, host: Node) -> String:
	var parts: PackedStringArray = []
	if has_footprint(item):
		var cells := cells_of(item)
		var metres := footprint_m(item)
		parts.append("Footprint %d x %d cells = %s x %s m" % [cells.x, cells.y, _m(metres.x), _m(metres.y)])
	var size := model_aabb(item, host).size
	var note := ""
	if item.kind == ViewerItem.Kind.BUILDING and item.building_type.model == null:
		note = " (placeholder box)"
	parts.append("Model %s x %s x %s m (w x d x h)%s" % [_m(size.x), _m(size.z), _m(size.y), note])
	return "\n".join(parts)


static func _m(value: float) -> String:
	return "%.2f" % value if value < 10.0 else "%.1f" % value


## True if the item has a build-view stand-in the "Far model" toggle can show.
static func has_far_model(item: ViewerItem) -> bool:
	if item.kind != ViewerItem.Kind.BUILDING or item.building_type.model == null:
		return false
	return LandsideLayer.parts_of(item.building_type.model).any(func(p: LandsideLayer.Part) -> bool:
		return p.kind == LandsideLayer.Kind.FAR)


## A plane at the real size of its class (PlaneVisual.size_for), not yet in the tree.
static func make_plane(item: ViewerItem) -> PlaneVisual:
	var plane := PlaneVisual.new()
	var plane_class := TimetableSlot.PlaneClass.WIDE if item.wide_body else TimetableSlot.PlaneClass.NARROW
	plane.size_factor = TimetableSlot.WINGSPAN_M[plane_class] / PlaneVisual.WINGSPAN
	plane.wide_body = item.wide_body
	return plane


## The union of every mesh below `root`, in the root's own frame.
static func node_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var local := _relative_transform(instance, root) * instance.mesh.get_aabb()
		result = local if first else result.merge(local)
		first = false
	return result


# The bounds of what a landside model draws (paint and the full-detail meshes, not the stand-in).
static func _model_bounds(model: PackedScene) -> AABB:
	var result := AABB()
	var first := true
	for part: LandsideLayer.Part in LandsideLayer.parts_of(model):
		if part.kind == LandsideLayer.Kind.FAR:
			continue
		var local := part.local * part.mesh.get_aabb()
		result = local if first else result.merge(local)
		first = false
	return result


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D()
	var current: Node = node
	while current != root and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


static func _building_item(type: BuildingType) -> ViewerItem:
	var item := ViewerItem.new()
	item.id = type.id
	item.display_name = type.display_name
	item.category = type.category
	item.sub_category = type.sub_category
	item.kind = ViewerItem.Kind.BUILDING
	item.building_type = type
	return item


static func _ground_item(id: StringName, name: String, surface: ViewerItem.Surface) -> ViewerItem:
	var item := ViewerItem.new()
	item.id = id
	item.display_name = name
	item.category = CATEGORY_GROUND
	item.kind = ViewerItem.Kind.GROUND
	item.surface = surface
	return item


static func _plane_item(id: StringName, name: String, wide: bool) -> ViewerItem:
	var item := ViewerItem.new()
	item.id = id
	item.display_name = name
	item.category = CATEGORY_PLANES
	item.kind = ViewerItem.Kind.PLANE
	item.wide_body = wide
	return item


## A slab of `size` metres (centred on its own origin) with `material`. The texture coordinates are in
## metres on every face, like the models in assets/models, so the material shows at the scale it has in the game.
static func swatch_mesh(size: Vector3, material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var u := Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.BACK
		var v := normal.cross(u)
		var centre := normal * half.dot(normal.abs())
		var eu := u * half.dot(u.abs())
		var ev := v * half.dot(v.abs())
		var corners: Array[Vector3] = [centre + eu + ev, centre - eu + ev, centre - eu - ev, centre + eu - ev]
		# Godot draws clockwise triangles as front faces.
		var order: Array[int] = [0, 1, 2, 0, 2, 3]
		if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for index in order:
			var point := corners[index]
			surface.set_normal(normal)
			surface.set_uv(Vector2(point.dot(u), point.dot(v)))
			surface.add_vertex(point)
	surface.generate_tangents()
	var mesh := surface.commit()
	mesh.surface_set_material(0, material)
	return mesh
