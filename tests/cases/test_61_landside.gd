extends TestCase
## Landside pieces (design doc §4, "Landside grows piece by piece"): data rules, placing from the
## build menu, and the start layout in the showcase.


func _landside_pieces() -> Array[BuildingType]:
	var result: Array[BuildingType] = []
	for type in Airport.CATALOG.types:
		if type.category == "Landside" and not type.sub_category.is_empty():
			result.append(type)
	return result


func test_pieces_follow_the_landside_rules() -> void:
	var pieces := _landside_pieces()
	check(pieces.size() >= 35, "the whole catalogue is there (%d pieces)" % pieces.size())
	var ids: Dictionary[StringName, bool] = {}
	for type in pieces:
		check(not ids.has(type.id), "%s: one type per id" % type.id)
		ids[type.id] = true
		check_eq(type.zone_rule, BuildingType.ZoneRule.LANDSIDE, "%s: landside only" % type.id)
		# Decorative: no role, no passenger access, no staff, no running cost (design doc §4, nothing defined yet).
		check_eq(type.role, BuildingType.Role.NONE, "%s: no simulation role" % type.id)
		check_eq(type.front_access, BuildingType.Access.NONE, "%s: no front access" % type.id)
		check_eq(type.back_access, BuildingType.Access.NONE, "%s: no back access" % type.id)
		check_eq(type.running_cost_per_minute, 0.0, "%s: no running cost" % type.id)
		check(type.build_cost > 0.0, "%s: has a (placeholder) price" % type.id)
		check_eq(type.unlocked_at, 0, "%s: part of the start kit" % type.id)
		check(type.footprint.x >= 1 and type.footprint.y >= 1, "%s: has a footprint" % type.id)
	for sub in ["Roads", "Curb", "Sidewalk", "Car park", "Props"]:
		check(pieces.any(func(t: BuildingType) -> bool: return t.sub_category == sub), "sub-category %s exists" % sub)


func test_every_piece_places_rotates_and_demolishes() -> void:
	Airport.economy.balance = 1.0e6
	var origin := at(Vector2i(20, 20))
	for type in _landside_pieces():
		for steps in 4:
			var before := Airport.economy.balance
			var building := Airport.place_building(type, origin, steps)
			check(building != null, "%s placed, rotation %d" % [type.id, steps])
			if building == null:
				continue
			check_eq(building.get_rect().size, Building.rotated_size(type.footprint, steps), "%s: rotated footprint" % type.id)
			check_eq(before - Airport.economy.balance, type.build_cost, "%s: costs its price" % type.id)
			check_eq(Airport.place_building(type, origin, steps), null, "%s: the cells are taken now" % type.id)
			check(Airport.demolish(building), "%s demolished" % type.id)
			check(Airport.can_place(type, origin, steps), "%s: cells free again" % type.id)
	# Pieces stay on the map.
	check(not Airport.can_place(type_of(&"road_country_straight"), Vector2i(-1, 5), 0), "no piece outside the map")


func test_pieces_do_not_change_what_the_airport_does() -> void:
	# The same airport with and without the landside layout: the simulation is the same.
	var without := _state_after(false)
	var with_pieces := _state_after(true)
	check_eq(with_pieces, without, "same simulation state with and without landside pieces")


# The saved state after a minute of play, without the landside buildings and the id counter.
func _state_after(with_landside: bool) -> String:
	Airport.reseed(321)
	ShowcaseAirport.build(60.0, Vector2i.ZERO, with_landside)
	sim_seconds(30)
	var state := Airport.save_state()
	var landside := _landside_pieces().map(func(t: BuildingType) -> String: return str(t.id))
	state["buildings"] = (state["buildings"] as Array).filter(func(entry: Dictionary) -> bool: return not landside.has(entry["type"]))
	state.erase("next_building_id")
	return BehaviourHash.canonical_json(state).sha256_text()


func test_showcase_has_the_whole_layout() -> void:
	ShowcaseAirport.build(0.0)
	check(ShowcaseLandside.failures.is_empty(), "every piece of the layout fits: %s" % [ShowcaseLandside.failures])
	var used: Dictionary[StringName, int] = {}
	for building in Airport.buildings:
		used[building.type.id] = used.get(building.type.id, 0) + 1
	for type in _landside_pieces():
		check(used.has(type.id), "showcase has a %s" % type.display_name)
	check(ShowcaseLandside.placed >= 400, "a real start layout, not a handful of pieces (%d)" % ShowcaseLandside.placed)
	# Where the layout meets the terminal: sidewalk in front of the entrance, nothing walked over.
	for building in Airport.buildings:
		var problem := Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps)
		check(problem.is_empty(), "%s connected: %s" % [building.type.display_name, problem])


func test_layout_is_on_the_landside_of_the_terminal() -> void:
	ShowcaseAirport.build(0.0)
	var entrance: Building = null
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.ENTRANCE:
			entrance = building
	for building in Airport.buildings:
		if building.type.category == "Landside" and not building.type.sub_category.is_empty():
			check(building.get_rect().end.y <= entrance.origin_cell.y, "%s lies north of the terminal" % building.type.id)
			for cell in building.get_cells():
				check_eq(Airport.grid.get_zone(cell), AirportGrid.Zone.LANDSIDE, "%s stands on landside ground" % building.type.id)
				break


func test_place_a_piece_from_the_build_menu() -> void:
	await start_game()
	await open_build_view()
	check(await place("Country road", at(Vector2i(20, 12)), 1), "a road placed rotated, from Landside > Roads")
	check(await place("Bollard", at(Vector2i(30, 12))), "a bollard placed from Landside > Props")
	var row := ui("BuildMenu/BuildingButtons")
	await press(_menu_button(row, "‹"))
	var texts: Array = row.get_children().filter(func(b: Node) -> bool: return not b.is_queued_for_deletion()).map(func(b: Node) -> String: return (b as Button).text)
	check(texts.has("Roads ›") and texts.has("Props ›") and texts.has("Car park"), "Landside lists its sub-categories and the car park: %s" % [texts])
	await close_build_view()


# --- Visuals (.glb models, MultiMesh, visibility ranges) ---

# Pieces that are too small for a stand-in model: hidden in the build view instead.
const NO_STAND_IN: Array[StringName] = [&"bollard", &"light_mast", &"fence_post", &"carpark_info_board", &"sign_parking", &"pay_station", &"sign_wayfinding"]


func test_every_model_fits_its_footprint() -> void:
	var cell := Airport.grid.cell_size
	for type in _landside_pieces():
		check(type.model != null, "%s has a model" % type.id)
		if type.model == null:
			continue
		var half := Vector2(type.footprint) * cell * 0.5
		var has_far := false
		for part: LandsideLayer.Part in LandsideLayer.parts_of(type.model):
			var box := part.local * part.mesh.get_aabb()
			# Props may stick out a little (lamp arms, signs, crowns); roads and sidewalks must not.
			var slack := 2.0 if type.id == &"tree_deciduous" else (0.3 if type.sub_category == "Props" else 0.15)
			check(absf(box.position.x) <= half.x + slack and absf(box.end.x) <= half.x + slack, "%s: %s fits the footprint in x (%.2f..%.2f of %.2f)" % [type.id, part.mesh.resource_name, box.position.x, box.end.x, half.x])
			check(absf(box.position.z) <= half.y + slack and absf(box.end.z) <= half.y + slack, "%s: %s fits the footprint in z (%.2f..%.2f of %.2f)" % [type.id, part.mesh.resource_name, box.position.z, box.end.z, half.y])
			has_far = has_far or part.kind == LandsideLayer.Kind.FAR
		check_eq(has_far, not NO_STAND_IN.has(type.id), "%s: a stand-in for the build view unless it is a small prop" % type.id)


func _landside_layer() -> LandsideLayer:
	return main.get_node("Landside") as LandsideLayer


func _showcase_layer() -> LandsideLayer:
	ShowcaseAirport.build(0.0)
	await start_game()
	var layer := _landside_layer()
	layer.flush()
	return layer


func test_pieces_are_multimeshes_not_a_node_each() -> void:
	var layer := await _showcase_layer()
	var trees := 0
	var tree_nodes := 0
	for building in Airport.buildings:
		if building.type.id == &"tree_deciduous":
			trees += 1
	for node in layer.multimesh_nodes():
		if String(node.name).begins_with("tree_deciduous_0_"):
			tree_nodes += 1
			trees -= node.multimesh.instance_count
	check_eq(trees, 0, "every tree is an instance of the tree MultiMesh")
	check(tree_nodes >= 1, "trees are drawn")
	check_eq(layer.find_children("*", "MeshInstance3D", true, false).size(), 0, "no single mesh nodes: it is all MultiMesh")
	# A fence of dozens of panels is one MultiMesh per area, not a node per panel.
	check(layer.multimesh_nodes().size() < 400, "few nodes for %d pieces (%d)" % [ShowcaseLandside.placed, layer.multimesh_nodes().size()])
	await cleanup()


func test_markings_and_flat_pieces_cast_no_shadow() -> void:
	var layer := await _showcase_layer()
	var markings := 0
	for node in layer.multimesh_nodes():
		var name := String(node.name)
		if node.get_meta(LandsideLayer.KIND_META) != LandsideLayer.Kind.MAIN:
			markings += 1
			check_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % name)
		if name.begins_with("road_") or name.begins_with("sidewalk_") or name.begins_with("curb_"):
			var box := node.multimesh.mesh.get_aabb()
			if box.end.y < LandsideLayer.FLAT_HEIGHT_M:
				check_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: flat, casts no shadow" % name)
	check(markings > 5, "paint and wear are drawn (%d groups)" % markings)
	var bollard_shadows := layer.multimesh_nodes().filter(func(n: MultiMeshInstance3D) -> bool: return String(n.name).begins_with("bollard_0") and n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	check(not bollard_shadows.is_empty(), "things that stand up do cast shadows")
	await cleanup()


func test_stand_ins_for_the_build_view_full_models_for_the_manager() -> void:
	var layer := await _showcase_layer()
	var near_bit := 1 << (LandsideLayer.NEAR_LAYER - 1)
	var far_bit := 1 << (LandsideLayer.FAR_LAYER - 1)
	var build_far := 0
	var manager_far := 0
	for node in layer.multimesh_nodes():
		var name := String(node.name)
		var kind: LandsideLayer.Kind = node.get_meta(LandsideLayer.KIND_META)
		if kind == LandsideLayer.Kind.FAR and node.layers == far_bit:
			build_far += 1
			check_eq(node.visibility_range_begin, 0.0, "%s: the build view's stand-in has no distance limit (its camera is orthographic)" % name)
			check_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: a stand-in casts no shadow" % name)
		else:
			check_eq(node.layers, near_bit, "%s: full detail and the manager's copy are on the near layer" % name)
		if kind == LandsideLayer.Kind.FAR and node.layers == near_bit:
			manager_far += 1
			check_eq(node.visibility_range_begin, LandsideLayer.FENCE_END_M if name.begins_with("fence") else LandsideLayer.LOD_FAR_M, "%s: takes over where the full model ends" % name)
		if name.begins_with("fence_panel_2m_0_"):
			check_eq(node.visibility_range_end, LandsideLayer.FENCE_END_M, "fence panels end at about 60 m")
			check_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF, "and fade out")
			check(node.visibility_range_end_margin > 0.0, "over a margin")
		if name.begins_with("bollard_"):
			check_eq(node.layers, near_bit, "a bollard has no stand-in: hidden in the build view")
			check(node.visibility_range_end > 0.0 and node.visibility_range_end <= 100.0, "and hidden far away in the manager view")
	check(build_far > 10, "the build view has stand-ins to show (%d)" % build_far)
	check(manager_far > 10, "the manager view has them beyond the full models (%d)" % manager_far)
	# Each camera draws one set.
	check(not build_camera().get_cull_mask_value(LandsideLayer.NEAR_LAYER), "the build camera does not draw full models")
	check(build_camera().get_cull_mask_value(LandsideLayer.FAR_LAYER), "the build camera draws stand-ins")
	check(not manager_camera().get_cull_mask_value(LandsideLayer.FAR_LAYER), "the manager camera does not draw the build view's stand-ins")
	check(manager_camera().get_cull_mask_value(LandsideLayer.NEAR_LAYER), "the manager camera draws full models")
	await cleanup()


func test_fence_mesh_is_alpha_scissor_with_alpha_to_coverage() -> void:
	var fence := type_of(&"fence_panel_2m")
	var cut_out := false
	for part: LandsideLayer.Part in LandsideLayer.parts_of(fence.model):
		for surface in part.mesh.get_surface_count():
			var material := part.mesh.surface_get_material(surface) as BaseMaterial3D
			if part.kind == LandsideLayer.Kind.MAIN and material.albedo_texture != null:
				cut_out = true
				check_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "fence mesh: alpha scissor")
				check_eq(material.alpha_antialiasing_mode, BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE, "fence mesh: alpha to coverage")
	check(cut_out, "the fence has a wire mesh")


func test_removing_a_piece_removes_its_drawing() -> void:
	await start_game()
	var layer := _landside_layer()
	Airport.economy.balance = 1.0e6
	var tree := Airport.place_building(type_of(&"tree_deciduous"), at(Vector2i(20, 12)), 0)
	layer.flush()
	var drawn := layer.multimesh_nodes().filter(func(n: MultiMeshInstance3D) -> bool: return n.visible).size()
	check(drawn >= 1, "the tree is drawn")
	check(Airport.demolish(tree), "demolished")
	layer.flush()
	check_eq(layer.multimesh_nodes().filter(func(n: MultiMeshInstance3D) -> bool: return n.visible).size(), 0, "nothing of it is left")
	await cleanup()
