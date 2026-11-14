extends TestCase
## Reputation: star rating, on-time rate and delays (design doc §11.7).


func _first_flight() -> Flight:
	return first_flight()


func test_star_rating() -> void:
	var reputation := Reputation.new()
	var new_airport := reputation.stars()
	check(new_airport > 3.0 and new_airport < 5.0, "a new airport has 3–5 stars: %.2f" % new_airport)
	reputation.on_time_rate = 1.0
	check_eq(reputation.stars(), 5.0, "punctual: 5 stars")
	reputation.on_time_rate = 0.0
	check_eq(reputation.stars(), 1.0, "always late: 1 star")
	check_eq(Reputation.shown_stars(3.74), 3.5, "shown in half stars")


func test_on_time_rate() -> void:
	var reputation := Reputation.new()
	for i in 30:
		reputation.record_departure(0.0)
	check(reputation.on_time_rate > 0.97, "punctual flights: %.2f" % reputation.on_time_rate)
	for i in 30:
		reputation.record_departure(Reputation.ON_TIME_LIMIT + 5.0)
	check(reputation.on_time_rate < 0.1, "late flights: %.2f" % reputation.on_time_rate)
	check_eq(reputation.late_departures, 30, "late departures counted")


func test_reputation_sets_demand() -> void:
	var bad := Reputation.demand_factor(1.0)
	var good := Reputation.demand_factor(5.0)
	check(good > bad * 2.0, "a 5-star airport gets far more demand: %.2f vs %.2f" % [good, bad])


func test_showcase_is_punctual_and_well_rated() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(900)
	check(Airport.reputation.departures >= 8, "flights departed: %d" % Airport.reputation.departures)
	check(Airport.reputation.on_time_rate > 0.8, "mostly on time: %.2f" % Airport.reputation.on_time_rate)
	check(Airport.stars() >= 4.0, "a good airport earns at least 4 stars: %.2f" % Airport.stars())


func test_reputation_is_saved() -> void:
	Airport.reputation.on_time_rate = 0.42
	Airport.reputation.departures = 7
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	Airport.load_state(data)
	check(is_equal_approx(Airport.reputation.on_time_rate, 0.42), "on-time rate restored")
	check_eq(Airport.reputation.departures, 7, "departures restored")


func test_hud_shows_stars() -> void:
	await start_game()
	await frames(2)
	var stars := ui("InfoPanel/RatingRow/Stars") as StarRating
	check_eq(stars.value, Reputation.shown_stars(Airport.stars()), "stars drawn")
	var text := (ui("InfoPanel/RatingRow/RatingLabel") as Label).text
	check(text.ends_with("Regional airport"), "rating line with the tier: '%s'" % text)
	hud().show_stats()
	await frames(1)
	var stats := (ui("StatsPanel/Content/PunctualityLabel") as Label).text
	check(stats.contains("On time"), "details in the statistics: '%s'" % stats)
