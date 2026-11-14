extends TestCase
## Long-haul flights: wide-body stands and planes (design doc §10.2). A wide stand gets wide planes,
## a narrow stand narrow ones (the timetable decides, see test_51_timetable).


func _gate_3() -> Building:
	var gates := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.GATE)
	return gates[2]


func _flights_planned(seconds: float) -> Array[Flight]:
	var seen: Array[Flight] = []
	for i in int(seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if not seen.has(flight):
				seen.append(flight)
	return seen


func test_wide_body_stand_can_be_built_from_the_start() -> void:
	var type := type_of(&"wide_body_stand")
	check_eq(Airport.check_placement(type, at(Vector2i(20, 36)), 0), "", "no tier, no money needed")


func test_long_haul_flies_from_the_wide_body_gate() -> void:
	ShowcaseAirport.build(0.0)
	var wide := 0
	var narrow := 0
	for flight in _flights_planned(1500):
		if flight.plane_class == TimetableSlot.PlaneClass.WIDE:
			wide += 1
			check(flight.gate == _gate_3(), "only from the gate with the wide-body stand")
		else:
			narrow += 1
			check(flight.gate != _gate_3(), "narrow planes keep off the wide stand")
	check(wide >= 2, "wide-body flights: %d" % wide)
	check(narrow >= 2, "narrow-body flights: %d" % narrow)


func test_a_narrow_stand_never_gets_a_wide_plane() -> void:
	ShowcaseAirport.build(0.0)
	for flight in _flights_planned(1500):
		if not flight.stand.type.wide_body:
			check_eq(flight.plane_class, TimetableSlot.PlaneClass.NARROW, "%s at a narrow stand" % flight.number)


func test_wide_body_plane_is_bigger() -> void:
	ShowcaseAirport.build(0.0)
	await start_game()
	var wide_flight: Flight = null
	for i in 20000:
		Airport.step(Airport.SIM_STEP)
		for flight in Airport.schedule.flights:
			if flight.plane_class == TimetableSlot.PlaneClass.WIDE and flight.phase == Flight.Phase.AT_STAND:
				wide_flight = flight
		if wide_flight != null:
			break
	check(wide_flight != null, "a wide-body plane parked")
	if wide_flight == null:
		return
	await frames(2)
	var planes := main.get_node("Planes") as PlaneLayer
	check(planes._planes.has(wide_flight) and planes._planes[wide_flight].size_factor > 1.0, "drawn bigger")
