extends TestCase
## VIP visits (design doc §14.2).


func _run_vip_visit(warm_up: float = 1.0) -> Array:
	var results := []
	Airport.vip_result.connect(func(happy: bool, mood: float) -> void: results.append([happy, mood]))
	sim_seconds(warm_up)
	var flight := Airport.announce_vip()
	check(flight != null, "a VIP is announced on a departure")
	var vip_seen := [false]
	for i in 6000:
		Airport.step(Airport.SIM_STEP)
		if not vip_seen[0] and Airport.passenger_flow.passengers.any(func(p: Passenger) -> bool: return p.is_vip):
			vip_seen[0] = true
			var vip: Passenger = Airport.passenger_flow.passengers.filter(func(p: Passenger) -> bool: return p.is_vip)[0]
			check(vip.flight == flight, "on the announced flight")
			check_eq(vip.type, FlightSchedule.BUSINESS, "travelling business")
			check_eq(PassengerLayer.color_of(vip), PassengerLayer.VIP_COLOR, "drawn in gold")
		if not results.is_empty():
			break
	check(vip_seen[0], "the VIP arrived")
	return results


func test_happy_vip_brings_money_and_stars() -> void:
	ShowcaseAirport.build(0.0)
	var money := Airport.economy.balance
	var results := _run_vip_visit()
	check_eq(results.size(), 1, "the visit ended once")
	if results.is_empty():
		return
	check(results[0][0], "a well-run airport makes the VIP happy: %d %%" % roundi(results[0][1]))
	check(Airport.reputation.penalty < 0.0, "a bonus on the rating for a while")


func test_unhappy_vip_costs_reputation() -> void:
	ShowcaseAirport.build(0.0)
	# Security nearly closed: the VIP waits far too long or misses the flight.
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SECURITY)[0]
	security.fast_track = false
	while Airport.staff_at(security).size() > 1:
		Airport.dismiss(security)
	var normal := security.type.service_time
	security.type.service_time = 40.0
	var results := _run_vip_visit(240.0)  # a long queue first
	security.type.service_time = normal
	check(not results.is_empty() and not results[0][0], "the VIP was unhappy")
	check(Airport.reputation.penalty > 0.0, "the rating suffers for a while")


func test_reward() -> void:
	var money := Airport.economy.balance
	Airport._on_vip_finished(true, 95.0)
	check_eq(Airport.economy.balance, money + Airport.VIP_REWARD, "€5,000 for a happy VIP")
	check_eq(Airport.reputation.penalty, -Airport.VIP_STARS, "half a star more for a while")


func test_vips_only_from_national() -> void:
	Airport.incidents_automatic = true
	sim_seconds(Airport.VIP_EVERY_MIN + 5.0)
	check(not Airport.passenger_flow.schedule.flights.any(func(f: Flight) -> bool: return f.vip_pending), "no VIPs for a regional airport")


func test_bonus_never_exceeds_five_stars() -> void:
	Airport.reputation.penalty = -2.0
	Airport.reputation.on_time_rate = 1.0
	check(Airport.stars() <= 5.0, "five stars at most")


func test_notice() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(1)
	await start_game()
	Airport.announce_vip()
	await frames(1)
	check(hud().notice_text().begins_with("A VIP flies with"), "notice: '%s'" % hud().notice_text())
