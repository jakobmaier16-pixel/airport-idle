class_name PassengerType
extends Resource
## A kind of passenger, e.g. business traveller (design doc §8.2, §8.7).
## Instances live in data/passengers/*.tres.

@export var id: StringName
## Plural name for statistics, e.g. "Families".
@export var display_name: String
## Figure colors; each passenger gets one of them.
@export var colors: Array[Color] = []
@export var walk_speed: float = 1.3

@export_group("Arrival")
## Earliest and latest arrival at the entrance, in seconds before departure.
@export var arrives_from: float = 240.0
@export var arrives_until: float = 150.0

@export_group("Processing")
## Share that checked in online with hand luggage only and skip the check-in counters.
@export_range(0.0, 1.0) var skip_check_in_chance: float = 0.0
## Multiplies the time per passenger at check-in / security (1.4 = 40 % slower).
@export var check_in_time_factor: float = 1.0
@export var security_time_factor: float = 1.0

## Arriving passengers: share with a checked bag, who wait at the baggage claim (design doc §8.8).
@export_range(0.0, 1.0) var checked_bag_chance: float = 1.0

@export_group("Shopping")
## Chance to visit a shop or café after security, if there is time (design doc §8.6).
@export_range(0.0, 1.0) var shop_chance: float = 0.6
## Multiplies what they spend there.
@export var spend_factor: float = 1.0
