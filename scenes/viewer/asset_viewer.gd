class_name AssetViewer
extends Node3D
## The asset viewer (test world "Asset viewer", docs/worlds.md): one asset at a time, alone on an empty
## grass field, drawn by the game's own layers and light. Buildings are placed for real in the brain
## (so BuildingLayer, LandsideLayer and the ground draw them exactly as in the game); ground surfaces are
## painted; planes and display-only items are nodes under `_item_root`. Switching items demolishes /
## unpaints / frees the previous one first, so nothing is left over.

signal item_changed(index: int)

## The grey figure's height (a person 1.80 m tall).
const PERSON_HEIGHT: float = 1.8
const PERSON_COLOR: Color = Color(0.55, 0.56, 0.58)
## How far the figure stands from the item's edge, in metres.
const PERSON_GAP: float = 1.0

@export var camera: ViewerCamera
## Draws the buildings; its "No stand" / "Not connected" hints are hidden here.
@export var building_layer: BuildingLayer

var items: Array[ViewerItem] = []
var index: int = -1
## Show the grey 1.80 m figure beside the item.
var person_visible: bool = true
## Show the build view's stand-in model instead of the full one (items that have one).
var far_model: bool = false

var _building: Building = null
var _painted: Array[Vector2i] = []
var _paint_is_taxiway: bool = false
var _item_root: Node3D
var _person: Node3D
# The item's bounds in world space and what the size line says.
var _frame: AABB = AABB()
var _size_text: String = ""


func _ready() -> void:
	name = "AssetViewer"
	_item_root = Node3D.new()
	_item_root.name = "Item"
	add_child(_item_root)
	_person = _make_person()
	add_child(_person)
	if building_layer != null:
		building_layer.hints_enabled = false


## Sets the catalog (the first item is shown). Tests pass their own list.
func set_items(list: Array[ViewerItem]) -> void:
	items = list
	index = -1
	show_item(0)


## Shows item number `new_index` (0-based), wrapping around at both ends.
func show_item(new_index: int) -> void:
	if items.is_empty():
		return
	_clear()
	index = posmod(new_index, items.size())
	var item := items[index]
	var anchor := ViewerCatalog.anchor_of(item)
	match item.kind:
		ViewerItem.Kind.BUILDING:
			_building = Airport.place_building(item.building_type, ViewerCatalog.origin_cell_of(item), 0)
			if _building == null:
				push_error("Asset viewer: %s does not fit in the middle of the map" % item.id)
		ViewerItem.Kind.GROUND:
			_paint(item)
		ViewerItem.Kind.PLANE:
			var plane := ViewerCatalog.make_plane(item)
			plane.position = anchor
			_item_root.add_child(plane)
		ViewerItem.Kind.DISPLAY:
			_spawn_display(item, anchor)
	_frame = ViewerCatalog.frame_aabb(item, self)
	_frame.position += anchor
	_size_text = ViewerCatalog.size_text(item, self)
	_place_person()
	_apply_far_model()
	camera.frame(_frame)
	item_changed.emit(index)


func next_item() -> void:
	show_item(index + 1)


func previous_item() -> void:
	show_item(index - 1)


## Jumps to the first item of `category`. Returns false if there is none.
func show_category(category: String) -> bool:
	for i in items.size():
		if items[i].category == category:
			show_item(i)
			return true
	return false


func current_item() -> ViewerItem:
	return items[index] if index >= 0 else null


## "12 / 61 · bollard · Bollard · Landside › Props".
func label_text() -> String:
	return ViewerCatalog.label_of(items, index)


## Footprint and real model size of the shown item.
func size_text() -> String:
	return _size_text


## The shown item's bounds in world space (what the camera frames).
func frame_bounds() -> AABB:
	return _frame


## True if the shown item has a stand-in for the "Far model" toggle.
func has_far_model() -> bool:
	return ViewerCatalog.has_far_model(items[index]) if index >= 0 else false


func set_person_visible(value: bool) -> void:
	person_visible = value
	_person.visible = value


## Shows the build view's stand-in (layer 4) instead of the full model (layer 3) - items without one
## stay as they are.
func set_far_model(value: bool) -> void:
	far_model = value
	_apply_far_model()


## The nodes of the shown item (planes, display-only items), for tests.
func item_nodes() -> Array[Node]:
	return _item_root.get_children()


## The real building the shown item placed in the brain, or null.
func shown_building() -> Building:
	return _building


func person() -> Node3D:
	return _person


# --- Placing and clearing ---

func _clear() -> void:
	if _building != null:
		Airport.demolish(_building)
		_building = null
	if not _painted.is_empty():
		if _paint_is_taxiway:
			Airport.paint_taxiway(_painted, false)
		else:
			Airport.paint_walkway(_painted, false)
		_painted.clear()
	# Freed now, not queued: nothing of the previous item may be around when the next one shows.
	for child in _item_root.get_children():
		_item_root.remove_child(child)
		child.free()


func _paint(item: ViewerItem) -> void:
	if item.surface == ViewerItem.Surface.GRASS:
		return
	var origin := ViewerCatalog.origin_cell_of(item)
	var size := ViewerCatalog.cells_of(item)
	for y in size.y:
		for x in size.x:
			_painted.append(origin + Vector2i(x, y))
	_paint_is_taxiway = item.surface == ViewerItem.Surface.TAXIWAY
	if _paint_is_taxiway:
		Airport.paint_taxiway(_painted, true)
	else:
		Airport.paint_walkway(_painted, true)


func _spawn_display(item: ViewerItem, anchor: Vector3) -> void:
	if item.display.scene != null:
		var node := item.display.scene.instantiate() as Node3D
		node.position = anchor
		_item_root.add_child(node)
		return
	var swatch := MeshInstance3D.new()
	swatch.mesh = ViewerCatalog.swatch_mesh(item.display.swatch_size, item.display.material)
	swatch.position = anchor + Vector3(0.0, item.display.swatch_size.y * 0.5, 0.0)
	_item_root.add_child(swatch)


# The figure stands just off the item's edge, on the right as the start view sees it, so it is as far from
# the camera as the item itself (a figure in front of the item would look huge).
func _place_person() -> void:
	var middle := _frame.get_center()
	var right := Vector3(cos(deg_to_rad(ViewerCamera.START_YAW_DEG)), 0.0, -sin(deg_to_rad(ViewerCamera.START_YAW_DEG)))
	var reach := minf((_frame.size.x * 0.5) / absf(right.x), (_frame.size.z * 0.5) / absf(right.z))
	_person.position = Vector3(middle.x, 0.0, middle.z) + right * (reach + PERSON_GAP)
	_person.visible = person_visible


func _apply_far_model() -> void:
	if camera == null:
		return
	var far := far_model and has_far_model()
	camera.set_cull_mask_value(LandsideLayer.NEAR_LAYER, not far)
	camera.set_cull_mask_value(LandsideLayer.FAR_LAYER, far)


# A simple grey figure: legs and body as one capsule, a sphere for the head. 1.80 m in all.
func _make_person() -> Node3D:
	var figure := Node3D.new()
	figure.name = "Person"
	var material := StandardMaterial3D.new()
	material.albedo_color = PERSON_COLOR
	material.roughness = 0.9
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.55
	capsule.material = material
	body.mesh = capsule
	body.position.y = capsule.height * 0.5
	figure.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.125
	sphere.height = 0.25
	sphere.material = material
	head.mesh = sphere
	head.position.y = PERSON_HEIGHT - 0.125
	figure.add_child(head)
	return figure
