class_name Clock
extends RefCounted
## Time of day at the airport (design doc §12.1). Pure data.
## Compressed like the rest of the game: one real second is 15 game seconds, so a game minute is 4
## real seconds and a day lasts 96 real minutes.

const GAME_SECONDS_PER_SECOND: float = 15.0
## A new airport opens at this hour of its first day.
const START_HOUR: float = 6.0
## Game seconds since midnight of day 1.
## Game seconds per real second, under the name the schedule code uses to convert.
const GAME_PER_REAL: float = GAME_SECONDS_PER_SECOND

## The one clock (tech_architecture.md §3): real seconds since the airport opened, only ever
## running forward. Flights and the timetable are timed against it, and the time of day
## is derived from it. (Kept in real seconds so those timings stay exactly as they were.)
var real_elapsed: float = 0.0

## The same in game seconds.
var elapsed: float:
	get:
		return real_elapsed * GAME_PER_REAL

## The game time since midnight of day 1: the time of day and the day number come from it.
## Tests and dev tools may set it to jump the time of day; `real_elapsed` (and with it every
## planned flight) stays where it is.
var game_seconds: float = START_HOUR * 3600.0


func tick(delta: float) -> void:
	real_elapsed += delta
	game_seconds += delta * GAME_PER_REAL


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


## 1 at noon, 0 at night, smooth in between (for the lighting).
static func daylight(at_hour: float) -> float:
	# Sunrise around 5–7, sunset around 19–21.
	return clampf(minf((at_hour - 5.0) / 2.0, (21.0 - at_hour) / 2.0), 0.0, 1.0)


## A new airport: 06:00 on day 1, nothing elapsed.
func reset() -> void:
	real_elapsed = 0.0
	game_seconds = START_HOUR * 3600.0


## Restores a saved clock: `saved_elapsed` game seconds have passed and it is `saved_game_seconds` now.
func load_state(saved_elapsed: float, saved_game_seconds: float) -> void:
	real_elapsed = saved_elapsed / GAME_PER_REAL
	game_seconds = saved_game_seconds
