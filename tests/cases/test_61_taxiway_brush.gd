extends TestCase
## The taxiway tool drags out a rectangle from the start cell to the finger whose short side is 12 cells
## (24 m): what the preview shows is what is painted on release, a tap lays nothing, and nothing is
## painted over a building. (Remove still uses the older stamp that locks to one axis.)


func _bbox_of_taxiway() -> Rect2i:
	var found := false
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	var count := 0
	var area := Rect2i(Vector2i(at(Vector2i(0, 40))), Vector2i(200, 120))
	area.position = Vector2i(at(Vector2i(0, 40)).x - 10, at(Vector2i(0, 40)).y)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if Airport.grid.is_taxiway(Vector2i(x, y)):
				count += 1
				if not found:
					low = Vector2i(x, y)
					high = Vector2i(x + 1, y + 1)
					found = true
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x + 1), maxi(high.y, y + 1))
	var box := Rect2i(low, high - low)
	if found:
		check_eq(count, box.size.x * box.size.y, "the painted taxiway is one solid rectangle")
	return box if found else Rect2i()


func _taxiway_cells() -> int:
	var count := 0
	for y in range(at(Vector2i(0, 40)).y, at(Vector2i(0, 40)).y + 120):
		for x in range(at(Vector2i(0, 40)).x - 10, at(Vector2i(0, 40)).x + 190):
			if Airport.grid.is_taxiway(Vector2i(x, y)):
				count += 1
	return count


func _start() -> void:
	await start_game()
	await open_build_view()
	await show_whole_map(0.0, Vector3.ZERO)


func test_drag_paints_a_12_wide_strip() -> void:
	await _start()
	var a := at(Vector2i(20, 70))
	var b := at(Vector2i(40, 70))
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(a), screen_of_cell(b))
	var box := _bbox_of_taxiway()
	check_eq(box.size.y, 12, "12 cells wide across the strip")
	check_eq(box.size.x, 21, "from the start cell to the finger, both included")
	check_eq(box.position, a - Vector2i(0, 6), "starts at the start cell, centred on it across the strip")


func test_dragging_the_other_way_and_down() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var a := at(Vector2i(40, 70))
	drag(screen_of_cell(a), screen_of_cell(at(Vector2i(20, 70))))
	var box := _bbox_of_taxiway()
	check_eq(box, Rect2i(Vector2i(a.x - 20, a.y - 6), Vector2i(21, 12)), "left of the start cell")
	Airport.reset()
	await start_game()
	await open_build_view()
	await show_whole_map(0.0, Vector3.ZERO)
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var c := at(Vector2i(30, 50))
	drag(screen_of_cell(c), screen_of_cell(at(Vector2i(31, 62))))
	box = _bbox_of_taxiway()
	check_eq(box.size, Vector2i(12, 13), "a mostly vertical drag gives a vertical strip")
	check_eq(box.position, c - Vector2i(6, 0), "from the start cell down")


func test_a_diagonal_drag_follows_the_bigger_movement() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(at(Vector2i(20, 70))), screen_of_cell(at(Vector2i(40, 74))))
	var box := _bbox_of_taxiway()
	check_eq(box.size, Vector2i(21, 12), "the small y movement is ignored: the strip follows x")


func test_a_short_drag_is_one_12_by_12_stamp() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var a := at(Vector2i(20, 70))
	drag(screen_of_cell(a), screen_of_cell(at(Vector2i(22, 71))))
	check_eq(_bbox_of_taxiway(), Rect2i(a - Vector2i(0, 6), Vector2i(12, 12)), "under 12 cells: a stamp, extending towards the finger")


func test_what_the_preview_shows_is_what_is_painted() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var mode := build_mode()
	var start := screen_of_cell(at(Vector2i(20, 70)))
	touch(0, true, start)
	var last := Rect2i()
	# Slow, wobbly finger: the rectangle follows it without jumping (its size changes by what the finger moved).
	var previous := Rect2i()
	for i in range(1, 60):
		var finger := screen_of_cell(at(Vector2i(20 + i, 70 + (i % 3) - 1)))
		move(0, finger)
		last = mode._paint_rect
		if i > 1:
			check(absi(last.size.x - previous.size.x) <= 1 and last.position == previous.position, "no jump at step %d: %s -> %s" % [i, previous, last])
		previous = last
	check(mode._paint_preview.visible, "the preview is shown while dragging")
	touch(0, false, screen_of_cell(at(Vector2i(20 + 59, 70 + (59 % 3) - 1))))
	check_eq(_bbox_of_taxiway(), last, "painted exactly the last preview")
	check(not mode._paint_preview.visible, "preview is gone afterwards")


func test_a_tap_lays_nothing() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var cell := at(Vector2i(30, 70))
	tap(screen_of_cell(cell))
	check_eq(_taxiway_cells(), 0, "a tap paints nothing")
	await frames(1)
	check((ui("ToolPanel/HintLabel") as Label).text.begins_with("Drag to"), "the hint tells to drag")


func test_no_taxiway_over_a_building() -> void:
	await _start()
	# A landside piece in the way (a road) and a building.
	var road := Airport.place_building(type_of(&"road_country_straight"), at(Vector2i(30, 72)), 0)
	check(road != null, "a road piece is placed")
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var mode := build_mode()
	var a := at(Vector2i(20, 70))
	var start := screen_of_cell(a)
	touch(0, true, start)
	move(0, screen_of_cell(at(Vector2i(40, 70))))
	check_eq(mode._building_in(mode._paint_rect), road, "the drag covers the road")
	check_eq((mode._paint_material as StandardMaterial3D).albedo_color, mode.invalid_color, "the preview is red")
	touch(0, false, screen_of_cell(at(Vector2i(40, 70))))
	check_eq(_taxiway_cells(), 0, "nothing was painted")
	await frames(1)
	check((ui("ToolPanel/HintLabel") as Label).text.contains("over a building"), "and the player is told why")
	# A drag that misses the road paints.
	drag(screen_of_cell(at(Vector2i(20, 50))), screen_of_cell(at(Vector2i(40, 50))))
	check_eq(_taxiway_cells(), 21 * 12, "a free spot is painted")
	check((mode._paint_material as StandardMaterial3D).albedo_color == mode.taxiway_paint_color, "and its preview is not red")


func test_no_walkway_over_a_building() -> void:
	await _start()
	var road := Airport.place_building(type_of(&"road_country_straight"), at(Vector2i(30, 40)), 0)
	check(road != null, "a road piece is placed")
	await press(ui("BuildMenu/PaintButtons/WalkwayButton"))
	drag(screen_of_cell(at(Vector2i(25, 40))), screen_of_cell(at(Vector2i(35, 40))))
	check(not Airport.grid.is_walkway(at(Vector2i(25, 40))), "the whole rectangle is refused")
	await frames(1)
	check((ui("ToolPanel/HintLabel") as Label).text.contains("over a building"), "with a hint")
	drag(screen_of_cell(at(Vector2i(25, 36))), screen_of_cell(at(Vector2i(35, 36))))
	check(Airport.grid.is_walkway(at(Vector2i(30, 36))), "a free rectangle is painted")


func test_the_brain_leaves_out_cells_under_buildings() -> void:
	var road := Airport.place_building(type_of(&"road_country_straight"), at(Vector2i(30, 72)), 0)
	var cells_over := cells(at(Vector2i(20, 66)), Vector2i(30, 12))
	var hint := Airport.paint_taxiway(cells_over, true)
	check(hint.contains("over a building"), "a hint: %s" % hint)
	var painted := 0
	for cell in cells_over:
		if Airport.grid.is_taxiway(cell):
			painted += 1
			check(Airport.grid.is_empty(cell), "never under a building: %s" % cell)
	check(painted > 0 and painted < cells_over.size(), "the free cells were painted (%d of %d)" % [painted, cells_over.size()])
	check(road != null, "the road is still there")
	# Stands and runways have their own pavement too.
	var stand := Airport.place_building(type_of(&"aircraft_stand"), at(Vector2i(60, 40)), 0)
	check(stand != null, "a stand")
	check(Airport.paint_taxiway(cells(at(Vector2i(60, 40)), Vector2i(5, 5)), true).contains("over a building"), "not under a stand")
	check(not Airport.grid.is_taxiway(at(Vector2i(60, 40))), "no taxiway flag under the stand")


func test_remove_clears_a_12_wide_strip() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(at(Vector2i(20, 70))), screen_of_cell(at(Vector2i(50, 70))))
	check_eq(_taxiway_cells(), 12 * 31, "painted")
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	await press(ui("BuildMenu/PaintButtons/RemoveButton"))
	drag(screen_of_cell(at(Vector2i(30, 70))), screen_of_cell(at(Vector2i(36, 70))))
	check_eq(_taxiway_cells(), 12 * 31 - 12 * 18, "removed a 12 x 18 strip in the middle")
	check_eq(Airport.grid.is_taxiway(at(Vector2i(30, 70))), false, "centre removed")
	check_eq(Airport.grid.is_taxiway(at(Vector2i(20, 70))), true, "the ends stay")


func test_a_drag_cut_short_by_the_map_edge_is_refused() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var mode := build_mode()
	# Along the top edge of the map: the strip would be centred on row 3 and the map cuts it to 9 rows.
	var start_cell := Vector2i(Airport.grid.size.x / 2, 3)
	var end_cell := start_cell + Vector2i(30, 0)
	touch(0, true, screen_of_cell(start_cell))
	move(0, screen_of_cell(end_cell))
	check(mode._paint_rect.size.y < 12, "the map cut the strip to %d rows" % mode._paint_rect.size.y)
	check_eq((mode._paint_material as StandardMaterial3D).albedo_color, mode.invalid_color, "the preview is red")
	touch(0, false, screen_of_cell(end_cell))
	var painted := 0
	for y in 20:
		for x in range(start_cell.x - 5, start_cell.x + 40):
			if Airport.grid.is_taxiway(Vector2i(x, y)):
				painted += 1
	check_eq(painted, 0, "nothing was painted")
	await frames(1)
	check((ui("ToolPanel/HintLabel") as Label).text.contains("Not enough room"), "and the player is told why")
	# Further from the edge the same drag paints a full 12 cell strip.
	drag(screen_of_cell(start_cell + Vector2i(0, 20)), screen_of_cell(end_cell + Vector2i(0, 20)))
	var full := 0
	for y in range(start_cell.y + 10, start_cell.y + 40):
		for x in range(start_cell.x - 5, start_cell.x + 40):
			if Airport.grid.is_taxiway(Vector2i(x, y)):
				full += 1
	check_eq(full, 31 * 12, "away from the edge it paints the full strip")
