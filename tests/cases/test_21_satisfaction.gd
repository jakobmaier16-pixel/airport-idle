extends TestCase
## Passenger satisfaction (design doc §8.10).


func _security() -> Building:
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.SECURITY:
			return building
	return null


func test_running_average_follows_journeys() -> void:
	var satisfaction := Satisfaction.new()
	check_eq(satisfaction.average, Satisfaction.START, "a new airport starts neutral")
	for i in 200:
		satisfaction.record("Families", 20.0)
	check(satisfaction.average < 25.0, "many unhappy passengers pull it down: %.1f" % satisfaction.average)
	check(satisfaction.by_type["Families"] < 25.0, "per type too")
	satisfaction.record("Business", 150.0)
	check(satisfaction.by_type["Business"] <= 100.0, "mood is capped at 100")
	check(satisfaction.by_type["Families"] < satisfaction.average, "overall lies between the types")


func test_complaints_fade() -> void:
	var satisfaction := Satisfaction.new()
	check_eq(satisfaction.main_complaint(), "", "no complaints at the start")
	satisfaction.complain(Satisfaction.LONG_QUEUES, 100.0)
	satisfaction.complain(Satisfaction.LONG_WALKS, 40.0)
	check_eq(satisfaction.main_complaint(), Satisfaction.LONG_QUEUES, "the biggest reason wins")
	for i in 600:
		satisfaction.tick_second()
	check(satisfaction.complaints[Satisfaction.LONG_QUEUES] < 30.0, "halves every 5 minutes")
	for i in 600:
		satisfaction.tick_second()
	check_eq(satisfaction.main_complaint(), "", "old complaints are forgotten")


func test_showcase_passengers_are_fairly_happy() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(600)
	var satisfaction := Airport.passenger_flow.satisfaction
	check(satisfaction.journeys > 40, "journeys finished: %d" % satisfaction.journeys)
	check(satisfaction.average > 60.0, "a good layout keeps them happy: %.1f" % satisfaction.average)
	check(satisfaction.by_type.size() >= 2, "tracked per type: %s" % satisfaction.by_type)


func test_slow_security_makes_passengers_unhappy() -> void:
	ShowcaseAirport.build(0.0)
	var security := _security()
	while Airport.dismiss(security):
		pass
	Airport.hire(security)  # one lane for everyone
	var normal_time := security.type.service_time
	security.type.service_time = normal_time * 3.0
	sim_seconds(600)
	security.type.service_time = normal_time
	var satisfaction := Airport.passenger_flow.satisfaction
	check(satisfaction.average < 60.0, "queues and missed flights hurt: %.1f" % satisfaction.average)
	check(satisfaction.main_complaint() in [Satisfaction.LONG_QUEUES, Satisfaction.MISSED],
		"they complain about queues or missed flights: '%s'" % satisfaction.main_complaint())


func test_missed_flight_ruins_the_trip() -> void:
	var flow := Airport.passenger_flow
	var flight := Flight.new()
	var passenger := Passenger.new()
	passenger.flight = flight
	passenger.mood = 90.0
	flow.passengers.append(passenger)
	flow.remove_flight_passengers(flight, true)
	check(flow.satisfaction.average < Satisfaction.START, "a missed flight counts as mood 0")
	check(flow.satisfaction.complaints.get(Satisfaction.MISSED, 0.0) >= 90.0, "and is complained about")


func test_satisfaction_is_saved() -> void:
	for i in 80:  # more than the memory, so the ring buffer wraps
		Airport.passenger_flow.satisfaction.record("Business", 33.0)
		Airport.passenger_flow.satisfaction.record("Families", 51.0)
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check_eq(roundi(Airport.passenger_flow.satisfaction.average), 42, "average restored")
	check_eq(Airport.passenger_flow.satisfaction.journeys, 160, "journeys restored")
	check_eq(roundi(Airport.passenger_flow.satisfaction.by_type.get("Business", 0.0)), 33, "per type restored")


func test_stats_show_satisfaction() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(300)
	await start_game()
	await press(ui("TopButtons/StatsButton"))
	await frames(2)
	var text := (ui("StatsPanel/Content/SatisfactionLabel") as Label).text
	check(text.begins_with("Satisfaction: ") and text.contains("Main complaint:"), "stats line: '%s'" % text)
