class_name Reputation
extends RefCounted
## The airport's reputation (design doc §11.7): a 1–5 star rating from the on-time rate of
## departures (it was satisfaction and punctuality until 2026-11-14, see docs/removed_features.md).
## Pure data.

## A departure counts as on time with at most this much delay, in seconds (compressed time).
const ON_TIME_LIMIT: float = 10.0
## A new airport's on-time rate, before any flights have left.
const ON_TIME_START: float = 0.9
## Each departure moves the on-time rate this far (about the last 10 flights count).
const SMOOTHING: float = 0.1
## On-time rate (0..1) that gives 1 star, and the rate that gives 5 stars.
const ONE_STAR_SCORE: float = 0.5
const FIVE_STAR_SCORE: float = 0.95
## Demand compared to an average airport: at 1 star and at 5 stars.
const DEMAND_AT_ONE_STAR: float = 0.6
const DEMAND_AT_FIVE_STARS: float = 1.4
## Stars lost through a restructuring (design doc §11.6) fade away over this many seconds.
const PENALTY_SECONDS: float = 600.0

## Share of recent departures that left on time (0..1).
var on_time_rate: float = ON_TIME_START
## Departures counted so far, and how many of them were late.
var departures: int = 0
var late_departures: int = 0
## Stars currently taken off (after a restructuring), fading to 0.
var penalty: float = 0.0


func record_departure(delay: float) -> void:
	var on_time := delay <= ON_TIME_LIMIT
	on_time_rate = lerpf(on_time_rate, 1.0 if on_time else 0.0, SMOOTHING)
	departures += 1
	if not on_time:
		late_departures += 1


func tick(delta: float) -> void:
	if penalty > 0.0:
		penalty = maxf(penalty - delta / PENALTY_SECONDS * 2.0, 0.0)
	elif penalty < 0.0:
		penalty = minf(penalty + delta / PENALTY_SECONDS * 2.0, 0.0)


## Star rating from 1.0 to 5.0 (continuous).
func stars() -> float:
	var rating := 1.0 + 4.0 * clampf((on_time_rate - ONE_STAR_SCORE) / (FIVE_STAR_SCORE - ONE_STAR_SCORE), 0.0, 1.0)
	return clampf(rating - penalty, 1.0, 5.0)


## How many flights the market offers compared to normal, for a star rating.
static func demand_factor(rating: float) -> float:
	return lerpf(DEMAND_AT_ONE_STAR, DEMAND_AT_FIVE_STARS, (rating - 1.0) / 4.0)


## The rating rounded to half stars, as shown to the player.
static func shown_stars(rating: float) -> float:
	return roundf(rating * 2.0) / 2.0


func save_state() -> Dictionary:
	return {"on_time": on_time_rate, "departures": departures, "late": late_departures, "penalty": penalty}


func load_state(data: Dictionary) -> void:
	on_time_rate = float(data.get("on_time", ON_TIME_START))
	departures = int(data.get("departures", 0))
	late_departures = int(data.get("late", 0))
	penalty = float(data.get("penalty", 0.0))
