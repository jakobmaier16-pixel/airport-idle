extends TestCase
## Build view fixes from the device test 2026-11-14: zoom about the fingers, no camera jump when
## choosing a landside piece, placement hints that are information and not errors.


# The ground point under a screen position, from the camera's own projection.
func _ground_at(screen: Vector2) -> Vector3:
	var camera := build_camera()
	var from := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, direction) as Vector3


func test_zoom_keeps_the_point_under_the_fingers() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	camera.view_height = 120.0
	camera.center_on(Vector3.ZERO)
	await frames(1)
	var pivot := screen_size() * Vector2(0.75, 0.3)
	var before := _ground_at(pivot)
	# Zoom out in steps around the off-centre point, until the clamp or the farthest zoom.
	for i in 6:
		pinch(pivot, 400.0, 250.0)
		await frames(1)
		var after := _ground_at(pivot)
		var gap := Vector2(after.x - before.x, after.z - before.z).length()
		var clamped := camera.size >= camera._largest_view_height() - 0.01
		if not clamped:
			check(gap < camera.size * 0.01, "step %d: the point under the fingers stays put (moved %.2f m)" % [i, gap])
		else:
			break
	# Zooming in around the same point keeps it too.
	var zoomed := _ground_at(pivot)
	pinch(pivot, 250.0, 400.0)
	await frames(1)
	var back := _ground_at(pivot)
	check(Vector2(back.x - zoomed.x, back.z - zoomed.z).length() < camera.size * 0.02 + 0.5, "zooming in keeps the point too")


func test_wheel_zooms_about_the_mouse() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	camera.view_height = 120.0
	camera.center_on(Vector3.ZERO)
	await frames(1)
	var mouse := screen_size() * Vector2(0.8, 0.8)
	var before := _ground_at(mouse)
	wheel(false, 5, mouse)
	check(camera.size > 120.0 * 1.4, "the wheel zoomed out (%.0f m)" % camera.size)
	var after := _ground_at(mouse)
	check(Vector2(after.x - before.x, after.z - before.z).length() < 0.5, "the point under the mouse stays put (moved %.2f m)" % Vector2(after.x - before.x, after.z - before.z).length())
	wheel(true, 3, mouse)
	var back := _ground_at(mouse)
	check(Vector2(back.x - before.x, back.z - before.z).length() < 0.5, "zooming in keeps it too")


func test_farthest_zoom_never_shows_void() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	TouchGestures.pinch_center = screen_size() * 0.5
	wheel(false, 120, screen_size() * 0.5)
	var map := Airport.grid.get_world_rect()
	var half := Vector2(camera.size * screen_size().x / screen_size().y, camera.size) * 0.5
	check(half.x * 2.0 <= map.size.x + 0.01 and half.y * 2.0 <= map.size.y + 0.01, "the farthest view fits in the map (%s)" % [half * 2.0])
	# Off-centre before zooming out: no forced jump to the middle while the view fits.
	camera.view_height = 120.0
	camera.center_on(Vector3(map.position.x + 300.0, 0.0, map.position.y + 300.0))
	var start := camera.position
	TouchGestures.pinch_center = screen_size() * 0.5
	camera._on_pinched(0.9)
	check(Vector2(camera.position.x - start.x, camera.position.z - start.z).length() < 40.0, "zooming out a little does not pull to the centre")


func test_landside_piece_does_not_move_the_camera() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	var map := Airport.grid.get_world_rect()
	var spots: Array[Vector3] = [
		Airport.grid.cell_to_world(at(Vector2i(10, 12))), Vector3.ZERO,
		Vector3(map.position.x + 200.0, 0.0, map.position.y + 200.0),
		Vector3(map.end.x - 200.0, 0.0, map.end.y - 200.0)]
	# 60 m, a normal view, and the farthest zoom (the suspected cause: the clamp centred the view).
	for height in [60.0, 250.0, 1.0e6]:
		for spot in spots:
			camera.view_height = height
			camera.center_on(spot)
			await frames(1)
			var start := camera.position
			var label := "zoom %.0f at %s" % [camera.size, spot]
			check(await pick_building("Sidewalk"), "%s: picked a landside piece from Build > Landside" % label)
			await frames(2)
			check(camera.position.distance_to(start) < 0.01, "%s: the camera stays (%s -> %s)" % [label, start, camera.position])
			var preview := build_mode()._preview
			check(preview != null, "%s: a preview exists" % label)
			if preview != null:
				var offset := Vector2(preview.position.x - start.x, preview.position.z - start.z)
				check(offset.length() < 20.0, "%s: the preview is under the view centre (%.1f m away)" % [label, offset.length()])
			await press(ui("ToolPanel/ToolBar/CancelButton"))


func test_gate_hint_is_information() -> void:
	await start_game()
	build_basic_terminal()  # a walkway reaches the gate's front, so only the stand is missing
	await open_build_view()
	await show_whole_map(0.0, Vector3.ZERO)
	var hint := ui("ToolPanel/HintLabel") as Label
	await pick_building("Gate")
	build_mode()._set_preview_origin(at(Vector2i(40, 34)))
	var place_button := ui("ToolPanel/ToolBar/PlaceButton") as Button
	check(not place_button.disabled, "a gate can be placed without a stand")
	check_eq(hint.text, "Gate works once a stand is behind it", "hint")
	check_eq(hint.get_theme_color(&"font_color"), Hud.HINT_INFO_COLOR, "info colour")
	await press(place_button)
	await frames(1)
	var gate: Building = Airport.buildings[-1]
	check_eq(gate.type.id, &"gate", "the gate was placed")
	var layer := main.get_node("Buildings")
	var label := layer._hints[gate] as Label3D
	check(label.visible, "the placed gate shows a marker")
	check_eq(label.text, "No stand", "marker text")


func test_taxiway_button_says_plane_taxiway() -> void:
	await start_game()
	await open_build_view()
	var button := ui("BuildMenu/PaintButtons/TaxiwayButton") as Button
	check_eq(button.text, "Plane taxiway", "button label")
	await press(button)
	check_eq(build_mode()._tool, BuildMode.Tool.PAINT, "tapping it starts the paint tool")
	check_eq(build_mode()._paint_kind, BuildMode.PaintKind.TAXIWAY, "...for taxiways")
