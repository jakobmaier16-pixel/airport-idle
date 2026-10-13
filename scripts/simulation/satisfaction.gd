class_name Satisfaction
extends RefCounted
## How happy passengers leave the airport (design doc §8.10). Pure data.
## Every finished journey (boarded, left the airport, or missed the flight) moves a running
## average a little towards that passenger's mood, so the value follows recent passengers.

## Where a new airport starts: neither loved nor hated yet.
const START: float = 75.0
## Each finished journey moves the averages this far towards its mood (about the last 60 passengers count).
const SMOOTHING: float = 0.03
## Complaints fade with this half-life in seconds, so the main complaint shows what is wrong now.
const COMPLAINT_HALF_LIFE: float = 300.0
## Missed flights weigh this many times as much as a normal journey: people remember the
## trip that went wrong (and tell others).
const MISSED_WEIGHT: float = 3.0

## Why passengers lose mood. Keys of `complaints`.
const LONG_QUEUES: String = "Long queues"
const LONG_WALKS: String = "Long walks"
const BAG_WAITS: String = "Waiting for bags"
const NO_WAY: String = "No way through"
const MISSED: String = "Missed flights"

## Average mood of recent passengers, 0..100.
var average: float = START
## The same per passenger type ("Families" -> 80.0).
var by_type: Dictionary[String, float] = {}
## Mood points lost per reason, fading over time.
var complaints: Dictionary[String, float] = {}
## Finished journeys counted so far.
var journeys: int = 0


## A passenger's journey ended with `mood` (0..100). `weight` counts it several times.
func record(type_name: String, mood: float, weight: float = 1.0) -> void:
	mood = clampf(mood, 0.0, 100.0)
	var step := 1.0 - pow(1.0 - SMOOTHING, weight)
	average = lerpf(average, mood, step)
	by_type[type_name] = lerpf(by_type.get(type_name, START), mood, step)
	journeys += 1


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
	return {"average": average, "by_type": by_type, "journeys": journeys}


func load_state(data: Dictionary) -> void:
	average = float(data.get("average", START))
	journeys = int(data.get("journeys", 0))
	var types: Dictionary = data.get("by_type", {})
	for type_name in types:
		by_type[str(type_name)] = float(types[type_name])
