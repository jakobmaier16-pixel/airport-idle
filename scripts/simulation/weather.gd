class_name Weather
extends RefCounted
## Seasons and weather events (design doc §12.2). Pure data; Airport owns it and calls tick().

## Weather changed (the HUD shows a notice for storms and snow).
signal changed(kind: Kind)

enum Kind { CLEAR, RAIN, STORM, FOG, SNOW }
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const KIND_NAMES: Array[String] = ["Clear", "Rain", "Thunderstorm", "Fog", "Snow"]
const SEASON_NAMES: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
## Game days per season.
const DAYS_PER_SEASON: int = 2
## Seconds between two weather events (real time), and how long each kind lasts.
const EVENT_EVERY_MIN: float = 480.0
const EVENT_EVERY_MAX: float = 900.0
const DURATIONS: Array[float] = [0.0, 180.0, 90.0, 120.0, 240.0]
## Chance of each kind per season: [rain, storm, fog, snow].
const CHANCES: Array = [
	[0.5, 0.2, 0.3, 0.0],  # spring
	[0.5, 0.5, 0.0, 0.0],  # summer
	[0.4, 0.1, 0.5, 0.0],  # autumn
	[0.0, 0.0, 0.4, 0.6],  # winter
]
## Demand by season and route type (design doc §12.2).
const SEASON_DEMAND: Dictionary = {
	"Holiday": [1.0, 1.35, 1.0, 0.75],
	"Low-cost": [1.0, 1.15, 1.0, 0.9],
	"Business": [1.0, 0.9, 1.05, 1.05],
	"Long-haul": [1.0, 1.0, 1.0, 1.0],
}
## De-icing before each departure in snow, in seconds, without and with a de-icing pad.
const DEICING_SECONDS: float = 20.0
const DEICING_SECONDS_WITH_PAD: float = 5.0

var kind: Kind = Kind.CLEAR
## Seconds left of the current event (0 while clear).
var time_left: float = 0.0
## Seconds until the next event starts.
var next_event_in: float = EVENT_EVERY_MIN
## False in tests: no random events (tests start the weather they need with start()).
## Not touched by reset().
var automatic: bool = true
## Exposed so tests can make weather repeatable.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func reset() -> void:
	kind = Kind.CLEAR
	time_left = 0.0
	next_event_in = EVENT_EVERY_MIN


func tick(delta: float, season: Season) -> void:
	if kind != Kind.CLEAR:
		time_left -= delta
		if time_left <= 0.0:
			start(Kind.CLEAR)
		return
	next_event_in -= delta
	if next_event_in <= 0.0 and automatic:
		var chances := PackedFloat32Array(CHANCES[season])
		start((rng.rand_weighted(chances) + 1) as Kind)


## Starts `new_kind` now (CLEAR ends the current event and plans the next one).
func start(new_kind: Kind) -> void:
	kind = new_kind
	time_left = DURATIONS[new_kind]
	if new_kind == Kind.CLEAR:
		next_event_in = rng.randf_range(EVENT_EVERY_MIN, EVENT_EVERY_MAX)
	changed.emit(new_kind)


## Lightning: no ground work at all (boarding, deplaning, taxiing).
func ramp_closed() -> bool:
	return kind == Kind.STORM


## Planes can't land.
func landing_closed() -> bool:
	return kind == Kind.STORM or kind == Kind.FOG


## Seconds of de-icing every departure needs right now.
func deicing_seconds(has_pad: bool) -> float:
	if kind != Kind.SNOW:
		return 0.0
	return DEICING_SECONDS_WITH_PAD if has_pad else DEICING_SECONDS


static func season_of(day: int) -> Season:
	return (((day - 1) / DAYS_PER_SEASON) % 4) as Season


static func demand_factor(route: String, season: Season) -> float:
	return SEASON_DEMAND.get(route, [1.0, 1.0, 1.0, 1.0])[season]


## "Summer · Rain"
func text(season: Season) -> String:
	if kind == Kind.CLEAR:
		return SEASON_NAMES[season]
	return "%s · %s" % [SEASON_NAMES[season], KIND_NAMES[kind]]


func save_state() -> Dictionary:
	return {"kind": kind, "time_left": time_left, "next_event_in": next_event_in}


func load_state(data: Dictionary) -> void:
	kind = clampi(int(data.get("kind", Kind.CLEAR)), Kind.CLEAR, Kind.SNOW) as Kind
	time_left = float(data.get("time_left", 0.0))
	next_event_in = float(data.get("next_event_in", EVENT_EVERY_MIN))
