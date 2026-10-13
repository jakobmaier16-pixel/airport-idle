extends TestCase
## Contract renewals (design doc §10.4).


func _airline() -> Airline:
	return Airport.airlines.signed[0]


func _offered(airline: Airline) -> AirlineOffer:
	return Airport.airlines.renewal_of(airline)


func test_renewal_offer_before_the_end() -> void:
	var airline := _airline()
	airline.contract_left = Airlines.RENEWAL_NOTICE + 5.0
	sim_seconds(4)
	check(_offered(airline) == null, "not yet")
	sim_seconds(2)
	var offer := _offered(airline)
	check(offer != null, "ten minutes before the end, the airline asks to renew")
	if offer != null:
		check(absf(offer.expires_in - airline.contract_left) < 0.2, "the offer runs until the contract ends")


func test_terms_follow_happiness() -> void:
	var airline := _airline()
	airline.happiness = 90.0
	var happy := Airport.airlines.renewal_terms(airline)
	check_eq(happy.flights_per_hour, airline.flights_per_hour + Airlines.HAPPY_EXTRA_FLIGHTS, "happy airlines want more flights")
	check(happy.fee > airline.fee, "and pay more")
	airline.happiness = 60.0
	check_eq(Airport.airlines.renewal_terms(airline).fee, airline.fee, "content: the same terms")
	airline.happiness = 30.0
	check(Airport.airlines.renewal_terms(airline).fee < airline.fee, "unhappy airlines want a discount")


func test_renewing_keeps_the_airline() -> void:
	var airline := _airline()
	airline.happiness = 90.0
	airline.contract_left = Airlines.RENEWAL_NOTICE - 1.0
	sim_seconds(0.2)
	var offer := _offered(airline)
	check(offer != null, "renewal offered")
	if offer == null:
		return
	var answer := Airport.airlines.propose(offer, offer.fee, offer.flights_per_hour, airline.type.likes, 5.0)
	if answer == Airlines.Answer.COUNTER:
		Airport.airlines.accept_counter(offer)
	elif answer == Airlines.Answer.REJECTED:
		check(false, "a fair renewal at a five-star airport isn't rejected")
	check(Airport.airlines.signed.has(airline), "the same airline")
	check(airline.contract_left > Airlines.CONTRACT_SECONDS - 1.0, "with a new contract")
	check_eq(airline.flights_per_hour, offer.flights_per_hour, "and the new terms")
	check(airline.happiness > 80.0, "and its happiness kept")


func test_no_renewal_means_leaving() -> void:
	var airline := _airline()
	var left: Array[Airline] = []
	Airport.airlines.airline_left.connect(func(a: Airline) -> void: left.append(a))
	airline.contract_left = Airlines.RENEWAL_NOTICE - 1.0
	sim_seconds(0.2)
	Airport.airlines.decline(_offered(airline))
	check(Airport.airlines.signed.has(airline), "it keeps flying until the contract ends")
	sim_seconds(Airlines.RENEWAL_NOTICE)
	check(not Airport.airlines.signed.has(airline), "then it leaves")
	check_eq(left.size(), 1, "and the player is told")


func test_contracts_are_saved() -> void:
	var airline := _airline()
	airline.contract_left = 1234.0
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check_eq(Airport.airlines.signed[0].contract_left, 1234.0, "contract time restored")


func test_panel_shows_renewal() -> void:
	ShowcaseAirport.build(0.0)
	var airline: Airline = Airport.airlines.signed[1]
	sim_seconds(airline.contract_left - Airlines.RENEWAL_NOTICE + 1.0)
	await start_game()
	hud().show_airlines()
	await frames(2)
	var buttons := ui("AirlinesPanel/Content/ListView").get_children().filter(func(c: Node) -> bool: return c is Button)
	check(buttons.any(func(b: Button) -> bool: return b.text.begins_with("Renewal: " + airline.type.display_name)), "renewal listed")
