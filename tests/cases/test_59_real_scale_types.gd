extends TestCase
## Real-scale airside types (game_design §16): 1 cell = 2 m. Stands are sized by the wingspan of the
## planes they take, runways by their length, and one stand serves exactly one gate. Every number is
## read from the data (building types, TimetableSlot.WINGSPAN_M), never pasted here.

## Runways at least this long (ICAO code 4: 1,800 m and up; the starting airport has 2,000 m).
const MIN_RUNWAY_LENGTH_M: float = 2000.0
## ... and at least this wide (code E runways are 45 m).
const MIN_RUNWAY_WIDTH_M: float = 45.0


func _types_with_role(role: BuildingType.Role) -> Array[BuildingType]:
	var result: Array[BuildingType] = []
	for type in Airport.CATALOG.types:
		if type.role == role:
			result.append(type)
	return result


func _widest_accepted_m(stand: BuildingType) -> float:
	var widest := 0.0
	for plane_class: TimetableSlot.PlaneClass in TimetableSlot.PlaneClass.values():
		if stand.fits(plane_class):
			widest = maxf(widest, TimetableSlot.WINGSPAN_M[plane_class])
	return widest


func test_every_stand_is_at_least_as_wide_as_the_planes_it_accepts() -> void:
	var stands := _types_with_role(BuildingType.Role.AIRCRAFT_STAND)
	check(stands.size() >= 2, "a narrow-body and a wide-body stand exist")
	for stand in stands:
		var widest := _widest_accepted_m(stand)
		check(widest > 0.0, "%s takes some plane class" % stand.display_name)
		check(stand.width_m(Airport.grid.cell_size) >= widest,
			"%s is %.0f m wide, its widest plane has %.0f m wingspan" % [stand.display_name, stand.width_m(Airport.grid.cell_size), widest])
		# Not absurdly big either: at most 15 m of apron beside the wingspan.
		check(stand.width_m(Airport.grid.cell_size) <= widest + 15.0, "%s is not much wider than its planes" % stand.display_name)


func test_bigger_stands_take_everything_smaller_stands_take() -> void:
	var stands := _types_with_role(BuildingType.Role.AIRCRAFT_STAND)
	for big in stands:
		for small in stands:
			if big.width_m(Airport.grid.cell_size) >= small.width_m(Airport.grid.cell_size):
				for plane_class: TimetableSlot.PlaneClass in TimetableSlot.PlaneClass.values():
					check(not small.fits(plane_class) or big.fits(plane_class), "%s takes what %s takes" % [big.display_name, small.display_name])
	# Every plane class has a stand, and the widest class only fits the widest stands.
	for plane_class: TimetableSlot.PlaneClass in TimetableSlot.PlaneClass.values():
		check(stands.any(func(t: BuildingType) -> bool: return t.fits(plane_class)), "a stand takes class %d" % plane_class)
	var widest_class: TimetableSlot.PlaneClass = TimetableSlot.PlaneClass.WIDE
	for stand in stands:
		check_eq(stand.fits(widest_class), stand.wide_body, "%s: wide-body flag follows the class" % stand.display_name)
		check_eq(stand.wide_body, stand.stand_class == BuildingType.StandClass.WIDE, "%s: derived from stand_class" % stand.display_name)
	check(not type_of(&"gate").fits(TimetableSlot.PlaneClass.NARROW), "only stands take planes")


func test_runway_is_at_least_two_kilometres() -> void:
	var runways := _types_with_role(BuildingType.Role.RUNWAY)
	check(runways.size() >= 1, "there is a runway type")
	for runway in runways:
		var length_m := maxi(runway.footprint.x, runway.footprint.y) * Airport.grid.cell_size
		var width_m := mini(runway.footprint.x, runway.footprint.y) * Airport.grid.cell_size
		check(length_m >= MIN_RUNWAY_LENGTH_M, "%s is %.0f m long" % [runway.display_name, length_m])
		check(width_m >= MIN_RUNWAY_WIDTH_M, "%s is %.0f m wide" % [runway.display_name, width_m])
	# The runway a new game starts with is that type.
	Airport.reset()
	var laid: Array[Building] = []
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.RUNWAY:
			laid.append(building)
	check_eq(laid.size(), 1, "a new game starts with one runway")
	check(laid[0].type in runways, "it is a real-scale runway")


func _gate_with_stand(stand_id: StringName, gate_cell: Vector2i, stand_cell: Vector2i) -> Building:
	var gate := Airport.place_building(type_of(&"gate"), gate_cell, 0)
	var stand := Airport.place_building(type_of(stand_id), stand_cell, 0)
	check(gate != null and stand != null, "gate and %s placed" % stand_id)
	return gate


func test_a_stand_takes_its_own_class_or_a_smaller_one() -> void:
	var narrow := type_of(&"aircraft_stand")
	var wide := type_of(&"wide_body_stand")
	check(wide.fits(TimetableSlot.PlaneClass.NARROW), "a narrow plane fits the wide-body stand")
	check(narrow.fits(TimetableSlot.PlaneClass.NARROW), "narrow on narrow")
	check(wide.fits(TimetableSlot.PlaneClass.WIDE), "wide on wide")
	check(not narrow.fits(TimetableSlot.PlaneClass.WIDE), "a wide-body plane never takes a narrow stand")
	var narrow_gate := _gate_with_stand(&"aircraft_stand", at(Vector2i(10, 34)), at(Vector2i(6, 39)))
	var wide_gate := _gate_with_stand(&"wide_body_stand", at(Vector2i(34, 34)), at(Vector2i(30, 39)))
	check(Airport.stand_behind(narrow_gate).type == narrow and Airport.stand_behind(wide_gate).type == wide, "each gate has its own stand")


func test_a_gate_may_not_share_its_stand() -> void:
	check(Airport.place_building(type_of(&"gate"), at(Vector2i(10, 34)), 0) != null, "gate 1")
	check(Airport.place_building(type_of(&"aircraft_stand"), at(Vector2i(6, 39)), 0) != null, "its stand")
	# A second gate whose back touches the same stand is refused, wherever along the stand it is.
	for x in [16, 21, 24]:
		check_eq(Airport.check_placement(type_of(&"gate"), at(Vector2i(x, 34)), 0), "This stand already has a gate", "second gate at x=%d" % x)
	# Beside the stand it is fine.
	check_eq(Airport.check_placement(type_of(&"gate"), at(Vector2i(26, 34)), 0), "", "a gate beside the stand")


func test_a_stand_may_not_reach_two_gates() -> void:
	check(Airport.place_building(type_of(&"gate"), at(Vector2i(10, 34)), 0) != null, "gate 1 (no stand yet: build first, connect after)")
	check(Airport.place_building(type_of(&"gate"), at(Vector2i(20, 34)), 0) != null, "gate 2")
	check_eq(Airport.check_placement(type_of(&"aircraft_stand"), at(Vector2i(6, 39)), 0), "A stand serves one gate: two gates would reach it", "a stand under both gates")
	check_eq(Airport.check_placement(type_of(&"wide_body_stand"), at(Vector2i(6, 39)), 0), "A stand serves one gate: two gates would reach it", "a wide-body stand too")
	check_eq(Airport.check_placement(type_of(&"aircraft_stand"), at(Vector2i(-9, 39)), 0), "", "a stand under gate 1 only")


func test_a_gate_faces_one_stand_and_a_stand_gets_one_gate() -> void:
	check(Airport.place_building(type_of(&"gate"), at(Vector2i(24, 34)), 0) != null, "a gate")
	check(Airport.place_building(type_of(&"aircraft_stand"), at(Vector2i(5, 39)), 0) != null, "a stand under it")
	check_eq(Airport.check_placement(type_of(&"aircraft_stand"), at(Vector2i(25, 39)), 0), "That gate already has a stand", "a second stand under the same gate")
	# Two stands side by side and a gate across both: it would not know which one is its own.
	Airport.demolish(Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)[0])
	check(Airport.place_building(type_of(&"aircraft_stand"), at(Vector2i(25, 39)), 0) != null, "the second stand")
	check_eq(Airport.check_placement(type_of(&"gate"), at(Vector2i(22, 34)), 0), "A gate must face one stand only", "a gate across two stands")
	check_eq(Airport.check_placement(type_of(&"gate"), at(Vector2i(10, 34)), 0), "", "a gate over one of them")


func test_every_showcase_gate_has_its_own_stand() -> void:
	ShowcaseAirport.build(0.0)
	var users: Dictionary[Building, int] = {}
	var gates := 0
	for building in Airport.buildings:
		if building.type.back_access != BuildingType.Access.STAND:
			continue
		gates += 1
		var stand := Airport.stand_behind(building)
		check(stand != null, "%s at %s has a stand" % [building.type.display_name, building.origin_cell])
		if stand != null:
			users[stand] = users.get(stand, 0) + 1
	check(gates >= 3, "the showcase has its gates (%d)" % gates)
	for stand in users:
		check_eq(users[stand], 1, "stand at %s serves one gate" % stand.origin_cell)
