class_name Seasons
extends RefCounted
## The four seasons (design doc §12.2). They only change how many people want to fly where
## (demand by route type); the seasons used to drive weather too, which is gone. Pure data, static.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const SEASON_NAMES: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
## Game days per season.
const DAYS_PER_SEASON: int = 2
## Demand by season and route type (design doc §12.2).
const SEASON_DEMAND: Dictionary = {
	"Holiday": [1.0, 1.35, 1.0, 0.75],
	"Low-cost": [1.0, 1.15, 1.0, 0.9],
	"Business": [1.0, 0.9, 1.05, 1.05],
	"Long-haul": [1.0, 1.0, 1.0, 1.0],
}


static func season_of(day: int) -> Season:
	return (((day - 1) / DAYS_PER_SEASON) % 4) as Season


static func demand_factor(route: String, season: Season) -> float:
	return SEASON_DEMAND.get(route, [1.0, 1.0, 1.0, 1.0])[season]


static func text(season: Season) -> String:
	return SEASON_NAMES[season]
