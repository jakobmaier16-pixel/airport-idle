extends TestCase
## Renders standard screenshots of the reference airport into build/screenshots/.
## Run with tools/screenshots.sh (needs a window, not headless).

const OUT_DIR: String = "res://build/screenshots/"


func _ready() -> void:
	# Let the scene tree finish starting up before adding the game to it.
	await get_tree().process_frame
	Airport.set_process(false)
	if "--world-shots" in OS.get_cmdline_user_args():
		await _world_shots()
		get_tree().quit()
		return
	ShowcaseAirport.build()  # exactly what the player sees after an update
	await start_game()

	await _shot("manager_view")
	# First person in the landside hall, looking at check-in 1 (design doc §15).
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(31, 25)))
	manager_camera().face(Airport.grid.cell_to_world(at(Vector2i(22, 23))) + Vector3.UP * 1.5)
	await _shot("manager_view_hall")
	await _landside_shots()
	if "--landside-only" in OS.get_cmdline_user_args() and "--realism" not in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	hud().get_node("SafeArea/NoticeBox/NoticePanel").visible = false

	# South of gate 1's stand, looking across the plane to the gate, while it boards (first departure at 210 s, boarding from 120 s).
	sim_seconds(170 if "--realism" in OS.get_cmdline_user_args() else 60)  # realism: the plane is at its stand
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(16, 70)))
	manager_camera().face(Airport.grid.block_center(at(Vector2i(6, 39)), Vector2i(20, 23)) + Vector3.UP * 2.0)
	if "--realism" in OS.get_cmdline_user_args():
		# Realism pass: stand 45 m from the first plane on an apron and look at it.
		await frames(3)
		var planes := get_tree().root.find_child("Planes", true, false)
		var stand_spot := Airport.grid.block_center(at(Vector2i(6, 39)), Vector2i(20, 23))
		var best: Node3D = null
		for child in planes.get_children():
			if child is Node3D and (best == null or (child as Node3D).global_position.distance_to(stand_spot) < best.global_position.distance_to(stand_spot)):
				best = child
		if best != null:
			manager().global_position = best.global_position + Vector3(30.0, 0.0, 40.0)
			manager_camera().face(best.global_position + Vector3.UP * 3.0)
	await _shot("manager_at_gate_boarding")
	if "--realism" in OS.get_cmdline_user_args():
		await open_build_view()
		build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 30))))
		await _shot("build_view")
		get_tree().quit()
		return

	# The long-haul plane at the wide-body stand behind gate 3 (design doc §10.2).
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(43, 84)))
	manager_camera().face(Airport.grid.block_center(at(Vector2i(26, 39)), Vector2i(35, 40)) + Vector3.UP * 3.0)
	await _shot("wide_body_plane")

	# Station panel: security seen from the airside walkway.
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(32, 33)))
	manager_camera().face(Airport.grid.block_center(at(Vector2i(30, 28)), Vector2i(5, 3)) + Vector3.UP * 1.5)
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SECURITY)[0]
	hud().show_station(security)
	await _shot("station_panel")
	hud().hide_station()

	await open_build_view()
	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 30))))
	await _shot("build_view")
	await show_whole_map()
	await _shot("build_view_whole_map")
	# Fully zoomed out: the whole 4.4 x 3.2 km map, shadows off.
	build_camera().view_height = 1.0e6
	build_camera().center_on(Vector3.ZERO)
	await _shot("build_view_zoomed_out")
	await show_whole_map()
	# A plane taxiing in from the runway, and one taking off (design doc §7.5a).
	for i in 3000:
		var taxiing := Airport.schedule.flights.any(func(f: Flight) -> bool:
			var left := f.departs_at() - Airport.sim_time
			var route := Airport.schedule.route_of(f)
			return f.phase == Flight.Phase.ARRIVING and route != null \
				and left < FlightSchedule.lead_of(route) - route.roll_in_time - 3.0)
		if taxiing:
			break
		Airport.step(Airport.SIM_STEP)
	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 52))))
	await _shot("plane_taxiing")
	for i in 3000:
		var leaving := Airport.schedule.flights.any(func(f: Flight) -> bool:
			return f.phase == Flight.Phase.DEPARTING and Airport.sim_time - f.departs_at() > 11.0)
		if leaving:
			break
		Airport.step(Airport.SIM_STEP)
	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 52))))
	await _shot("plane_taking_off")
	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 30))))
	await pick_building("Security")  # Security, in an invalid spot
	build_mode()._set_preview_origin(at(Vector2i(44, 24)))
	await _shot("placing_invalid")
	await press(ui("ToolPanel/ToolBar/CancelButton"))

	# Demolish tool with a check-in selected.
	await press(ui("BuildMenu/PaintButtons/DemolishToolButton"))
	var check_in: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.CHECK_IN)[0]
	tap(screen_of_cell(check_in.origin_cell + Vector2i(1, 1)))
	await _shot("demolish_selected")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await frames(20)
	var path := ProjectSettings.globalize_path(OUT_DIR + file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved " + path)


## The landside start layout (art/landside/landside_preview.py) from the build view and at eye level.
## The layout is turned by 180 degrees against the preview (ShowcaseLandside): preview (x, y) metres
## is the reference cell (54 - x / 2, -18 + y / 2).
func _landside_shots() -> void:
	var layout := func(x: float, y: float) -> Vector2i:
		return at(Vector2i(roundi(ShowcaseLandside.ORIGIN_X - x / 2.0), roundi(ShowcaseLandside.ORIGIN_Z + y / 2.0)))
	# Eye level on the terminal sidewalk, looking east along the curb (bollards, zebra, bus bay).
	manager().global_position = Airport.grid.cell_to_world(layout.call(30.0, 70.0))
	manager_camera().face(Airport.grid.cell_to_world(layout.call(100.0, 66.0)) + Vector3.UP * 1.5)
	await _shot("landside_curb")
	# At the car park gate, looking into the car park.
	manager().global_position = Airport.grid.cell_to_world(layout.call(3.0, 46.0))
	manager_camera().face(Airport.grid.cell_to_world(layout.call(60.0, 36.0)) + Vector3.UP * 1.0)
	await _shot("landside_carpark")
	# Fence seen from outside, close (6 m) and far (30 m), and the hedge row (realism pass).
	manager().global_position = Airport.grid.cell_to_world(layout.call(8.0, 30.0))
	manager_camera().face(Airport.grid.cell_to_world(layout.call(30.0, 36.0)) + Vector3.UP * 1.3)
	await _shot("landside_fence_near")
	manager().global_position = Airport.grid.cell_to_world(layout.call(-12.0, 20.0))
	manager_camera().face(Airport.grid.cell_to_world(layout.call(40.0, 40.0)) + Vector3.UP * 1.0)
	await _shot("landside_fence_far")
	await open_build_view()
	build_camera().view_height = 200.0
	build_camera().center_on(Airport.grid.cell_to_world(layout.call(72.0, 40.0)))
	await _shot("landside_build_view")
	await close_build_view()


## The test worlds (scripts/dev/worlds/): the world list and the asset viewer's items, with the notch of an
## iPhone 13 Pro simulated (landscape: about 59 pt at the sides and 21 pt at the bottom, 1.85 px per pt).
## Pass `--item=<id>` (and `--eye`) to shoot one item only.
func _world_shots() -> void:
	TestWorlds.reload = func() -> void: pass
	await start_game()
	_simulate_notch()
	hud().open_world_list()
	await _shot("world_list")
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--item="):
			only = arg.trim_prefix("--item=")
	await enter_world(TestWorlds.ASSET_VIEWER)
	_simulate_notch()
	var viewer := main.get_node("AssetViewer") as AssetViewer
	(hud().get_node("WorldInfo") as WorldInfo).open(TestWorlds.current())
	await _shot("world_info")
	(hud().get_node("WorldInfo") as WorldInfo).close_panel()
	var camera := main.get_node("ViewerCamera") as ViewerCamera
	# [file, item id, eye level]
	var shots: Array = [
		["viewer_prop_person", &"pay_station", false],
		["viewer_road_piece", &"curb_dropoff_segment", false],
		["viewer_tree", &"tree_deciduous", false],
		["viewer_stand", &"aircraft_stand", false],
		["viewer_plane_eye_level", &"plane_narrow", true],
		["viewer_swatch_paving", &"swatch_paving", false],
		["viewer_terminal_facade", &"terminal_facade_glass", false],
		["viewer_runway", &"runway", false],
		["viewer_taxiway", &"ground_taxiway", false],
	]
	for shot: Array in shots:
		if not only.is_empty() and only != str(shot[1]):
			continue
		for i in viewer.items.size():
			if viewer.items[i].id == shot[1]:
				viewer.show_item(i)
		if shot[2]:
			camera.go_eye_level()
		await _shot(shot[0])


# Margins like the iPhone 13 Pro in landscape (the notch side, the home indicator) on the HUD.
func _simulate_notch() -> void:
	for area in hud().find_children("*", "SafeAreaContainer", true, false) + [hud().get_node("SafeArea")]:
		area.add_theme_constant_override(&"margin_left", 16 + 109)
		area.add_theme_constant_override(&"margin_right", 16 + 109)
		area.add_theme_constant_override(&"margin_bottom", 16 + 39)
