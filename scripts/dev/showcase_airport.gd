class_name ShowcaseAirport
extends RefCounted
## A ready-made airport that uses every current feature, so updates can be tried on the device
## without building by hand. Test builds load it on the first start after each new export
## (see SaveGame); the tests and screenshots use the same layout.
## **When a feature is added, add it here too**, so the newest feature is visible after an update.

## Builds the showcase into an empty airport. `warm_up_seconds` lets the airport run for a while
## first, so it's already busy when the player looks at it: after the default 3 minutes the first
## plane is at its stand and boarding opens, the second plane is about to taxi in.
static func build(warm_up_seconds: float = 180.0) -> void:
	Airport.reset()
	var catalog := Airport.CATALOG
	# Build on an unlimited test budget, so nothing in the showcase fails for lack of money.
	# The player gets the normal starting money at the end.
	Airport.economy.balance = 1.0e9
	# An International airport (design doc §14.1): the whole map, transfer security and long-haul
	# flights are unlocked, and it is on its way to Hub.
	Airport.progression.tier = Progression.Tier.INTERNATIONAL
	Airport.progression.passengers = 15000
	Airport.progression.transfers = 400
	Airport.land_changed.emit()

	# Zones: landside in the north, airside in the south (security sits on the border), down to the
	# runway every airport starts with (design doc §7.5a).
	Airport.paint_zone(_cells(Vector2i(8, 31), Vector2i(54, 26)), AirportGrid.Zone.AIRSIDE)

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
	# Long-haul (§10.2): gate 3 in the middle with a wide-body stand behind it.
	Airport.place_building(catalog.find(&"gate"), Vector2i(27, 34), 0)
	Airport.place_building(catalog.find(&"wide_body_stand"), Vector2i(22, 39), 0)
	# De-icing pad for snowy days (§12.2), east of the transfer corridor.
	Airport.place_building(catalog.find(&"deicing_pad"), Vector2i(56, 31), 0)
	# Cargo (§10.3): a cargo terminal with its own stand in the east, on the parallel taxiway.
	Airport.place_building(catalog.find(&"cargo_terminal"), Vector2i(52, 38), 0)
	Airport.place_building(catalog.find(&"aircraft_stand"), Vector2i(50, 43), 0)
	# Taxiways (§7.5a): a parallel taxiway along the runway, and short links down from the stands.
	Airport.paint_taxiway(_cells(Vector2i(8, 55), Vector2i(48, 2)), true)
	Airport.paint_taxiway(_cells(Vector2i(15, 51), Vector2i(2, 4)), true)
	Airport.paint_taxiway(_cells(Vector2i(43, 51), Vector2i(2, 4)), true)

	# Arrivals: baggage claim on the border next to security, out into the landside hall (§8.8).
	Airport.place_building(catalog.find(&"baggage_claim"), Vector2i(37, 27), 0)

	# Transfers (§8.9): transfer security beside gate 2; a small corridor loop leads from its back
	# exit (row 37) round to the gates' walkway again.
	Airport.paint_walkway(_cells(Vector2i(47, 34), Vector2i(7, 4)), true)
	Airport.place_building(catalog.find(&"transfer_security"), Vector2i(47, 34), 0)

	# Airside shopping between the gates (design doc §8.6).
	Airport.place_building(catalog.find(&"shop"), Vector2i(22, 34), 0)
	Airport.place_building(catalog.find(&"cafe"), Vector2i(33, 34), 0)
	# Lounge for business travellers next to the café, a car park beside the landside hall, and
	# a fast track at security (design doc §11.8).
	Airport.place_building(catalog.find(&"lounge"), Vector2i(37, 34), 0)
	Airport.place_building(catalog.find(&"car_park"), Vector2i(46, 21), 3)

	# Station upgrades (design doc §7.8): security fully upgraded (3 lanes, faster scanners) for
	# the morning rush.
	Airport.start_upgrade(_first(BuildingType.Role.SECURITY))
	_first(BuildingType.Role.SECURITY).upgrade_seconds_left = 0.0
	_first(BuildingType.Role.SECURITY).level = 3
	Airport.buy_fast_track(_first(BuildingType.Role.SECURITY))

	# Airlines (§10.1): the starter deal, two more and a long-haul airline, together as many
	# flights as the three gates can take (60 per hour), and an open offer to negotiate.
	var airlines := Airport.airlines
	airlines.sign_deal(Airlines.CATALOG.find(&"zippa"), 16, 9.0)
	airlines.sign_deal(Airlines.CATALOG.find(&"norvane"), 14, 20.0)
	airlines.sign_deal(Airlines.CATALOG.find(&"orynth"), 10, 32.0)
	airlines.sign_deal(Airlines.CATALOG.find(&"paqet"), 10, 20.0)
	# These have flown here for a while: no first-landing cutscene for them.
	for airline in airlines.signed:
		airline.first_landing_seen = true
	airlines.offers.append(AirlineOffer.new(Airlines.CATALOG.find(&"sunkiss"), 10, 13.0))

	# Staff for every counter and lane, with a mix of new and experienced employees (§9.1).
	for building in Airport.buildings:
		Airport.staff_fully(building)
	for employee in Airport.staff:
		employee.served[employee.workplace.type.role] = randi() % 200

	# The showcase is a test fixture: start with fresh money, as if it had been there all along.
	Airport.economy = Economy.new()
	# The morning rush has just started when the player looks (after the warm-up: about 08:00).
	Airport.clock.game_seconds = 7.25 * 3600.0
	for i in int(warm_up_seconds / Airport.SIM_STEP):
		Airport.step(Airport.SIM_STEP)

	# A big upgrade under construction right when the player looks (check-in to level 3).
	var check_in := _first(BuildingType.Role.CHECK_IN)
	check_in.level = 2
	Airport.start_upgrade(check_in)
	Airport.economy.balance = Economy.STARTING_MONEY

	# The newest events, so they're visible right after an update (§12.2, §12.3): light rain and
	# an unattended bag at the second check-in. Not when tests build the showcase (no warm-up).
	if warm_up_seconds > 0.0:
		Airport.weather.start(Weather.Kind.RAIN)
		var check_ins := Airport.buildings.filter(func(b: Building) -> bool: return b.type.role == BuildingType.Role.CHECK_IN)
		Airport.start_incident(check_ins[1])


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
