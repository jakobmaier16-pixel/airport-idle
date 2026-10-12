class_name Station
extends RefCounted
## A building passengers visit (check-in, security, gate) with its queue and its statistics
## (design doc §13.1). Pure data.

## Statistics cover this many seconds (one sample per second).
const STATS_WINDOW: int = 300

var building: Building
## Walkable cells along the side where passengers arrive (front), in row order.
var entry_cells: Array[Vector2i] = []
## Walkable cells along the side where passengers leave (security: the airside back).
var exit_cells: Array[Vector2i] = []
## Direction from the building out of its front side, on the ground (world).
var outward: Vector3 = Vector3.ZERO

var queue: Array[Passenger] = []
## One entry per counter / lane; null = free.
var serving: Array[Passenger] = []
var service_left: PackedFloat32Array = PackedFloat32Array()
## Gates only: passengers waiting inside for their flight to board.
var waiting: Array[Passenger] = []

# Statistics: one sample per second (ring buffers), and the waits of recently served passengers.
var _queue_samples: PackedInt32Array = PackedInt32Array()
var _busy_samples: PackedFloat32Array = PackedFloat32Array()
var _sample_index: int = 0
var _samples_taken: int = 0
var _wait_times: PackedFloat32Array = PackedFloat32Array()
var _wait_seconds: PackedFloat32Array = PackedFloat32Array()


func _init(placed: Building) -> void:
	building = placed
	sync_slots()
	_queue_samples.resize(STATS_WINDOW)
	_busy_samples.resize(STATS_WINDOW)
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var front := directions[placed.rotation_steps]
	outward = Vector3(front.x, 0.0, front.y)


## Adds counters / lanes after an upgrade (the number never goes down).
func sync_slots() -> void:
	var slots := building.service_slots()
	if serving.size() < slots:
		serving.resize(slots)
		service_left.resize(slots)


func role() -> BuildingType.Role:
	return building.type.role


## Records one statistics sample; called once per simulated second.
func record_sample() -> void:
	_queue_samples[_sample_index] = queue_length()
	_busy_samples[_sample_index] = busy_share_now()
	_sample_index = (_sample_index + 1) % STATS_WINDOW
	_samples_taken = mini(_samples_taken + 1, STATS_WINDOW)


## Records how long a passenger stood in the queue before being served.
func record_wait(now: float, seconds: float) -> void:
	_wait_times.append(now)
	_wait_seconds.append(seconds)
	# Forget waits that are older than the statistics window.
	while not _wait_times.is_empty() and _wait_times[0] < now - STATS_WINDOW:
		_wait_times.remove_at(0)
		_wait_seconds.remove_at(0)


## Passengers in the queue right now (gates: waiting for their flight).
func queue_length() -> int:
	return waiting.size() if role() == BuildingType.Role.GATE else queue.size()


## Share of counters / lanes in use right now (0..1).
func busy_share_now() -> float:
	if serving.is_empty():
		return 0.0
	return float(serving.size() - serving.count(null)) / serving.size()


## Longest queue over the statistics window.
func longest_queue() -> int:
	var longest := queue_length()
	for i in _samples_taken:
		longest = maxi(longest, _queue_samples[i])
	return longest


## Average seconds in the queue over the statistics window, or -1 if nobody was served.
func average_wait(now: float) -> float:
	var total := 0.0
	var count := 0
	for i in _wait_times.size():
		if _wait_times[i] >= now - STATS_WINDOW:
			total += _wait_seconds[i]
			count += 1
	return total / count if count > 0 else -1.0


## Average share of counters / lanes in use over the statistics window (0..1).
func busy_share() -> float:
	if _samples_taken == 0:
		return busy_share_now()
	var total := 0.0
	for i in _samples_taken:
		total += _busy_samples[i]
	return total / _samples_taken


## How many passengers are queuing or being served, for passengers choosing between stations.
func busyness() -> int:
	return queue.size() + serving.size() - serving.count(null)
