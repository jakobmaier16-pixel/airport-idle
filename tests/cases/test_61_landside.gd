extends TestCase
## Landside pieces (design doc §4, "Landside grows piece by piece"): data rules, placing from the
## build menu, and the start layout in the showcase.


func _landside_pieces() -> Array[BuildingType]:
	var result: Array[BuildingType] = []
	for type in Airport.CATALOG.types:
		if type.category == "Landside" and not type.sub_category.is_empty():
			result.append(type)
	return result


func test_pieces_follow_the_landside_rules() -> void:
	var pieces := _landside_pieces()
	check(pieces.size() >= 35, "the whole catalogue is there (%d pieces)" % pieces.size())
	var ids: Dictionary[StringName, bool] = {}
	for type in pieces:
		check(not ids.has(type.id), "%s: one type per id" % type.id)
		ids[type.id] = true
		check_eq(type.zone_rule, BuildingType.ZoneRule.LANDSIDE, "%s: landside only" % type.id)
		# Decorative: no role, no passenger access, no staff, no running cost (design doc §4, nothing defined yet).
		check_eq(type.role, BuildingType.Role.NONE, "%s: no simulation role" % type.id)
		check_eq(type.front_access, BuildingType.Access.NONE, "%s: no front access" % type.id)
		check_eq(type.back_access, BuildingType.Access.NONE, "%s: no back access" % type.id)
		check_eq(type.running_cost_per_minute, 0.0, "%s: no running cost" % type.id)
		check(type.build_cost > 0.0, "%s: has a (placeholder) price" % type.id)
		check_eq(type.unlocked_at, 0, "%s: part of the start kit" % type.id)
		check(type.footprint.x >= 1 and type.footprint.y >= 1, "%s: has a footprint" % type.id)
	for sub in ["Roads", "Curb", "Sidewalk", "Car park", "Props"]:
		check(pieces.any(func(t: BuildingType) -> bool: return t.sub_category == sub), "sub-category %s exists" % sub)


func test_every_piece_places_rotates_and_demolishes() -> void:
	Airport.economy.balance = 1.0e6
	var origin := at(Vector2i(20, 20))
	for type in _landside_pieces():
		for steps in 4:
			var before := Airport.economy.balance
			var building := Airport.place_building(type, origin, steps)
			check(building != null, "%s placed, rotation %d" % [type.id, steps])
			if building == null:
				continue
			check_eq(building.get_rect().size, Building.rotated_size(type.footprint, steps), "%s: rotated footprint" % type.id)
			check_eq(before - Airport.economy.balance, type.build_cost, "%s: costs its price" % type.id)
			check_eq(Airport.place_building(type, origin, steps), null, "%s: the cells are taken now" % type.id)
			check(Airport.demolish(building), "%s demolished" % type.id)
			check(Airport.can_place(type, origin, steps), "%s: cells free again" % type.id)
	# Pieces stay on the map.
	check(not Airport.can_place(type_of(&"road_country_straight"), Vector2i(-1, 5), 0), "no piece outside the map")


func test_pieces_do_not_change_what_the_airport_does() -> void:
	# The same airport with and without the landside layout: the simulation is the same.
	var without := _state_after(false)
	var with_pieces := _state_after(true)
	check_eq(with_pieces, without, "same simulation state with and without landside pieces")


# The saved state after a minute of play, without the landside buildings and the id counter.
func _state_after(with_landside: bool) -> String:
	Airport.reseed(321)
	ShowcaseAirport.build(60.0, Vector2i.ZERO, with_landside)
	sim_seconds(30)
	var state := Airport.save_state()
	var landside := _landside_pieces().map(func(t: BuildingType) -> String: return str(t.id))
	state["buildings"] = (state["buildings"] as Array).filter(func(entry: Dictionary) -> bool: return not landside.has(entry["type"]))
	state.erase("next_building_id")
	return BehaviourHash.canonical_json(state).sha256_text()


func test_showcase_has_the_whole_layout() -> void:
	ShowcaseAirport.build(0.0)
	check(ShowcaseLandside.failures.is_empty(), "every piece of the layout fits: %s" % [ShowcaseLandside.failures])
	var used: Dictionary[StringName, int] = {}
	for building in Airport.buildings:
		used[building.type.id] = used.get(building.type.id, 0) + 1
	for type in _landside_pieces():
		check(used.has(type.id), "showcase has a %s" % type.display_name)
	check(ShowcaseLandside.placed >= 400, "a real start layout, not a handful of pieces (%d)" % ShowcaseLandside.placed)
	# Where the layout meets the terminal: sidewalk in front of the entrance, nothing walked over.
	for building in Airport.buildings:
		var problem := Airport.connection_problem(building.type, building.origin_cell, building.rotation_steps)
		check(problem.is_empty(), "%s connected: %s" % [building.type.display_name, problem])


func test_layout_is_on_the_landside_of_the_terminal() -> void:
	ShowcaseAirport.build(0.0)
	var entrance: Building = null
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.ENTRANCE:
			entrance = building
	for building in Airport.buildings:
		if building.type.category == "Landside" and not building.type.sub_category.is_empty():
			check(building.get_rect().end.y <= entrance.origin_cell.y, "%s lies north of the terminal" % building.type.id)
			for cell in building.get_cells():
				check_eq(Airport.grid.get_zone(cell), AirportGrid.Zone.LANDSIDE, "%s stands on landside ground" % building.type.id)
				break


func test_place_a_piece_from_the_build_menu() -> void:
	await start_game()
	await open_build_view()
	check(await place("Country road", at(Vector2i(20, 12)), 1), "a road placed rotated, from Landside > Roads")
	check(await place("Bollard", at(Vector2i(30, 12))), "a bollard placed from Landside > Props")
	var row := ui("BuildMenu/BuildingButtons")
	await press(_menu_button(row, "‹"))
	var texts: Array = row.get_children().filter(func(b: Node) -> bool: return not b.is_queued_for_deletion()).map(func(b: Node) -> String: return (b as Button).text)
	check(texts.has("Roads ›") and texts.has("Props ›") and texts.has("Car park"), "Landside lists its sub-categories and the car park: %s" % [texts])
	await close_build_view()
