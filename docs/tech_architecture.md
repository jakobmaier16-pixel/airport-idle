# Technical Architecture — Airport Manager (working title)

> Status: Draft v1 · 2026-11-06
> This document describes *how* the game is built. *What* the game is lives in [game_design.md](game_design.md); the order of work lives in [master_plan.md](master_plan.md).
> It covers what the **vertical slice** needs. Each section ends with **Later:** for what waits.
> Markers: **(proposal)** = suggested, not yet confirmed · **(open)** = undecided, see §19.
> Written in plain language on purpose: no code, so every decision can be checked by a non-programmer.

---

## 1. Purpose

- Claude Code reads this document before any technical work, next to `game_design.md` and `CLAUDE.md`.
- When a technical decision is made, this document changes the same day.
- `CLAUDE.md` holds the day-to-day coding rules; this document holds the structure behind them.

---

## 2. The big picture: brain, windows, hands

The game is split into three parts that are kept strictly apart:

| Part | What it is | What it may do |
|---|---|---|
| **The brain** (simulation) | Everything the airport *knows*: buildings, passengers, flights, money, the clock. Like the rules and the pieces of a board game. | Change the airport. It never draws anything and never knows what is on screen. |
| **The windows** (views) | The top-down view and the first-person view. | Look at the brain and draw what they see. They never change anything. |
| **The hands** (UI and touch) | Buttons, panels and gestures. | Ask the brain for changes (§11). They never change the airport directly. |

**Why:** the brain stays fast and can be tested without graphics, and the drawing can be made simpler on older iPhones without touching the rules. The prototype mostly works like this already; the leaks are listed in §17.

---

## 3. The brain's heartbeat

- **10 heartbeats per second.** The brain thinks in fixed steps, whatever the screen does. The drawing smooths movement between two heartbeats. (Already working in the prototype.)
- **One clock** for everything. The prototype has two (time of day, and a passenger timer that restarts at every load); they become one (**follow-up**: today the passenger timer is saved with the game, so timing survives a load; merging it into the clock is not needed for that). One real second is 15 game seconds; a new airport opens at 06:00 on day 1. **Step 6a done** (2026-11-13): the passenger timer is gone; `Clock` is the one clock (`real_elapsed`, only runs forward) and `PassengerFlow.time` just reads it. Times inside flights and passengers are still real seconds; they move to game seconds with the timetable (6b). Save format 7 stores it as `clock_elapsed`.
- **Dice with a seed.** All randomness (passenger types, arrival times, names) comes from one random generator that starts from a number, the *seed*. The same seed gives exactly the same game, so a bug can be replayed and tests always behave the same. The seed is saved with the game.
  - **Done** (2026-11-06): today the dice live in the global airport object (`Airport.rng`) and are shared with every part of the brain; every test runs with its own fixed seed.
  - **When the brain becomes one object, the shared dice move with it:** the brain object owns them, every part of the brain gets them from the brain, and they are saved with it. Nothing may keep its own dice or fall back to the global ones.
- **The brain is one object.** The whole airport lives in one self-contained object instead of being spread over a global that everything reaches into. A test can create a fresh airport in a split second; later a second airport could exist for previews.
  - **Step 2b done** (2026-11-13): the brain is `AirportWorld` (`scripts/simulation/airport_brain.gd`, RefCounted, owns the dice); the autoload `Airport` (`AirportHost`) only steps it and forwards properties, methods and signals. `dispose()` breaks the reference cycles. **Step 2c done** (2026-11-13): `Airport.reset()` disposes the old brain and creates a fresh `AirportWorld`; the host re-binds its signals (never twice). Step 2 is done. Never keep the brain or a part of it in a variable across a reset: read it through `Airport`.

**Later:** running the brain on its own processor core (a background thread) if the heartbeat gets too heavy for big hubs.

---

## 4. Map, buildings, automatic zones and areas

- **One grid map, real scale** (decided 2026-11-13). Everything is real size, also the airside (1 cell = 2 m, one value that is easy to change). The map is large (a full-length runway alone is ~1,250 cells), so the top-down view draws the whole airport with very cheap far models, and the first-person view loads only the manager's area in full detail.
  **Anchoring (PR 6A):** showcase, tests and the behaviour hash do not use absolute cells. Layouts are written in cells of a 64 × 64 reference map and moved to the same spot relative to the map centre by `MapAnchor` (`scripts/simulation/map_anchor.gd`); `BehaviourHash` moves cells back the same way and ignores the map size, so the hash is the same on every map size.
- **Buildings** come from a catalog in data files (§13): size, price, which sides passengers use, what the building does.
- **Automatic zones.** After every change, the brain "walks" from the entrance along all walkways. Everything it reaches without passing security is **landside**; everything behind security is **departures airside**. The player never paints zones.
- **Areas.** Connected walkways of the same zone get a name ("Check-in Hall", "Security", "Gates"). The statistics are grouped by area, and the first-person view draws the area the manager is in in full detail.
- **Slice:** two zones (landside and departures airside) and a handful of areas.

**Later:** Schengen and non-Schengen, arrivals, customs, staff-only areas, multiple floors, a bigger map, Terminal 2.

---

## 5. The passenger journey as a recipe

> **Removed 2026-11-14, see [removed_features.md](removed_features.md).** Passengers, stations, journeys and the passenger save block are deleted (PR 1 of the strip to core); the text stays as the design for when they come back.

- In the prototype the order "check-in → security → gate" is wired into the code. Now a journey is a **recipe in a data file**: a list of steps, each naming the kind of station that comes next.
- **Each passenger is a small record:** where they are, which step of the recipe they are on, how long they have waited, how happy they are. No 3D figure belongs to a passenger; the windows decide whether to draw one.
- **Stations** (check-in, security, gate) have queues and counters. How long a passenger takes comes from the station's data and its upgrade step.
- **Walking** follows the walkways (the grid's pathfinding, as in the prototype).
- **Slice:** one recipe, departures: entrance → check-in → security → gate → plane. Up to 1,000 passengers at once.

**Later:** arrivals and baggage claim, transfers, passenger types, shops and lounges, passport control, customs. Each is a new recipe or a new station type, not a new piece of special code. (Done: a visit before a step is a "detour" flag on the step, see `JourneyStep`; the passenger keeps their step and returns to it.)

---

## 6. Flights and demand

- **A daily timetable.** Flights are planned across the day: busy in the morning and evening, quiet at night. **Step 6b done** (2026-11-13): the brain owns a `Timetable` of `TimetableSlot` records (departure time, game day, plane class narrow / wide / cargo, route, seats, state pending / filled / dropped, airline code and flight number once filled). Slots are made once per game day: for today on the first step (or after a load without them), for tomorrow at 22:00. Flights per hour = `Demand.value` x `Clock.DEMAND_BY_HOUR[h]`, spread over the hour with the shared dice; none in curfew hours (a Hub flies all night); seasons multiply the count per route. The base demand is `Demand.value` (see next point), plus a few fixed wide-body and cargo flights an hour. Done slots are pruned only when the oldest one expired; `generated_days` keeps only recent days. `FlightSchedule` turns a slot into a `Flight` when its arrivals window opens (260 s before departure) and drops it if no gate is free a turnaround before it (wide-body slots need a wide-body stand, freighters a cargo terminal). Signed deals fill slots by their quotas (`Airlines.claim_for_slot`); without a deal the default airline (Velora Regional, 180 seats) flies narrow-body slots; wide-body and cargo slots need a signed airline. Planes are as full at night as at noon: the rush is more flights, not fuller ones. Times in flights, passengers and slots are still real seconds (game seconds were not simpler here). If the time of day is jumped (tests, dev tools) the pending slots are planned again.
- **Growing demand.** **Step 6c done** (2026-11-13): the brain owns a `Demand` (`scripts/simulation/demand.gd`, saved under `demand`, additive, no format bump; an old save starts at the base without catching up). One value, narrow-body flights per game hour at the average hour, starting at 3. Updated once per game day (catching up after a clock jump): grows by (6 - 3) / 5 a day up to `cap_for(tier, stars)` = tier maximum x `Reputation.demand_factor(stars)` / 1.4 when on-time >= 70 %; falls at a quarter of that speed when on-time < 50 % or above the cap; never below 3. The cap ignores infrastructure on purpose. Output: `flights_per_day()`, `load_factor(stars)`, `trend()`; the statistics panel shows them. Tier maxima above regional are placeholders. Arriving passengers whose plane is gone and who find no way out are sent home (`_give_up_if_stranded`).
- **Demand grows on its own** as the airport serves passengers well: more flights and fuller planes. This is the idle side of the core loop: passengers come by themselves; capacity comes from the player.
- **Slice:** one fictional airline, one plane type, no negotiation.

**Later:** airlines and deals, runway capacity, weather, night curfew, seasons, long-haul and cargo.

---

## 7. One service: electricity

- Buildings **use** power; power plants **produce** it. Only the total counts (no cables), as decided.
- If use is higher than production, things fail in visible ways (e.g. scanners slow down, displays go dark) and the statistics say why.
- **Slice:** electricity only.

**Later:** water, fuel, waste, staff areas, and coverage services that must be close enough (fire, police, medical).

---

## 8. Upgrade ladders

- Each station's upgrade ladder is a list in its data file. Each step says what it costs, what it improves, whether it takes construction time, and **what changes in 3D**.
- **Slice:** the security ladder with one real technology step:
  1. standard lanes
  2. more lanes
  3. fast-track lane
  4. **CT scanners** (liquids and laptops stay in the bag): passengers are much faster, and the lanes visibly get the new machines.
- The windows show every step: a new lane appears, the fast-track lane has its own sign, CT scanners look different from the old scanners.

**Later:** all other ladders (check-in, passport control, boarding, baggage, corridors), and the details of construction in progress (parked).

---

## 9. Milestone

The milestone, upgrade and rebuild moment is the core of the game, so the slice tests it once.

- **Slice:** reaching the first tier (Regional → National) is a milestone. A big moment on screen names it and shows what is new.
- What it unlocks in the slice (decided 2026-11-06): **new land** to expand into, and the **CT scanner step** of the security ladder. The player then has a reason to rebuild security and grow into the new land.
- The requirement uses the tier rules as built (passengers served and stars); the numbers are rebalanced for the slice.

**Later:** the other tiers and their rewards (game_design.md §13), first-landing cutscenes, special events.

---

## 10. Statistics

- The brain constantly records numbers: queue length, waiting time and how busy each counter is per station, power use and production, money in and out.
- The **bottleneck finder** picks the worst place ("Security · average wait 41 s").
- The statistics panel only shows these numbers; it never works them out itself. It lives in the top-down view.

**Later:** statistics per area and per airline, the day report.

---

## 11. Drawing (the windows)

- **Top-down view:** buildings as simple models; passengers as simple figures, all drawn in one batch. When zoomed out, fewer figures are drawn (crowds are simplified).
- **First-person view:** full detail only around the manager. Objects further away are hidden automatically (Godot's *visibility range*), and distant buildings use simpler versions (*level of detail*).
- **Texts and numbers** on screen ("Day 3 · 06:45", "Walk closer") are written by the UI. The brain only provides the raw numbers.
- **Slice:** near-final look for the slice's buildings, the upgrade steps of security, and the milestone moment.

**Later:** final models for everything, animations, more detail levels.

---

## 12. Player actions as requests

- Every player action (place, demolish, hire, upgrade) is a **request** to the brain: "upgrade this security".
- The brain checks it (enough money? allowed here?), carries it out, and announces "changed".
- Every change goes through this one door, so saving after every change happens automatically, and tests make the same requests a player would.

---

## 13. Saving

- **What is saved:** everything needed to continue exactly where the player left off: buildings, staff, money, the clock, the random seed, *and* the flights and passengers that are on their way. **Done** (save version 3, 2026-11-13): passengers (position, path, mood, queue place), flights (phase, delays, planned arrivals) and the schedule's bookkeeping are saved by building ID; a loaded game then runs exactly like the saved one (tested). Not saved: the stations' statistics windows and the money charts (they refill within minutes).
- **When:** after every change, when the app goes to the background, and a safety save every 30 seconds; each save stores a timestamp. The game writes to a temporary file first and swaps it in, so a crash can't break the save (already working).
- **Passengers (save version 6, 2026-11-13):** one deflated, base64 block of packed columns (`PassengerSave`), paths as grid cells with the grid width stored, positions at the engine's 32-bit precision and times at 64 bits, so a loaded game continues exactly. About 1,000 passengers take 60 KB instead of 1,030 KB. Version 5 -> 6 converts the old list.
- **Timetable (save version 8, 2026-11-13):** the slots and the days that are planned are saved (`timetable`). Version 7 -> 8 turns every planned flight into a filled slot and leaves the rest of today to be planned on the first step.
- **Map layers (save version 9, 2026-11-13):** walkways and taxiways are lists of non-empty 64 x 64 chunks (`{cx, cy, data}`, deflated base64; `GridSave`), so a save grows with what is built, not with the map. Version 8 -> 9 converts the dense arrays. A save from a map of another size is placed in the middle of the current one (cells shifted by (new - old) / 2: buildings, walkways, taxiways, passenger paths; world positions in metres stay the same when the difference is even). What does not fit is skipped with a warning. The behaviour hash turns chunk lists back into the old dense text, so it does not depend on the save format.
- **Real-scale airside (save version 10, 2026-11-14):** version 9 -> 10 removes the old stands, wide-body stands, runways and all taxiway paint (full refund added to `money`, `SaveGame.legacy_refund`) and `load_state` lays the new runway; the HUD shows "Old stands and runway were removed: €X refunded". Building type ids stay (`aircraft_stand`, `wide_body_stand`, `runway`): the converter is version-gated, so a version-10 save always means the new sizes. A 1,000-cell runway makes layout changes costly, so: `PlaneNetwork.rebuild` runs only when the taxiway layer (`AirportGrid.taxiway_revision`) or a stand or runway changed; the grid counts flag bits per chunk (`get_cells_with_flag` skips chunks without them, `count_flag` does not scan); `set_zone_rect` writes whole chunk rows; `begin_batch()` / `end_batch()` on the brain run the layout work once for many placements (the showcase).
- **Names, not numbers.** A building type is stored as `security`, not as "type 3". Every building gets a permanent ID, and staff point to that ID, not to a position in a list. Then reordering lists or adding types can't mix up old saves. (Done in save version 2; version 1 saves are converted on load. Version 2 → 3 only adds the in-flight data; older saves start with an empty apron.)
- **Save migrations.** Every save has a version number. When the format changes, a small converter upgrades old saves one step at a time (version 1 → 2 → 3 …). **A save is never thrown away.** (The prototype starts fresh when the version doesn't match.)
- **Nothing is lost silently.** If something in an old save can't be restored (e.g. a building that no longer exists), it is refunded, and the player is told.
- **Offline income** is worked out from the timestamp: after 36 hours or more away, 4 hours of the average profit of the last ~10 minutes.

**Later:** iCloud saves across devices.

---

## 14. Content is data

- Buildings, journey recipes, upgrade ladders, services, passenger types, airlines, prices and timings live in **data files** that can be edited in the Godot editor.
- Balancing never needs code changes. (In the prototype about half the numbers are still in the code.)
- Data files are checked by tests: every building has a price, every recipe step names a station that exists, and so on.

---

## 15. Performance budget

The test devices are an **iPhone 13 Pro** (the weaker one) and an **iPad Air M1**. The 13 Pro is much faster than the oldest iPhone Godot supports, so the budget on it is **stricter than necessary**, leaving room for older phones.

| What | Target on the iPhone 13 Pro | Target on the iPad Air M1 |
|---|---|---|
| Frame rate | a steady 60 frames per second | a steady 60 frames per second |
| Work per frame (brain + drawing) | **at most 8 ms**, half of the 16.7 ms a 60 fps frame allows | at most 12 ms |
| Brain, one heartbeat | **at most 2 ms** with 1,000 passengers | at most 2 ms |
| Passengers | 1,000 simulated, up to 400 drawn | same |
| Memory | **(open)**: set after the first measurement | same |
| Battery and heat | 30 minutes of play without the phone getting hot **(proposal)** | same |

- **Frame-rate cap: 60 fps on iPhone and iPad** (decided 2026-11-06), even on 120 Hz screens (ProMotion). It halves the drawing work, saves battery and heat, and matches this budget. An optional 120 Hz smooth mode is in the parking lot for the polish phase.
- **Why 8 ms:** an older phone that is about twice as slow still stays near 60 fps, and well above 30.
- **Baseline: the prototype's numbers** (benchmark in test builds, 1,000 passengers, seed 2026). The current passenger flow is not tuned to pass; it gets rewritten, and the rewrite must beat these numbers.

  | Device | Heartbeat (avg · 95 %) | Work per frame (95 %) | Result |
  |---|---|---|---|
  | Mac (development, no screen) | 2.3–2.4 ms · 2.7–3.0 ms | — | FAIL (heartbeat) |
  | iPhone 13 Pro, top-down (120 fps) | 2.6 ms · 3.1 ms (worst 3.9) | 11.7 ms (avg 8.9, worst 27.6) | FAIL (both) |
  | iPhone 13 Pro, first person (93 fps) | 3.1 ms · 3.8 ms (worst 4.3) | 14.4 ms (avg 13.3) | FAIL (both) |
  | iPad Air M1 | pending | pending | pending |

  iPhone 13 Pro (build b6f7d17, 2026-11-06): peak memory Godot 97 MB, video 218 MB. The graphics chip time reads 0 on the iPhone: it isn't reported this way there, so it means "not measured", not "free". The phone ran at 120 fps (ProMotion), not the 60 fps the budget assumes.

- **Measured, not felt:** a benchmark mode in test builds builds a busy airport with 1,000 passengers, runs it for a few minutes on the device and reports the numbers (frame time, heartbeat time, memory). It runs before every milestone.

---

## 16. Testing

| Kind | What it checks | Status |
|---|---|---|
| **Brain tests** | The brain alone, without graphics: queues, zones, recipes, money, saving. Fast. | new |
| **Walkthrough tests** | The real game, tapped and dragged like a player. | existing (286), kept |
| **Seeded randomness** | Every test run behaves exactly the same; a failure can be replayed with its seed. | done |
| **Performance test** | The benchmark of §15, on the device. | new (first tasks) |
| **Save tests** | Old saves load through every migration and nothing gets lost. Includes stored example saves from every version. | done for version 1 (2026-11-06) |
| **Data checks** | The data files are complete and consistent (§14). | new |

- All tests pass before every commit and every export (already the rule).
- A new feature or bug fix always comes with tests.

---

## 17. From prototype to foundation

From the prototype audit (keep / refactor / rewrite):

| Verdict | Parts |
|---|---|
| **Keep** | touch input, both cameras and the manager, the heartbeat, data files, the clock, the passenger figure batch, small systems (reputation, satisfaction, tiers, staff records), the test and export tools |
| **Keep, parked** | (nothing: airlines, goals, tiers, money, passengers, staff were removed 2026-11-14, see [removed_features.md](removed_features.md)) |
| **Removed** (2026-11-13) | weather (with de-icing), security incidents, VIP visits, the first-landing cutscene: removed to focus on fundamentals; they may return later, rebuilt on the new foundation |
| **Refactor** | the central airport object (split into the brain and small services), saving, money, building and plane drawing, the build tools, the main scene, the ground |
| **Rewrite** | zones (automatic), the passenger flow (recipes), the flight schedule (daily timetable), the HUD (separate panels), building behaviour from data instead of a fixed list of building kinds |

**Leaks to fix** (where brain and windows mix today): passenger colors and queue positions are worked out in the brain; the brain writes screen texts; the manager's position is set by a 3D node; parts of the brain reach into a global; resetting the airport needs a full scene reload.

**Order:** each step keeps all tests passing.
1. **Safety net:** seeded randomness, the device performance test, save migration tests
2. The brain as one object (no global) **(done 2026-11-13)**
3. Saving: names instead of numbers, migrations, flights and passengers included
4. Automatic zones and areas
5. Passenger journey as recipes (**done 2026-11-13**; 5a: recipes in `data/journeys/`, passengers carry recipe and step; 5b speed done (heartbeat about halved), 5c: save format 6, the passengers as one compressed block, about 1,030 KB -> 60 KB with 1,000 passengers; 5d: shop, café and lounge visits are a generic detour before a step and the step order, the exit and "the flight waits for this step" are read from the recipe, no special code left)
6. Daily timetable and growing demand
7. Electricity
8. Security upgrade ladder with CT scanners in 3D
9. Milestone (first tier)
10. UI: separate panels, statistics in the top-down view

---

## 18. Later (not in the slice)

Airlines and deals · arrivals, baggage and transfers · passenger types, shops and lounges · Schengen, passport control and customs · staff, training and promotion · bank loan and restructuring · weather, seasons, night curfew · cargo and long-haul · more services · more upgrade ladders · more tiers and milestones · multiple floors · Terminal 2 · department heads · the brain on a background thread · iCloud saves.

---

## 19. Open technical questions

1. **Minimum supported iPhone:** decide before TestFlight. Godot needs at least an A12 chip (iPhone XS / XR, 2018); the budget in §15 keeps room for it, but it must be tested on a real older device or dropped.
2. **Memory limit:** set after the first device measurement.
