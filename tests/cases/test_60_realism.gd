extends TestCase
## Realism pass (technical causes of the "looks worse than the previews" report): the landside layer sits
## above the ground plane (no z-fighting), fence cut-outs survive mipmapping, hedges are not flat green,
## the outdoor environment is set up (tone mapping, fog, shadow range, sun angle).


func test_landside_layer_is_lifted_above_the_ground() -> void:
	await start_game()
	var layer := main.get_node("Landside") as LandsideLayer
	check(layer.position.y >= 0.01, "the landside layer is at least 1 cm above the ground plane (road and ground must not share a depth)")
	check(layer.position.y <= 0.05, "but not so far that it shows as a step")
	var ground := main.get_node("Ground") as Node3D
	check_eq(ground.position.y, 0.0, "the ground stays at 0 (planes, stands and the runway are on it)")


func test_fence_cutout_material_survives_mipmaps() -> void:
	var fence := load("res://assets/models/landside/fence_panel_2m.glb") as PackedScene
	var found := false
	for part: LandsideLayer.Part in LandsideLayer.parts_of(fence):
		if part.kind != LandsideLayer.Kind.MAIN:
			continue
		for surface in part.mesh.get_surface_count():
			var material := part.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == "markings_solid":
				found = true
				check_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "the fence is an alpha cut-out (writes depth)")
				check(material.alpha_scissor_threshold <= 0.35, "a low threshold: thin wires still pass in the lower mip levels")
				check_eq(material.alpha_antialiasing_mode, BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE, "alpha to coverage")
	check(found, "the fence mesh uses the markings_solid material")
	check(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d") >= 1, "MSAA is on: alpha to coverage does nothing without it")
	var texture_import := FileAccess.get_file_as_string("res://assets/textures/markings/markings_albedo.png.import")
	check(texture_import.contains("mipmaps/generate=true"), "the paint atlas has mipmaps")


func test_hedge_is_not_flat_green() -> void:
	var hedge := load("res://assets/models/landside/hedge_2m.glb") as PackedScene
	for part: LandsideLayer.Part in LandsideLayer.parts_of(hedge):
		if part.kind != LandsideLayer.Kind.MAIN:
			continue
		var material := part.mesh.surface_get_material(0) as BaseMaterial3D
		check(material != null and material.albedo_texture != null, "the hedge has a leaf texture")


func test_environment_is_outdoor_realistic() -> void:
	await start_game()
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	check_eq(environment.tonemap_mode, Environment.TONE_MAPPER_AGX, "AgX tone mapping")
	check(environment.fog_enabled and environment.fog_density > 0.0, "distance haze")
	check_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_SKY, "ambient light comes from the sky")
	var sun := main.get_node("Sun") as DirectionalLight3D
	var elevation := rad_to_deg(asin((sun.global_transform.basis.z).y))
	check(elevation > 33.0 and elevation < 47.0, "the sun is about 35-45 degrees above the horizon (is %.1f)" % elevation)
	check(sun.directional_shadow_max_distance >= 100.0, "shadows reach far enough for first person")
	check(sun.shadow_enabled, "the sun casts shadows")


func test_haze_only_in_manager_view() -> void:
	await start_game()
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	await open_build_view()
	check(not environment.fog_enabled, "no haze in the build view (it would grey the map out)")
	await close_build_view()
	check(environment.fog_enabled, "haze is back in the manager view")
