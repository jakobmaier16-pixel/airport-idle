extends TestCase
## The test world framework: the world list, the Worlds button, picking and restarting a world, and the
## rule that a test world never touches the save file (scripts/dev/worlds/).

const TEST_SAVE: String = "user://test_world_savegame.json"


func _use_test_save() -> void:
	SaveGame.save_path = TEST_SAVE
	SaveGame.enabled = true


func _restore_save_settings() -> void:
	SaveGame.reset_game()
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"


func _file_text() -> String:
	return FileAccess.get_file_as_string(TEST_SAVE) if FileAccess.file_exists(TEST_SAVE) else ""


func test_catalog_is_ordered_and_complete() -> void:
	var ids: Array[StringName] = []
	for world in TestWorlds.all():
		ids.append(world.id)
		check(world.checks.size() <= TestWorld.MAX_CHECKS, "%s has at most five checks" % world.id)
		check(not world.question.is_empty() and not world.title.is_empty(), "%s has a title and a question" % world.id)
	check_eq(ids, [TestWorlds.ASSET_VIEWER, TestWorlds.FRESH_AIRPORT, TestWorlds.EVERYTHING_TOGETHER, TestWorlds.FREE_BUILD] as Array[StringName], "the worlds in list order")
	check(TestWorlds.find(TestWorlds.FREE_BUILD).is_saved(), "Free build is the saved game")
	for id in [TestWorlds.ASSET_VIEWER, TestWorlds.FRESH_AIRPORT, TestWorlds.EVERYTHING_TOGETHER]:
		check(not TestWorlds.find(id).is_saved(), "%s is never saved" % id)


func test_the_list_does_not_open_by_itself_in_tests() -> void:
	await start_game()
	await frames(2)
	check(not hud().get_node("WorldList").visible, "no list at start under --no-save")


func test_worlds_button_in_every_view_and_inside_the_safe_area() -> void:
	await start_game()
	var button := ui("TopButtons/WorldsButton") as Button
	check(button.is_visible_in_tree(), "Worlds button in the manager view")
	check(in_safe_area(button), "... inside the safe area")
	await open_build_view()
	check(button.is_visible_in_tree() and in_safe_area(button), "Worlds button in the build view")
	await enter_world(TestWorlds.ASSET_VIEWER)
	button = ui("TopButtons/WorldsButton") as Button
	check(button.is_visible_in_tree() and in_safe_area(button), "Worlds button in the viewer")
	# It never overlaps the other buttons.
	for other in visible_buttons():
		if other != button:
			check(not button.get_global_rect().intersects(other.get_global_rect()), "Worlds button does not cover %s" % other.name)


func test_list_groups_the_worlds_and_close_does_not_switch() -> void:
	await start_game()
	await press(ui("TopButtons/WorldsButton"))
	await frames(3)
	var list := hud().get_node("WorldList") as WorldList
	check(list.visible, "the list opened")
	var texts: PackedStringArray = []
	for node in list.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	for header in ["Look worlds", "Function worlds", "Combined worlds", "Your game"]:
		check(texts.has(header), "header %s" % header)
	var order: Array[String] = []
	for node in list.find_children("World_*", "Button", true, false):
		order.append(node.name)
		check(in_safe_area(node) or (node as Control).get_global_rect().size.y > 0.0, "%s has a place" % node.name)
		check((node as Button).custom_minimum_size.y >= 80.0, "%s is finger-sized" % node.name)
	check_eq(order.size(), 4, "one big button per world")
	check(in_safe_area(list.get_node("CloseButton") if list.has_node("CloseButton") else list.find_child("CloseButton", true, false)), "Close is inside the safe area")
	await press(list.find_child("CloseButton", true, false))
	check(not list.visible, "Close hides the list")
	check(TestWorlds.active == null, "and switches nothing")


func test_picking_each_world_builds_it_and_shows_its_title() -> void:
	await start_game()
	for id in [TestWorlds.ASSET_VIEWER, TestWorlds.FRESH_AIRPORT, TestWorlds.EVERYTHING_TOGETHER, TestWorlds.FREE_BUILD]:
		await pick_world(id)
		var world := TestWorlds.find(id)
		check(TestWorlds.current() == world, "%s is the active world" % id)
		var label := ui("BuildLabel") as Label
		check(label.text.contains(world.title), "the HUD shows '%s' (got '%s')" % [world.title, label.text])
		match id:
			TestWorlds.ASSET_VIEWER:
				check(main.get_node("ViewerCamera").current, "the viewer opens in the viewer view")
				check(Airport.buildings.size() <= 1, "an empty field with at most the shown item")
			TestWorlds.FRESH_AIRPORT:
				check(build_camera().current, "the fresh airport opens in the build view")
				check_eq(Airport.buildings.size(), 1, "only the starting runway")
			TestWorlds.EVERYTHING_TOGETHER:
				check(manager_camera().current, "the showcase opens in the manager view")
				check_eq(Airport.buildings.size(), SHOWCASE_WITH_LANDSIDE_BUILDINGS, "the showcase with its landside")
			TestWorlds.FREE_BUILD:
				check(manager_camera().current, "the free build opens in the manager view")
		check((ui("TopButtons/InfoButton") as Button).visible == (id != TestWorlds.FREE_BUILD), "the i button is there except for the saved game")
		check((ui("BuildMenu/PaintButtons/ResetButton") as Button).visible == (id == TestWorlds.FREE_BUILD), "Reset is for Free build only")


func test_restart_rebuilds_the_same_world() -> void:
	await enter_world(TestWorlds.FRESH_AIRPORT)
	Airport.place_building(type_of(&"check_in"), at(Vector2i(20, 20)), 0)
	check_eq(Airport.buildings.size(), 2, "something was built")
	TestWorlds.reload = func() -> void: pass
	await press(ui("TopButtons/InfoButton"))
	var info := hud().get_node("WorldInfo") as WorldInfo
	check(info.visible, "the i panel opened")
	var texts: PackedStringArray = []
	for node in info.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	var all := "\n".join(texts)
	check(all.contains("Fresh airport") and all.contains(TestWorlds.find(TestWorlds.FRESH_AIRPORT).question), "title and question")
	check(all.contains("it should open in the build view"), "the checks")
	await press(info.find_child("RestartButton", true, false))
	await restart_main()
	check(TestWorlds.current().id == TestWorlds.FRESH_AIRPORT, "still the fresh airport")
	check_eq(Airport.buildings.size(), 1, "rebuilt: only the runway again")


func test_a_test_world_never_changes_the_save_file() -> void:
	_use_test_save()
	Airport.place_building(type_of(&"check_in"), at(Vector2i(20, 20)), 0)
	SaveGame.save_now()
	check(not _file_text().is_empty(), "the free build was saved")
	await start_game()
	for id in [TestWorlds.ASSET_VIEWER, TestWorlds.FRESH_AIRPORT, TestWorlds.EVERYTHING_TOGETHER]:
		await pick_world(id)
		var before := _file_text()
		var stamp := FileAccess.get_modified_time(TEST_SAVE)
		Airport.place_building(type_of(&"check_in"), at(Vector2i(40, 20)), 0)
		SaveGame.save_now()
		SaveGame._notification(NOTIFICATION_APPLICATION_PAUSED)
		SaveGame._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		SaveGame._time_until_save = 0.0
		SaveGame._autosave_in = 0.0
		await frames(3)
		check_eq(_file_text(), before, "%s left the save file alone" % id)
		check_eq(FileAccess.get_modified_time(TEST_SAVE), stamp, "%s did not even rewrite it" % id)
	_restore_save_settings()


func test_free_build_loads_the_save_and_autosaves() -> void:
	_use_test_save()
	Airport.place_building(type_of(&"check_in"), at(Vector2i(20, 20)), 0)
	SaveGame.save_now()
	await start_game()
	await pick_world(TestWorlds.FRESH_AIRPORT)
	check(not Airport.buildings.any(func(b: Building) -> bool: return b.type.id == &"check_in"), "the test world does not hold the saved check-in")
	await pick_world(TestWorlds.FREE_BUILD)
	check(Airport.buildings.any(func(b: Building) -> bool: return b.type.id == &"check_in"), "Free build loaded the saved check-in")
	var before := _file_text()
	Airport.place_building(type_of(&"check_in"), at(Vector2i(40, 20)), 0)
	SaveGame._time_until_save = 0.0
	await frames(3)
	check(_file_text() != before, "Free build autosaved the change")
	_restore_save_settings()
