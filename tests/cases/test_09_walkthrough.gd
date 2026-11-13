extends TestCase
## End-to-end walkthrough: builds a complete airport only through the touch UI, like a player,
## then checks that passengers flow and depart. If this passes, the core loop works.


func test_build_airport_by_touch_and_fly_passengers() -> void:
	Airport.reset()  # a real new game: an empty field with the starting runway
	await start_game()
	await open_build_view()
	await show_whole_map()

	await paint("WalkwayButton", at(Vector2i(18, 21)), at(Vector2i(45, 27)))
	await paint("WalkwayButton", at(Vector2i(10, 31)), at(Vector2i(53, 33)))

	check(await place("Entrance", at(Vector2i(30, 19))), "entrance")
	check(await place("Check-in", at(Vector2i(20, 22)), 2), "check-in 1 (facing the hall)")
	check(await place("Check-in", at(Vector2i(39, 22)), 2), "check-in 2")
	check(await place("Security", at(Vector2i(30, 28))), "security on the border")
	check(await place("Gate", at(Vector2i(14, 34))), "gate 1")
	check(await place("Gate", at(Vector2i(42, 34))), "gate 2")
	check(await place("Stand", at(Vector2i(10, 39))), "stand 1")
	check(await place("Stand", at(Vector2i(38, 39))), "stand 2")
	check(not Airport.passenger_flow.route_problem.is_empty(), "stands without a taxiway get no planes")
	# Taxiways from both stands down to the runway (design doc §7.5a).
	await paint("TaxiwayButton", at(Vector2i(15, 51)), at(Vector2i(16, 56)))
	await paint("TaxiwayButton", at(Vector2i(43, 51)), at(Vector2i(44, 56)))
	check(not Airport.passenger_flow.route_problem.is_empty(), "without a baggage claim arrivals have no way out")
	check(await place("Baggage claim", at(Vector2i(37, 27))), "baggage claim on the border")

	check_eq(Airport.buildings.size(), 10, "all buildings placed (and the runway)")
	await frames(1)
	var layer := main.get_node("Buildings")
	var unconnected: Array = layer._hints.values().filter(func(l: Label3D) -> bool: return l.visible and l.text != "Needs staff")
	check_eq(unconnected.size(), 0, "every building connected")
	check(Airport.passenger_flow.route_problem.is_empty(), "complete route: %s" % Airport.passenger_flow.route_problem)

	# Staff the counters like a manager: walk over, tap the station, press Hire until it's full.
	await close_build_view()
	for building in Airport.buildings:
		if not Airport.needs_staff(building):
			continue
		var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
		var center := Airport.grid.block_center(building.origin_cell, size)
		await stand_and_look(Airport.grid.world_to_cell(center + Vector3(0.0, 0.0, 8.0)), building)
		tap(manager_camera().unproject_position(center + Vector3(0.0, 1.5, 0.0)))
		await frames(1)
		check(hud().shown_station == building, "%s panel opened by tap" % building.type.display_name)
		var hire := ui("StationPanel/Content/StaffButtons/HireButton") as Button
		for i in 6:
			if hire.disabled:
				break
			await press(hire)
			await frames(1)
		check_eq(Airport.staff_at(building).size(), building.service_slots(), "%s fully staffed" % building.type.display_name)

	# Sign a second airline (design doc §10.1): wait for an offer, open it, lower the fee until
	# they surely agree, and answer in the tone they like.
	sim_seconds(Airlines.FIRST_OFFER_AFTER + 1.0)
	check_eq(Airport.airlines.offers.size(), 1, "an airline made an offer")
	await press(ui("TopButtons/AirlinesButton"))
	await frames(1)
	var offer: AirlineOffer = Airport.airlines.offers[0]
	var offer_button: Button = ui("AirlinesPanel/Content/ListView").get_children().filter(
		func(c: Node) -> bool: return c is Button)[0]
	await press(offer_button)
	var chance_label := ui("AirlinesPanel/Content/NegotiationView/ChanceLabel") as Label
	# The shown chance is for a neutral tone; the liked tone adds 15 points.
	var shown_chance := func() -> int: return chance_label.text.get_slice("about ", 1).to_int()
	for i in 20:
		if shown_chance.call() >= 85:
			break
		await press(ui("AirlinesPanel/Content/NegotiationView/TermsRow/FeeMinus"))
	check(shown_chance.call() >= 85, "a lower fee makes it likely: '%s'" % chance_label.text)
	var tone_buttons := {AirlineType.Tone.FIRM: "FirmButton", AirlineType.Tone.FRIENDLY: "FriendlyButton", AirlineType.Tone.FLEXIBLE: "FlexibleButton"}
	await press(ui("AirlinesPanel/Content/NegotiationView/ToneButtons/" + tone_buttons[offer.type.likes]))
	check_eq(Airport.airlines.signed.size(), 2, "%s signed through the panel" % offer.type.display_name)
	await press(ui("AirlinesPanel/Content/CloseButton"))
	await open_build_view()

	# Flights depart within the next 6 minutes.
	sim_seconds(360)
	await frames(2)
	check(Airport.passenger_flow.departed_count > 15, "passengers departed: %d" % Airport.passenger_flow.departed_count)
	check(Airport.passenger_flow.arrived_count > 15, "arriving passengers left the airport: %d" % Airport.passenger_flow.arrived_count)
	check(main.get_node("Planes").plane_count() > 0, "the next planes are at their stands")
	var status := (ui("InfoPanel/StatusLabel") as Label).text
	check(status.begins_with("Passengers:"), "status shows passenger numbers: '%s'" % status)

	await close_build_view()
	check(manager_camera().current, "back to the manager view with a working airport")

	# Manage a station: tap security and upgrade it to a third lane, once the airport has earned
	# enough for it (how fast depends on which airline made the offer).
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SECURITY)[0]
	for minute in 10:
		if Airport.economy.can_afford(security.next_upgrade().cost):
			break
		sim_seconds(60)
	check(Airport.economy.can_afford(security.next_upgrade().cost), "the airport earned enough for the upgrade: %s" % Economy.format(Airport.economy.balance))
	await stand_and_look(at(Vector2i(32, 33)), security)
	tap(manager_camera().unproject_position(Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 1.5, 0.0)))
	await frames(1)
	await press(ui("StationPanel/Content/UpgradeButton"))
	check_eq(security.service_slots(), 3, "security upgraded to 3 lanes through the panel")
