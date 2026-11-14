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
