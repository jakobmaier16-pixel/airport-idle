extends TestCase
## The asset viewer world (scenes/viewer/, scripts/dev/worlds/): the catalog, stepping through it, nothing
## left over between items, the start view, the camera controls, the toggles and the HUD.


func _viewer() -> AssetViewer:
	return main.get_node("AssetViewer") as AssetViewer


func _camera() -> ViewerCamera:
	return main.get_node("ViewerCamera") as ViewerCamera


# A button of the viewer's controls by name (they sit in rows inside the ViewerHud).
func _vb(node_name: String) -> Button:
	return ui("ViewerHud").find_child(node_name, true, false) as Button


func _index_of(id: StringName) -> int:
	for i in _viewer().items.size():
		if _viewer().items[i].id == id:
			return i
	return -1


func _show(id: StringName) -> void:
	_viewer().show_item(_index_of(id))
	await frames(2)


# The pieces of the shown item that exist anywhere: buildings, painted cells, surfaces, nodes, drawn instances.
func _leftovers() -> Dictionary:
	var instances := 0
	for node in (main.get_node("Landside") as LandsideLayer).multimesh_nodes():
		instances += node.multimesh.instance_count
	return {
		"buildings": Airport.buildings.size(),
		"walkway": Airport.grid.count_flag(AirportGrid.WALKWAY_BIT),
		"taxiway": Airport.grid.count_flag(AirportGrid.TAXIWAY_BIT),
		"surface": Airport.grid.count_flag(AirportGrid.SURFACE_MASK),
		"nodes": _viewer().item_nodes().size(),
		"drawn": instances,
		"visuals": (main.get_node("Buildings") as BuildingLayer).visual_count(),
	}


func test_catalog_has_every_building_type_and_display_item_once() -> void:
	var list := ViewerCatalog.items()
	var seen: Dictionary[StringName, int] = {}
	for item in list:
		seen[item.id] = seen.get(item.id, 0) + 1
	for id in seen:
		check_eq(seen[id], 1, "id %s is in the catalog once" % id)
	for type in Airport.CATALOG.types:
		check_eq(seen.get(type.id, 0), 1, "building type %s is in the viewer (new assets need no showcase entry)" % type.id)
	for entry in ViewerCatalog.DISPLAY_ITEMS.items:
		check_eq(seen.get(entry.id, 0), 1, "display item %s is in the viewer" % entry.id)
		check(entry.scene != null or entry.material != null, "display item %s has a scene or a material" % entry.id)
	check_eq(list.size(), Airport.CATALOG.types.size() + 5 + ViewerCatalog.DISPLAY_ITEMS.items.size(), "buildings + 3 ground + 2 planes + display items")
	# Stable numbering: the first building is No. 1, display-only items come last.
	check_eq(list[0].id, Airport.CATALOG.types[0].id, "No. 1 is the first building type")
	check_eq(list[-1].id, ViewerCatalog.DISPLAY_ITEMS.items[-1].id, "the last item is the last display item")


func test_every_model_file_is_reachable_in_the_viewer() -> void:
	# Explicit list of what the viewer reaches (res:// listing is unreliable in exports); the files on
	# disk are listed here only because the test runs from the project.
	var reachable: Dictionary[String, bool] = {}
	for type in Airport.CATALOG.types:
		if type.model != null:
			reachable[type.model.resource_path] = true
	for entry in ViewerCatalog.DISPLAY_ITEMS.items:
		if entry.scene != null:
			reachable[entry.scene.resource_path] = true
	var files: Array[String] = []
	var folders: Array[String] = ["res://assets/models"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			folders.append("%s/%s" % [folder, sub])
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".glb"):
				files.append("%s/%s" % [folder, file])
	check(files.size() >= 60, "found the model files (%d)" % files.size())
	for path in files:
		check(reachable.has(path), "%s is reachable in the asset viewer (add a BuildingType or a display item)" % path)
	check("res://assets/models/terminal/terminal_facade_glass.glb" in files, "the terminal kit is on disk")


func test_next_and_prev_walk_through_everything_and_wrap() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var viewer := _viewer()
	var total := viewer.items.size()
	check(total > 80, "a full catalog (%d)" % total)
	check_eq(viewer.index, 0, "starts at the first item")
	var seen: Dictionary[StringName, bool] = {}
	for step in total:
		var item: ViewerItem = viewer.current_item()
		seen[item.id] = true
		check_eq(viewer.label_text(), "%d / %d · %s · %s · %s" % [step + 1, total, item.id, item.display_name, item.category_path()], "label of item %d" % (step + 1))
		# Exactly one item exists: the building it placed, or the painted cells, or its nodes, and nothing else.
		var left: Dictionary = _leftovers()
		var expected_buildings := 1 if item.kind == ViewerItem.Kind.BUILDING else 0
		check_eq(left.buildings, expected_buildings, "%s: buildings in the brain" % item.id)
		check_eq(left.visuals, 1 if item.kind == ViewerItem.Kind.BUILDING and item.building_type.model == null or item.kind == ViewerItem.Kind.BUILDING and item.building_type.is_solid else 0, "%s: building visuals" % item.id)
		var walkway := 0 if item.id != ViewerCatalog.GROUND_WALKWAY else ViewerCatalog.WALKWAY_PATCH.x * ViewerCatalog.WALKWAY_PATCH.y
		var taxiway := 0 if item.id != ViewerCatalog.GROUND_TAXIWAY else ViewerCatalog.TAXIWAY_STRIP.x * ViewerCatalog.TAXIWAY_STRIP.y
		check_eq(left.walkway, walkway, "%s: walkway cells" % item.id)
		check_eq(left.taxiway, taxiway, "%s: taxiway cells" % item.id)
		check_eq(left.surface > 0, item.kind == ViewerItem.Kind.BUILDING and item.building_type.role in [BuildingType.Role.AIRCRAFT_STAND, BuildingType.Role.RUNWAY], "%s: ground surface only for stands and runways" % item.id)
		check_eq(left.nodes, 1 if item.kind in [ViewerItem.Kind.PLANE, ViewerItem.Kind.DISPLAY] else 0, "%s: item nodes" % item.id)
		await press(_vb("NextButton"))
		(main.get_node("Landside") as LandsideLayer).flush()
	check_eq(seen.size(), total, "Next visited every item once")
	check_eq(viewer.index, 0, "Next wrapped around to the first item")
	await press(_vb("PrevButton"))
	check_eq(viewer.index, total - 1, "Prev from the first wraps to the last")
	await press(_vb("PrevButton"))
	check_eq(viewer.index, total - 2, "Prev steps back")
	# Back to the start: everything gone again, whatever the order.
	viewer.show_item(_index_of(&"ground_grass"))
	var left: Dictionary = _leftovers()
	check(left.buildings == 0 and left.walkway == 0 and left.taxiway == 0 and left.surface == 0 and left.nodes == 0, "grass is an empty field: %s" % [left])
	check_eq(left.drawn, 0, "nothing of the previous landside piece is drawn any more")


func test_category_row_jumps_to_the_first_item_of_a_category() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var row := ui("ViewerHud/CategoryRow")
	var names: Array[String] = []
	for button: Button in row.get_children():
		names.append(button.text)
	for expected in ["Terminal", "Airside", "Landside", "Ground", "Planes", "Terminal kit", "Decals", "Materials"]:
		check(names.has(expected), "category %s in the row" % expected)
	for button: Button in row.get_children():
		if button.button_pressed:
			continue
		await press(button)
		var first: ViewerItem = null
		for item in _viewer().items:
			if item.category == button.text:
				first = item
				break
		check_eq(_viewer().current_item().id, first.id, "%s jumps to its first item" % button.text)


func test_size_line_gives_footprint_and_model_size() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	await _show(&"carpark_module")
	var text := (ui("ViewerHud/SizeLabel") as Label).text
	check(text.contains("Footprint 5 x 8 cells = 10.0 x 16.0 m"), "footprint in cells and metres: %s" % text)
	check(text.contains("Model 10.0 x 16.0 x"), "real model size: %s" % text)
	await _show(&"check_in")
	check((ui("ViewerHud/SizeLabel") as Label).text.contains("placeholder box"), "a building without a model says so")


func test_start_view_frames_the_item() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var camera := _camera()
	check(camera.current, "the viewer camera is the current one")
	for id in [&"bollard", &"road_country_straight", &"aircraft_stand", &"runway", &"plane_narrow", &"plane_wide", &"tree_deciduous", &"terminal_facade_glass"]:
		await _show(id)
		var bounds := _viewer().frame_bounds()
		var centre := camera.unproject_position(bounds.get_center())
		var middle := screen_size() * 0.5
		check(absf(centre.x - middle.x) < screen_size().x * 0.05 and absf(centre.y - middle.y) < screen_size().y * 0.05, "%s: the centre is near the screen centre (%s)" % [id, centre])
		var extent := Rect2()
		for corner in 8:
			var point := bounds.position + bounds.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
			check(not camera.is_position_behind(point), "%s: corner %d is in front of the camera" % [id, corner])
			var on_screen := camera.unproject_position(point)
			extent = Rect2(on_screen, Vector2.ZERO) if corner == 0 else extent.expand(on_screen)
		check(Rect2(Vector2.ZERO, screen_size()).encloses(extent), "%s: the bounds are on screen (%s)" % [id, extent])
		var fill := maxf(extent.size.x / screen_size().x, extent.size.y / screen_size().y)
		check(fill > 0.4 and fill < 0.8, "%s: fills about half of the screen (%.2f)" % [id, fill])
		check(camera.global_position.y > 0.0, "%s: above the ground" % id)
		check(camera.far > camera.distance + bounds.size.length(), "%s: far clip reaches the whole item (%.0f)" % [id, camera.far])
		if id == &"runway":
			check(camera.far > 2000.0, "the 2 km runway fits in the far clip (%.0f)" % camera.far)


func test_drag_turns_and_tilts_and_pinch_zooms_within_limits() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	await _show(&"carpark_module")
	var camera := _camera()
	var middle := screen_size() * 0.5
	var yaw := camera.yaw
	var pitch := camera.pitch
	drag(middle, middle + Vector2(120, 0))
	await frames(1)
	check(not is_equal_approx(camera.yaw, yaw), "a horizontal drag turns the view")
	check(is_equal_approx(camera.pitch, pitch), "and does not tilt it")
	yaw = camera.yaw
	drag(middle, middle + Vector2(0, -60))
	await frames(1)
	check(camera.pitch < pitch, "dragging up tilts towards the ground")
	check(is_equal_approx(camera.yaw, yaw), "and does not turn it")
	for i in 30:
		drag(middle, middle + Vector2(0, 100))
	check_eq(snappedf(rad_to_deg(camera.pitch), 0.1), 85.0, "the highest view is 85 degrees")
	for i in 60:
		drag(middle, middle + Vector2(0, -100))
		check(camera.global_position.y > 0.0, "never below the ground (drag %d)" % i)
	check_eq(snappedf(rad_to_deg(camera.pitch), 0.1), 3.0, "the lowest view is 3 degrees")
	# Pinch and wheel.
	var before := camera.distance
	pinch(middle, 200.0, 400.0)
	check(camera.distance < before, "fingers apart come closer")
	before = camera.distance
	pinch(middle, 400.0, 200.0)
	check(camera.distance > before, "fingers together move away")
	for i in 40:
		pinch(middle, 100.0, 600.0)
	check(is_equal_approx(camera.distance, camera.min_distance()), "the closest distance is the limit (%.2f)" % camera.distance)
	check(camera.min_distance() < 2.0, "a close-up of a 18 m piece is possible")
	for i in 80:
		pinch(middle, 600.0, 100.0)
	check(is_equal_approx(camera.distance, camera.max_distance()), "the farthest distance is the limit")
	var diagonal := _viewer().frame_bounds().size.length()
	check(is_equal_approx(camera.max_distance(), diagonal * 6.0), "about 6 times the diagonal")
	wheel(true, 3, middle)
	check(camera.distance < camera.max_distance(), "the mouse wheel zooms")
	# A tiny prop has its own, smaller limits.
	await _show(&"bollard")
	check(camera.max_distance() < 30.0 and camera.min_distance() < 0.5, "limits follow the item's size (%.2f .. %.2f)" % [camera.min_distance(), camera.max_distance()])


func test_eye_level_and_reset_view() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var camera := _camera()
	for id in [&"bollard", &"tree_deciduous", &"aircraft_stand", &"plane_narrow", &"runway"]:
		await _show(id)
		var start := camera.global_position
		await press(_vb("EyeLevelButton"))
		check(absf(camera.global_position.y - 1.7) < 0.001, "%s: eye level is 1.7 m (%.3f)" % [id, camera.global_position.y])
		check(camera.global_position.distance_to(start) > 0.0, "%s: the camera moved" % id)
		var horizontal := Vector2(camera.global_position.x - camera.target.x, camera.global_position.z - camera.target.z).length()
		check(horizontal <= ViewerCamera.EYE_DISTANCE_MAX + 0.01, "%s: a natural distance (%.1f m)" % [id, horizontal])
		drag(screen_size() * 0.5, screen_size() * 0.5 + Vector2(80, 80))
		check(absf(camera.global_position.y - 1.7) < 0.001, "%s: turning keeps the eye height" % id)
		await press(_vb("ResetViewButton"))
		check(not camera.eye_level and is_equal_approx(camera.yaw, deg_to_rad(ViewerCamera.START_YAW_DEG)), "%s: Reset view is the start view again" % id)
		check(camera.global_position.distance_to(start) < 0.01, "%s: at the very same spot" % id)


func test_person_and_far_model_toggles() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	await _show(&"road_country_straight")
	var person := _viewer().person()
	check(person.visible, "the person is on by default")
	var size := ViewerCatalog.node_bounds(person).size
	check(absf(size.y - 1.8) < 0.01 and size.x < 1.0, "a 1.80 m figure (%s)" % [size])
	check(absf(ViewerCatalog.node_bounds(person).position.y) < 0.001, "standing on the ground")
	await press(_vb("PersonButton"))
	check(not person.visible, "Person off hides it")
	await press(_vb("PersonButton"))
	check(person.visible, "and on shows it again")
	var camera := _camera()
	var far := _vb("FarModelButton") as Button
	check(not far.disabled, "a road piece has a far model")
	check(camera.get_cull_mask_value(LandsideLayer.NEAR_LAYER) and not camera.get_cull_mask_value(LandsideLayer.FAR_LAYER), "the full model is shown first")
	await press(far)
	check(not camera.get_cull_mask_value(LandsideLayer.NEAR_LAYER) and camera.get_cull_mask_value(LandsideLayer.FAR_LAYER), "Far model switches to the build view stand-in")
	await _show(&"bollard")
	check(far.disabled, "a bollard has no far model: the toggle is disabled")
	check(camera.get_cull_mask_value(LandsideLayer.NEAR_LAYER) and not camera.get_cull_mask_value(LandsideLayer.FAR_LAYER), "and the full model is shown")
	for id in [&"plane_narrow", &"swatch_grass", &"terminal_facade_glass", &"ground_taxiway", &"gate"]:
		await _show(id)
		check(far.disabled, "%s: no far model" % id)
	await _show(&"road_country_straight")
	check(not far.disabled and not far.button_pressed, "back on a road piece the toggle is off and ready")


func test_no_hints_and_no_flights_here() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	for id in [&"gate", &"aircraft_stand", &"runway", &"security", &"check_in", &"car_park"]:
		await _show(id)
		for label in main.get_node("Buildings").find_children("*", "Label3D", true, false):
			check(not (label as Label3D).visible, "%s: no connection hint ('%s')" % [id, (label as Label3D).text])
		sim_seconds(900.0)
		check(Airport.schedule.flights.is_empty(), "%s: no flight can happen here" % id)
	check(not (main.get_node("Buildings") as BuildingLayer).hints_enabled, "hints are off in this world")


func test_every_control_is_on_screen_and_inside_the_safe_area() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var area := hud().get_node("SafeArea")
	for setup in [["plain", 0, 0], ["notch", 130, 60]]:
		# The notch: extra margin left and right (the Dynamic Island side) and at the bottom (home indicator).
		area.add_theme_constant_override(&"margin_left", 16 + setup[1])
		area.add_theme_constant_override(&"margin_right", 16 + setup[1])
		area.add_theme_constant_override(&"margin_bottom", 16 + setup[2])
		for id in [&"bollard", &"terminal_facade_glass", &"swatch_terrazzo_dark", &"road_oneway_2lane_access"]:
			await _show(id)
			await frames(3)
			var boxes: Array[Control] = []
			for button in visible_buttons():
				boxes.append(button)
			for node in area.find_children("*", "Label", true, false):
				if (node as Label).is_visible_in_tree() and not (node as Label).text.is_empty():
					boxes.append(node)
			check(boxes.size() >= 12, "%s/%s: the controls are there (%d)" % [setup[0], id, boxes.size()])
			for box in boxes:
				check(in_safe_area(box), "%s/%s: %s inside the safe area (%s in %s)" % [setup[0], id, box.name, box.get_global_rect(), safe_rect()])
				check(Rect2(Vector2.ZERO, screen_size()).encloses(box.get_global_rect()), "%s/%s: %s on screen" % [setup[0], id, box.name])
				if box is Button:
					check(box.get_global_rect().size.y >= 80.0 and box.get_global_rect().size.x >= 80.0, "%s: %s is finger-sized" % [id, box.name])
			for i in boxes.size():
				for j in range(i + 1, boxes.size()):
					if boxes[i] is Label and boxes[j] is Label:
						continue
					check(not boxes[i].get_global_rect().intersects(boxes[j].get_global_rect()), "%s/%s: %s and %s do not overlap" % [setup[0], id, boxes[i].name, boxes[j].name])
	# No manager, joystick, build menu or flights list in the viewer.
	check(not manager().visible, "no manager")
	check(not ui("TouchJoystick").visible and not ui("BuildMenu").visible and not ui("InfoPanel").visible, "no joystick, build menu or flights list")
	check(not ui("TopButtons/ViewButton").visible, "no view button")


func test_current_category_is_marked_not_locked() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var row := ui("ViewerHud/CategoryRow")
	for target in ["Landside", "Planes", "Materials"]:
		for button: Button in row.get_children():
			if button.text == target:
				await press(button)
		await frames(1)
		for button: Button in row.get_children():
			check(not button.disabled, "%s is never disabled" % button.text)
			check_eq(button.button_pressed, button.text == target, "%s: the mark is on %s only" % [button.text, target])
			check_eq(button.has_theme_color_override(&"font_color"), button.text == target, "%s: the colour mark" % button.text)


func test_person_is_visible_outside_the_item_on_the_camera_side() -> void:
	await enter_world(TestWorlds.ASSET_VIEWER)
	var camera := _camera()
	for id in [&"terminal_facade_glass", &"curb_dropoff_segment", &"aircraft_stand", &"runway", &"swatch_paving"]:
		await _show(id)
		var person := _viewer().person()
		var bounds := _viewer().frame_bounds()
		var spot := person.global_position
		var body := Vector3(spot.x, 0.9, spot.z)
		check(not camera.is_position_behind(body), "%s: the figure is in front of the camera" % id)
		check(Rect2(Vector2.ZERO, screen_size()).has_point(camera.unproject_position(body)), "%s: the figure is on screen" % id)
		var flat := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		check(not flat.has_point(Vector2(spot.x, spot.z)), "%s: the figure is outside the item's bounds" % id)
		var eye := Vector2(camera.global_position.x, camera.global_position.z)
		check(eye.distance_to(Vector2(spot.x, spot.z)) < eye.distance_to(Vector2(bounds.get_center().x, bounds.get_center().z)), "%s: nearer to the camera than the item's centre" % id)
		var edge := flat.grow(3.5)
		check(edge.has_point(Vector2(spot.x, spot.z)), "%s: within about 3 m of the item's edge" % id)
