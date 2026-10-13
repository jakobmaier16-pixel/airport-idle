extends TestCase
## Staff training and promotion (design doc §9.2).


func _staffed_check_in() -> Building:
	var check_in := Airport.place_building(type_of(&"check_in"), Vector2i(20, 20), 0)
	Airport.staff_fully(check_in)
	return check_in


func test_training_takes_time_and_money() -> void:
	var check_in := _staffed_check_in()
	var staff := Airport.staff_at(check_in)
	staff[0].served[BuildingType.Role.CHECK_IN] = 100
	staff[2].served[BuildingType.Role.CHECK_IN] = 50
	var money := Airport.economy.balance
	var trainee := Airport.train(check_in)
	check(trainee == staff[1], "the least experienced goes first")
	check_eq(Airport.economy.balance, money - Employee.TRAINING_COST, "the course costs money")
	check(trainee.is_training(), "away on the course")
	check_eq(Airport.staff_working_at(check_in).size(), 2, "one counter fewer meanwhile")
	check_eq(Airport.train_problem(check_in), "Training in progress", "one at a time")
	sim_seconds(Employee.TRAINING_SECONDS + 0.2)
	check(not trainee.is_training(), "back at the counter")
	check_eq(trainee.experience(), Employee.TRAINING_EXPERIENCE, "with experience")
	check_eq(trainee.level_name(), "Trained", "one level up")


func test_experts_need_no_training() -> void:
	var check_in := _staffed_check_in()
	for employee in Airport.staff_at(check_in):
		employee.served[BuildingType.Role.CHECK_IN] = Employee.EXPERT_AFTER
	check_eq(Airport.train_problem(check_in), "Everyone is an expert", "nothing to learn")


func test_promotion() -> void:
	var check_in := _staffed_check_in()
	check_eq(Airport.promote_problem(check_in), "Needs an expert", "only experts are promoted")
	var expert: Employee = Airport.staff_at(check_in)[1]
	expert.served[BuildingType.Role.CHECK_IN] = Employee.EXPERT_AFTER + 10
	var cost := Airport.running_cost_per_minute()
	check(Airport.promote(check_in) == expert, "the expert is promoted")
	check(expert.is_supervisor, "supervisor")
	check_eq(expert.level_name(), "Supervisor", "shown as supervisor")
	check(is_equal_approx(Airport.running_cost_per_minute(), cost + Employee.SUPERVISOR_RAISE), "with a raise")
	check_eq(Airport.promote_problem(check_in), "Has a supervisor", "one per station")


func test_supervisor_speeds_up_the_team() -> void:
	var check_in := _staffed_check_in()
	var team := Airport.staff_at(check_in)
	for employee in team:
		employee.served[BuildingType.Role.CHECK_IN] = Employee.EXPERT_AFTER
	var expert := Employee.EXPERT_TIME_FACTOR
	check(is_equal_approx(PassengerFlow.staff_time_factor(team[1], team, false), expert), "no supervisor yet")
	Airport.promote(check_in)
	var boss: Employee = team.filter(func(e: Employee) -> bool: return e.is_supervisor)[0]
	var colleague: Employee = team.filter(func(e: Employee) -> bool: return not e.is_supervisor)[0]
	check(is_equal_approx(PassengerFlow.staff_time_factor(colleague, team, false), expert * Employee.SUPERVISOR_TEAM_FACTOR), "colleagues 5 % faster")
	check(is_equal_approx(PassengerFlow.staff_time_factor(boss, team, false), expert), "the supervisor at the usual speed")
	check(is_equal_approx(PassengerFlow.staff_time_factor(boss, team, true), expert * PassengerFlow.PRESENCE_TIME_FACTOR), "the manager's presence on top")


func test_training_and_promotion_saved() -> void:
	var check_in := _staffed_check_in()
	var staff := Airport.staff_at(check_in)
	staff[0].served[BuildingType.Role.CHECK_IN] = Employee.EXPERT_AFTER
	Airport.promote(check_in)
	Airport.train(check_in)
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	var loaded := Airport.staff_at(Airport.buildings[0])
	check(loaded[0].is_supervisor, "supervisor restored")
	check_eq(loaded[0].salary_per_minute, Airport.SALARIES[BuildingType.Role.CHECK_IN] + Employee.SUPERVISOR_RAISE, "with the raise")
	check(loaded.any(func(e: Employee) -> bool: return e.is_training()), "training restored")


func test_panel_buttons() -> void:
	var check_in := _staffed_check_in()
	Airport.paint_walkway(cells(Vector2i(20, 19), Vector2i(5, 1)), true)
	await start_game()
	manager().global_position = Airport.grid.cell_to_world(Vector2i(22, 17))
	await physics_frames(2)
	hud().show_station(check_in)
	await frames(1)
	var train := ui("StationPanel/Content/TeamButtons/TrainButton") as Button
	check_eq(train.text, "Train · €400", "train button names the price")
	await press(train)
	check(Airport.staff_at(check_in).any(func(e: Employee) -> bool: return e.is_training()), "trained through the panel")
	await frames(1)
	var info := (ui("StationPanel/Content/InfoLabel") as Label).text
	check(info.contains("in training"), "the staff list says so: '%s'" % info)
	Airport.staff_at(check_in)[0].served[BuildingType.Role.CHECK_IN] = Employee.EXPERT_AFTER
	await frames(1)
	await press(ui("StationPanel/Content/TeamButtons/PromoteButton"))
	check(Airport.staff_at(check_in)[0].is_supervisor, "promoted through the panel")
