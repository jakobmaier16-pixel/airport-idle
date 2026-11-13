extends TestCase
## Car park, lounge and fast track (design doc §11.8).


func _first(role: BuildingType.Role) -> Building:
	for building in Airport.buildings:
		if building.type.role == role:
			return building
	return null


func test_car_park_earns_from_returning_travellers() -> void:
	ShowcaseAirport.build(0.0)
	var car_park := _first(BuildingType.Role.CAR_PARK)
	var station := Airport.passenger_flow.station_for(car_park)
	var front := Building.outside_row(car_park.type.footprint, car_park.origin_cell, car_park.rotation_steps, true)
	var started_there := 0
	var seen: Dictionary[Passenger, bool] = {}
	for i in 6000:  # 10 minutes
		Airport.step(Airport.SIM_STEP)
		for passenger in Airport.passenger_flow.passengers:
			if not seen.has(passenger) and not passenger.is_arriving and not passenger.is_transfer:
				seen[passenger] = true
				if front.has(Airport.grid.world_to_cell(passenger.position)):
					started_there += 1
	var income := station.income_in_window(Airport.passenger_flow.time)
	check(started_there > 10, "departing car travellers arrive at the car park: %d of %d" % [started_there, seen.size()])
	check(started_there < seen.size() * 0.6, "but most still come through the entrance")
	check(income >= PassengerFlow.PARKING_FEE * 5, "returning travellers pay for parking: %s" % Economy.format(income))
	check(is_equal_approx(fmod(income, PassengerFlow.PARKING_FEE), 0.0), "€8 each")


func test_without_car_park_everyone_uses_the_entrance() -> void:
	ShowcaseAirport.build(0.0)
	Airport.demolish(_first(BuildingType.Role.CAR_PARK))
	sim_seconds(400)
	check(Airport.passenger_flow.arrived_count > 10, "arrivals still leave: %d" % Airport.passenger_flow.arrived_count)
	check(Airport.passenger_flow.passengers.all(func(p: Passenger) -> bool: return p.state != Passenger.State.STUCK), "nobody looks for a car park")


func test_business_travellers_use_the_lounge() -> void:
	ShowcaseAirport.build(0.0)
	var lounge := _first(BuildingType.Role.LOUNGE)
	var station := Airport.passenger_flow.station_for(lounge)
	var guests: Dictionary[Passenger, bool] = {}
	var non_business := 0
	var too_many := false
	for i in 6000:
		Airport.step(Airport.SIM_STEP)
		too_many = too_many or station.waiting.size() > lounge.type.customer_capacity
		for guest in station.waiting:
			if not guests.has(guest):
				guests[guest] = true
				if guest.type.id != &"business":
					non_business += 1
	check(guests.size() > 5, "business travellers wait in the lounge: %d" % guests.size())
	check_eq(non_business, 0, "only business travellers")
	check(not too_many, "never more guests than seats")
	var income := station.income_in_window(Airport.passenger_flow.time)
	check(income >= 12.0 * 5, "€12 per guest for the airport: %s" % Economy.format(income))


func test_fast_track_puts_business_first() -> void:
	ShowcaseAirport.build(0.0)
	var security := _first(BuildingType.Role.SECURITY)
	check(security.fast_track, "the showcase security has a fast track")
	var station := Airport.passenger_flow.station_for(security)
	var flow := Airport.passenger_flow
	# Three people already queuing, then a business traveller arrives.
	var waiting: Array[Passenger] = []
	for type in [FlightSchedule.BUSINESS, FlightSchedule.FAMILY, FlightSchedule.LOW_COST]:
		var passenger := Passenger.new()
		passenger.type = type
		station.queue.append(passenger)
		waiting.append(passenger)
	var late_business := Passenger.new()
	late_business.type = FlightSchedule.BUSINESS
	late_business.target = security
	var money := Airport.economy.balance
	flow._arrive(late_business)
	check_eq(station.queue.find(late_business), 1, "ahead of everyone but the business traveller already there")
	check_eq(Airport.economy.balance, money + PassengerFlow.FAST_TRACK_FEE, "pays €5")
	var family := Passenger.new()
	family.type = FlightSchedule.FAMILY
	family.target = security
	flow._arrive(family)
	check_eq(station.queue.back(), family, "families join at the back")


func test_buying_fast_track() -> void:
	var security := Airport.place_building(type_of(&"security"), Vector2i(30, 28), 0)
	check_eq(Airport.fast_track_problem(security), "", "can be bought")
	var money := Airport.economy.balance
	check(Airport.buy_fast_track(security), "bought")
	check_eq(Airport.economy.balance, money - Airport.FAST_TRACK_COST, "for €5,000")
	check_eq(Airport.fast_track_problem(security), "Has a fast track", "once")
	var check_in := Airport.place_building(type_of(&"check_in"), Vector2i(20, 20), 0)
	check_eq(Airport.fast_track_problem(check_in), "Only for security", "security only")
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check(Airport.buildings[0].fast_track, "saved")


func test_fast_track_button() -> void:
	var security := Airport.place_building(type_of(&"security"), Vector2i(30, 28), 0)
	await start_game()
	manager().global_position = Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 0.0, 6.0)
	await physics_frames(2)
	hud().show_station(security)
	await frames(1)
	var button := ui("StationPanel/Content/FastTrackButton") as Button
	check(button.visible and button.text == "Add fast track · €5,000", "offered: '%s'" % button.text)
	await press(button)
	check(security.fast_track, "bought through the panel")
