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

## What a side of the building must touch to count as connected (design doc §7.1b).
enum Access {
	NONE, ## Nothing is needed on this side.
	WALKWAY, ## Needs at least one free walkway cell along this side.
	STAND, ## Needs an aircraft stand along this side (gate to aircraft).
}

## What the building is for. New roles go at the end: .tres files store the number.
## SHOP, BAGGAGE_CLAIM, TRANSFER_SECURITY and LOUNGE are unused since 2026-11-14 (docs/removed_features.md);
## their numbers stay so the others never move.
enum Role { NONE, ENTRANCE, CHECK_IN, SECURITY, GATE, AIRCRAFT_STAND, SHOP, BAGGAGE_CLAIM, TRANSFER_SECURITY, CAR_PARK, LOUNGE, RUNWAY, CARGO_TERMINAL }

## How big a plane a stand takes, by wingspan (TimetableSlot.WINGSPAN_M).
enum StandClass { NARROW, WIDE }

## Stable internal name, used for save games. Never change it once players have saves.
@export var id: StringName
## Name shown in the build menu.
@export var display_name: String
## Build menu category, e.g. "Terminal", "Airside", "Landside".
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
