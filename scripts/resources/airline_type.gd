class_name AirlineType
extends Resource
## A fictional airline that can fly to the airport (design doc §10.1).
## Instances live in data/airlines/*.tres.

## How the player answers an offer.
enum Tone { FIRM, FRIENDLY, FLEXIBLE }

@export var id: StringName
@export var display_name: String
## Two-letter code for flight numbers, e.g. "ZP" -> "ZP 214".
@export var code: String
## Route type: "Holiday", "Low-cost" or "Business" (sets the passenger mix, see FlightSchedule.ROUTES).
@export var route: String = "Holiday"
## Tail color of their planes.
@export var color: Color = Color(0.1, 0.45, 0.65)

@export_group("Deal")
## Fee per passenger they expect to pay, in euros.
@export var expected_fee: float = 15.0
## Flights per hour they ask for (a random amount in this range).
@export var flights_min: int = 8
@export var flights_max: int = 12
## Star rating the airport needs before they make an offer.
@export var min_stars: float = 1.0
## Airport tier needed before they make an offer (Progression.Tier, design doc §14.1).
@export_range(0, 3) var min_tier: int = 0
## Flies freighters to cargo terminals; `expected_fee` is per tonne (design doc §10.3).
@export var cargo: bool = false
## Flies wide-body planes: only gates with a wide-body stand can take them (design doc §10.2).
@export var wide_body: bool = false

@export_group("Personality")
@export var likes: Tone = Tone.FRIENDLY
@export var dislikes: Tone = Tone.FIRM
## What their representative says when making an offer (hints at their personality).
@export_multiline var pitch: String = ""
