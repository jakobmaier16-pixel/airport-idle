# Removed features

Decided 2026-11-14 (docs/decisions.md): the game is stripped to its core (map and building, runway,
taxiways, stands, terminal with gate, a simple timetable, planes that land, taxi and take off, the
clock). Removed features are **deleted from the code**, not switched off. Each entry says what it did,
the rules and numbers that mattered, the main files, and the last commit that still has it, so it can
be rebuilt (or restored with `git show 262844b:<file>`) in about a week or later.

**Last commit with all of it: `262844b`** (main, before the strip). Numbers are placeholders from the
prototype; the full rules stay in `docs/prototype_reference.md` (sections named below).

## Removed in PR 1 (passengers, stations, shops, satisfaction, staff)

### Passenger flow
- **What:** every passenger was simulated as data (10 Hz): arrive for a flight, walk on walkways to
  check-in, security and the gate, wait in queues, board; arriving passengers deplaned, went to the
  baggage claim and left. A route was needed (entrance, check-in, security, gate with stand) before
  flights ran at all.
- **Rules:** walking ~1.3 m/s; check-in 3 counters ~8 s per passenger, security 2 lanes ~6 s; security
  is the only link between landside and airside; passengers wait inside the gate until boarding
  (`FlightSchedule.BOARDING_OPENS`); a missed flight counts three times in satisfaction. Flights had
  seats (narrow 160, wide x2), bookings, a route type (holiday / low-cost / business) setting the mix of
  passenger types, and a hold on departure until boarding was done (max hold `MAX_HOLD`).
- **Money:** per passenger fee plus a EUR 5 arrival fee; progression counted passengers.
- **Files:** `scripts/simulation/passenger_flow.gd`, `passenger.gd`, `passenger_save.gd` (packed
  save block, format 6), `scenes/passengers/passenger_layer.gd` (MultiMesh figures near the camera),
  `Flight` passenger fields (`seats`, `booked`, `arrival_times`, `boarded`, `missed`, ...),
  `TimetableSlot.seats`. Prototype reference §8.1 to §8.5, §8.8.
- **Save:** passenger keys (`flow.passengers`, `flow.stations`) are no longer written or read; the
  schedule moved to the top-level key `schedule` (old saves are read from `flow.schedule`).

### Passenger types and journeys
- Three types (families, low-cost, business) with their own speeds, timing, spending, patience
  (`data/passengers/*.tres`, `PassengerType`), and recipe-based journeys (`data/journeys/`,
  `JourneyRecipe`, `JourneyStep`). Prototype reference §8.2, §8.7.

### Stations (queues and service)
- **What:** `Station` wrapped a service building: service slots (check-in counters, security lanes),
  a queue, people being served, customers inside, income window. The HUD table listed them with queue
  length and bottleneck; `Building.service_slots`, `service_time` and `BuildingType` passenger
  fields (`customer_capacity`, `visit_seconds_*`, `spend_*`) fed it.
- **Files:** `scripts/simulation/station.gd`, HUD stations tab, bottleneck line. The station panel now
  shows only name, zone and close.

### Shops, cafes, lounge
- **Shop** (EUR 3,500 build, 5/min, 8 customers, 20-40 s, spend 20-40) and **cafe** (3,000, 6/min,
  12 customers, 30-60 s, spend 8-16): after security, passengers with at least 45 s to spare visited
  one with 70 % probability; the airport kept a 30 % concession share. Final call sent customers out
  before boarding.
- **Lounge** (airside 5 x 3, 10,000, 20/min, 16 guests): business travellers waited there, EUR 12 per
  guest, +10 mood.
- **Files:** `data/buildings/shop.tres`, `cafe.tres`, `lounge.tres`, the awning in `building_visual.gd`.
  Prototype reference §8.6, §11.8. `Economy.SHOPS`, `LOUNGE` constants remain (unused) for PR 2.

### Baggage claim and transfers
- **Baggage claim** (6,000, 30/min): border building like security, used airside to landside; bags
  came off the belt 30-90 s after the plane parked; without it no flights ran. **Transfer security**
  (4 x 3, 4,000, 8/min, 2 lanes): connecting passengers (business 25 %, holiday 10 %, low-cost 5 %)
  skipped the claim and had to catch a flight leaving at least 2.5 min later; `ZoneMap` joined the
  transfer security to the border logic. Prototype reference §8.8, §8.9.
- **Files:** `data/buildings/baggage_claim.tres`, `transfer_security.tres`; the `Role` values
  `BAGGAGE_CLAIM`, `TRANSFER_SECURITY` (and `SHOP`, `LOUNGE`) stay in the enum because saves store
  numbers. Old saves skip these buildings on load with a half-price refund.

### Satisfaction
- **What:** a mood (0-100) per passenger, dropping on long queues (-0.5/s beyond patience), long walks
  (-0.1 per m beyond 150 m), waiting for bags, no way through, missed flights; shop visits +5. The airport
  satisfaction was the mean of the last 60 journeys (starts 75 %), overall and per type, with a "main
  complaint". It fed reputation (stars) next to punctuality.
- **Files:** `scripts/simulation/satisfaction.gd`. `Reputation.stars()` now uses punctuality only
  (1 star at 50 % on time, 5 stars at 95 %). Prototype reference §8.10, §11.7.

### Staff, training, supervisors
- **What:** individual employees with names and experience per station type (new 25 % slower, expert
  15 % faster after 150 passengers); every check-in counter and security lane needed one, hire and
  dismiss in the station panel; salaries (check-in 8/min, security 10/min); training (EUR 400, 45 s
  away, +40 experience); promotion to supervisor (+4/min, +5 % speed at the station); cargo handling
  speed came from handlers (4 places x 0.25 t/s).
- **Files:** `scripts/simulation/employee.gd`, staff functions in `airport_brain.gd` (`SALARIES`,
  `FIRST_NAMES`, hire / dismiss / train / promote), HUD staff and team buttons.
  Prototype reference §9.1, §9.2.
- **Now:** salaries are 0 in the economy; cargo handling is a fixed `FlightSchedule.HANDLING_RATE`
  (1.0 t/s). `Economy.SALARIES` stays for PR 2.

### Station upgrades and fast track
- **What:** check-in level 2/3 (+1 counter, EUR 2,500 / 4,000), security (+1 lane 4,000, faster scanners
  -25 %), small upgrades instant, big ones with construction time; fast track lane at security
  (EUR 5,000 one-off, business passengers pay 5 each and skip the queue). Data: `StationUpgrade`
  resources inside each building `.tres`.
- **Files:** `scripts/resources/station_upgrade.gd`, `Building.level`, `next_upgrade`, `fast_track`,
  upgrade-timer code in `airport_brain.gd`, HUD upgrade / fast track buttons.
  Prototype reference §7.8, §11.8.

### Manager on the spot
- **What:** hiring, dismissing and upgrading needed the manager within 10 m of the building; within 6 m
  of a staffed station staff were 10 % faster and queues cost half the mood; a green "Manager here"
  hint floated over the station. Prototype reference §15.1.
- **Files:** `manage_problem`, `is_manager_near` in `airport_brain.gd`, hints in `building_layer.gd`.

### Car park fees
- With a connected car park, 35 % of passengers arrived there and paid EUR 8 on the way out. The car park
  building stays as a landside building without income. Prototype reference §11.8.

### Walkway network (passenger pathfinding)
- `scripts/simulation/walkway_network.gd`: sparse A* over the walkway cells (one AStar2D, chunked) with
  area ids, used only by passengers. Walkway painting and the zone map stay.

### Benchmark with crowds
- `scripts/dev/benchmark.gd` filled the airport with up to `PASSENGER_LIMIT` passengers and measured
  frame time with figures drawn. It now measures planes plus the build view. The behaviour hash no
  longer covers passengers (re-baselined in PR 1).

## Removed in PR 2 (money, airlines, demand, reputation, tiers, seasons, cargo, goals)

**Last commit with all of it: `bec1f7c`** (main after PR 1; restore a file with `git show bec1f7c:<file>`).
Save format 11 drops all their saved data; buildings of removed types are dropped on load without refund.

### Money and economy
- **What:** the airport's cash. Start EUR 50,000; every building, walkway cell (20) and taxiway cell cost
  money to place, demolishing refunded part of it, buildings had a running cost per minute. Income: EUR 15 per
  departing passenger, EUR 300 per departing flight, EUR 5 per arriving passenger, 30 % of shop and cafe
  spending. "Profit per minute" was averaged over the last minute. A loan (borrow, repay, restructure when
  over the limit) kept the player going; offline income paid 4 h of average profit after 36 h away.
- **Files:** `scripts/simulation/economy.gd`, money checks in `airport_brain.gd` (`check_placement`,
  `paint_walkway`, `paint_taxiway`, `demolish`), `build_cost` / `running_cost_per_minute` in `BuildingType`,
  offline code in `save_game.gd`, HUD money and loan labels. Game design §11, prototype reference §11.
- **Now:** everything is free; building is limited only by the rules (zones, overlap, map edge).

### Building upgrades and levels
- **What:** there was no separate upgrade system left after PR 1 (station upgrades went then). PR 2 removed
  the remaining level and upgrade fields from buildings and the save (`level`, `upgrade*`, `closed`, `cost`).
- **Files:** `Building` fields, building entries in `airport_brain.gd` save and load. Game design §3.2.

### Airlines, offers and deals
- **What:** fictional airlines with a catalog (`data/airlines/*.tres`, `AirlineType`, `AirlineCatalog`).
  A starter deal (Velora, 20 flights); the first offer came after 120 s, then every 240-420 s, at most 3 open,
  each lasting 600 s; the player accepted, negotiated or declined, and signed airlines supplied the flights
  for free gate slots. Tail colours on planes came from the airline.
- **Files:** `airlines.gd`, `airline.gd`, `airline_offer.gd`, `scenes/ui/airlines_panel.*`, `data/airlines/`.
  Game design §10.
- **Now:** one constant default livery and the flight number prefix `AI`.

### Demand
- **What:** one number, narrow-body flights per game hour (start 3.0), times an hour-of-day rush factor
  (`Clock.DEMAND_BY_HOUR`); updated once per game day from stars and on-time rate; tier caps 6 / 9 / 12 / 16;
  about 5 days to the cap when run well; falling was slower than growing.
- **Files:** `demand.gd`, `Clock.demand_factor`, `Clock.DEMAND_BY_HOUR`. Tech architecture §6.

### Stars and reputation
- **What:** a 1-5 star rating from the smoothed on-time rate of departures (on time = at most 10 s delay,
  start 0.9, smoothing 0.1, 1 star at 0.5, 5 stars at 0.95); stars scaled demand (0.6 at 1 star) and gated tiers.
- **Files:** `reputation.gd`, `scenes/ui/star_rating.*`, HUD rating row. Game design §11.7.

### Tiers, progression and land gating
- **What:** Regional / National / International / Hub. Needs: 1,000 / 6,000 / 25,000 passengers, 3 / 3.5 / 4
  stars, 600 transfers for Hub. Each tier unlocked building types (`unlocked_at`) and, for Regional, only the
  1,200 x 400 cell starting rectangle was ownable; the ground shader dimmed unowned land. A milestone panel
  announced each tier.
- **Files:** `progression.gd`, `BuildingType.unlocked_at`, `owns_cell`, `land_changed`, `ground.gd` and
  `ground_grid.gdshader` (`owned_rect`), milestone panel. Game design §13.
- **Now:** the whole map is buildable and every type is available. The `OWNED_BIT` in the grid stays unused.

### Seasons
- **What:** four seasons of 2 game days each (Spring, Summer, Autumn, Winter) that shifted demand by route type.
- **Files:** `seasons.gd`. Game design §12.2.

### Night curfew
- **What:** no flights from 00:00 to 05:00 until the Hub tier. Files: `Clock.CURFEW_START/END`,
  `is_curfew_hour`, a check in `flight_schedule.gd`. Game design §12.4.

### Cargo terminal and freighters
- **What:** a cargo terminal building and cargo stands; freighter flights loaded tonnes at a fixed handling
  rate (1.0 t/s) and paid a fee. `BuildingType.Role.CARGO_TERMINAL` stays in the enum (saved numbers are never
  renumbered) but no type uses it.
- **Files:** `data/buildings/cargo_terminal.tres`, cargo code in `flight_schedule.gd` and `flight.gd`,
  `usable_cargo_terminals` in `airport_brain.gd`, grey freighter livery in `plane_visual.gd`.

### Goals, milestone panel and stats panel
- **What:** ten "Getting started" goals read from the airport state (hideable); the milestone panel; a stats
  panel with tabs and a message log in the HUD.
- **Files:** `goals.gd`, goal / milestone / stats nodes in `hud.tscn` and `hud.gd`. Game design §6.1.

### HUD and save leftovers (PR 1 + 2)
- **HUD:** money, profit and loan rows, the star rating row, the stations tab with queues, staff / team /
  upgrade / fast-track buttons, the airlines panel button, goal line, milestone and stats panels, message log.
  The station panel shows only name, zone and area. The status line shows the clock and flights.
- **Data:** `data/airlines/`, `data/journeys/`, `data/passengers/`, the building types shop, cafe, lounge,
  baggage claim, transfer security, cargo terminal (and the older de-icing pad); their `Role` numbers stay.
- **Save:** format 11 drops the keys listed in `SaveGame` (`money`, `staff`, `flow`, `goals_hidden`, ...);
  old saves still load.

### Old timetable (rng based)
- **What:** `FlightSchedule` planned flights every `INTERVAL` from the demand and rush factor, picked gates
  and airlines with `Airport.rng`. Replaced by `Timetable`: one fixed turnaround per usable gate every
  `TURNAROUND_MINUTES` (90) game minutes, staggered by gate id, no rng.
