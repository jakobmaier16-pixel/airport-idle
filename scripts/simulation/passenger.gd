class_name Passenger
extends RefCounted
## One passenger in the simulation: pure data, no visuals (design doc §8.4).

enum State {
	WALKING, ## Following `path` towards the station in `target`.
	QUEUING, ## In the queue of the station in `target`.
	IN_SERVICE, ## Being served at the station in `target` (counter, security lane).
	AT_GATE, ## Waiting inside the gate until boarding. Not drawn.
	IN_SHOP, ## Inside a shop or café. Not drawn.
	AT_BELT, ## Arriving: inside the baggage claim, waiting for the bag. Not drawn.
	GONE, ## Left the airport this step (removed at the end of the step).
	STUCK, ## No reachable station for the next step; retries regularly.
}

var state: State = State.WALKING
## The flight this passenger is booked on (decides the gate and the deadline).
var flight: Flight = null
## Families, low-cost or business (design doc §8.7): speed, processing times, shopping.
var type: PassengerType = null
## Arriving passengers (design doc §8.8) came off `flight`'s inbound plane and are heading out.
var is_arriving: bool = false
## Transfer passengers (design doc §8.9) came off an inbound plane; `flight` is their connection.
var is_transfer: bool = false
## Arriving: whether they wait for a checked bag, and when it comes off the belt.
var has_bag: bool = false
var bag_ready_at: float = 0.0
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
## Simulation time when the passenger joined their current queue (for wait statistics).
var queued_since: float = 0.0
## Seconds left inside a shop or café.
var visit_left: float = 0.0
## Shops and cafés: where to go afterwards (security before it, the gate after it), and the
## simulation time by which the passenger must leave to still make boarding.
var after_shop: BuildingType.Role = BuildingType.Role.GATE
var leave_shop_by: float = 0.0
## How happy the passenger is with the airport so far, 0..100 (design doc §8.10).
var mood: float = 100.0
## Meters walked inside the airport so far.
var walked: float = 0.0
## Seconds until a STUCK passenger tries again.
var retry_in: float = 0.0
