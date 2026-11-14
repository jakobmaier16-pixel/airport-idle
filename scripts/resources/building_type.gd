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
	ANY, ## Landside or airside (e.g. cafés exist on both sides).
}

## What a side of the building must touch for passengers to get in or out (design doc §7.1b).
enum Access {
	NONE, ## Passengers don't use this side.
	WALKWAY, ## Needs at least one free walkway cell along this side.
	STAND, ## Needs an aircraft stand along this side (gate to aircraft).
}

## What the building does in the passenger flow (design doc §8.4).
## New roles go at the end: saves and .tres files store the number.
enum Role { NONE, ENTRANCE, CHECK_IN, SECURITY, GATE, AIRCRAFT_STAND, SHOP, BAGGAGE_CLAIM, TRANSFER_SECURITY, CAR_PARK, LOUNGE, RUNWAY, CARGO_TERMINAL }

## How big a plane a stand takes, by wingspan (TimetableSlot.WINGSPAN_M).
enum StandClass { NARROW, WIDE }

## Stable internal name, used for save games. Never change it once players have saves.
@export var id: StringName
## Name shown in the build menu.
@export var display_name: String
## Build menu category, e.g. "Terminal", "Airside", "Shops".
@export var category: String = "Terminal"
## Second menu level inside a category (landside pieces: "Roads", "Curb", ...); "" = directly in the category.
@export var sub_category: String = ""
## Size in grid cells before rotation: x = width along the front side, y = depth.
## The front side faces -Z ("up" on screen) when the building is not rotated.
@export var footprint: Vector2i = Vector2i.ONE
@export var zone_rule: ZoneRule = ZoneRule.LANDSIDE
## Solid buildings block the manager; flat ones (e.g. aircraft stands) can be walked on.
@export var is_solid: bool = true
@export var front_access: Access = Access.NONE
@export var back_access: Access = Access.NONE
@export var role: Role = Role.NONE
## Stands: the biggest plane class that fits (design doc §10.2). A stand takes its own class and
## every smaller one (see `fits`). Numbers are stored in .tres files: new classes go at the end.
@export var stand_class: StandClass = StandClass.NARROW
## The airport tier that unlocks it (Progression.Tier, design doc §14.1); 0 = from the start.
@export_range(0, 3) var unlocked_at: int = 0

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

@export_group("Shop")
## Customers inside at the same time (shops and cafés, design doc §8.6).
@export var customer_capacity: int = 0
## Seconds a customer stays inside (random between min and max).
@export var visit_seconds_min: float = 0.0
@export var visit_seconds_max: float = 0.0
## What a customer spends in euros (random between min and max); the airport earns a share.
@export var spend_min: float = 0.0
@export var spend_max: float = 0.0
## Run by the airport itself (lounge): the airport keeps the whole amount, a fixed price.
@export var airport_run: bool = false

@export_group("Upgrades")
## Upgrade levels in order (design doc §7.8). Empty = the station can't be upgraded.
@export var upgrades: Array[StationUpgrade] = []

@export_group("Landside piece visuals")
## The 3D model of a landside piece (.glb with `<piece>`, `<piece>_markings` and `<piece>_lodfar`).
## Drawn by LandsideLayer as MultiMeshes; empty = the placeholder box.
@export var model: PackedScene
## Stands on a sidewalk: a paved tile is drawn under every cell (bollards, masts, signs, shelter).
@export var paved_base: bool = false

@export_group("Placeholder visuals")
@export var color: Color = Color(0.7, 0.7, 0.75)
## Box height in meters.
@export var height: float = 2.5


## Stands: true for long-haul (wide-body) stands. Derived from `stand_class`.
var wide_body: bool:
	get:
		return stand_class == StandClass.WIDE


## True if a plane of `plane_class` can park on this stand: its own class or a smaller one.
func fits(plane_class: TimetableSlot.PlaneClass) -> bool:
	return role == Role.AIRCRAFT_STAND and TimetableSlot.size_rank(plane_class) <= int(stand_class)


## Width of the footprint in metres (a stand's width is its wingspan limit), for any rotation.
func width_m(cell_size: float) -> float:
	return minf(footprint.x, footprint.y) * cell_size
