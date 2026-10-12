extends TestCase
## End-to-end walkthrough: builds a complete airport only through the touch UI, like a player,
## then checks that passengers flow and depart. If this passes, the core loop works.


func test_build_airport_by_touch_and_fly_passengers() -> void:
	await start_game()
	await open_build_view()
	await show_whole_map()

	await paint("AirsideButton", Vector2i(8, 31), Vector2i(56, 55))
	await paint("WalkwayButton", Vector2i(18, 21), Vector2i(45, 27))
	await paint("WalkwayButton", Vector2i(10, 31), Vector2i(53, 33))

	check(await place("Entrance", Vector2i(30, 19)), "entrance")
	check(await place("Check-in", Vector2i(20, 22), 2), "check-in 1 (facing the hall)")
	check(await place("Check-in", Vector2i(39, 22), 2), "check-in 2")
	check(await place("Security", Vector2i(30, 28)), "security on the border")
	check(await place("Gate", Vector2i(14, 34)), "gate 1")
	check(await place("Gate", Vector2i(42, 34)), "gate 2")
	check(await place("Stand", Vector2i(10, 39)), "stand 1")
	check(await place("Stand", Vector2i(38, 39)), "stand 2")

	check_eq(Airport.buildings.size(), 8, "all buildings placed")
	var layer := main.get_node("Buildings")
	var unconnected: Array = layer._hints.values().filter(func(l: Label3D) -> bool: return l.visible)
	check_eq(unconnected.size(), 0, "every building connected")
	check(Airport.passenger_flow.route_problem.is_empty(), "complete route: %s" % Airport.passenger_flow.route_problem)

	# Two flights depart within 5 minutes (at 3:30 and 4:15).
	sim_seconds(300)
	await frames(2)
	check(Airport.passenger_flow.departed_count > 15, "passengers departed: %d" % Airport.passenger_flow.departed_count)
	check(main.get_node("Planes").plane_count() > 0, "the next planes are at their stands")
	var status := (ui("InfoPanel/StatusLabel") as Label).text
	check(status.begins_with("Passengers:"), "status shows passenger numbers: '%s'" % status)

	await close_build_view()
	check(manager_camera().current, "back to the manager view with a working airport")

	# Manage a station: tap security and upgrade it to a third lane.
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SECURITY)[0]
	manager().global_position = Airport.grid.cell_to_world(Vector2i(32, 33))
	manager_camera().snap_to_target()
	await physics_frames(2)
	tap(manager_camera().unproject_position(Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 1.5, 0.0)))
	await frames(1)
	await press(ui("StationPanel/Content/UpgradeButton"))
	check_eq(security.service_slots(), 3, "security upgraded to 3 lanes through the panel")
