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
## Contracts (design doc §10.4): length, how early the airline asks to renew, and how its
## happiness changes the terms it asks for.
const CONTRACT_SECONDS: float = 5760.0
const RENEWAL_NOTICE: float = 600.0
const HAPPY_RENEWAL: float = 70.0
const UNHAPPY_RENEWAL: float = 45.0
const HAPPY_FEE_FACTOR: float = 1.1
const UNHAPPY_FEE_FACTOR: float = 0.85
const HAPPY_EXTRA_FLIGHTS: int = 2
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
func tick(delta: float, stars: float, operating: bool, tier: int = 0, has_cargo_terminal: bool = false) -> void:
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
	_tick_contracts(delta)
	for id in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)

	_next_offer_in -= delta
	if _next_offer_in <= 0.0:
		_next_offer_in = rng.randf_range(OFFER_EVERY_MIN, OFFER_EVERY_MAX)
		make_offer(stars, tier, has_cargo_terminal)


## A new offer from an airline that would fly here now, or null if none would (or too many are open).
## Cargo airlines only make offers once the airport has a cargo terminal (`has_cargo_terminal`).
func make_offer(stars: float, tier: int = 0, has_cargo_terminal: bool = false) -> AirlineOffer:
	if offers.size() >= MAX_OFFERS:
		return null
	var candidates: Array[AirlineType] = []
	for type in CATALOG.types:
		if type.cargo and not has_cargo_terminal:
			continue
		if stars >= type.min_stars and tier >= type.min_tier and find_signed(type) == null and _find_offer(type) == null and not _cooldowns.has(type.id):
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
## Wide-body airlines only fit gates with a wide-body stand (`wide_stand`).
## Cargo terminals (`cargo_slot`) only take freighters, gates only passenger airlines (§10.3).
func next_airline(wide_stand: bool = false, cargo_slot: bool = false) -> Airline:
	var best: Airline = null
	for airline in signed:
		if airline.type.cargo != cargo_slot:
			continue
		if airline.type.wide_body and not wide_stand:
			continue
		# A wide-body stand goes to a wide-body airline first, if one is owed a flight.
		var better_fit := best != null and wide_stand and airline.type.wide_body and not best.type.wide_body
		var worse_fit := best != null and wide_stand and best.type.wide_body and not airline.type.wide_body
		if airline.credit >= MIN_CREDIT and not worse_fit and (best == null or better_fit or airline.credit > best.credit):
			best = airline
	if best != null:
		best.credit -= 1.0
	return best


## How likely the airline agrees to `fee` and `flights` said in `tone`, 0..1.
func chance(offer: AirlineOffer, fee: float, flights: int, tone: AirlineType.Tone, stars: float) -> float:
	var type := offer.type
	var result := BASE_CHANCE - (fee / offer.base_fee - 1.0) * CHANCE_PER_FEE_SHARE
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
		offer.fee = roundf((fee + offer.base_fee) * 0.5)
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
## A turned-down renewal: the airline keeps flying until its contract ends, then leaves.
func decline(offer: AirlineOffer) -> void:
	offers.erase(offer)
	if not offer.is_renewal:
		_cooldowns[offer.type.id] = COOLDOWN


## The renewal offer of `airline`, or null.
func renewal_of(airline: Airline) -> AirlineOffer:
	for offer in offers:
		if offer.is_renewal and offer.type == airline.type:
			return offer
	return null


# Contracts run out (design doc §10.4): the airline asks to renew shortly before, on terms set by
# its happiness, and leaves when the contract ends without a renewal.
func _tick_contracts(delta: float) -> void:
	for airline in signed.duplicate():
		airline.contract_left -= delta
		if airline.contract_left <= RENEWAL_NOTICE and not airline.renewal_offered:
			airline.renewal_offered = true
			var offer := renewal_terms(airline)
			offer.expires_in = airline.contract_left
			offers.append(offer)
			offer_arrived.emit(offer)
		if airline.contract_left <= 0.0:
			var pending := renewal_of(airline)
			if pending != null:
				offers.erase(pending)
			end_deal(airline)
			airline_left.emit(airline)


## What `airline` asks for to renew: more flights and a higher fee when happy, a discount when not.
func renewal_terms(airline: Airline) -> AirlineOffer:
	var flights := airline.flights_per_hour
	var fee := airline.fee
	if airline.happiness >= HAPPY_RENEWAL:
		flights += HAPPY_EXTRA_FLIGHTS
		fee = roundf(fee * HAPPY_FEE_FACTOR)
	elif airline.happiness < UNHAPPY_RENEWAL:
		fee = roundf(fee * UNHAPPY_FEE_FACTOR)
	var offer := AirlineOffer.new(airline.type, flights, fee)
	offer.is_renewal = true
	return offer


## The player ends a deal.
func end_deal(airline: Airline) -> void:
	signed.erase(airline)
	_cooldowns[airline.type.id] = COOLDOWN


## A flight of `airline` left: rates it (late or not, share of its passengers who missed it).
func record_flight(airline: Airline, late: bool, missed_share: float) -> void:
	if airline == null or not signed.has(airline):
		return
	airline.flown += 1
	if late:
		airline.late += 1
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
			"refused": airline.refused, "complained": airline.complained, "late": airline.late,
			"contract_left": airline.contract_left, "renewal_offered": airline.renewal_offered,
		})
	var saved_offers: Array[Dictionary] = []
	for offer in offers:
		saved_offers.append({
			"id": String(offer.type.id), "flights": offer.flights_per_hour, "fee": offer.fee,
			"expires_in": offer.expires_in, "counter": offer.is_counter,
			"renewal": offer.is_renewal, "base_fee": offer.base_fee,
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
		airline.late = int(entry.get("late", 0))
		airline.contract_left = float(entry.get("contract_left", CONTRACT_SECONDS))
		airline.renewal_offered = bool(entry.get("renewal_offered", false))
		airline.complained = bool(entry.get("complained", false))
		signed.append(airline)
	for entry: Dictionary in data.get("offers", []):
		var type := CATALOG.find(StringName(entry.get("id", "")))
		if type == null:
			continue
		var offer := AirlineOffer.new(type, int(entry.get("flights", type.flights_min)), float(entry.get("fee", type.expected_fee)))
		offer.expires_in = float(entry.get("expires_in", OFFER_LIFETIME))
		offer.is_counter = bool(entry.get("counter", false))
		offer.is_renewal = bool(entry.get("renewal", false))
		offer.base_fee = float(entry.get("base_fee", offer.fee))
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
	var current := find_signed(offer.type)
	if offer.is_renewal and current != null:
		# A renewal: the same airline, new terms and a new contract.
		current.fee = fee
		current.flights_per_hour = flights
		current.contract_left = CONTRACT_SECONDS
		current.renewal_offered = false
		return current
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
