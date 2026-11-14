extends TestCase
## The build menu can never get stuck: from every state each category is at most two taps away.


func _row(name: String) -> Control:
	return ui("BuildMenu/" + name)


func _top_texts() -> Array:
	return _row("BuildingButtons").get_children().filter(func(b: Node) -> bool: return not b.is_queued_for_deletion()).map(func(b: Node) -> String: return (b as Button).text)


## Taps at most two buttons (category row, else Back then category) to reach `category`.
func _reach(category: String) -> int:
	var taps := 0
	var cat_row := _row("CategoryButtons")
	var building_row := _row("BuildingButtons")
	var button := _menu_button(cat_row, category + " ›")
	if button == null or button.disabled:
		button = _menu_button(building_row, category + " ›")
	if button == null and _menu_button(building_row, "‹ Back") != null:
		await press(_menu_button(building_row, "‹ Back"))
		taps += 1
		button = _menu_button(cat_row, category + " ›")
		if button == null or button.disabled:
			button = _menu_button(building_row, category + " ›")
	if button == null:
		check(false, "no way to reach '%s'" % category)
		return 99
	await press(button)
	taps += 1
	return taps


## Every button of both rows lies inside the safe area (what the player can actually tap).
func _check_on_screen(label: String) -> void:
	var safe: Rect2 = (hud().get_node("SafeArea") as Control).get_global_rect()
	for row_name in ["CategoryButtons", "BuildingButtons"]:
		for child in _row(row_name).get_children():
			if child.is_queued_for_deletion():
				continue
			check(safe.encloses((child as Control).get_global_rect().grow(-1.0)), "%s: '%s' is inside the safe area" % [label, (child as Button).text])


func _check_gate_reachable(label: String) -> void:
	var taps: int = await _reach("Terminal")
	check(taps <= 2, "%s: Terminal reachable in %d taps" % [label, taps])
	check(_menu_button(_row("BuildingButtons"), "Gate") != null, "%s: Gate is listed" % label)


func test_every_menu_state_reaches_gate() -> void:
	await start_game()
	await open_build_view()
	var states: Array[Array] = [["Terminal"], ["Airside"], ["Landside"], ["Landside", "Roads"], ["Landside", "Curb"], ["Landside", "Sidewalk"], ["Landside", "Car park"], ["Landside", "Props"]]
	for state in states:
		await _reach(state[0])
		if state.size() > 1:
			await press(_menu_button(_row("BuildingButtons"), state[1] + " ›"))
		await _check_on_screen(" > ".join(state))
		await _check_gate_reachable(" > ".join(state))
		check(_menu_button(_row("BuildingButtons"), "‹ Back") != null, "Back button exists")
	# After picking a piece and cancelling, after a paint tool and Done.
	await pick_building("One-way road")
	await press(ui("ToolPanel/ToolBar/CancelButton"))
	await _check_gate_reachable("after cancel")
	await press(ui("BuildMenu/PaintButtons/TaxiwayButton"))
	check(not ui("BuildMenu").visible, "tool hides the menu")
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	check(ui("BuildMenu").visible, "Done brings the menu back")
	await _check_gate_reachable("after Done")


func test_place_gate_from_deep_menu() -> void:
	await start_game()
	await open_build_view()
	await pick_building("One-way road")
	await press(ui("ToolPanel/ToolBar/CancelButton"))
	check(await place("Gate", at(Vector2i(30, 20))), "gate placed after wandering through the landside menu")


func test_view_switch_resets_menu() -> void:
	await start_game()
	await open_build_view()
	await pick_building("One-way road")
	await press(ui("ToolPanel/ToolBar/CancelButton"))
	await close_build_view()
	await open_build_view()
	check_eq(_top_texts(), ["Terminal ›", "Airside ›", "Landside ›"], "menu back at the top level")


func test_place_gate_after_tool_and_done() -> void:
	await start_game()
	await open_build_view()
	await press(ui("BuildMenu/PaintButtons/WalkwayButton"))
	await press(ui("ToolPanel/ToolBar/DoneButton"))
	check(await place("Gate", at(Vector2i(30, 20))), "gate placed after a tool and Done")
