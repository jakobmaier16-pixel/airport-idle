extends TestCase
## Airlines and deals (design doc §10.1).


func _type(id: StringName) -> AirlineType:
	return Airlines.CATALOG.find(id)


# Counts every flight planned while the simulation runs for `seconds`.
func _flights_planned(seconds: float) -> Array[Flight]:
	var seen: Array[Flight] = []
	for i in int(seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if not seen.has(flight):
				seen.append(flight)
	return seen


func test_new_airport_has_the_starter_deal() -> void:
	var signed := Airport.airlines.signed
	check_eq(signed.size(), 1, "one airline")
	check_eq(signed[0].type.id, Airlines.STARTER, "the starter airline")
	check_eq(signed[0].flights_per_hour, Airlines.STARTER_FLIGHTS, "its flights")
	check(Airport.airlines.offers.is_empty(), "no offers yet")


func test_flights_belong_to_airlines() -> void:
	ShowcaseAirport.build(0.0)
	var flights := _flights_planned(600)
	check(flights.size() >= 6, "flights planned: %d" % flights.size())
	var codes := {}
	for flight in flights:
		if flight.airline == null:
			# No deal had a flight owed: the default airline filled the slot.
			check(flight.number.begins_with(Timetable.default_airline().code + " "), "unsigned flights are the default airline's: %s" % flight.number)
			continue
		codes[flight.airline.type.code] = true
		check(flight.number.begins_with(flight.airline.type.code + " "), "number with the airline code: %s" % flight.number)
		check_eq(flight.route, flight.airline.type.route, "the airline's route type")
		check_eq(flight.fee_per_passenger, flight.airline.fee, "the airline's fee")
	check(codes.size() >= 2, "several airlines fly: %s" % [codes.keys()])


func test_no_deal_the_default_airline_flies() -> void:
	ShowcaseAirport.build(0.0)
	Airport.airlines.signed.clear()
	var flights := _flights_planned(900)
	check(flights.size() >= 3, "slots are still flown: %d" % flights.size())
	var default := Timetable.default_airline()
	for flight in flights:
		if flight.cargo or flight.wide_body:
			check(false, "no freighters or wide-bodies without a deal: %s" % flight.number)
			continue
		check(flight.airline == null and flight.number.begins_with(default.code + " "), "default airline: %s" % flight.number)
		check_eq(flight.route, default.route, "its route type")


func test_flights_follow_the_deal() -> void:
	ShowcaseAirport.build(0.0)
	Airport.airlines.signed.clear()
	Airport.airlines.sign_deal(_type(&"zippa"), 6, 9.0)
	var flights := _flights_planned(1800)
	var count := flights.filter(func(f: Flight) -> bool: return f.airline != null).size()
	# 6 per hour for half an hour = 3, plus the first one right away; the other slots of the
	# timetable go to the default airline.
	check(count >= 3 and count <= 5, "about 3–4 deal flights in 30 minutes: %d" % count)
	check(flights.size() > count, "the rest of the timetable is flown by the default airline")


func test_too_few_gates_refuse_flights() -> void:
	ShowcaseAirport.build(0.0)
	# Two gates take 40 flights per hour; these airlines want 70.
	Airport.airlines.sign_deal(_type(&"budjet"), 20, 8.0)
	Airport.airlines.sign_deal(_type(&"sunkiss"), 8, 13.0)
	sim_seconds(900)
	var refused := 0
	for airline in Airport.airlines.signed:
		refused += airline.refused
	check(refused > 5, "flights refused: %d" % refused)
	var unhappiest := 100.0
	for airline in Airport.airlines.signed:
		unhappiest = minf(unhappiest, airline.happiness)
	check(unhappiest < Airlines.START_HAPPINESS, "refused flights make airlines unhappy: %.0f" % unhappiest)


func test_chance_to_agree() -> void:
	var airlines := Airport.airlines
	var type := _type(&"zippa")  # likes firm, dislikes flexible
	var offer := AirlineOffer.new(type, 14, type.expected_fee)
	var stars := type.min_stars
	var neutral := AirlineType.Tone.FRIENDLY
	check(is_equal_approx(airlines.chance(offer, type.expected_fee, 14, neutral, stars), Airlines.BASE_CHANCE), "75 % at their own terms")
	check(airlines.chance(offer, type.expected_fee * 1.2, 14, neutral, stars) < 0.5, "a higher fee is less likely")
	check_eq(airlines.chance(offer, type.expected_fee * 0.6, 14, neutral, stars), 1.0, "a much lower fee is certain")
	check(airlines.chance(offer, type.expected_fee, 6, neutral, stars) < Airlines.BASE_CHANCE, "fewer flights than asked is less likely")
	check(is_equal_approx(airlines.chance(offer, type.expected_fee, 14, AirlineType.Tone.FIRM, stars), 0.9), "the liked tone helps")
	check(is_equal_approx(airlines.chance(offer, type.expected_fee, 14, AirlineType.Tone.FLEXIBLE, stars), 0.6), "the disliked tone hurts")
	check(airlines.chance(offer, type.expected_fee, 14, neutral, 5.0) > Airlines.BASE_CHANCE, "a better rating helps")


func test_proposals() -> void:
	var airlines := Airport.airlines
	var type := _type(&"zippa")
	var sure := AirlineOffer.new(type, 14, type.expected_fee)
	airlines.offers.append(sure)
	check_eq(airlines.propose(sure, 4.0, 14, AirlineType.Tone.FIRM, 3.0), Airlines.Answer.ACCEPTED, "certain deal accepted")
	check(airlines.find_signed(type) != null and airlines.find_signed(type).fee == 4.0, "signed at the proposed fee")
	check(not airlines.offers.has(sure), "offer closed")

	var hopeless_type := _type(&"corvista")
	var hopeless := AirlineOffer.new(hopeless_type, 10, hopeless_type.expected_fee)
	airlines.offers.append(hopeless)
	check_eq(airlines.propose(hopeless, Airlines.FEE_MAX, 10, hopeless_type.dislikes, 1.0), Airlines.Answer.REJECTED, "hopeless terms rejected")
	check(not airlines.offers.has(hopeless), "they walk away")
	for i in 30:
		var offer := airlines.make_offer(5.0)
		if offer != null:
			check(offer.type != hopeless_type, "no new offer from them for a while")
			airlines.offers.erase(offer)

	# A fair chance: never rejected outright; a "no" is a counter-offer halfway between the fees.
	var answers := {}
	var lagoona := _type(&"lagoona")
	for seed_value in 40:
		airlines.rng.seed = seed_value
		var offer := AirlineOffer.new(lagoona, 8, lagoona.expected_fee)
		airlines.offers.append(offer)
		var proposed_fee := lagoona.expected_fee * 1.25
		var answer := airlines.propose(offer, proposed_fee, 8, AirlineType.Tone.FIRM, lagoona.min_stars)
		answers[answer] = true
		if answer == Airlines.Answer.COUNTER:
			check_eq(offer.fee, roundf((proposed_fee + lagoona.expected_fee) * 0.5), "counter fee halfway")
			check(airlines.accept_counter(offer) != null, "a counter-offer can be signed")
		airlines.signed = airlines.signed.filter(func(a: Airline) -> bool: return a.type != lagoona)
	check(answers.has(Airlines.Answer.COUNTER) and answers.has(Airlines.Answer.ACCEPTED), "both answers happen: %s" % [answers.keys()])
	check(not answers.has(Airlines.Answer.REJECTED), "never walks away with a fair chance")


func test_offers_arrive_and_expire() -> void:
	var airlines := Airport.airlines
	sim_seconds(Airlines.FIRST_OFFER_AFTER + 1.0)
	check_eq(airlines.offers.size(), 1, "the first offer after two minutes")
	var offer := airlines.offers[0]
	check(Airport.stars() >= offer.type.min_stars, "only airlines the rating allows")
	sim_seconds(Airlines.OFFER_LIFETIME)
	check(not airlines.offers.has(offer), "it expires")
	# A badly rated airport only hears from airlines without demands.
	for i in 40:
		var low := airlines.make_offer(1.0)
		if low != null:
			check(low.type.min_stars <= 1.0, "%s needs %.1f stars" % [low.type.display_name, low.type.min_stars])
			airlines.offers.erase(low)


func test_unhappy_airline_leaves() -> void:
	var airlines := Airport.airlines
	var airline := airlines.signed[0]
	var events: Array[String] = []
	airlines.airline_unhappy.connect(func(a: Airline) -> void: events.append("unhappy " + a.type.code))
	airlines.airline_left.connect(func(a: Airline) -> void: events.append("left " + a.type.code))
	# Late flights alone only drag happiness down to LATE_SCORE (50) now that missed passengers are
	# gone (removed 2026-11-14; PR 2 reworks the airline rating), so push the rating directly.
	for i in 20:
		if airlines.signed.has(airline):
			airlines._rate(airline, 0.0)
	check(not airlines.signed.has(airline), "it ended the deal")
	check_eq(events, ["unhappy VR", "left VR"] as Array[String], "the player is told")


func test_airlines_are_saved() -> void:
	var airlines := Airport.airlines
	airlines.sign_deal(_type(&"brisk"), 8, 21.0)
	airlines.signed[0].happiness = 55.0
	var offer := AirlineOffer.new(_type(&"zippa"), 12, 9.0)
	offer.is_counter = true
	airlines.offers.append(offer)
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check_eq(airlines.signed.size(), 2, "deals restored")
	check_eq(airlines.signed[1].fee, 21.0, "fee restored")
	check_eq(airlines.signed[0].happiness, 55.0, "happiness restored")
	check_eq(airlines.offers.size(), 1, "offer restored")
	check(airlines.offers[0].is_counter, "still a counter-offer")


func test_old_save_keeps_the_starter() -> void:
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	data.erase("airlines")
	Airport.load_state(data)
	check_eq(Airport.airlines.signed.size(), 1, "the starter deal")


func test_panel_lists_and_ends_deals() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	check_eq((ui("TopButtons/AirlinesButton") as Button).text, "Airlines (1)", "button shows the open offer")
	await press(ui("TopButtons/AirlinesButton"))
	await frames(2)
	var list := ui("AirlinesPanel/Content/ListView")
	var rows := list.get_children().filter(func(c: Node) -> bool: return c is HBoxContainer)
	check_eq(rows.size(), 5, "one row per signed airline")
	check(((rows[0] as Node).get_child(0) as Label).text.begins_with("Velora Regional"), "starter listed first")
	var capacity := (ui("AirlinesPanel/Content/CapacityLabel") as Label).text
	check(capacity.contains("60 flights/h") and capacity.contains("Signed: 60 flights/h + 10 cargo"), "capacity line: '%s'" % capacity)
	var end_button := (rows[2] as Node).get_child(1) as Button
	await press(end_button)
	check_eq(Airport.airlines.signed.size(), 5, "first tap only arms the button")
	await press(end_button)
	check_eq(Airport.airlines.signed.size(), 4, "second tap ends the deal")


func test_counter_offer_through_the_panel() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var offer: AirlineOffer = Airport.airlines.offers[0]
	offer.is_counter = true
	offer.fee = 15.0
	hud().show_airlines()
	await frames(2)
	await press(ui("AirlinesPanel/Content/ListView").get_children().filter(func(c: Node) -> bool: return c is Button)[0])
	check(ui("AirlinesPanel/Content/NegotiationView/CounterButtons").visible, "sign / decline shown")
	await press(ui("AirlinesPanel/Content/NegotiationView/CounterButtons/SignButton"))
	var signed := Airport.airlines.find_signed(offer.type)
	check(signed != null and signed.fee == 15.0, "signed at the counter-offer's fee")


func test_planes_wear_airline_colors() -> void:
	ShowcaseAirport.build(0.0)
	var flight := first_flight()
	await start_game()
	sim_seconds(flight.departure_time - Airport.sim_time - 60.0)
	await frames(2)
	var planes := main.get_node("Planes") as PlaneLayer
	check(planes._planes.has(flight), "plane drawn")
	if planes._planes.has(flight):
		check_eq(planes._planes[flight].tail_color, flight.airline.type.color, "tail in the airline's color")
