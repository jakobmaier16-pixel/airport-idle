extends TestCase
## Passenger journeys as data (tech architecture §5): the recipes in data/journeys/ keep the
## order the prototype had wired into the code.

const Role := BuildingType.Role


func _roles(recipe: JourneyRecipe) -> Array[Role]:
	var roles: Array[Role] = []
	for step in recipe.steps:
		roles.append(step.role)
	return roles


func test_recipe_data_matches_the_prototype_order() -> void:
	check_eq(_roles(PassengerFlow.DEPARTURE), [Role.CHECK_IN, Role.SECURITY, Role.GATE], "departures: check-in, security, gate")
	check_eq(_roles(PassengerFlow.ARRIVAL), [Role.BAGGAGE_CLAIM, Role.ENTRANCE], "arrivals: baggage claim, out")
	check_eq(_roles(PassengerFlow.TRANSFER), [Role.TRANSFER_SECURITY, Role.GATE], "transfers: transfer security, gate")
	check(PassengerFlow.ARRIVAL.step_at(1).exit_via_car_park, "arrivals leave through the car park for car travellers")
	var departure := PassengerFlow.DEPARTURE
	check(not departure.step_at(0).detour_before, "no shop before check-in")
	check(departure.step_at(1).detour_before and departure.step_at(2).detour_before, "shops before security and before the gate")
	check_eq(departure.step_at(1).detour_allowance, PassengerFlow.SECURITY_ALLOWANCE, "time kept for security")
	check_eq(departure.step_at(1).detour_chance_factor, PassengerFlow.LANDSIDE_CAFE_FACTOR, "landside cafés are rarer")
	check(departure.step_at(1).emerges_behind and PassengerFlow.TRANSFER.step_at(0).emerges_behind, "security lanes lead through")
	check_eq(departure.index_of(Role.SECURITY), 1, "index_of finds a role")
	check_eq(departure.index_of(Role.LOUNGE), -1, "index_of: unknown role")


func test_passengers_follow_their_recipe() -> void:
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	flow.transfer_share_override = 0.5
	var seen: Dictionary = {"departure": 0, "arrival": 0, "transfer": 0, "car": 0}
	for second in 600:
		sim_seconds(1)
		for p in flow.passengers:
			check(p.recipe != null, "every passenger has a journey")
			if p.recipe == null:
				continue
			seen[String(p.recipe.id)] += 1
			var expected := PassengerFlow.TRANSFER if p.is_transfer else (PassengerFlow.ARRIVAL if p.is_arriving else PassengerFlow.DEPARTURE)
			check(p.recipe == expected, "the recipe matches the kind of passenger")
			var role := p.after_shop if p.goal in [Role.SHOP, Role.LOUNGE] else p.goal
			check_eq(p.recipe.role_at(p.step), role, "the goal is the role of the current step (or a detour back to it)")
			if p.by_car and p.is_arriving:
				seen["car"] += 1
	check(seen["departure"] > 0 and seen["arrival"] > 0 and seen["transfer"] > 0, "all three journeys happened: %s" % [seen])
	check(seen["car"] > 0, "car travellers arrived")


func test_journey_survives_save_and_load() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(400)
	var flow := Airport.passenger_flow
	var before: Array = flow.passengers.map(func(p: Passenger) -> Array: return [p.recipe.id, p.step])
	check(not before.is_empty(), "passengers in the airport")
	var state := Airport.save_state()
	Airport.reset()
	Airport.load_state(state)
	var after: Array = Airport.passenger_flow.passengers.map(func(p: Passenger) -> Array: return [p.recipe.id, p.step])
	check_eq(after, before, "recipe and step come back after loading")
