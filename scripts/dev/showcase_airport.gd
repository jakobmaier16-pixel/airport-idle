class_name ShowcaseAirport
extends RefCounted
## A ready-made airport that uses every current feature, so updates can be tried on the device
## without building by hand. Test builds load it on the first start after each new export
## (see SaveGame); the tests and screenshots use the same layout.
## **When a feature is added, add it here too**, so the newest feature is visible after an update.

## Builds the showcase into an empty airport. `warm_up_seconds` lets passengers flow for a while
## first, so the airport is already busy when the player looks at it.
static func build(warm_up_seconds: float = 60.0) -> void:
	Airport.reset()
	var catalog := Airport.CATALOG

	# Zones: landside in the north, airside in the south (security sits on the border).
	Airport.paint_zone(_cells(Vector2i(8, 31), Vector2i(49, 25)), AirportGrid.Zone.AIRSIDE)

	# Walkways: a landside hall and an airside walkway along the gates.
	Airport.paint_walkway(_cells(Vector2i(18, 21), Vector2i(28, 7)), true)
	Airport.paint_walkway(_cells(Vector2i(10, 31), Vector2i(44, 3)), true)

	# Passenger route: Entrance -> Check-in -> Security -> Gate -> Stand.
	Airport.place_building(catalog.find(&"entrance"), Vector2i(30, 19), 0)
	Airport.place_building(catalog.find(&"check_in"), Vector2i(20, 22), 2)
	Airport.place_building(catalog.find(&"check_in"), Vector2i(39, 22), 2)
	Airport.place_building(catalog.find(&"security"), Vector2i(30, 28), 0)
	Airport.place_building(catalog.find(&"gate"), Vector2i(14, 34), 0)
	Airport.place_building(catalog.find(&"gate"), Vector2i(42, 34), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), Vector2i(10, 39), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), Vector2i(38, 39), 0)

	for i in int(warm_up_seconds / Airport.SIM_STEP):
		Airport.passenger_flow.tick(Airport.SIM_STEP)


static func _cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			result.append(origin + Vector2i(x, y))
	return result
