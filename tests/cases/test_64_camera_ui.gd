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
	TouchGestures.pinch_center = screen_size() * Vector2(0.8, 0.8)
	var before := _ground_at(TouchGestures.pinch_center)
	camera._on_pinched(1.0 / 1.5)
	var after := _ground_at(TouchGestures.pinch_center)
	check(Vector2(after.x - before.x, after.z - before.z).length() < 0.5, "wheel zoom keeps the point under the mouse")


func test_farthest_zoom_never_shows_void() -> void:
	await start_game()
	await open_build_view()
	var camera := build_camera()
	wheel(false, 120)
	var map := Airport.grid.get_world_rect()
	var half := Vector2(camera.size * screen_size().x / screen_size().y, camera.size) * 0.5
	check(half.x * 2.0 <= map.size.x + 0.01 and half.y * 2.0 <= map.size.y + 0.01, "the farthest view fits in the map (%s)" % [half * 2.0])
	# Off-centre before zooming out: no forced jump to the middle while the view fits.
	camera.view_height = 120.0
	camera.center_on(Vector3(map.position.x + 300.0, 0.0, map.position.y + 300.0))
	var start := camera.position
	camera._on_pinched(0.9)
	check(Vector2(camera.position.x - start.x, camera.position.z - start.z).length() < 40.0, "zooming out a little does not pull to the centre")


func test_landside_piece_does_not_move_the_camera() -> void:
	await start_game()
	await open_build_view()
	var spot := Airport.grid.cell_to_world(at(Vector2i(10, 12)))
	var camera := build_camera()
	camera.view_height = 100.0
	camera.center_on(spot)
	await frames(1)
	var start := camera.position
	check(await pick_building("Sidewalk"), "picked a landside piece from Build > Landside")
	await frames(2)
	check(camera.position.distance_to(start) < 0.01, "the camera stays where it was (%s -> %s)" % [start, camera.position])
	var preview := build_mode()._preview
	check(preview != null, "a preview exists")
	if preview != null:
		var offset := Vector2(preview.position.x - start.x, preview.position.z - start.z)
		check(offset.length() < 20.0, "the preview is under the view centre (%s m away)" % offset.length())


func test_gate_hint_is_information() -> void:
	await start_game()
	await open_build_view()
	var hint := ui("ToolPanel/HintLabel") as Label
	await pick_building("Gate")
	build_mode()._set_preview_origin(at(Vector2i(10, 10)))
	var place_button := ui("ToolPanel/ToolBar/PlaceButton") as Button
	check(not place_button.disabled, "a gate can be placed anywhere")
	check(hint.text.begins_with("Gate works once"), "hint reads as information: '%s'" % hint.text)
	check(not hint.text.contains("Needs"), "no error wording")
	check_eq(hint.get_theme_color(&"font_color"), Hud.HINT_INFO_COLOR, "info colour")
	await press(place_button)
	await frames(1)
	var layer := main.get_node("Buildings")
	var markers: Array[String] = []
	for label: Label3D in layer._hints.values():
		if label.visible:
			markers.append(label.text)
	check(markers.has("No walkway in front") or markers.has("No stand"), "the placed gate shows a marker: %s" % [markers])


func test_taxiway_button_says_plane_taxiway() -> void:
	await start_game()
	await open_build_view()
	check_eq((ui("BuildMenu/PaintButtons/TaxiwayButton") as Button).text, "Plane taxiway", "button label")
