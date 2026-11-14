extends TestCase
## End-to-end walkthrough: builds a complete airport only through the touch UI, like a player,
## then checks that planes land, taxi to their stands and depart. If this passes, the core loop works.


func test_build_airport_by_touch_and_fly_planes() -> void:
	Airport.reset()  # a real new game: an empty field with the starting runway
	# Real-scale stands cost EUR 18,000 each: the starting money pays for one, so the player is
	# given what the second gate and stand need.
	Airport.economy.bonus(40000.0)
	await start_game()
	await open_build_view()
	# The airside is 20-cell stands and a taxiway down to the runway: taller than the reference
	# area, so look at the middle of it from higher up.
	await show_whole_map(170.0, Airport.grid.cell_to_world(at(Vector2i(32, 50))))

	await paint("WalkwayButton", at(Vector2i(18, 21)), at(Vector2i(45, 27)))
	await paint("WalkwayButton", at(Vector2i(10, 31)), at(Vector2i(53, 33)))

	check(await place("Entrance", at(Vector2i(30, 19))), "entrance")
	check(await place("Check-in", at(Vector2i(20, 22)), 2), "check-in 1 (facing the hall)")
	check(await place("Check-in", at(Vector2i(39, 22)), 2), "check-in 2")
	check(await place("Security", at(Vector2i(30, 28))), "security on the border")
	check(await place("Gate", at(Vector2i(14, 34))), "gate 1")
	check(await place("Gate", at(Vector2i(42, 34))), "gate 2")
	check(await place("Stand", at(Vector2i(6, 39))), "stand 1")
	check(await place("Stand", at(Vector2i(38, 39))), "stand 2")
	check(Airport.usable_gates().is_empty(), "stands without a taxiway get no planes")
	# Taxiways from both stands down to the runway (design doc §7.5a).
	# The taxiway brush is 24 m wide, so each strip costs about €11k: top up the budget.
	Airport.economy.balance += 25000.0
	await paint("TaxiwayButton", at(Vector2i(15, 62)), at(Vector2i(16, 80)))
	await paint("TaxiwayButton", at(Vector2i(43, 62)), at(Vector2i(44, 80)))

	check_eq(Airport.buildings.size(), 9, "all buildings placed (and the runway)")
	await frames(1)
	var layer := main.get_node("Buildings")
	var unconnected: Array = layer._hints.values().filter(func(l: Label3D) -> bool: return l.visible)
	check_eq(unconnected.size(), 0, "every building connected")
	check_eq(Airport.usable_gates().size(), 2, "both gates can have flights")

	# Tapping a building in the manager view opens its panel: name, zone, close.
	await close_build_view()
	var security: Building = Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.SECURITY)[0]
	await stand_and_look(at(Vector2i(32, 33)), security)
	tap(manager_camera().unproject_position(Airport.grid.block_center(security.origin_cell, Vector2i(5, 3)) + Vector3(0.0, 1.5, 0.0)))
	await frames(1)
	check(hud().shown_station == security, "security panel opened by tap")
	check((ui("StationPanel/Content/TitleLabel") as Label).text.contains("Security"), "the panel names the building")
	check((ui("StationPanel/Content/InfoLabel") as Label).text.contains("Border"), "and its zone")
	await press(ui("StationPanel/Content/CloseButton"))
	check(hud().shown_station == null, "the panel closes")

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

	# Planes land, taxi to their stands and depart within the next 6 minutes.
	var seen_at_stand := false
	for i in 36:
		sim_seconds(10.0)
		await frames(1)
		seen_at_stand = seen_at_stand or main.get_node("Planes").plane_count() > 0
	check(seen_at_stand, "a plane was drawn at or on its way to a stand")
	check(Airport.reputation.departures > 0, "flights departed: %d" % Airport.reputation.departures)
	var status := (ui("InfoPanel/StatusLabel") as Label).text
	check(status.begins_with("Flights departed:"), "status shows the departures: '%s'" % status)

	await close_build_view()
	check(manager_camera().current, "back to the manager view with a working airport")
