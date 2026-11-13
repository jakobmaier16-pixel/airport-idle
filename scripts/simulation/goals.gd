class_name Goals
extends RefCounted
## "Getting started" goals for a new airport (design doc §6.1): the next step, read from the
## airport's state. Nothing is stored except whether the player hid the goals; a goal that becomes
## unmet again (e.g. after demolishing) shows up again.

const Role := BuildingType.Role

## Each goal: [text shown to the player, name of the check method].
const STEPS: Array = [
	["Build Security and lay a walkway behind it: that is the airside, where gates and stands go", "_has_airside"],
	["Paint walkways (Walkway) and build an Entrance with its back on one", "_has_entrance"],
	["Build a Check-in facing the entrance's walkway", "_has_check_in"],
	["Build Security between the check-in hall and the airside walkway", "_has_security"],
	["Build a Gate with a Stand behind it, and paint a Taxiway from the stand to the runway", "_has_gate"],
	["Build a Baggage claim for arriving passengers", "_has_claim"],
	["Hire staff: tap check-in and security in the manager view", "_has_staff"],
	["Wait for your first departure (watch the departures board)", "_has_departure"],
	["Sign a second airline: open Airlines when an offer arrives", "_has_second_airline"],
	["Reach National airport (see Stats for your progress)", "_is_national"],
]

## The airport this part of the simulation works for; set by the Airport autoload.
var world: AirportWorld

## The player hid the goals.
var hidden: bool = false


## Index of the first unmet goal, or -1 when all are done.
func current() -> int:
	for i in STEPS.size():
		if not call(STEPS[i][1]):
			return i
	return -1


## "Goal 3/10: …", or "" when there is nothing to show.
func text() -> String:
	var index := current()
	if hidden or index < 0:
		return ""
	return "Goal %d/%d: %s" % [index + 1, STEPS.size(), STEPS[index][0]]


func _has_airside() -> bool:
	return world.zone_map.airside_reached


func _has_entrance() -> bool:
	return _connected(Role.ENTRANCE)


func _has_check_in() -> bool:
	return _connected(Role.CHECK_IN)


func _has_security() -> bool:
	return _connected(Role.SECURITY)


func _has_gate() -> bool:
	return not world.passenger_flow.usable_gates().is_empty() or _route_needs_only_a_claim()


func _has_claim() -> bool:
	return world.passenger_flow.route_problem.is_empty()


func _has_staff() -> bool:
	for role in [Role.CHECK_IN, Role.SECURITY]:
		if not world.buildings.any(func(b: Building) -> bool: return b.type.role == role and not world.staff_at(b).is_empty()):
			return false
	return true


func _has_departure() -> bool:
	return world.progression.passengers > 0


func _has_second_airline() -> bool:
	return world.airlines.signed.size() >= 2


func _is_national() -> bool:
	return world.progression.tier >= Progression.Tier.NATIONAL


# A building of `role` exists with all its sides connected.
func _connected(role: BuildingType.Role) -> bool:
	return world.buildings.any(func(b: Building) -> bool:
		return b.type.role == role and world.connection_problem(b.type, b.origin_cell, b.rotation_steps).is_empty())


# Gates can't be "usable" while the route lacks a baggage claim, so accept that state too.
func _route_needs_only_a_claim() -> bool:
	return world.passenger_flow.route_problem.contains("baggage claim")
