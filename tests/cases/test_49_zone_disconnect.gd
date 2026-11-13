extends TestCase
## Airside buildings before security are unused; demolishing security strands nobody for good.


func _security() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.SECURITY:
			return building
	return null


func _count(state: Passenger.State) -> int:
	var total := 0
	for passenger in Airport.passenger_flow.passengers:
		if passenger.state == state:
			total += 1
	return total


func _shop_income() -> float:
	var total := 0.0
	for station in Airport.passenger_flow.stations():
		if station.role() == BuildingType.Role.SHOP:
			total += station.income_in_window(Airport.passenger_flow.time)
	return total


func _gate_users() -> int:
	var total := 0
	for station in Airport.passenger_flow.stations():
		if station.role() == BuildingType.Role.GATE:
			total += station.waiting.size()
	return total


func test_gate_and_shop_before_security_are_unused_until_connected() -> void:
	ShowcaseAirport.build(0.0)
	var security := _security()
	var type := security.type
	var origin := security.origin_cell
	var rotation := security.rotation_steps
	Airport.demolish(security)
	sim_seconds(600)
	var flow := Airport.passenger_flow
	check_eq(_count(Passenger.State.STUCK), 0, "nobody is stuck")
	check_eq(flow.passengers.size(), 0, "no passengers enter a terminal without a way to the airside")
	check_eq(flow.departed_count, 0, "no departures")
	check_eq(_gate_users(), 0, "the unconnected gates are not used")
	check_eq(_shop_income(), 0.0, "the unconnected shop earns nothing")
	var rebuilt := Airport.place_building(type, origin, rotation)
	check(rebuilt != null, "security built")
	Airport.staff_fully(rebuilt)  # a new building has no staff yet
	for i in 60:
		sim_seconds(10)
		if flow.departed_count > 0 and _shop_income() > 0.0:
			break
	check(flow.departed_count > 0, "passengers fly once security connects the gates")
	check(_shop_income() > 0.0, "and shop in the airside")


func test_demolishing_security_with_passengers_airside() -> void:
	ShowcaseAirport.build(300.0)
	var flow := Airport.passenger_flow
	# Wait until people really queue at security and wait at gates.
	for i in 120:
		sim_seconds(5)
		var in_security := 0
		for station in flow.stations():
			if station.role() == BuildingType.Role.SECURITY:
				in_security += station.queue.size() + station.serving.size()
		if in_security > 0 and _gate_users() > 0:
			break
	check(flow.passengers.size() > 0, "a busy airport")
	var security := _security()
	var type := security.type
	var origin := security.origin_cell
	var rotation := security.rotation_steps
	Airport.demolish(security)
	sim_seconds(2400)
	# Departing passengers go home when their flight is cancelled. (Arriving passengers who had
	# just left a plane when the gates were cut off wait for the way to be restored: that depends
	# on where the planes happen to be, so they are not counted here.)
	var stuck_leaving := Airport.passenger_flow.passengers.filter(func(p: Passenger) -> bool: return p.state == Passenger.State.STUCK and not p.is_arriving)
	check_eq(stuck_leaving.size(), 0, "nobody stays stuck for good")
	var rebuilt := Airport.place_building(type, origin, rotation)
	check(rebuilt != null, "security rebuilt")
	Airport.staff_fully(rebuilt)
	var departed := flow.departed_count
	sim_seconds(1200)
	check(flow.departed_count > departed, "flow is restored: %d -> %d departures" % [departed, flow.departed_count])
