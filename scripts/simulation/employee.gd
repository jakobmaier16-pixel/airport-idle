class_name Employee
extends RefCounted
## One member of staff (design doc §9.1). Pure data.
## Points to their workplace; buildings never point back (no reference cycles).

## Passengers served at a station type until an employee is an expert there.
const EXPERT_AFTER: int = 150
## Time per passenger compared to the standard: new employees are slower, experts faster.
const NEW_TIME_FACTOR: float = 1.25
const EXPERT_TIME_FACTOR: float = 0.85
## Experience levels: passengers served -> name.
const LEVELS: Array = [[0, "New"], [30, "Trained"], [80, "Experienced"], [150, "Expert"]]

var name: String
var workplace: Building
var salary_per_minute: float
## Passengers served per station type (BuildingType.Role -> count). Experience grows per station.
var served: Dictionary[int, int] = {}


## Passengers served at the current workplace's station type.
func experience() -> int:
	return served.get(workplace.type.role, 0) if workplace != null else 0


## Multiplies the time per passenger: 1.25 when new, 0.85 as an expert.
func time_factor() -> float:
	var progress := minf(float(experience()) / EXPERT_AFTER, 1.0)
	return lerpf(NEW_TIME_FACTOR, EXPERT_TIME_FACTOR, progress)


func level_name() -> String:
	var level: String = LEVELS[0][1]
	for entry: Array in LEVELS:
		if experience() >= entry[0]:
			level = entry[1]
	return level
