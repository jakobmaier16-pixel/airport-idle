extends TestCase
## Named areas derived from the walkways and zones (tech_architecture.md §4, game_design §8.2).


func _names() -> Array[String]:
	var names: Array[String] = []
	for area: Dictionary in Airport.areas():
		names.append(area["name"])
	return names


func test_showcase_area_names() -> void:
	ShowcaseAirport.build(0.0)
	check_eq(_names(), ["Check-in Hall", "Gates"] as Array[String], "landside hall and airside gate walkway")
	check_eq(Airport.area_name(Vector2i(24, 25)), "Check-in Hall", "hall cell")
	check_eq(Airport.area_name(Vector2i(31, 32)), "Gates", "airside cell")
	check_eq(Airport.area_name(Vector2i(1, 1)), "", "no walkway, no area")


func test_splitting_the_hall_renames_deterministically() -> void:
	ShowcaseAirport.build(0.0)
	var cut: Array[Vector2i] = []
	for y in range(21, 28):
		cut.append(Vector2i(25, y))
	Airport.paint_walkway(cut, false)
	var names := _names()
	check_eq(names.size(), 3, "hall split in two: %s" % [names])
	check_eq(Airport.area_name(Vector2i(19, 25)), "Check-in Hall", "west part keeps the plain name (lowest cell)")
	check_eq(Airport.area_name(Vector2i(40, 25)), "Check-in Hall 2", "east part is numbered")
	var again := _names()
	check_eq(again, names, "same layout, same names")


func test_unnamed_areas_are_numbered() -> void:
	ShowcaseAirport.build(0.0)
	Airport.paint_walkway([Vector2i(2, 2), Vector2i(3, 2)] as Array[Vector2i], true)
	Airport.paint_walkway([Vector2i(2, 5)] as Array[Vector2i], true)
	check_eq(Airport.area_name(Vector2i(2, 2)), "Landside 1", "first lonely walkway")
	check_eq(Airport.area_name(Vector2i(2, 5)), "Landside 2", "second lonely walkway")


func test_names_survive_save_and_load() -> void:
	ShowcaseAirport.build(0.0)
	var before := _names()
	var state := Airport.save_state()
	Airport.reset()
	Airport.load_state(state)
	check_eq(_names(), before, "same names after loading")
