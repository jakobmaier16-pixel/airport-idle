extends TestCase
## The placeholder plane stands on the ground: the lowest point of its meshes (the wheels) is at
## ground height for both plane classes, and planes on the ground are drawn at ground height.


func _lowest_y(plane: PlaneVisual) -> float:
	var lowest := INF
	for child in plane.get_children():
		if child is MeshInstance3D:
			var box := (child as MeshInstance3D).mesh.get_aabb()
			var xf := plane.global_transform * (child as MeshInstance3D).transform
			for i in 8:
				lowest = minf(lowest, (xf * box.get_endpoint(i)).y)
	return lowest


func test_wheels_touch_the_ground_for_both_classes() -> void:
	await start_game()
	for wide in [false, true]:
		var plane := PlaneVisual.new()
		plane.wide_body = wide
		plane.size_factor = (65.0 if wide else 37.0) / PlaneVisual.WINGSPAN
		main.add_child(plane)
		await frames(1)
		check(absf(_lowest_y(plane)) < 0.05, "lowest point on the ground (wide=%s): %f" % [wide, _lowest_y(plane)])


func test_planes_on_the_ground_are_at_ground_height() -> void:
	await start_game()
	ShowcaseAirport.build(0.0)
	var layer := main.get_node("Planes") as PlaneLayer
	var grounded := 0
	for i in 15000:
		Airport.step(Airport.SIM_STEP)
		if i % 10 != 0:
			continue
		await frames(1)
		for plane in layer._planes.values():
			var p := plane as PlaneVisual
			# Airborne planes (approach, climb) are higher; every other one must stand on the ground.
			if p.position.y < 0.01:
				grounded += 1
				check(absf(_lowest_y(p)) < 0.05, "grounded plane stands on the ground: %f" % _lowest_y(p))
	check(grounded > 0, "saw planes on the ground")
