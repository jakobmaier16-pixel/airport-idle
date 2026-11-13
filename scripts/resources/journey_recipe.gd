class_name JourneyRecipe
extends Resource
## A passenger journey as data: an ordered list of steps (tech architecture §5).
## Instances live in data/journeys/*.tres.

@export var id: StringName
@export var steps: Array[JourneyStep] = []


func step_at(index: int) -> JourneyStep:
	return steps[clampi(index, 0, steps.size() - 1)]


func role_at(index: int) -> BuildingType.Role:
	return step_at(index).role


## Index of the first step of `role`, or -1.
func index_of(role: BuildingType.Role) -> int:
	for i in steps.size():
		if steps[i].role == role:
			return i
	return -1


func is_last(index: int) -> bool:
	return index >= steps.size() - 1
