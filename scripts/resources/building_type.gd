class_name BuildingType
extends Resource
## Definition of a kind of building the player can place, e.g. check-in.
## Shared by all buildings of that kind. Instances live in data/buildings/*.tres and are listed
## in data/buildings/catalog.tres.

## Which zone a building must stand in (design doc §7.2).
enum ZoneRule {
	LANDSIDE, ## The whole footprint must be landside.
	AIRSIDE, ## The whole footprint must be airside.
	BORDER, ## On the border: the row in front must be landside, the row behind airside (security).
}

## What a side of the building must touch for passengers to get in or out (design doc §7.1b).
enum Access {
	NONE, ## Passengers don't use this side.
	WALKWAY, ## Needs at least one free walkway cell along this side.
	STAND, ## Needs an aircraft stand along this side (gate to aircraft).
}

## What the building does in the passenger flow (design doc §8.4).
enum Role { NONE, ENTRANCE, CHECK_IN, SECURITY, GATE, AIRCRAFT_STAND }

## Stable internal name, used for save games. Never change it once players have saves.
@export var id: StringName
## Name shown in the build menu.
@export var display_name: String
## Size in grid cells before rotation: x = width along the front side, y = depth.
## The front side faces -Z ("up" on screen) when the building is not rotated.
@export var footprint: Vector2i = Vector2i.ONE
@export var zone_rule: ZoneRule = ZoneRule.LANDSIDE
## Solid buildings block the manager; flat ones (e.g. aircraft stands) can be walked on.
@export var is_solid: bool = true
@export var front_access: Access = Access.NONE
@export var back_access: Access = Access.NONE
@export var role: Role = Role.NONE

@export_group("Economy")
## One-off construction cost in euros (design doc §11.5).
@export var build_cost: float = 0.0
## Staff, maintenance and utilities in euros per minute.
@export var running_cost_per_minute: float = 0.0

@export_group("Passenger service")
## Passengers served at the same time (counters, lanes). 0 = no service.
@export var service_slots: int = 0
## Average seconds to serve one passenger (compressed game time).
@export var service_time: float = 0.0

@export_group("Placeholder visuals")
@export var color: Color = Color(0.7, 0.7, 0.75)
## Box height in meters.
@export var height: float = 2.5
