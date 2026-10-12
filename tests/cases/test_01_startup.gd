extends TestCase
## The game starts in a sensible state.


func test_starts_in_manager_view() -> void:
	await start_game()
	check(manager_camera().current, "manager camera is active")
	check(not build_camera().current, "build camera is not active")
	check_eq((ui("ViewButton") as Button).text, "Build", "view button text")
	check(not ui("BuildMenu").visible, "build menu hidden in manager view")
	check(not ui("ToolPanel").visible, "tool panel hidden in manager view")


func test_status_explains_missing_route() -> void:
	await start_game()
	await frames(1)
	var status := (ui("StatusLabel") as Label).text
	check(status.contains("build an entrance"), "status asks for an entrance: '%s'" % status)


func test_landscape_and_settings() -> void:
	check_eq(ProjectSettings.get_setting("display/window/handheld/orientation"), DisplayServer.SCREEN_SENSOR_LANDSCAPE, "landscape orientation")
	check(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc"), "ETC2/ASTC import for iOS")
	check_eq(InputMap.action_get_events(&"move_up").size(), 2, "move_up has W and Up arrow")


func test_map_matches_grid() -> void:
	await start_game()
	var ground := main.get_node("Ground") as Node3D
	var plane := (ground.get_node("MeshInstance3D") as MeshInstance3D).mesh as PlaneMesh
	check_eq(plane.size, Airport.grid.get_world_rect().size, "ground size follows the grid")
