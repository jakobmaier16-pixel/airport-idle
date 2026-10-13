class_name Satisfaction
extends RefCounted
## How happy passengers leave the airport (design doc §8.10). Pure data.
## Every finished journey (boarded, left the airport, or missed the flight) moves a running
## average a little towards that passenger's mood, so the value follows recent passengers.

## Where a new airport starts: neither loved nor hated yet.
const START: float = 75.0
## The averages cover this many recent journeys.
const MEMORY: int = 60
## Until that many journeys are known, imagined neutral ones (START) fill the gap up to this many,
## so the first few passengers don't swing the value wildly.
const PRIOR_JOURNEYS: int = 10
## Complaints fade with this half-life in seconds, so the main complaint shows what is wrong now.
const COMPLAINT_HALF_LIFE: float = 300.0
## Missed flights count as this many journeys: people remember the trip that went wrong
## (and tell others).
const MISSED_WEIGHT: int = 3

## Why passengers lose mood. Keys of `complaints`.
const LONG_QUEUES: String = "Long queues"
const LONG_WALKS: String = "Long walks"
const BAG_WAITS: String = "Waiting for bags"
const NO_WAY: String = "No way through"
const MISSED: String = "Missed flights"

## Average mood of recent passengers, 0..100.
var average: float = START
## The same per passenger type ("Families" -> 80.0), for types among the recent journeys.
var by_type: Dictionary[String, float] = {}
## Mood points lost per reason, fading over time.
var complaints: Dictionary[String, float] = {}
## Finished journeys counted so far.
var journeys: int = 0

# The most recent journeys: mood and passenger type (ring buffer of up to MEMORY entries).
var _moods: PackedFloat32Array = PackedFloat32Array()
var _types: PackedStringArray = PackedStringArray()
var _next: int = 0


## A passenger's journey ended with `mood` (0..100). `weight` counts it several times.
func record(type_name: String, mood: float, weight: int = 1) -> void:
	for i in weight:
		if _moods.size() < MEMORY:
			_moods.append(clampf(mood, 0.0, 100.0))
			_types.append(type_name)
		else:
			_moods[_next] = clampf(mood, 0.0, 100.0)
			_types[_next] = type_name
			_next = (_next + 1) % MEMORY
	journeys += 1
	_update_averages()


## A passenger lost `points` of mood because of `reason`.
func complain(reason: String, points: float) -> void:
	if points > 0.0:
		complaints[reason] = complaints.get(reason, 0.0) + points


## Fades the complaints; called once per simulated second.
func tick_second() -> void:
	var fade := pow(0.5, 1.0 / COMPLAINT_HALF_LIFE)
	for reason in complaints:
		complaints[reason] *= fade


## The reason passengers lost the most mood recently, or "" if nothing worth mentioning.
func main_complaint() -> String:
	var worst := ""
	var worst_points := 20.0  # a few grumbles are normal
	for reason in complaints:
		if complaints[reason] > worst_points:
			worst_points = complaints[reason]
			worst = reason
	return worst


func save_state() -> Dictionary:
	# Oldest first, so loading can simply append.
	var moods: Array[float] = []
	var types: Array[String] = []
	for i in _moods.size():
		var index := (_next + i) % _moods.size()
		moods.append(_moods[index])
		types.append(_types[index])
	return {"moods": moods, "types": types, "journeys": journeys}


func load_state(data: Dictionary) -> void:
	var moods: Array = data.get("moods", [])
	var types: Array = data.get("types", [])
	for i in mini(moods.size(), types.size()):
		record(str(types[i]), float(moods[i]))
	journeys = int(data.get("journeys", journeys))


func _update_averages() -> void:
	var prior := maxi(PRIOR_JOURNEYS - _moods.size(), 0)
	var total := START * prior
	var per_type: Dictionary[String, Vector2] = {}  # type -> (sum, count)
	for i in _moods.size():
		total += _moods[i]
		per_type[_types[i]] = per_type.get(_types[i], Vector2.ZERO) + Vector2(_moods[i], 1.0)
	average = total / (_moods.size() + prior)
	by_type.clear()
	for type_name in per_type:
		by_type[type_name] = per_type[type_name].x / per_type[type_name].y
