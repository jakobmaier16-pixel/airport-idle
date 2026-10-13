class_name Airlines
extends RefCounted
## Signed airlines, their offers and negotiations (design doc §10.1). Pure data; Airport owns it
## and calls tick(). Gates are the airport's capacity, airlines are the demand: FlightSchedule asks
## next_airline() for every free gate slot.

## The airport heard from an airline (the HUD shows a notice).
signal offer_arrived(offer: AirlineOffer)
signal airline_unhappy(airline: Airline)
signal airline_left(airline: Airline)

const CATALOG: AirlineCatalog = preload("res://data/airlines/catalog.tres")
## A new airport starts with this deal.
const STARTER: StringName = &"velora"
const STARTER_FLIGHTS: int = 20
## Offers: the first arrives after this many seconds, then one every OFFER_EVERY_MIN..MAX.
const FIRST_OFFER_AFTER: float = 120.0
const OFFER_EVERY_MIN: float = 240.0
const OFFER_EVERY_MAX: float = 420.0
const MAX_OFFERS: int = 3
const OFFER_LIFETIME: float = 600.0
## An airline that walked away (or left) doesn't make a new offer for this long.
const COOLDOWN: float = 900.0
## Owed flights beyond this many are refused: the airport had no gate slot for them.
const MAX_BACKLOG: float = 2.0
## A gate slot may go to an airline that is owed at least this much (a flight slightly early is fine).
const MIN_CREDIT: float = 0.5
## Happiness: start, how fast it follows recent flights, and the thresholds.
const START_HAPPINESS: float = 75.0
const HAPPINESS_SMOOTHING: float = 0.15
const LATE_SCORE: float = 50.0
const COMPLAIN_BELOW: float = 40.0
const CALM_ABOVE: float = 50.0
const LEAVE_BELOW: float = 25.0
## Limits of the terms the player can propose.
const FEE_MIN: float = 4.0
const FEE_MAX: float = 40.0
const FLIGHTS_MIN: int = 2
## Chance to agree (all in shares of 1): at their expected fee; per share of fee above / below it;
## per share of flights fewer than asked; per star above their minimum; for the tone they like or
## dislike. A "no" with at least COUNTER_MIN_CHANCE brings a counter-offer.
const BASE_CHANCE: float = 0.75
const CHANCE_PER_FEE_SHARE: float = 1.5
const CHANCE_PER_MISSING_FLIGHTS: float = 0.5
const CHANCE_PER_STAR: float = 0.05
const TONE_EFFECT: float = 0.15
const COUNTER_MIN_CHANCE: float = 0.25

enum Answer { ACCEPTED, COUNTER, REJECTED }

var signed: Array[Airline] = []
var offers: Array[AirlineOffer] = []
## Exposed so tests can make negotiations repeatable.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _next_offer_in: float = FIRST_OFFER_AFTER
var _cooldowns: Dictionary[StringName, float] = {}


func _init() -> void:
	rng.randomize()
	reset()


## A new airport: only the starter deal.
func reset() -> void:
	signed.clear()
	offers.clear()
	_cooldowns.clear()
	_next_offer_in = FIRST_OFFER_AFTER
	var starter := CATALOG.find(STARTER)
	sign_deal(starter, STARTER_FLIGHTS, starter.expected_fee)


## `operating` is false while no gate can have flights: airlines don't count flights as owed then.
func tick(delta: float, stars: float, operating: bool) -> void:
	for airline in signed.duplicate():
		if not operating:
			continue
		airline.credit += airline.flights_per_hour / 3600.0 * delta
		if airline.credit > MAX_BACKLOG:
			# No gate slot for this flight: refused.
			airline.credit -= 1.0
			airline.refused += 1
			_rate(airline, 0.0)

	for offer in offers.duplicate():
		offer.expires_in -= delta
		if offer.expires_in <= 0.0:
			offers.erase(offer)
	for id in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)

	_next_offer_in -= delta
	if _next_offer_in <= 0.0:
		_next_offer_in = rng.randf_range(OFFER_EVERY_MIN, OFFER_EVERY_MAX)
		make_offer(stars)


## A new offer from an airline that would fly here now, or null if none would (or too many are open).
func make_offer(stars: float) -> AirlineOffer:
	if offers.size() >= MAX_OFFERS:
		return null
	var candidates: Array[AirlineType] = []
	for type in CATALOG.types:
		if stars >= type.min_stars and find_signed(type) == null and _find_offer(type) == null and not _cooldowns.has(type.id):
			candidates.append(type)
	if candidates.is_empty():
		return null
	var type := candidates[rng.randi() % candidates.size()]
	var offer := AirlineOffer.new(type, rng.randi_range(type.flights_min, type.flights_max), type.expected_fee)
	offers.append(offer)
	offer_arrived.emit(offer)
	return offer


## A special offer from one airline (a milestone reward, design doc §14.1), whatever the rating.
## Returns null if that airline already flies here or has an open offer.
func offer_from(id: StringName) -> AirlineOffer:
	var type := CATALOG.find(id)
	if type == null or find_signed(type) != null or _find_offer(type) != null:
		return null
	_cooldowns.erase(id)
	var offer := AirlineOffer.new(type, type.flights_max, type.expected_fee)
	offers.append(offer)
	offer_arrived.emit(offer)
	return offer


## The airline that gets the next free gate slot (the one owed the most flights), or null.
func next_airline() -> Airline:
	var best: Airline = null
	for airline in signed:
		if airline.credit >= MIN_CREDIT and (best == null or airline.credit > best.credit):
			best = airline
	if best != null:
		best.credit -= 1.0
	return best


## How likely the airline agrees to `fee` and `flights` said in `tone`, 0..1.
func chance(offer: AirlineOffer, fee: float, flights: int, tone: AirlineType.Tone, stars: float) -> float:
	var type := offer.type
	var result := BASE_CHANCE - (fee / type.expected_fee - 1.0) * CHANCE_PER_FEE_SHARE
	result -= (1.0 - float(flights) / offer.flights_per_hour) * CHANCE_PER_MISSING_FLIGHTS
	result += maxf(stars - type.min_stars, 0.0) * CHANCE_PER_STAR
	if tone == type.likes:
		result += TONE_EFFECT
	elif tone == type.dislikes:
		result -= TONE_EFFECT
	return clampf(result, 0.0, 1.0)


## The player proposes terms. Signs the deal, turns the offer into a counter-offer, or the
## airline walks away.
func propose(offer: AirlineOffer, fee: float, flights: int, tone: AirlineType.Tone, stars: float) -> Answer:
	if not offers.has(offer) or offer.is_counter:
		return Answer.REJECTED
	var agree_chance := chance(offer, fee, flights, tone, stars)
	if rng.randf() < agree_chance:
		_sign(offer, fee, flights)
		return Answer.ACCEPTED
	if agree_chance >= COUNTER_MIN_CHANCE:
		offer.is_counter = true
		offer.fee = roundf((fee + offer.type.expected_fee) * 0.5)
		offer.flights_per_hour = flights
		return Answer.COUNTER
	decline(offer)
	return Answer.REJECTED


## Signs a counter-offer as it stands.
func accept_counter(offer: AirlineOffer) -> Airline:
	if not offers.has(offer) or not offer.is_counter:
		return null
	return _sign(offer, offer.fee, offer.flights_per_hour)


## Turns an offer down (or the airline walked away): no new offer from them for a while.
func decline(offer: AirlineOffer) -> void:
	offers.erase(offer)
	_cooldowns[offer.type.id] = COOLDOWN


## The player ends a deal.
func end_deal(airline: Airline) -> void:
	signed.erase(airline)
	_cooldowns[airline.type.id] = COOLDOWN


## A flight of `airline` left: rates it (late or not, share of its passengers who missed it).
func record_flight(airline: Airline, late: bool, missed_share: float) -> void:
	if airline == null or not signed.has(airline):
		return
	airline.flown += 1
	_rate(airline, (LATE_SCORE if late else 100.0) - missed_share * 100.0)


## Flights per hour all signed airlines want together.
func signed_flights_per_hour() -> int:
	var total := 0
	for airline in signed:
		total += airline.flights_per_hour
	return total


func find_signed(type: AirlineType) -> Airline:
	for airline in signed:
		if airline.type == type:
			return airline
	return null


func save_state() -> Dictionary:
	var saved_signed: Array[Dictionary] = []
	for airline in signed:
		saved_signed.append({
			"id": String(airline.type.id), "flights": airline.flights_per_hour, "fee": airline.fee,
			"credit": airline.credit, "happiness": airline.happiness, "flown": airline.flown,
			"refused": airline.refused, "complained": airline.complained,
		})
	var saved_offers: Array[Dictionary] = []
	for offer in offers:
		saved_offers.append({
			"id": String(offer.type.id), "flights": offer.flights_per_hour, "fee": offer.fee,
			"expires_in": offer.expires_in, "counter": offer.is_counter,
		})
	return {"signed": saved_signed, "offers": saved_offers, "next_offer_in": _next_offer_in, "cooldowns": _cooldowns}


## Restores from save_state(). Saves from before airlines existed keep the starter deal.
func load_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	signed.clear()
	offers.clear()
	_cooldowns.clear()
	for entry: Dictionary in data.get("signed", []):
		var type := CATALOG.find(StringName(entry.get("id", "")))
		if type == null:
			continue
		var airline := Airline.new(type, int(entry.get("flights", type.flights_min)), float(entry.get("fee", type.expected_fee)))
		airline.credit = float(entry.get("credit", 1.0))
		airline.happiness = float(entry.get("happiness", START_HAPPINESS))
		airline.flown = int(entry.get("flown", 0))
		airline.refused = int(entry.get("refused", 0))
		airline.complained = bool(entry.get("complained", false))
		signed.append(airline)
	for entry: Dictionary in data.get("offers", []):
		var type := CATALOG.find(StringName(entry.get("id", "")))
		if type == null:
			continue
		var offer := AirlineOffer.new(type, int(entry.get("flights", type.flights_min)), float(entry.get("fee", type.expected_fee)))
		offer.expires_in = float(entry.get("expires_in", OFFER_LIFETIME))
		offer.is_counter = bool(entry.get("counter", false))
		offers.append(offer)
	_next_offer_in = float(data.get("next_offer_in", FIRST_OFFER_AFTER))
	var cooldowns: Dictionary = data.get("cooldowns", {})
	for id in cooldowns:
		_cooldowns[StringName(id)] = float(cooldowns[id])


## Signs a deal without negotiating (new game, showcase, tests).
func sign_deal(type: AirlineType, flights: int, fee: float) -> Airline:
	var airline := Airline.new(type, flights, fee)
	signed.append(airline)
	return airline


func _sign(offer: AirlineOffer, fee: float, flights: int) -> Airline:
	offers.erase(offer)
	return sign_deal(offer.type, flights, fee)


func _find_offer(type: AirlineType) -> AirlineOffer:
	for offer in offers:
		if offer.type == type:
			return offer
	return null


func _rate(airline: Airline, score: float) -> void:
	airline.happiness = lerpf(airline.happiness, clampf(score, 0.0, 100.0), HAPPINESS_SMOOTHING)
	if airline.happiness < LEAVE_BELOW:
		end_deal(airline)
		airline_left.emit(airline)
	elif airline.happiness < COMPLAIN_BELOW and not airline.complained:
		airline.complained = true
		airline_unhappy.emit(airline)
	elif airline.happiness > CALM_ABOVE:
		airline.complained = false
