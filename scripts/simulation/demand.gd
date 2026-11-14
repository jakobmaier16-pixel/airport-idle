class_name Demand
extends RefCounted
## How many flights the airline market wants at this airport (tech_architecture.md §6, design doc §3).
## One value, in narrow-body flights per game hour at the average hour; the timetable multiplies
## it by the hour's rush factor. It is updated once per game day from the star rating and the
## on-time rate: a well-run airport grows to its cap in about 5 days, a badly run one loses demand
## slowly (never below the start). The cap depends on tier and stars, never on infrastructure, so
## demand outgrows capacity and bottlenecks appear. Pure data; the brain owns it.

## The starting value: about 3 flights an hour (more than one gate can turn around).
const START: float = 3.0
## The most demand each tier can bring at 5 stars (index = Progression.Tier). Only the regional
## value is decided; the others are placeholders for the later tiers.
const TIER_MAX: Array[float] = [6.0, 9.0, 12.0, 16.0]
## Days from the start to the tier maximum when the airport runs well.
const DAYS_TO_MAX: float = 5.0
## Falling is this much slower than growing.
const FALL_SPEED: float = 0.25
## Growing needs at least this on-time rate; below FALL_ON_TIME the market loses interest.
const GROW_ON_TIME: float = 0.7
const FALL_ON_TIME: float = 0.5

## Narrow-body flights per game hour at the average hour.
var value: float = START
## Change at the last daily update (for the trend arrow), and the day it was made.
var last_change: float = 0.0
var last_day: int = 1


func reset() -> void:
	value = START
	last_change = 0.0
	last_day = 1


## What demand the airport could reach right now: the tier's maximum scaled by the star rating
## (the existing passenger factor: 0.6 at 1 star, 1.4 at 5), never below the start.
static func cap_for(tier: Progression.Tier, stars: float) -> float:
	return maxf(START, TIER_MAX[tier] * Reputation.demand_factor(stars) / Reputation.DEMAND_AT_FIVE_STARS)


## One daily update.
func update_day(tier: Progression.Tier, stars: float, on_time_rate: float) -> void:
	var cap := cap_for(tier, stars)
	var grow_step := (TIER_MAX[Progression.Tier.REGIONAL] - START) / DAYS_TO_MAX
	var before := value
	if on_time_rate < FALL_ON_TIME:
		value -= grow_step * FALL_SPEED
	elif value > cap:
		value -= grow_step * FALL_SPEED
		value = maxf(value, cap)
	elif on_time_rate >= GROW_ON_TIME:
		value = minf(value + grow_step, cap)
	value = maxf(value, START)
	last_change = value - before


## Catches up to game day `day` (several updates after a jump or a long fast-forward).
func tick(day: int, tier: Progression.Tier, stars: float, on_time_rate: float) -> void:
	if day < last_day:
		last_day = day  # the clock was set back (tests, dev tools)
	while last_day < day:
		last_day += 1
		update_day(tier, stars, on_time_rate)


## Narrow-body flights planned per game day (the hourly rush factors add up).
func flights_per_day() -> float:
	var total := 0.0
	for rate in Clock.DEMAND_BY_HOUR:
		total += rate
	return value * total


## "up", "down" or "steady", from the last daily update.
func trend() -> String:
	if last_change > 0.001:
		return "up"
	if last_change < -0.001:
		return "down"
	return "steady"


func save_state() -> Dictionary:
	return {"value": value, "last_change": last_change, "last_day": last_day}


func load_state(data: Dictionary) -> void:
	value = maxf(float(data.get("value", START)), START)
	last_change = float(data.get("last_change", 0.0))
	last_day = int(data.get("last_day", 1))
