class_name JourneyStep
extends Resource
## One step of a passenger journey (tech architecture §5): the kind of station that comes next.
## Instances live inside the recipes in data/journeys/*.tres.

## The kind of station the passenger heads for in this step.
@export var role: BuildingType.Role = BuildingType.Role.NONE
## A shop, café or lounge visit may come before this step (design doc §8.6).
@export var detour_before: bool = false
## Time (seconds) still needed after such a visit, e.g. for security.
@export var detour_allowance: float = 0.0
## Scales the chance of the visit (landside cafés are less popular than airside shops).
@export var detour_chance_factor: float = 1.0
## After this step the passenger appears behind the building (through the security lane).
@export var emerges_behind: bool = false
## Leaving: car travellers walk to their car park instead of the entrance (design doc §11.8).
@export var exit_via_car_park: bool = false
