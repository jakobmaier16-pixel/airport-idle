class_name ShowcaseAirport
extends RefCounted
## A ready-made airport that uses every current feature, so updates can be tried on the device
## without building by hand. Test builds load it on the first start after each new export
## (see SaveGame); the tests and screenshots use the same layout.
## **When a feature is added, add it here too**, so the newest feature is visible after an update.
## The layout is written in cells of the 64 x 64 reference map and placed around the middle of the
## real map by `MapAnchor`, so it works on every map size that holds the 1,000-cell runway.
## Real scale (1 cell = 2 m): stands are 20 x 23 (narrow) and 35 x 40 (wide-body) cells, each served
## by exactly one gate, with a parallel taxiway between the stands and the runway.

## Builds the showcase into an empty airport. `warm_up_seconds` lets the airport run for a while
## first, so it's already busy when the player looks at it: the first flight is on its way and
## after the default 3 minutes its plane is at the stand, the next one is not far behind.
## `map_size` (tests only) builds it on a map of another size; zero is the game's map.
## `with_landside` false leaves out the landside pieces (scripts/dev/showcase_landside.gd): the behaviour
## hash and the device benchmark measure the simulation and keep their airport.
static func build(warm_up_seconds: float = 180.0, map_size: Vector2i = Vector2i.ZERO, with_landside: bool = true) -> void:
	Airport.reset(true, -1, map_size)
	var catalog := Airport.CATALOG
	# One layout update for the whole layout instead of one per building (the real-scale runway
	# makes each update expensive).
	Airport.begin_batch()
	# Walkways: a landside hall and an airside walkway along the gates.
	Airport.paint_walkway(_cells(Vector2i(18, 21), Vector2i(28, 7)), true)
	Airport.paint_walkway(_cells(Vector2i(6, 31), Vector2i(82, 3)), true)

	# Terminal: Entrance -> Check-in -> Security -> Gate -> Stand (flights use the gates).
	Airport.place_building(catalog.find(&"entrance"), _at(Vector2i(30, 19)), 0)
	Airport.place_building(catalog.find(&"check_in"), _at(Vector2i(20, 22)), 2)
	Airport.place_building(catalog.find(&"check_in"), _at(Vector2i(39, 22)), 2)
	Airport.place_building(catalog.find(&"security"), _at(Vector2i(30, 28)), 0)
	Airport.place_building(catalog.find(&"gate"), _at(Vector2i(14, 34)), 0)
	Airport.place_building(catalog.find(&"gate"), _at(Vector2i(64, 34)), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), _at(Vector2i(6, 39)), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), _at(Vector2i(62, 39)), 0)
	# Long-haul (§10.2): gate 3 in the middle with a wide-body stand behind it (wide planes).
	Airport.place_building(catalog.find(&"gate"), _at(Vector2i(27, 34)), 0)
	Airport.place_building(catalog.find(&"wide_body_stand"), _at(Vector2i(26, 39)), 0)
	# Taxiways (§7.5a): a parallel taxiway along the runway (the wide-body stand touches it), and
	# links up to the narrow stands.
	Airport.paint_taxiway(_cells(Vector2i(6, 79), Vector2i(100, 2)), true)
	Airport.paint_taxiway(_cells(Vector2i(15, 62), Vector2i(2, 17)), true)
	Airport.paint_taxiway(_cells(Vector2i(71, 62), Vector2i(2, 17)), true)
	Airport.paint_taxiway(_cells(Vector2i(93, 66), Vector2i(2, 13)), true)

	# A car park beside the landside hall.
	Airport.place_building(catalog.find(&"car_park"), _at(Vector2i(46, 21)), 3)

	# Landside pieces (design doc §4): roads, curb, car park, sidewalks and props. Decorative only.
	if with_landside:
		ShowcaseLandside.build()

	Airport.end_batch()

	# Morning when the player looks (after the warm-up: about 08:00).
	Airport.clock.game_seconds = 7.25 * 3600.0
	if warm_up_seconds > 0.0:
		# The timetable's first slot opens its flight a little after the start: wait for it, so
		# the warm-up always shows a first flight on its way (at most about 10 game hours).
		for i in int(2400.0 / Airport.SIM_STEP):
			if not Airport.schedule.flights.is_empty():
				break
			Airport.step(Airport.SIM_STEP)
	for i in int(warm_up_seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)


## A cell of the reference map (see MapAnchor) on the current map.
static func _at(reference_cell: Vector2i) -> Vector2i:
	return MapAnchor.cell(reference_cell, Airport.grid.size)


static func _first(role: BuildingType.Role) -> Building:
	for building in Airport.buildings:
		if building.type.role == role:
			return building
	return null


## The cells of a rectangle whose origin is given in reference-map cells (see MapAnchor).
static func _cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	origin = _at(origin)
	var result: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			result.append(origin + Vector2i(x, y))
	return result
