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

@export_group("Placeholder visuals")
@export var color: Color = Color(0.7, 0.7, 0.75)
## Box height in meters.
@export var height: float = 2.5
