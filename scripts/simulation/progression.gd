class_name Progression
extends RefCounted
## Airport tiers and milestones (design doc §14.1). Pure data; Airport owns it.

## A new tier was reached (the HUD shows the milestone panel).
signal tier_reached(tier: Tier)

enum Tier { REGIONAL, NATIONAL, INTERNATIONAL, HUB }

const NAMES: Array[String] = ["Regional", "National", "International", "Hub"]
## What reaching each tier needs: passengers, star rating, transfers. (Index = tier.)
const PASSENGERS_NEEDED: Array[int] = [0, 2000, 10000, 40000]
const STARS_NEEDED: Array[float] = [0.0, 3.0, 3.5, 4.0]
const TRANSFERS_NEEDED: Array[int] = [0, 0, 0, 1000]
## What each tier brings, for the milestone panel.
const REWARDS: Array[String] = [
	"",
	"New land: the whole map is yours.\nTransfer security: sell connecting flights.\nNorvane Airways wants to fly here.",
	"Long-haul flights: build a wide-body stand for big planes.\nOrynth Pacific wants to fly here.",
	"Hub status: airlines route twice as many connections through you.\nCorvista Airlines wants to fly here.",
]
## Regional airports own this many cells in the middle of the map; from National on, all of it.
const REGIONAL_LAND: Vector2i = Vector2i(48, 48)
## Hub status: transfer shares of every route are multiplied by this (design doc §14.1).
const HUB_TRANSFER_FACTOR: float = 2.0

var tier: Tier = Tier.REGIONAL
## Counted over the whole game.
var passengers: int = 0
var transfers: int = 0


func reset() -> void:
	tier = Tier.REGIONAL
	passengers = 0
	transfers = 0


func name_of(which: Tier) -> String:
	return NAMES[which]


## The tier after the current one, or -1 at the top.
func next_tier() -> int:
	return tier + 1 if tier < Tier.HUB else -1


## Checks the requirements; reaching a tier sends tier_reached (one tier per call).
func check(stars: float) -> void:
	var next := next_tier()
	if next < 0:
		return
	if passengers >= PASSENGERS_NEEDED[next] and stars >= STARS_NEEDED[next] and transfers >= TRANSFERS_NEEDED[next]:
		tier = next as Tier
		tier_reached.emit(tier)


## "National airport: 1,234 / 2,000 passengers · 3 ★ needed (now 3.5)".
func progress_text(stars: float) -> String:
	var next := next_tier()
	if next < 0:
		return "%s airport: the highest tier." % name_of(tier)
	var parts: PackedStringArray = ["%s / %s passengers" % [_number(passengers), _number(PASSENGERS_NEEDED[next])]]
	parts.append("%.1f / %.1f stars" % [Reputation.shown_stars(stars), STARS_NEEDED[next]])
	if TRANSFERS_NEEDED[next] > 0:
		parts.append("%s / %s transfers" % [_number(transfers), _number(TRANSFERS_NEEDED[next])])
	return "%s airport · next: %s (%s)" % [name_of(tier), name_of(next as Tier), "  ·  ".join(parts)]


## Cells the airport owns: the middle of the map for a regional airport, then everything.
func owned_land(map_size: Vector2i) -> Rect2i:
	if tier >= Tier.NATIONAL:
		return Rect2i(Vector2i.ZERO, map_size)
	return Rect2i((map_size - REGIONAL_LAND) / 2, REGIONAL_LAND)


func save_state() -> Dictionary:
	return {"tier": tier, "passengers": passengers, "transfers": transfers}


func load_state(data: Dictionary) -> void:
	tier = clampi(int(data.get("tier", Tier.REGIONAL)), Tier.REGIONAL, Tier.HUB) as Tier
	passengers = int(data.get("passengers", 0))
	transfers = int(data.get("transfers", 0))


static func _number(value: int) -> String:
	return Economy.format(value).trim_prefix("€")
