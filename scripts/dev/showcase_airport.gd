class_name ShowcaseAirport
extends RefCounted
## A ready-made airport that uses every current feature, so updates can be tried on the device
## without building by hand. Test builds load it on the first start after each new export
## (see SaveGame); the tests and screenshots use the same layout.
## **When a feature is added, add it here too**, so the newest feature is visible after an update.

## Builds the showcase into an empty airport. `warm_up_seconds` lets the airport run for a while
## first, so it's already busy when the player looks at it: after the default 2 minutes the first
## plane is at its stand and boarding is about to open, the second plane is taxiing in.
static func build(warm_up_seconds: float = 120.0) -> void:
	Airport.reset()
	var catalog := Airport.CATALOG

	# Zones: landside in the north, airside in the south (security sits on the border).
	Airport.paint_zone(_cells(Vector2i(8, 31), Vector2i(49, 25)), AirportGrid.Zone.AIRSIDE)

	# Walkways: a landside hall and an airside walkway along the gates.
	Airport.paint_walkway(_cells(Vector2i(18, 21), Vector2i(28, 7)), true)
	Airport.paint_walkway(_cells(Vector2i(10, 31), Vector2i(44, 3)), true)

	# Passenger route: Entrance -> Check-in -> Security -> Gate -> Stand (flights use both gates).
	Airport.place_building(catalog.find(&"entrance"), Vector2i(30, 19), 0)
	Airport.place_building(catalog.find(&"check_in"), Vector2i(20, 22), 2)
	Airport.place_building(catalog.find(&"check_in"), Vector2i(39, 22), 2)
	Airport.place_building(catalog.find(&"security"), Vector2i(30, 28), 0)
	Airport.place_building(catalog.find(&"gate"), Vector2i(14, 34), 0)
	Airport.place_building(catalog.find(&"gate"), Vector2i(42, 34), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), Vector2i(10, 39), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), Vector2i(38, 39), 0)

	# Station upgrades (design doc §7.8): security already at level 2.
	Airport.start_upgrade(_first(BuildingType.Role.SECURITY))

	# The showcase is a test fixture: start with fresh money, as if it had been there all along.
	Airport.economy = Economy.new()
	for i in int(warm_up_seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)

	# A big upgrade under construction right when the player looks (check-in to level 3).
	var check_in := _first(BuildingType.Role.CHECK_IN)
	check_in.level = 2
	Airport.start_upgrade(check_in)
	Airport.economy.balance = Economy.STARTING_MONEY


static func _first(role: BuildingType.Role) -> Building:
	for building in Airport.buildings:
		if building.type.role == role:
			return building
	return null


static func _cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			result.append(origin + Vector2i(x, y))
	return result
