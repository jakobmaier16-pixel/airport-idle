extends TestCase
## Getting started goals (design doc §6.1).


func test_goals_follow_the_build() -> void:
	var goals := Airport.goals
	check_eq(goals.current(), 0, "a new airport starts with goal 1")
	check(goals.text().begins_with("Goal 1/10: Build view: paint an airside zone"), "text: '%s'" % goals.text())
	Airport.paint_zone(cells(Vector2i(8, 31), Vector2i(48, 25)), AirportGrid.Zone.AIRSIDE)
	check_eq(goals.current(), 1, "airside painted")
	ShowcaseAirport.build(0.0)
	Airport.progression.tier = Progression.Tier.REGIONAL
	Airport.progression.passengers = 0  # as if it had just been built
	check_eq(goals.current(), 7, "the showcase still waits for its first departure")
	sim_seconds(330)
	check_eq(goals.current(), 9, "departed, two airlines: next is National")
	Airport.progression.tier = Progression.Tier.NATIONAL
	check_eq(goals.current(), -1, "all done")
	check_eq(goals.text(), "", "nothing to show")


func test_undone_goal_comes_back() -> void:
	ShowcaseAirport.build(0.0)
	for building in Airport.buildings.duplicate():
		if building.type.role == BuildingType.Role.BAGGAGE_CLAIM:
			Airport.demolish(building)
	check_eq(Airport.goals.current(), 5, "baggage claim is needed again")


func test_goal_line_in_the_hud() -> void:
	await start_game()
	hud()._goal_refresh_in = 0.0
	await frames(2)
	check(hud().goal_text().begins_with("Goal 1/10"), "shown: '%s'" % hud().goal_text())
	hud().show_stats()
	await frames(1)
	check_eq(hud().goal_text(), "", "hidden while a panel is open")
	hud().hide_stats()
	await frames(1)
	await press(ui("GoalPanel/Row/HideButton"))
	check(Airport.goals.hidden, "Hide hides it for good")
	await frames(1)
	check_eq(hud().goal_text(), "", "gone")
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check(Airport.goals.hidden, "saved")
