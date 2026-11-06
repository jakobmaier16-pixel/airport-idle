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
- **One clock** for everything. The prototype has two (time of day, and a passenger timer that restarts at every load); they become one. One real second is 15 game seconds; a new airport opens at 06:00 on day 1.
- **Dice with a seed.** All randomness (passenger types, arrival times, names) comes from one random generator that starts from a number, the *seed*. The same seed gives exactly the same game, so a bug can be replayed and tests always behave the same. The seed is saved with the game.
  - **Done** (2026-11-06): today the dice live in the global airport object (`Airport.rng`) and are shared with every part of the brain; every test runs with its own fixed seed.
  - **When the brain becomes one object, the shared dice move with it:** the brain object owns them, every part of the brain gets them from the brain, and they are saved with it. Nothing may keep its own dice or fall back to the global ones.
- **The brain is one object.** The whole airport lives in one self-contained object instead of being spread over a global that everything reaches into. A test can create a fresh airport in a split second; later a second airport could exist for previews.

**Later:** running the brain on its own processor core (a background thread) if the heartbeat gets too heavy for big hubs.

---

## 4. Map, buildings, automatic zones and areas

- **One grid map.** The terminal and landside are near real size (1 cell = 2 m, one value that is easy to change); the airside is scaled down.
- **Buildings** come from a catalog in data files (§13): size, price, which sides passengers use, what the building does.
- **Automatic zones.** After every change, the brain "walks" from the entrance along all walkways. Everything it reaches without passing security is **landside**; everything behind security is **departures airside**. The player never paints zones.
- **Areas.** Connected walkways of the same zone get a name ("Check-in Hall", "Security", "Gates"). The statistics are grouped by area, and the first-person view draws the area the manager is in in full detail.
- **Slice:** two zones (landside and departures airside) and a handful of areas.

**Later:** Schengen and non-Schengen, arrivals, customs, staff-only areas, multiple floors, a bigger map, Terminal 2.

---

## 5. The passenger journey as a recipe

- In the prototype the order "check-in → security → gate" is wired into the code. Now a journey is a **recipe in a data file**: a list of steps, each naming the kind of station that comes next.
- **Each passenger is a small record:** where they are, which step of the recipe they are on, how long they have waited, how happy they are. No 3D figure belongs to a passenger; the windows decide whether to draw one.
- **Stations** (check-in, security, gate) have queues and counters. How long a passenger takes comes from the station's data and its upgrade step.
- **Walking** follows the walkways (the grid's pathfinding, as in the prototype).
- **Slice:** one recipe, departures: entrance → check-in → security → gate → plane. Up to 1,000 passengers at once.

**Later:** arrivals and baggage claim, transfers, passenger types, shops and lounges, passport control, customs. Each is a new recipe or a new station type, not a new piece of special code.

---

## 6. Flights and demand

- **A daily timetable.** Flights are planned across the day: busy in the morning and evening, quiet at night.
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

- **What is saved:** everything needed to continue exactly where the player left off: buildings, staff, money, the clock, the random seed, *and* the flights and passengers that are on their way. (The prototype loses flights and passengers at every load.)
- **When:** after every change, when the app goes to the background, and a safety save every 30 seconds; each save stores a timestamp. The game writes to a temporary file first and swaps it in, so a crash can't break the save (already working).
- **Names, not numbers.** A building type is stored as `security`, not as "type 3". Every building gets a permanent ID, and staff point to that ID, not to a position in a list. Then reordering lists or adding types can't mix up old saves.
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

- **Why 8 ms:** an older phone that is about twice as slow still stays near 60 fps, and well above 30.
- **Measured, not felt:** a benchmark mode in test builds builds a busy airport with 1,000 passengers, runs it for a few minutes on the device and reports the numbers (frame time, heartbeat time, memory). It runs before every milestone.

---

## 16. Testing

| Kind | What it checks | Status |
|---|---|---|
| **Brain tests** | The brain alone, without graphics: queues, zones, recipes, money, saving. Fast. | new |
| **Walkthrough tests** | The real game, tapped and dragged like a player. | existing (266), kept |
| **Seeded randomness** | Every test run behaves exactly the same; a failure can be replayed with its seed. | done |
| **Performance test** | The benchmark of §15, on the device. | new (first tasks) |
| **Save tests** | Old saves load through every migration and nothing gets lost. Includes stored example saves from every version. | new (first tasks) |
| **Data checks** | The data files are complete and consistent (§14). | new |

- All tests pass before every commit and every export (already the rule).
- A new feature or bug fix always comes with tests.

---

## 17. From prototype to foundation

From the prototype audit (keep / refactor / rewrite):

| Verdict | Parts |
|---|---|
| **Keep** | touch input, both cameras and the manager, the heartbeat, data files, the clock, the passenger figure batch, small systems (reputation, satisfaction, tiers, staff records), the test and export tools |
| **Keep, parked** | airlines and negotiation, weather, incidents, VIP visits, the goal line: not in the slice, untouched until Phase 3 |
| **Refactor** | the central airport object (split into the brain and small services), saving, money, building and plane drawing, the build tools, the main scene, the ground |
| **Rewrite** | zones (automatic), the passenger flow (recipes), the flight schedule (daily timetable), the HUD (separate panels), building behaviour from data instead of a fixed list of building kinds |

**Leaks to fix** (where brain and windows mix today): passenger colors and queue positions are worked out in the brain; the brain writes screen texts; the manager's position is set by a 3D node; parts of the brain reach into a global; resetting the airport needs a full scene reload.

**Order:** each step keeps all tests passing.
1. **Safety net:** seeded randomness, the device performance test, save migration tests
2. The brain as one object (no global)
3. Saving: names instead of numbers, migrations, flights and passengers included
4. Automatic zones and areas
5. Passenger journey as recipes
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
