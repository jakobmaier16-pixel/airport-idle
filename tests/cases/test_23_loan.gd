extends TestCase
## Bank loan and restructuring (design doc §11.6).


func _roles() -> Array:
	return Airport.buildings.map(func(b: Building) -> BuildingType.Role: return b.type.role)


func test_loan_costs_interest() -> void:
	Airport.economy.balance = -10000.0
	sim_seconds(60)
	var expected := -10000.0 * (1.0 + Economy.LOAN_INTEREST_PER_MINUTE)
	check(absf(Airport.economy.balance - expected) < 2.0, "1 %% interest per minute: %s" % Airport.economy.balance)
	check(Airport.economy.profit_per_minute() < -90.0, "interest counts as a running cost")


func test_within_the_limit_nothing_happens() -> void:
	Airport.economy.balance = -0.9 * Economy.CREDIT_BASE
	sim_seconds(Economy.RESTRUCTURE_AFTER + 10.0)
	check_eq(Airport.restructure_in(), -1.0, "no countdown within the limit")
	check(Airport.economy.balance < 0.0, "still in debt, but nobody sells anything")


func test_over_the_limit_the_bank_restructures() -> void:
	ShowcaseAirport.build(0.0)
	var count := Airport.buildings.size()
	var sold_names: Array[PackedStringArray] = []
	Airport.restructured.connect(func(sold: PackedStringArray) -> void: sold_names.append(sold))
	Airport.economy.balance = -(Airport.credit_limit() + 5000.0)
	sim_seconds(Economy.RESTRUCTURE_AFTER - 2.0)
	check_eq(Airport.buildings.size(), count, "the bank waits two minutes")
	check(Airport.restructure_in() > 0.0 and Airport.restructure_in() < 3.0, "countdown: %.1f" % Airport.restructure_in())
	sim_seconds(3.0)
	check(Airport.buildings.size() < count, "buildings were sold")
	# About €0 right after; running costs since then may already have taken a few euros.
	check(Airport.economy.balance > -50.0, "the debt is gone: %s" % Airport.economy.balance)
	check_eq(sold_names.size(), 1, "the player is told once")
	check(not sold_names.is_empty() and sold_names[0].size() > 0, "and told what was sold")
	check(Airport.stars() <= Airport.reputation.stars(Airport.passenger_flow.satisfaction.average) + 0.01, "rating includes the penalty")
	check(Airport.reputation.penalty > 0.9, "reputation suffers")
	check(Airport.passenger_flow.route_problem.is_empty(), "passengers still have a route: '%s'" % Airport.passenger_flow.route_problem)


func test_restructuring_keeps_the_essentials() -> void:
	ShowcaseAirport.build(0.0)
	Airport.economy.balance = -10000000.0
	Airport.restructure()
	var roles := _roles()
	for role in [BuildingType.Role.ENTRANCE, BuildingType.Role.CHECK_IN, BuildingType.Role.SECURITY,
			BuildingType.Role.GATE, BuildingType.Role.AIRCRAFT_STAND, BuildingType.Role.BAGGAGE_CLAIM]:
		check_eq(roles.count(role), 1, "one %s left" % BuildingType.Role.keys()[role])
	check_eq(roles.count(BuildingType.Role.SHOP), 0, "shops sold first")
	check_eq(Airport.economy.balance, 0.0, "the rest is written off")
	check(Airport.passenger_flow.route_problem.is_empty(), "the small airport still works: '%s'" % Airport.passenger_flow.route_problem)
	sim_seconds(400)
	check(Airport.passenger_flow.departed_count > 0, "and flights still leave")


func test_penalty_fades() -> void:
	Airport.reputation.penalty = 1.0
	sim_seconds(Reputation.PENALTY_SECONDS)
	check_eq(Airport.reputation.penalty, 0.0, "forgotten after a while")


func test_hud_shows_loan_and_notice() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	Airport.economy.balance = -5000.0
	await frames(2)
	var loan := ui("InfoPanel/LoanLabel") as Label
	check(loan.visible and loan.text.begins_with("Bank loan"), "loan line: '%s'" % loan.text)
	Airport.economy.balance = -(Airport.credit_limit() + 1000.0)
	sim_seconds(1)
	await frames(2)
	check(loan.text.contains("restructures in"), "countdown shown: '%s'" % loan.text)
	Airport.restructure()
	await frames(2)
	check(hud().notice_text().contains("restructured"), "notice: '%s'" % hud().notice_text())
	check(not loan.visible, "loan line gone after restructuring")


func test_loan_state_is_saved() -> void:
	Airport.economy.balance = -50000.0
	Airport.economy.over_limit_seconds = 33.0
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check_eq(Airport.economy.over_limit_seconds, 33.0, "countdown restored")
	check_eq(Airport.economy.balance, -50000.0, "debt restored")
