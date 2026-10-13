class_name AirlineOffer
extends RefCounted
## An airline's offer to fly to the airport, waiting for the player's answer (design doc §10.1).

var type: AirlineType
## What the airline asks for: flights per hour, and the fee per passenger it offers to pay.
var flights_per_hour: int
var fee: float
## Seconds until the offer expires.
var expires_in: float = Airlines.OFFER_LIFETIME
## A counter-offer after the player's terms were turned down: sign or decline, no more haggling.
var is_counter: bool = false


func _init(airline_type: AirlineType, flights: int, fee_per_passenger: float) -> void:
	type = airline_type
	flights_per_hour = flights
	fee = fee_per_passenger
