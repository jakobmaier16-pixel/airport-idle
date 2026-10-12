extends TestCase
## Renders standard screenshots of the reference airport into build/screenshots/.
## Run with tools/screenshots.sh (needs a window, not headless).

const OUT_DIR: String = "res://build/screenshots/"


func _ready() -> void:
	# Let the scene tree finish starting up before adding the game to it.
	await get_tree().process_frame
	Airport.set_process(false)
	build_reference_airport()
	sim_seconds(90)
	await start_game()

	await _shot("manager_view")
	manager_camera().distance = manager_camera().max_distance
	await _shot("manager_view_zoomed_out")

	await open_build_view()
	build_camera().center_on(Airport.grid.cell_to_world(Vector2i(32, 30)))
	await _shot("build_view")
	await show_whole_map()
	await _shot("build_view_whole_map")

	build_camera().center_on(Airport.grid.cell_to_world(Vector2i(32, 30)))
	await press(ui("BuildMenu/BuildingButtons").get_child(2))  # Security, in an invalid spot
	build_mode()._set_preview_origin(Vector2i(44, 24))
	await _shot("placing_invalid")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await frames(20)
	var path := ProjectSettings.globalize_path(OUT_DIR + file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved " + path)
