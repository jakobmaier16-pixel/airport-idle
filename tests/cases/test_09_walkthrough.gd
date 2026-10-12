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

	sim_seconds(180)
	await frames(2)
	check(Airport.passenger_flow.departed_count > 20, "passengers departed: %d" % Airport.passenger_flow.departed_count)
	var status := (ui("StatusLabel") as Label).text
	check(status.begins_with("Passengers:"), "status shows passenger numbers: '%s'" % status)

	await close_build_view()
	check(manager_camera().current, "back to the manager view with a working airport")
