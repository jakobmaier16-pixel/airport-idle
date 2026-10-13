class_name Airline
extends RefCounted
## A signed deal: an airline flying to the airport (design doc §10.1). Pure data.
## Flights point to their airline; the airline never points to flights (no reference cycles).

var type: AirlineType
## What the deal says: flights per hour and the fee per passenger (euros).
var flights_per_hour: int
var fee: float
## Flights the airline is "owed": grows with flights_per_hour, one is used per scheduled flight.
var credit: float = 1.0
## How happy the airline is with the airport, 0..100.
var happiness: float = Airlines.START_HAPPINESS
## Flights flown (and how many of them the airport made late), and flights the airport had no
## gate slot for.
var flown: int = 0
var late: int = 0
var refused: int = 0
## Seconds until the contract ends (design doc §10.4), and whether the airline already asked to renew.
var contract_left: float = Airlines.CONTRACT_SECONDS
var renewal_offered: bool = false
## True once its first landing was celebrated (design doc §14).
var first_landing_seen: bool = false
## True after the airline complained, until it is happy again (so it complains once).
var complained: bool = false


func _init(airline_type: AirlineType, flights: int, fee_per_passenger: float) -> void:
	type = airline_type
	flights_per_hour = flights
	fee = fee_per_passenger
