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
## Terminal fee for every arriving passenger, paid when they leave the airport (design doc §8.8).
const ARRIVAL_FEE: float = 5.0
## The airport's share of what customers spend in shops and cafés (concession fee).
const CONCESSION_SHARE: float = 0.3
const WALKWAY_COST_PER_CELL: float = 20.0
const WALKWAY_RUNNING_COST_PER_CELL: float = 0.05
## Taxiways for planes (design doc §7.5a).
const TAXIWAY_COST_PER_CELL: float = 30.0
const TAXIWAY_RUNNING_COST_PER_CELL: float = 0.05
## Bank loan (design doc §11.6): a negative balance is a loan with this interest per minute.
const LOAN_INTEREST_PER_MINUTE: float = 0.01
## The bank lends up to this much, plus a share of what the airport is worth.
const CREDIT_BASE: float = 20000.0
const CREDIT_SHARE_OF_VALUE: float = 0.25
## Over the credit limit for this long (seconds) and the bank restructures the airport.
const RESTRUCTURE_AFTER: float = 120.0
## The long-term average profit follows the last minute's profit with this time constant (seconds).
## It decides the welcome-back bonus after a long break (design doc §5).
const AVERAGE_PROFIT_SECONDS: float = 600.0
## Income and costs by source (design doc §13.2) cover this many seconds.
const SOURCE_WINDOW_SECONDS: int = 300
## Where money comes from and goes to.
const AIRLINE_FEES: String = "Airline fees"
const ARRIVAL_FEES: String = "Arrival fees"
const SHOPS: String = "Shops & cafés"
const LOUNGE: String = "Lounge"
const PARKING: String = "Parking"
const FAST_TRACK: String = "Fast track"
const RUNNING_COSTS: String = "Buildings & walkways"
const SALARIES: String = "Salaries"
const INTEREST: String = "Loan interest"
## Display order of the sources.
const INCOME_SOURCES: Array[String] = [AIRLINE_FEES, ARRIVAL_FEES, SHOPS, LOUNGE, PARKING, FAST_TRACK]
const COST_SOURCES: Array[String] = [RUNNING_COSTS, SALARIES, INTEREST]
## "Per minute" figures cover this many seconds.
const WINDOW_SECONDS: int = 60

var balance: float = STARTING_MONEY
## Profit per minute averaged over roughly the last ten minutes.
var average_profit_per_minute: float = 0.0
## Seconds the debt has been over the credit limit without a break.
var over_limit_seconds: float = 0.0

# Money per source per second over the last five minutes (ring buffers; costs are positive).
var _by_source: Dictionary[String, PackedFloat64Array] = {}
var _source_index: int = 0

# Net operating money per second over the last minute (ring buffer).
var _window: PackedFloat64Array = PackedFloat64Array()
var _window_index: int = 0
var _window_time: float = 0.0


func _init() -> void:
	_window.resize(WINDOW_SECONDS)


func can_afford(amount: float) -> bool:
	return balance >= amount


## Income from operations, from `source` (one of INCOME_SOURCES).
func earn(amount: float, source: String = AIRLINE_FEES) -> void:
	balance += amount
	_window[_window_index] += amount
	_add_to_source(source, amount)


## Income (or, for a cost source, costs) from `source` over the last five minutes.
func source_total(source: String) -> float:
	var total := 0.0
	for amount in _by_source.get(source, PackedFloat64Array()):
		total += amount
	return total


func _add_to_source(source: String, amount: float) -> void:
	if not _by_source.has(source):
		var buffer := PackedFloat64Array()
		buffer.resize(SOURCE_WINDOW_SECONDS)
		_by_source[source] = buffer
	_by_source[source][_source_index] += amount


## A one-off construction cost.
func pay_construction(amount: float) -> void:
	balance -= amount


## Money back for demolishing (a one-off, like construction; not part of profit per minute).
func refund(amount: float) -> void:
	balance += amount


## A one-off gift, e.g. the welcome-back bonus (not part of profit per minute).
func bonus(amount: float) -> void:
	balance += amount


## What the airport owes the bank (0 while the balance is positive).
func debt() -> float:
	return maxf(-balance, 0.0)


## Interest on the loan, in euros per minute.
func interest_per_minute() -> float:
	return debt() * LOAN_INTEREST_PER_MINUTE


## How much the bank lends to an airport worth `airport_value`.
static func credit_limit(airport_value: float) -> float:
	return CREDIT_BASE + airport_value * CREDIT_SHARE_OF_VALUE


## Charges running costs, salaries and loan interest for `delta` seconds and moves the windows along.
func tick(delta: float, running_cost_per_minute: float, salaries_per_minute: float = 0.0) -> void:
	var interest := interest_per_minute()
	var cost := (running_cost_per_minute + salaries_per_minute + interest) / 60.0 * delta
	balance -= cost
	_window[_window_index] -= cost
	_add_to_source(RUNNING_COSTS, running_cost_per_minute / 60.0 * delta)
	_add_to_source(SALARIES, salaries_per_minute / 60.0 * delta)
	_add_to_source(INTEREST, interest / 60.0 * delta)
	_window_time += delta
	while _window_time >= 1.0:
		_window_time -= 1.0
		_source_index = (_source_index + 1) % SOURCE_WINDOW_SECONDS
		# Packed arrays are copied when changed through a loop variable: index the dictionary.
		for source in _by_source:
			_by_source[source][_source_index] = 0.0
		average_profit_per_minute = lerpf(average_profit_per_minute, profit_per_minute(), 1.0 / AVERAGE_PROFIT_SECONDS)
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
