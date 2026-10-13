class_name Clock
extends RefCounted
## Time of day at the airport (design doc §12.1). Pure data.
## Compressed like the rest of the game: a 3-minute gate turnaround stands for about 45 minutes,
## so one real second is 15 game seconds and a day lasts 96 real minutes.

const GAME_SECONDS_PER_SECOND: float = 15.0
## A new airport opens at this hour of its first day.
const START_HOUR: float = 6.0
## Passengers per flight compared to the daily average, for every hour 0..23 (morning and evening
## peaks, a quiet night). Between two hours the value is interpolated.
const DEMAND_BY_HOUR: Array[float] = [
	0.4, 0.4, 0.4, 0.4, 0.5, 0.8, 1.2, 1.3, 1.3, 1.1, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.1, 1.25, 1.3, 1.2, 1.0, 0.8, 0.6, 0.45,
]

## Game seconds since midnight of day 1.
var game_seconds: float = START_HOUR * 3600.0


func tick(delta: float) -> void:
	game_seconds += delta * GAME_SECONDS_PER_SECOND


## Hour of the day, 0.0 ..< 24.0.
func hour() -> float:
	return hour_at(0.0)


## Hour of the day `real_seconds_ahead` real seconds from now.
func hour_at(real_seconds_ahead: float) -> float:
	return fmod((game_seconds + real_seconds_ahead * GAME_SECONDS_PER_SECOND) / 3600.0, 24.0)


func day() -> int:
	return int(game_seconds / 86400.0) + 1


## "Day 3 · 06:45"
func text() -> String:
	var minutes := int(hour() * 60.0)
	return "Day %d · %02d:%02d" % [day(), minutes / 60, minutes % 60]


## Passengers per flight compared to the average, at `at_hour` (design doc §12.1).
static func demand_factor(at_hour: float) -> float:
	var index := int(at_hour) % 24
	return lerpf(DEMAND_BY_HOUR[index], DEMAND_BY_HOUR[(index + 1) % 24], at_hour - floorf(at_hour))


## 1 at noon, 0 at night, smooth in between (for the lighting).
static func daylight(at_hour: float) -> float:
	# Sunrise around 5–7, sunset around 19–21.
	return clampf(minf((at_hour - 5.0) / 2.0, (21.0 - at_hour) / 2.0), 0.0, 1.0)
