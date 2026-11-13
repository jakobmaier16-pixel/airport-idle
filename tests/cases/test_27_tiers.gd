extends TestCase
## Airport tiers and milestones (design doc §14.1).


func _make_excellent() -> void:
	for i in Satisfaction.MEMORY:
		Airport.passenger_flow.satisfaction.record("Business", 100.0)
	Airport.reputation.on_time_rate = 1.0


func test_regional_airport_owns_the_middle() -> void:
	check_eq(Airport.progression.tier, Progression.Tier.REGIONAL, "a new airport is regional")
	var land := Airport.progression.owned_land(Airport.grid.size)
	check_eq(land, Progression.STARTING_LAND, "the starting land (one named constant)")
	check_eq(land.position % 200, Vector2i.ZERO, "aligned to the 200-cell land grid")
	check_eq(land.size % 200, Vector2i.ZERO, "a whole number of land pieces")
	var map := Rect2i(Vector2i.ZERO, Airport.grid.size)
	check(map.encloses(land), "inside the map")
	check(absi(land.get_center().x - map.get_center().x) <= 200, "about centred horizontally (within one land piece)")
	check(land.has_point(MapAnchor.from_centre(Vector2i.ZERO, Airport.grid.size)), "the map centre is owned")
	check(land.has_point(at(Vector2i(30, 56))), "the land reaches down to the runway")
	var outside := land.position - Vector2i(2, 2)
	check_eq(Airport.check_placement(type_of(&"check_in"), outside, 0), "Not your land yet (National airport)", "no building outside")
	var row := land.position + Vector2i(-4, 20)
	Airport.paint_walkway(cells(row, Vector2i(12, 1)), true)
	check(not Airport.grid.is_walkway(row + Vector2i(3, 0)), "no painting outside")
	check(Airport.grid.is_walkway(row + Vector2i(9, 0)), "painting inside works")


func test_reaching_national() -> void:
	_make_excellent()
	var progression := Airport.progression
	var reached: Array[Progression.Tier] = []
	progression.tier_reached.connect(func(tier: Progression.Tier) -> void: reached.append(tier))
	var needed := Progression.PASSENGERS_NEEDED[Progression.Tier.NATIONAL]
	progression.passengers = needed - 1
	sim_seconds(1)
	check_eq(progression.tier, Progression.Tier.REGIONAL, "one passenger short")
	progression.passengers = needed
	sim_seconds(0.2)
	check_eq(progression.tier, Progression.Tier.NATIONAL, "national with enough passengers and 3 stars")
	check_eq(reached, [Progression.Tier.NATIONAL] as Array[Progression.Tier], "milestone sent once")
	check(Airport.check_placement(type_of(&"check_in"), Progression.STARTING_LAND.position - Vector2i(2, 2), 0) != "Not your land yet (National airport)", "new land")
	check(Airport.airlines.find_signed(Airlines.CATALOG.find(&"norvane")) != null \
		or Airport.airlines.offers.any(func(o: AirlineOffer) -> bool: return o.type.id == &"norvane"), "a major airline makes an offer")


func test_rating_matters() -> void:
	Airport.reputation.on_time_rate = 0.0
	for i in Satisfaction.MEMORY:
		Airport.passenger_flow.satisfaction.record("Families", 30.0)
	Airport.progression.passengers = 5000
	sim_seconds(1)
	check_eq(Airport.progression.tier, Progression.Tier.REGIONAL, "a badly rated airport doesn't grow")


func test_hub_needs_transfers() -> void:
	_make_excellent()
	var progression := Airport.progression
	progression.tier = Progression.Tier.INTERNATIONAL
	progression.passengers = 50000
	progression.transfers = Progression.TRANSFERS_NEEDED[Progression.Tier.HUB] - 1
	sim_seconds(1)
	check_eq(progression.tier, Progression.Tier.INTERNATIONAL, "not without enough transfers")
	progression.transfers = Progression.TRANSFERS_NEEDED[Progression.Tier.HUB]
	sim_seconds(0.2)
	check_eq(progression.tier, Progression.Tier.HUB, "hub")
	check_eq(progression.next_tier(), -1, "the top")
	check(progression.progress_text(5.0).contains("highest tier"), "progress says so")


func test_passengers_are_counted() -> void:
	ShowcaseAirport.build(0.0)
	var before := Airport.progression.passengers
	sim_seconds(400)
	var flow := Airport.passenger_flow
	check_eq(Airport.progression.passengers - before, flow.departed_count + flow.arrived_count, "departed + arrived")
	check(Airport.progression.passengers - before > 30, "counted: %d" % (Airport.progression.passengers - before))


func test_hub_doubles_connections() -> void:
	ShowcaseAirport.build(0.0)
	var flow := Airport.passenger_flow
	var inbound: Flight = first_flight_with_connection()  # there is something to connect to
	check(inbound != null, "a flight with a connection is planned")
	if inbound == null:
		return
	inbound.route = "Business"  # 25 % connect
	var share := func() -> float:
		var connecting := 0
		for i in 2000:
			if flow._connecting_flight(inbound) != null:
				connecting += 1
		return connecting / 2000.0
	var national: float = share.call()
	Airport.progression.tier = Progression.Tier.HUB
	var hub: float = share.call()
	check(absf(national - 0.25) < 0.05, "national: about 25 %%: %.2f" % national)
	check(absf(hub - 0.5) < 0.05, "hub: about 50 %%: %.2f" % hub)


func test_milestone_panel_and_menu() -> void:
	_make_excellent()
	await start_game()
	Airport.progression.passengers = Progression.PASSENGERS_NEEDED[Progression.Tier.NATIONAL]
	sim_seconds(0.2)
	await frames(2)
	check(hud().is_milestone_open(), "the milestone panel opens")
	check_eq((ui("MilestonePanel/Content/TitleLabel") as Label).text, "National airport!", "title")
	check((ui("MilestonePanel/Content/RewardsLabel") as Label).text.contains("Transfer security"), "rewards listed")
	await press(ui("MilestonePanel/Content/OkButton"))
	check(not hud().is_milestone_open(), "closed with Let's build!")
	await open_build_view()
	check(await pick_building("Transfer security"), "unlocked in the build menu without a note")
	var rating := (ui("InfoPanel/RatingRow/RatingLabel") as Label).text
	check(rating.contains("National airport"), "tier shown next to the stars: '%s'" % rating)


func test_ground_shows_owned_land() -> void:
	await start_game()
	var material := (main.get_node("Ground/MeshInstance3D") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var rect: Vector4 = material.get_shader_parameter(&"owned_rect")
	var grid := Airport.grid
	var land := Progression.STARTING_LAND
	var corner := Vector2(grid.origin.x, grid.origin.z)
	var from := corner + Vector2(land.position) * grid.cell_size
	var to := corner + Vector2(land.end) * grid.cell_size
	check_eq(rect, Vector4(from.x, from.y, to.x, to.y), "regional land shaded")
	Airport.progression.tier = Progression.Tier.NATIONAL
	Airport.land_changed.emit()
	rect = material.get_shader_parameter(&"owned_rect")
	var world := grid.get_world_rect()
	check_eq(rect, Vector4(world.position.x, world.position.y, world.end.x, world.end.y), "the whole map after National")


func test_progression_saved_and_old_buildings_kept() -> void:
	Airport.progression.tier = Progression.Tier.NATIONAL
	Airport.progression.passengers = 4321
	Airport.place_building(type_of(&"check_in"), Vector2i(1, 1), 0)
	var data := JSON.parse_string(JSON.stringify(Airport.save_state())) as Dictionary
	data["progression"]["tier"] = Progression.Tier.REGIONAL  # e.g. an older save
	Airport.load_state(data)
	check_eq(Airport.progression.passengers, 4321, "passengers restored")
	check_eq(Airport.buildings.size(), 2, "a building on land a regional airport doesn't own still loads (plus the runway)")
