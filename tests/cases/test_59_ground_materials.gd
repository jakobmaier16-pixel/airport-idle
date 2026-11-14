extends TestCase
## Ground materials: surface bits for stands / runways, the build-view-only zone overlay, one draw call.

const TYPE_FREE_SPOT := Vector2i(40, 10)


func _ground() -> Ground:
	return main.get_node("Ground") as Ground


func _material() -> ShaderMaterial:
	return (main.get_node("Ground/MeshInstance3D") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial


func test_stand_and_runway_set_and_clear_surface_bits() -> void:
	Airport.reset(true)
	await start_game()
	var grid := Airport.grid
	var runway: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.RUNWAY)[0]
	var rect := runway.get_rect()
	check_eq(grid.get_surface(rect.position), AirportGrid.SURFACE_RUNWAY, "the runway's first cell is runway asphalt")
	check_eq(grid.get_surface(rect.end - Vector2i.ONE), AirportGrid.SURFACE_RUNWAY, "and its last cell")
	check_eq(grid.get_surface(rect.position - Vector2i.ONE), 0, "outside it nothing")

	var stand_type := type_of(&"aircraft_stand")
	var stand := Airport.place_building(stand_type, TYPE_FREE_SPOT, 1, false)
	check(stand != null, "a stand can be placed")
	var area := stand.get_rect()
	check_eq(area.size, Vector2i(stand_type.footprint.y, stand_type.footprint.x), "rotation swaps the rectangle")
	var concrete := 0
	for y in range(area.position.y - 1, area.end.y + 1):
		for x in range(area.position.x - 1, area.end.x + 1):
			if grid.get_surface(Vector2i(x, y)) == AirportGrid.SURFACE_CONCRETE:
				concrete += 1
	check_eq(concrete, area.size.x * area.size.y, "exactly the footprint is concrete")
	var shop := Airport.place_building(type_of(&"check_in"), Vector2i(10, 10), 0, false)
	check(shop != null and grid.get_surface(shop.origin_cell) == 0, "other buildings lay no surface")

	await frames(1)
	var flags := _ground().get_flag_texture()
	check_eq(flags.image.get_pixel(area.position.x, area.position.y).r8 & AirportGrid.SURFACE_MASK, AirportGrid.SURFACE_CONCRETE, "the texture has the surface bit")

	check(Airport.demolish(stand), "the stand can be demolished")
	check_eq(grid.get_surface(area.position), 0, "the surface is gone with it")
	check_eq(grid.get_surface(runway.origin_cell), AirportGrid.SURFACE_RUNWAY, "the runway keeps its surface")
	await frames(1)
	check_eq(flags.image.get_pixel(area.position.x, area.position.y).r8, 0, "and out of the texture")


func test_surface_is_rebuilt_on_load_and_not_saved() -> void:
	await start_game()
	var stand := Airport.place_building(type_of(&"aircraft_stand"), TYPE_FREE_SPOT, 0, false)
	check(stand != null, "stand placed")
	var state := Airport.save_state()
	var again := Airport.load_state(state)
	check(again >= 0, "the state loads")
	check_eq(Airport.grid.get_surface(TYPE_FREE_SPOT), AirportGrid.SURFACE_CONCRETE, "the load places the stand again, with its surface")
	check(not var_to_str(state).contains("surface"), "the surface is derived, not part of the save")


func test_zone_overlay_is_build_view_only() -> void:
	await start_game()
	var material := _material()
	check_eq(material.get_shader_parameter(&"zone_overlay"), 0.0, "off in the manager view")
	check_eq(material.get_shader_parameter(&"show_grid"), 0.0, "no grid in the manager view")
	check(not ui("BuildMenu").visible, "no build menu, so no toggle, in the manager view")
	await open_build_view()
	check_eq(material.get_shader_parameter(&"show_grid"), 1.0, "grid in the build view")
	check_eq(material.get_shader_parameter(&"zone_overlay"), 0.0, "the overlay starts off")
	var toggle := ui("BuildMenu/PaintButtons/ZonesButton") as Button
	check(toggle.is_visible_in_tree(), "the toggle is in the build menu")
	await press(toggle)
	check_eq(material.get_shader_parameter(&"zone_overlay"), 1.0, "the toggle switches the overlay on")
	await close_build_view()
	check_eq(material.get_shader_parameter(&"zone_overlay"), 0.0, "back in the manager view it is off again")
	await open_build_view()
	check_eq(material.get_shader_parameter(&"zone_overlay"), 1.0, "the choice is remembered in the build view")
	await press(toggle)
	check_eq(material.get_shader_parameter(&"zone_overlay"), 0.0, "and the toggle switches it off")


func test_shader_has_the_materials() -> void:
	await start_game()
	var material := _material()
	for name: StringName in [&"grass_tex", &"asphalt_tex", &"concrete_tex", &"paving_tex", &"markings_tex"]:
		check(material.get_shader_parameter(name) is Texture2D, "%s is set" % name)
	check_eq((material.get_shader_parameter(&"markings_tex") as Texture2D).get_size(), Vector2(1024, 1024), "the markings atlas")
	check(material.get_shader_parameter(&"flag_map") != null, "the flag map is set")


func test_ground_is_one_draw_call() -> void:
	await start_game()
	var ground := _ground()
	var map_meshes := 0
	for child in ground.get_children():
		if child is GeometryInstance3D and child.name != &"Surroundings":
			map_meshes += 1
	check_eq(map_meshes, 1, "the map ground is one mesh instance")
	var mesh := (ground.get_node("MeshInstance3D") as MeshInstance3D).mesh
	check_eq(mesh.get_surface_count(), 1, "with one surface (one material)")
	check_eq(ground.get_node("MeshInstance3D").get_child_count(), 0, "no per-material child meshes")
	# Markings are painted by the shader: nothing is spawned for taxiway lines or stand edges.
	var before := ground.get_child_count()
	var cells: Array[Vector2i] = []
	for x in range(30, 40):
		cells.append(Vector2i(x, 90))
	Airport.paint_taxiway(cells, true)
	await frames(2)
	check_eq(ground.get_child_count(), before, "painting a taxiway adds no nodes")
