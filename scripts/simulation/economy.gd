class_name Economy
extends RefCounted
## The airport's money (design doc §11.5). Pure data.
## Operations (fees, running costs) are tracked over the last minute for "profit per minute";
## construction is a one-off and doesn't count towards it.

const STARTING_MONEY: float = 50000.0
## Paid by the airline for every passenger on a departing flight.
const PASSENGER_FEE: float = 15.0
## Paid by the airline for every departing flight (landing / turnaround).
const FLIGHT_FEE: float = 300.0
## The airport's share of what customers spend in shops and cafés (concession fee).
const CONCESSION_SHARE: float = 0.3
const WALKWAY_COST_PER_CELL: float = 20.0
const WALKWAY_RUNNING_COST_PER_CELL: float = 0.05
## "Per minute" figures cover this many seconds.
const WINDOW_SECONDS: int = 60

var balance: float = STARTING_MONEY

# Net operating money per second over the last minute (ring buffer).
var _window: PackedFloat64Array = PackedFloat64Array()
var _window_index: int = 0
var _window_time: float = 0.0


func _init() -> void:
	_window.resize(WINDOW_SECONDS)


func can_afford(amount: float) -> bool:
	return balance >= amount


## Income from operations (fees).
func earn(amount: float) -> void:
	balance += amount
	_window[_window_index] += amount


## A one-off construction cost.
func pay_construction(amount: float) -> void:
	balance -= amount


## Charges running costs for `delta` seconds and moves the one-minute window along.
func tick(delta: float, running_cost_per_minute: float) -> void:
	var cost := running_cost_per_minute / 60.0 * delta
	balance -= cost
	_window[_window_index] -= cost
	_window_time += delta
	while _window_time >= 1.0:
		_window_time -= 1.0
		_window_index = (_window_index + 1) % WINDOW_SECONDS
		_window[_window_index] = 0.0


## Income minus running costs over the last minute.
func profit_per_minute() -> float:
	var total := 0.0
	for amount in _window:
		total += amount
	return total


## "€12,345" or "-€1,200" (whole euros, thousands separated).
static func format(amount: float) -> String:
	var euros := absi(roundi(amount))
	var digits := str(euros)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if roundi(amount) < 0 else "") + "€" + digits + grouped
