extends TestCase
## Airside buildings before security are unused; demolishing security cuts the flights off,
## and rebuilding it brings them back.


func _security() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.SECURITY:
			return building
	return null


func test_gates_before_security_are_unused_until_connected() -> void:
	ShowcaseAirport.build(0.0)
	var security := _security()
	var type := security.type
	var origin := security.origin_cell
	var rotation := security.rotation_steps
	Airport.demolish(security)
	sim_seconds(600)
	check_eq(Airport.usable_gates().size(), 0, "the gates are not usable without security")
	for flight in Airport.schedule.flights:
		check(flight.cargo, "only freighters still fly (the cargo terminal does not need security)")
	var before := Airport.reputation.departures
	var rebuilt := Airport.place_building(type, origin, rotation)
	check(rebuilt != null, "security built")
	for i in 60:
		sim_seconds(10)
		if Airport.schedule.flights.any(func(f: Flight) -> bool: return not f.cargo):
			break
	check(Airport.schedule.flights.any(func(f: Flight) -> bool: return not f.cargo), "passenger flights come back once security connects the gates")
	check(Airport.reputation.departures >= before, "departures never go back")


func test_demolishing_security_with_planes_on_the_apron() -> void:
	ShowcaseAirport.build(300.0)
	# Wait until planes are really at the gates.
	for i in 120:
		sim_seconds(5)
		if Airport.schedule.flights.size() > 0:
			break
	check(Airport.schedule.flights.size() > 0, "a busy airport")
	var security := _security()
	var type := security.type
	var origin := security.origin_cell
	var rotation := security.rotation_steps
	Airport.demolish(security)
	sim_seconds(2400)
	var rebuilt := Airport.place_building(type, origin, rotation)
	check(rebuilt != null, "security rebuilt")
	var departed := Airport.reputation.departures
	sim_seconds(1200)
	check(Airport.reputation.departures > departed, "flow is restored: %d -> %d departures" % [departed, Airport.reputation.departures])
