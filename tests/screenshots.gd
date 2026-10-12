extends TestCase
## Renders standard screenshots of the reference airport into build/screenshots/.
## Run with tools/screenshots.sh (needs a window, not headless).

const OUT_DIR: String = "res://build/screenshots/"


func _ready() -> void:
	# Let the scene tree finish starting up before adding the game to it.
	await get_tree().process_frame
	Airport.set_process(false)
	ShowcaseAirport.build()  # exactly what the player sees after an update
	await start_game()

	await _shot("manager_view")
	manager_camera().distance = manager_camera().max_distance
	await _shot("manager_view_zoomed_out")

	# South of gate 1's stand, looking across the plane to the gate, while it boards (first departure at 210 s, boarding from 120 s).
	sim_seconds(60)
	manager().global_position = Airport.grid.cell_to_world(Vector2i(16, 50))
	manager_camera().snap_to_target()
	await _shot("manager_at_gate_boarding")

	# Station panel: security seen from the airside walkway.
	manager().global_position = Airport.grid.cell_to_world(Vector2i(32, 33))
	manager_camera().snap_to_target()
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SECURITY)[0]
	hud().show_station(security)
	await _shot("station_panel")
	hud().hide_station()

	hud().show_stats()
	await _shot("stats_panel")
	hud().hide_stats()

	await open_build_view()
	build_camera().center_on(Airport.grid.cell_to_world(Vector2i(32, 30)))
	await _shot("build_view")
	await show_whole_map()
	await _shot("build_view_whole_map")

	build_camera().center_on(Airport.grid.cell_to_world(Vector2i(32, 30)))
	await pick_building("Security")  # Security, in an invalid spot
	build_mode()._set_preview_origin(Vector2i(44, 24))
	await _shot("placing_invalid")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await frames(20)
	var path := ProjectSettings.globalize_path(OUT_DIR + file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved " + path)
