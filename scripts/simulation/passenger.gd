class_name Passenger
extends RefCounted
## One passenger in the simulation: pure data, no visuals (design doc §8.4).

enum State {
	WALKING, ## Following `path` towards the station in `target`.
	QUEUING, ## In the queue of the station in `target`.
	IN_SERVICE, ## Being served at the station in `target` (counter, security lane).
	AT_GATE, ## Waiting inside the gate until boarding. Not drawn.
	STUCK, ## No reachable station for the next step; retries regularly.
}

var state: State = State.WALKING
## The kind of station the passenger is heading for next.
var goal: BuildingType.Role = BuildingType.Role.CHECK_IN
## The building of the station the passenger is heading for or standing at.
## (Not the Station itself: stations hold their passengers, and two objects holding each other
## would never be freed.)
var target: Building = null

## Position on the ground (world coordinates, y = 0), updated every simulation step.
var position: Vector3 = Vector3.ZERO
## Position at the previous simulation step, so visuals can move smoothly in between.
var previous_position: Vector3 = Vector3.ZERO

## Remaining waypoints (world positions) and the index of the next one.
var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
## Small personal sideways offset, so a crowd doesn't walk in one perfect line.
var offset: Vector3 = Vector3.ZERO
## Clothing color (index into the visual palette).
var color_index: int = 0
## Seconds until a STUCK passenger tries again.
var retry_in: float = 0.0
