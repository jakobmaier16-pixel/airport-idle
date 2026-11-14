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
	# First person in the landside hall, looking at check-in 1 (design doc §15).
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(31, 25)))
	manager_camera().face(Airport.grid.cell_to_world(at(Vector2i(22, 23))) + Vector3.UP * 1.5)
	await _shot("manager_view_hall")
	# Night and evening light (design doc §12.1); back to the morning afterwards.
	var morning := Airport.clock.game_seconds
	Airport.clock.game_seconds = 23.0 * 3600.0
	await _shot("night")
	Airport.clock.game_seconds = 19.5 * 3600.0
	await _shot("evening")
	Airport.clock.game_seconds = morning
	hud().get_node("SafeArea/NoticeBox/NoticePanel").visible = false

	# South of gate 1's stand, looking across the plane to the gate, while it boards (first departure at 210 s, boarding from 120 s).
	sim_seconds(60)
	manager().global_position = Airport.grid.cell_to_world(at(Vector2i(16, 70)))
	manager_camera().face(Airport.grid.block_center(at(Vector2i(6, 39)), Vector2i(20, 23)) + Vector3.UP * 2.0)
	await _shot("manager_at_gate_boarding")

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

	hud().show_stats()
	await _shot("stats_panel")
	hud().show_stats_tab(Hud.StatsTab.MONEY)
	await _shot("stats_money")
	hud().show_stats_tab(Hud.StatsTab.AIRLINES)
	await _shot("stats_airlines")
	hud().show_stats_tab(Hud.StatsTab.STATIONS)
	hud().hide_stats()

	hud().show_airlines()
	await _shot("airlines_panel")
	hud().airlines_panel.negotiate(Airport.airlines.offers[0])
	await _shot("airlines_negotiation")
	hud().hide_airlines()

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
		var taxiing := Airport.passenger_flow.schedule.flights.any(func(f: Flight) -> bool:
			var left := f.departs_at() - Airport.passenger_flow.time
			return f.phase == Flight.Phase.ARRIVING and left < FlightSchedule.PLANE_ARRIVES - 7.0)
		if taxiing:
			break
		Airport.step(Airport.SIM_STEP)
	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 52))))
	await _shot("plane_taxiing")
	for i in 3000:
		var leaving := Airport.passenger_flow.schedule.flights.any(func(f: Flight) -> bool:
			return f.phase == Flight.Phase.DEPARTING and Airport.passenger_flow.time - f.departs_at() > 11.0)
		if leaving:
			break
		Airport.step(Airport.SIM_STEP)
	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 52))))
	await _shot("plane_taking_off")
	# A regional airport only owns the middle of the map (design doc §14.1).
	Airport.progression.tier = Progression.Tier.REGIONAL
	Airport.land_changed.emit()
	await _shot("build_view_regional_land")
	Airport.progression.tier = Progression.Tier.NATIONAL
	Airport.land_changed.emit()
	hud().show_milestone("National airport!", Progression.REWARDS[Progression.Tier.NATIONAL])
	await _shot("milestone")
	hud().get_node("SafeArea/MilestonePanel").visible = false

	build_camera().center_on(Airport.grid.cell_to_world(at(Vector2i(32, 30))))
	await pick_building("Security")  # Security, in an invalid spot
	build_mode()._set_preview_origin(at(Vector2i(44, 24)))
	await _shot("placing_invalid")
	await press(ui("ToolPanel/ToolBar/CancelButton"))

	# Demolish tool with the shop selected.
	await press(ui("BuildMenu/PaintButtons/DemolishToolButton"))
	var shop: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SHOP)[0]
	tap(screen_of_cell(shop.origin_cell + Vector2i(1, 1)))
	await _shot("demolish_selected")
	get_tree().quit()


func _shot(file_name: String) -> void:
	await frames(20)
	var path := ProjectSettings.globalize_path(OUT_DIR + file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved " + path)
