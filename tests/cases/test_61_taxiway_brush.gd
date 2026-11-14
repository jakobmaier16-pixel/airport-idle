extends TestCase
## The taxiway tool paints with a 12-cell (24 m) wide brush that locks to one axis.


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
	Airport.economy.balance = 1000000.0
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
	check_eq(box.size.x, 20 + 12, "stamp slid 20 cells along x")
	check_eq(box.position, a - Vector2i(6, 6), "stamp centred on the start cell")


func test_diagonal_drag_locks_to_one_axis() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(at(Vector2i(20, 70))), screen_of_cell(at(Vector2i(40, 74))))
	var box := _bbox_of_taxiway()
	check_eq(box.size.y, 12, "the small y movement is ignored")
	check_eq(box.size.x, 32, "strip follows x")


func test_short_drag_does_not_lock_and_tap_stamps() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(at(Vector2i(20, 70))), screen_of_cell(at(Vector2i(22, 71))))
	var box := _bbox_of_taxiway()
	check_eq(box.size, Vector2i(12, 12), "under 3 cells: a single stamp")


func test_preview_cost_equals_actual_cost() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var before := Airport.economy.balance
	var from := screen_of_cell(at(Vector2i(20, 70)))
	var to := screen_of_cell(at(Vector2i(34, 70)))
	touch(0, true, from)
	for i in range(1, 11):
		move(0, from.lerp(to, i / 10.0))
	await frames(1)
	var hint := (ui("ToolPanel/HintLabel") as Label).text
	touch(0, false, to)
	var paid := before - Airport.economy.balance
	check(paid > 0.0, "something was paid")
	check_eq(paid, 12.0 * 26.0 * Economy.TAXIWAY_COST_PER_CELL, "12 x 26 cells")
	check_eq(hint, "Taxiway: %s" % Economy.format(paid), "preview showed the real cost")


func test_remove_clears_a_12_wide_strip() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(at(Vector2i(20, 70))), screen_of_cell(at(Vector2i(50, 70))))
	check_eq(_taxiway_cells(), 12 * 42, "painted")
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	await press(ui("BuildMenu/PaintButtons/RemoveButton"))
	drag(screen_of_cell(at(Vector2i(30, 70))), screen_of_cell(at(Vector2i(36, 70))))
	check_eq(_taxiway_cells(), 12 * 42 - 12 * 18, "removed a 12 x 18 strip in the middle")
	check_eq(Airport.grid.is_taxiway(at(Vector2i(30, 70))), false, "centre removed")
	check_eq(Airport.grid.is_taxiway(at(Vector2i(20, 70))), true, "the ends stay")


func test_tap_stamps_the_brush_and_charges_once() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	var before := Airport.economy.balance
	var cell := at(Vector2i(30, 70))
	tap(screen_of_cell(cell))
	var box := _bbox_of_taxiway()
	check_eq(box.size, Vector2i(12, 12), "a tap stamps one 12 x 12 brush")
	check_eq(box.position, cell - Vector2i(6, 6), "centred on the tapped cell")
	check_eq(before - Airport.economy.balance, 144.0 * Economy.TAXIWAY_COST_PER_CELL, "144 cells paid")
	var paid := Airport.economy.balance
	tap(screen_of_cell(cell))
	check_eq(Airport.economy.balance, paid, "a second tap on the same pavement costs nothing")
	check_eq(_taxiway_cells(), 144, "and adds no cells")
	await frames(1)
	check((ui("ToolPanel/HintLabel") as Label).text.begins_with("Drag to"), "the hint is the tool's usual one after a tap")


func test_price_hint_is_not_stale_over_existing_pavement() -> void:
	await _start()
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	drag(screen_of_cell(at(Vector2i(20, 70))), screen_of_cell(at(Vector2i(50, 70))))
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	# A new drag that starts on the strip, leaves it (a price shows) and comes back (nothing new to pave).
	var start := screen_of_cell(at(Vector2i(30, 70)))
	touch(0, true, start)
	for i in range(1, 11):
		move(0, start.lerp(screen_of_cell(at(Vector2i(70, 70))), i / 10.0))
	await frames(1)
	var outside := (ui("ToolPanel/HintLabel") as Label).text
	check(outside.begins_with("Taxiway: ") and not outside.contains("€0"), "over new ground the price shows: %s" % outside)
	for i in range(1, 11):
		move(0, screen_of_cell(at(Vector2i(70, 70))).lerp(screen_of_cell(at(Vector2i(40, 70))), i / 10.0))
	await frames(1)
	var inside := (ui("ToolPanel/HintLabel") as Label).text
	touch(0, false, screen_of_cell(at(Vector2i(40, 70))))
	check(inside.contains("€0"), "over existing pavement it says so, not the old price: %s" % inside)
