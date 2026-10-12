class_name BuildingType
extends Resource
## Definition of a kind of building the player can place, e.g. check-in.
## Shared by all buildings of that kind. Instances live in data/buildings/*.tres.

## Stable internal name, used later for save games.
@export var id: StringName
## Name shown in the build menu.
@export var display_name: String
## Size in grid cells before rotation: x = width along the front side, y = depth.
## The front side faces -Z ("up" on screen) when the building is not rotated.
@export var footprint: Vector2i = Vector2i.ONE

@export_group("Placeholder visuals")
@export var color: Color = Color(0.7, 0.7, 0.75)
## Box height in meters.
@export var height: float = 2.5
