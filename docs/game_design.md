# Game Design — Airport Manager (working title)

> Status: Draft v0.4 · Last updated: 2026-11-06
> This document is the source of truth for *what* we are building. Code follows the design, not the other way round.
> Markers: **(proposal)** = suggested, not yet confirmed · **(open)** = undecided, see [Open Questions](#20-open-questions) · **current prototype** = what the existing prototype does; details in [prototype_reference.md](prototype_reference.md), not final. Everything else is decided.
>
> **What changed in v0.4:** decisions on devices, scope, feel, automatic zones, both views, tiers, time, offline income, saving, services, upgrades and bankruptcy. New sections: Technical Approach, Not in Scope, Risks, Parked for Later.
> **What changed in v0.3:** the focus moved from an idle money game to **building and running a real airport**. Idle is now a supporting layer that fits the realism, not the core.

---

## 1. Pitch

A **free, realistic airport builder and management game** for iPhone and iPad.

You are an airport manager whose dream is to run a hub like Munich or Dubai. You build your own airport freely on one map: roads and train station, terminal halls, security, shops, piers, gates, aprons, runways, and all the services behind them. Passengers and flights come on their own and keep the airport running and earning. As it grows, it needs more of everything, and your job is to plan, rebuild and expand faster than the demand grows.

**The defining moment:** you just reached a milestone, and now you upgrade staff and stations and restructure your layout.

Inspirations: *TheoTown* (services that grow with the city), *Builderment*, *Idle Train Empire*, *Airplane Inc.*

---

## 2. Design Pillars

1. **The airport is the game.** Building and running a believable airport comes first. Idle mechanics support it; they never replace it.
2. **Realistic.** Real passenger flows, real zone rules (security, Schengen, customs), real services. If it wouldn't work in reality, it shouldn't work in the game.
3. **Freeform on one map.** The player decides the layout. Bottlenecks and walking distances are the main thing to think about.
4. **Grows like a city.** Like in TheoTown, every new flight and passenger creates demand for services. Growth always brings the next problem to solve.
5. **Progress by playing, not waiting.** Small upgrades are instant; only big construction takes 1–10 minutes.
6. **Special milestones.** Every milestone unlocks something new to build around, never just "+10% income".
7. **Free and fair.** No ads, no in-app purchases.
8. **How the player feels:** thoughtful, clever, powerful (free to demolish and rebuild), a collector, and a bit of an architect.

---

## 3. Idle + Building: How They Fit Together

**The rule in one line: passengers come by themselves; capacity comes from you.**

| Runs by itself (idle side) | Done by the player (building side) |
|---|---|
| Flights arrive and depart on the schedule | Design the layout |
| Passengers flow through and spend money | Build and upgrade stations |
| Demand grows as reputation and airlines grow | Expand services (power, water, fire, …) |
| Staff gain experience at their station | Hire, train and assign staff |
| Construction progresses | Negotiate airline deals |
| Department heads handle routine work **(proposal)** | Decide what to build next, and where |

### 3.1 The growth loop
1. **Demand grows on its own.** A well-run airport attracts more airlines, flights and passengers.
   *Pace (decided 2026-11-13):* demand is one value, updated once per game day from the star rating and the on-time rate. A well-run regional airport grows from the start (about 3 narrow-body flights an hour at the average hour) to the regional maximum (6) in about **5 game days** (about 8 real hours). It **falls slowly** when the airport runs badly (long queues, delays): at a quarter of the growth speed, never below the start. The cap depends on tier and stars, **not** on infrastructure: demand outgrows capacity, so bottlenecks appear; gates, stands and runway still limit the flights that actually happen. The HUD shows flights per day, load factor and the trend.
2. **Something hits its limit.** A queue at security, not enough power, no free aircraft stand, a runway the fire station can't reach in time.
3. **Statistics show where.** The player rebuilds, upgrades or adds a service.
4. **Capacity rises**, reputation rises, airlines offer more flights. Back to 1.

There is always a next bottleneck, so the player never has to wait. The idle part is that the airport keeps running and earning while the player thinks and builds.

### 3.2 Upgrades are real airport technology
Instead of abstract multipliers, each station has an upgrade ladder made of things real airports use. Every step is visible in 3D. The exact steps per ladder are tuned during development.

| Station | Upgrade ladder |
|---|---|
| Check-in | staffed counters → more counters → self check-in kiosks → automated bag drop |
| Security | standard lanes → more lanes → fast-track lane → automatic tray return → CT scanners (liquids and laptops stay in the bag) |
| Passport control | officer booths → more booths → e-gates |
| Corridors | normal corridors → moving walkways |
| Boarding | walk boarding → bus boarding → jet bridges → double jet bridges for wide-body jets |
| Baggage | manual handling → conveyor belts → automated sorting with bag screening |
| Terminal connection | bus → train → autonomous people mover |

Current prototype: simple level upgrades (more counters, more lanes, faster scanners), see prototype_reference §7.8.

### 3.3 Automation through delegation (proposal)
Idle games let you hire "managers" so things run without you. The realistic version: as the airport grows, the player hires **department heads** (Head of Security, Head of Ground Operations, Head of Retail, …). Each takes over routine work in their area, such as planning shifts. A small airport is hands-on; at a hub the player sets direction and the team runs the details. The game becomes more idle as the airport grows, which is how a real manager's job changes too.

### 3.4 Time, offline and saving
- **Game clock** with day and night. A new airport opens at **06:00 on day 1**; the clock runs through all 24 hours. Flights follow a daily schedule; night curfews and quiet hours are real.
- **Day length:** one real second is 15 game seconds, so a game day lasts **96 real minutes**.
- A short **day report** at the end of each day: income, passengers, worst bottleneck. **(proposal)**
- **Offline:** no income for breaks under 36 hours. After **36 hours or more** away, the player gets **4 hours of income** once. "Income" is the airport's average profit per minute over the last ~10 minutes of play.
- **Saving** is automatic, with no save button: after every change, when the app goes to the background, and a safety save every 30 seconds. Every save stores a timestamp, which the offline income uses.
- **Waiting:** small upgrades are instant; big construction takes 1–10 minutes and is visible on site.
- Pause and speed controls, and what a station does while it is being upgraded: parked (§19).

---

## 4. The Passenger Journey — Departures

### Station 0 — Getting to the airport
- **Car:** parking garages and lots, drop-off zone
- **Taxi** and **ride-hailing** (fictional brands): pick-up and drop-off zones
- **Bus:** bus stops and bus lanes
- **Train:** train station connected to the terminal

Each mode needs its own infrastructure, and the mix affects how crowded the entrance gets.

**Landside grows piece by piece (decided 2026-11-13).** No fixed layouts and no "airport per tier":
- The player places landside **pieces** freely: roads, curb (drop-off / pick-up), car park, bus stop, taxi rank, rail station, later ramps, garages, bus station, people mover.
- Milestones only **unlock new piece types**; they never prescribe a layout.
- Every piece has **upgrade levels**. Two kinds:
  - *Same footprint:* better or taller on the same cells (surface car park → multi-storey garage; bus stop → shelter and display).
  - *Bigger footprint:* needs free cells next to it (taxi rank 4 → 12 places → holding area; single-level curb → two levels with ramps). The player makes room by moving or demolishing roads ("demolish anything", §8.5).
- Real airports (BER, Hamburg, Munich, Frankfurt, Düsseldorf) are references for **how things work**, never copied 1:1 (no real names, logos or signature buildings).
- **Built so far (2026-11-14):** the start kit of 35 pieces (roads, curb with Kiss & Fly / taxi rank / bus bay, sidewalks, car park modules and barrier gate, fence, lights, signs, trees) is in the build menu under Landside, on the 2 m grid, landside only. They are **decorative**: no role, no staff, no running cost, prices are placeholders, all unlocked from the start. What roads, curb and car park mean for the passenger flow (who arrives how, capacity, congestion) is not built yet. Details and the start layout: `art/landside/pieces.md`, `scripts/dev/showcase_landside.gd`.

### Station 1 — Landside hall (public)
- Baggage drop and check-in
- Food (fictional brands)
- Flight information displays and information desks
- WCs

### Station 2 — Security
- Security lanes: the main crowd-flow puzzle
- Fast-track lane for premium passengers
- Aviation security only (weapons, explosives, liquids). No drug or customs checks here.
- Information stands

### Station 3 — Airside marketplace
- Duty free: real duty-free prices only for passengers leaving the EU, so passengers on non-EU flights spend more
- Shops, showrooms (e.g. a car brand, fictional), restaurants
- Lounges
- Displays showing which gate to go to

### Station 4 — Piers (to the gate)
- Long walks, moving walkways
- Advertising (income)
- Lots of seating, small shops (water, snacks), WCs
- Gate waiting areas
- **Schengen and non-Schengen gates are in separate areas.** Leaving Schengen means passport control between them.

### Station 5 — Boarding
- **Jet bridge**: direct from gate to aircraft
- **Bus boarding**: aircraft at a remote stand
- **Walk boarding**: across the apron to stairs (typical for low-cost carriers)
- **VIP car**: straight to the aircraft
- Boarding in groups (priority first)

Remote stands are cheap; jet bridges are expensive but faster and passengers like them more.

---

## 5. Arrivals, Transfers & Zone Rules

### 5.1 Arrivals
Deboarding (same options as boarding) → passport control (only from non-Schengen) → baggage claim → customs → arrivals hall (meeting point, car rental, lost-baggage desk) → ground transport.

**Customs (Zoll)** sits after baggage claim: green channel (nothing to declare), red channel (goods to declare), blue channel (EU flights). Officers do random checks, sniffer dogs and bag scans. No security check on the way out.

### 5.2 Transfers
- A **one-way** connection from arrivals into departures. Never the other way around.
- **Transfer security** for passengers arriving from airports outside the EU's "one-stop security" system.
- **Passport control** when switching between Schengen and non-Schengen.

### 5.3 Zone rules
| Zone | Who is inside | How you get in |
|---|---|---|
| Landside (public) | everyone | entrance |
| Departures airside, Schengen | screened passengers | security |
| Departures airside, non-Schengen | screened passengers | passport control |
| Arrivals airside | arriving passengers (unscreened) | from the aircraft |
| Baggage claim & customs | arriving passengers | directly, or via passport control |
| Transfer | transfer passengers | from arrivals, via transfer checks |
| Staff-only | staff and the manager | staff doors |
| Airfield (apron, taxiways, runways) | staff, vehicles, aircraft | staff and vehicle gates |

**Core rule:** unscreened arriving passengers must never mix with screened departing passengers. Real airports often solve this with separate floors.

---

## 6. Premium & VIP

- **Premium passengers** (business class, frequent flyers): priority check-in, fast-track security, lounges, priority boarding. Fast track and lounge access can also be sold to anyone.
- **Lounges:** rented space that earns money.
- **VIP terminal:** a separate building with private check-in, security and passport control in a lounge, then a car to the aircraft. Few passengers, very profitable. Milestone unlock.

---

## 7. Airport Services — The TheoTown Principle

In TheoTown a growing city needs more power, water, police and fire stations. The airport works the same way: **every passenger, flight and building creates demand for services.** If supply falls behind, things break in realistic ways. This is a key system of the game.

Two kinds of services:
- **Capacity services** produce an amount that must cover total demand (power, water, fuel, …). **Only the total counts:** there are no networks (cables, pipes) to lay.
- **Coverage services** must be close enough to what they protect (fire, police, medical).

| Service | Kind | Needed for | If it's short |
|---|---|---|---|
| Electricity | capacity | everything | outages stop belts, displays, jet bridges |
| Water | capacity | WCs, restaurants, firefighting | WCs and restaurants close |
| Fuel (fuel farm, trucks/hydrants) | capacity | every departure | departure delays |
| Waste | capacity | shops, restaurants, aircraft | dirt, satisfaction drops |
| Fire station | coverage | runways, terminal | flights not allowed. Real rule: reach any point on the runway in about 3 minutes |
| Police & security base | coverage | terminal, landside, security | incidents, unrest in crowds |
| Medical center | coverage | terminal | slow help, reputation drops |
| Staff area (break rooms, canteen, staff parking) | capacity | all staff | tired, slower staff |
| Ground handling (pushback, catering, cleaning) | capacity | every turnaround | slow turnarounds, delays |
| Baggage system | capacity | check-in, arrivals | late or lost bags |
| Air traffic control tower | capacity | flight movements | limit on flights per hour |
| De-icing | capacity | winter departures | winter delays |
| Maintenance hangars | capacity | airlines basing aircraft | some airlines won't base aircraft here |
| Cargo terminal | income building | cargo flights | — |
| Hotel, car rental | income building | passengers | — |

- Services unlock step by step; some become **required** at certain airport sizes, like TheoTown's city levels.

---

## 8. Building, Areas & Views

### 8.0 Three kinds of building (decided 2026-11-14)
Every airport should look different: the player decides what goes where and what shape the terminal has.
| Kind | How it is built |
|---|---|
| **Terminal halls and piers** | Drawn freely on the grid (rectangles, L-shapes, extensions), snapping to a **12 m column grid** (6 cells). The shell (facade, roof, columns, ceiling, doors where a sidewalk or walkway meets it) is assembled automatically from a hand-made kit. Halls can be extended later; the shell grows with them. |
| **Service buildings** (fire station, police, tower, VIP terminal, hangar, cargo, multi-storey car park, …) | Predesigned, hand-made buildings with upgrade levels, placed and rotated freely. |
| **Inside** (check-in, security, shops, gates, …) | Stations placed freely inside the halls, as today. |
The manager view is the heart of the game, so halls must look like real buildings at eye level: the column grid keeps columns, ceiling and facade consistent in any shape.

### 8.1 One map, automatic zones
- The whole airport is **one continuous grid map**.
- The player places **predesigned, rotatable buildings** and draws corridors and waiting areas to connect them.
- **Zones are not painted. They follow from the buildings.** The **security building is the border**: everything passengers reach from the entrance without passing security is landside; everything behind security is departures airside.
- Passport control, customs and staff doors set the borders of the other zones (§5.3) the same way **(proposal)**.
- Buildings only work in a matching zone (e.g. a duty-free shop only airside); a building outside its zone can be placed but is "not connected" and unused.
- **Placement (decided 2026-11-13):** placement checks only geometry and money. Airside buildings (gate, shop, stand, …) can be placed anywhere; until the walk from the entrance through security reaches them they show a "Not connected" hint and passengers don't use them. Border buildings (security) need a free row on both sides. **Transfer security is not a border** (it joins two airside walkways).

### 8.2 Areas (derived automatically)
- The game groups connected zones into named **areas**, e.g. "T1 Check-in Hall", "T1 Security", "Pier A (Schengen)".
- Areas are what the manager view loads, and what the statistics are grouped by.

### 8.3 Two views
- **Top-down view:** understand the airport and its passenger flow, place buildings, read statistics, and enjoy watching it run. All building happens here. Zoom is limited; passengers are simple figures drawn in bulk.
- **First-person view** (manager view): enjoy the airport up close. The manager walks around, inspects stations and staff, and upgrades them. Only the area the manager is in is loaded in full detail.
- Handling incidents in first person is cut until much later (§19).

### 8.4 Simulation vs. what's drawn
- Every passenger exists as **lightweight data** (position on route, needs, waiting time) for the whole airport, all the time.
- Only drawing depends on the view: simple figures in top-down, detailed people only in the area you're in.
- This keeps the game smooth on older iPhones. See §16.

### 8.5 Also planned
- **Multiple floors** (departures upstairs, arrivals downstairs): later.
- **Demolish anything**, also during operations.
- **Terminal 2** and its connection (bus → train → autonomous people mover): milestone unlock.

---

## 9. Passengers & Staff

**Passenger types** (quantity vs. quality):
| Type | Volume | Spending | Needs |
|---|---|---|---|
| Families / holiday | high | low–medium | space, food, family facilities |
| Low-cost travelers | very high | low | fast and cheap |
| Business travelers | low | high | speed, lounges, fast track |
| Transfer passengers | medium | medium | short transfer times |

Current prototype: three passenger types with their own speeds, timing and spending, and a mood (satisfaction) per passenger (prototype_reference §8.7, §8.10).

**Staff:** individual employees with names, skills and experience. Experience grows at each station, so a long-time check-in agent is faster than a new hire. How staff upgrades work: **(open)**. Current prototype: training and promotion to supervisor (prototype_reference §9).

---

## 10. Airlines, Flights & Deals

- The player attracts **fictional airlines** and their flights; the player does not own aircraft.
- **Negotiations:** dialogue choices plus adjustable terms (fees, slots, gates), always linked to the airport's real performance (on-time rate, turnaround speed, satisfaction, capacity).
- **Routes matter:** holiday routes (families, seasonal peaks), business routes (high spenders at peak hours), long-haul (bigger stands, gates, runways; more income), non-Schengen (passport control, duty free), hub routes (transfer flows).
- Current prototype: offer cards with fee, flights and tone, airline happiness, contract renewals, long-haul and cargo airlines (prototype_reference §10).

---

## 11. Economy

- **Income:** airline fees (per passenger, landing, slot), shops and restaurants, duty free, parking, advertising, rented space (lounges, offices), premium services.
- **Costs:** salaries, maintenance, services (power, water, fuel, waste), construction and demolition.
- **Bankruptcy is possible, but there is no game over.** Below €0 the bank covers the gap with a **loan** that costs interest. If the debt grows past the credit limit, the bank **restructures** the airport: it sells buildings until the debt is covered, and the airport's reputation drops. Current prototype numbers: prototype_reference §11.6.
- **Reputation** as a second value that unlocks airlines and tiers: **(open)**. Current prototype: a 1–5 star rating from passenger satisfaction and the on-time rate (prototype_reference §11.7).

---

## 12. Realism Systems

All wanted, added in phases: flight schedules, delays with knock-on effects, weather, night curfews, security incidents, seasons, winter de-icing.

**Removed 2026-11-13:** weather, incidents, VIP visits and the first-landing cutscene removed from the prototype on 2026-11-13 to focus on fundamentals; realism systems may return later, rebuilt on the new foundation. Seasons stay (they drive demand).

Current prototype: clock and demand by hour, seasons (demand only), night curfew (prototype_reference §12).

---

## 13. Progression & Milestones

### 13.1 Airport tiers
Four tiers, as built in the prototype. The thresholds are the current prototype's and will be balanced later.

| Tier | Reached with (current prototype) | Unlocks (as built) | Also unlocks (proposal) |
|---|---|---|---|
| **Regional** | start | starting land, every basic building | one small terminal, Schengen flights, walk and bus boarding, power, water, fire station, police, waste, staff area |
| **National** | 1,000 passengers, 3 ★ | the whole map, transfer security, cargo, an offer from a major airline | non-Schengen flights (passport control, duty free), jet bridges, ATC upgrade |
| **International** | 6,000 passengers, 3½ ★ | long-haul flights: wide-body stands and planes | Terminal 2 and its connection, VIP terminal |
| **Hub** | 25,000 passengers, 4 ★, 600 transfers | hub status (twice the connections), night flights, an offer from a premium airline | autonomous people mover, department heads |

Details: prototype_reference §14.1.

### 13.2 Milestone rewards
Special, never a flat bonus: a new mechanic, new land, a new major airline with a cinematic first landing, special events (first wide-body jet, a state visit). The prototype's first-landing cutscene and VIP visits were removed on 2026-11-13 (§12).

One airport for the whole game. No playtime limit.

---

## 14. Platform, Look & Tutorial

- **Devices:** iPhone and iPad are **both main devices** and must both play well. **Landscape only.**
- **Platform:** iOS / iPadOS via the App Store. English only. Offline single-player.
- **Tech:** Godot, VS Code (Claude Code), Xcode, Blender. See §16.
- **Art:** realistic look within the iPhone budget (decided 2026-11-13): few shared PBR materials / trim sheets, baked light, LOD, MultiMesh for repeated furniture, ASTC textures; a look-probe on the device comes first. **Look (decided 2026-11-13):** cool Nordic (anthracite, glass, dark stone, light oak as accent), quiet realism (calm surfaces, little texture noise), hybrid light (real moving sun, baked AO and interior light, emissive night lights). Rules: `docs/art_direction.md`.
- **Tutorial:** a fictional regional airport inspired by Memmingen that clearly shows what kind of game this is. Details **(open)** until the core game exists.
- **Brands:** everything fictional (airlines, shops, food chains, ride-hailing).

---

## 15. First Playable Version (MVP)

Goal: prove the core loop: demand grows by itself, the player builds capacity.

1. One continuous grid map, one floor
2. Two zones, landside and departures airside, set automatically by the buildings; security is the border and the only connection
3. Place and rotate: entrance with drop-off, check-in, security, gate, aircraft stand
4. Corridors and waiting areas
5. Passengers as data, drawn as simple figures: entrance → check-in → security → gate → plane
6. Flights on a simple daily schedule; demand grows over time
7. Money per passenger; running costs
8. **One service: electricity** with capacity, to test the TheoTown principle **(proposal)**
9. **One upgrade ladder:** security, with one real technology step visible in 3D: more lanes → fast track → CT scanners
10. Basic statistics: queue length per station, power use
11. **One milestone:** reaching the first tier unlocks something new (new land and the CT scanner step), to test the milestone, upgrade and rebuild moment

**Next, in order (proposal):** manager view for one area → more services (water, fire) → shops → staff → passenger types → airlines and deals → arrivals → Schengen / non-Schengen → Terminal 2.

How we get there (phases, gates, vertical slice): [master_plan.md](master_plan.md).

---

## 16. Technical Approach

The details live in `tech_architecture.md` (to write) and `CLAUDE.md`. The principles:
- **Godot 4**, GDScript, Mobile renderer.
- **Simulation and drawing are strictly separate.** The simulation is pure data for the whole airport and always runs. It never depends on what the camera sees.
- **Fixed simulation step** (current prototype: 10 steps per second); drawing smooths movement between steps.
- **Only what the camera sees is drawn in detail:** culling, visibility ranges and level of detail; crowds as instanced figures, simplified when zoomed out.
- **Content is data, not code:** buildings, airlines, passenger types and upgrade steps live in data files, so balancing needs no code changes.
- **Real scale (decided 2026-11-13, replaces "compressed scale"):** everything is real size, 1 cell = 2 m (one easy-to-change value), also the airside: planes, stands, taxiways and the runway at full length. The map is large and is unlocked piece by piece (§13). The top-down view always shows the whole airport with very cheap far models; the first-person view loads only the area the manager is in, in full detail (§8.3).
  *Details (decided 2026-11-13):*
  - **Map:** about 4.4 × 3.2 km (2,200 × 1,600 cells). **Step 6.5 / PR 6A done** (2026-11-13): the map has this size; the old building types kept their size until 6B. The starting land is one placeholder rectangle of 1,200 × 400 cells (2.4 × 0.8 km) on the 200-cell grid, one named constant (`Progression.STARTING_LAND`); **(open)** the real starting airport is Jakob's decision (§19). National and above own the whole map until PR 9. The build view opens at about 250 m and zooms out to the whole map (shadows off beyond 400 m).
  - **Runway:** starts at 2,000 m; extended to about 3,200 m with the International tier.
  - **Land:** bought in pieces of about 400 × 400 m, only next to owned land; some pieces are tied to tiers.
  - **Types (PR 6B done, 2026-11-14):** runway 1,000 × 23 cells (2,000 × 46 m); narrow-body stand 20 × 23 (40 × 46 m, €18,000 · €30/min); wide-body stand 35 × 40 (70 × 80 m, €60,000 · €70/min); the runway stays at €400,000 · €20/min. Prices are placeholders (about 3× the old stand for the bigger footprint). A new game starts with the runway at 49 to 71 rows below the map centre, inside the starting land.
  - **One gate per stand:** a plane parks at the stand its gate's back row touches, so a stand serves exactly one gate. Placement refuses a second gate (or cargo terminal) on a stand that already has one, a stand that two gates would reach, and a gate that would face two stands.
  - **Old saves (save format 10):** stands, runways and taxiway paint in the old small size are removed on load with a full refund (saved price; taxiway paint €30 per cell) added to the money; the new runway is laid; a notice tells the player what came back. Gates stay and wait for new stands; their flights are cancelled.
  - **Taxi time:** comes from the real route; the timetable plans the taxi time per stand, so close stands are worth more.
  - **Walking:** real distances and normal walking speed for now; moving walkways come later as an upgrade.
  - **Planes:** two classes by wingspan (narrow-body about 37 m, wide-body about 65 m; freighters are narrow-body size). A stand takes its own class or a smaller one (`BuildingType.stand_class`, `fits()`); the wingspans are data (`TimetableSlot.WINGSPAN_M`) and a test checks every stand is at least as wide as the widest plane it takes.
- **Versioned saves:** old saves are upgraded, never silently lost.
- **Target:** smooth on older iPhones and on iPads, measured against a performance budget (master_plan.md, Phase 1).

---

## 17. Not in Scope (for now)

- Ads and in-app purchases
- Multiplayer and online features
- Multiple airports
- Languages other than English
- Android: not a focus now; revisit later if there is an easy way

---

## 18. Risks

- **Scope is large.** Building + realistic simulation + 3D on mobile is ambitious. Vertical slice first, small steps, ideas go to the parking lot.
- **Performance** with hundreds of passengers on older iPhones. Passengers as data, a performance budget, tests on real devices.
- **Touch controls** for freeform building (later with floors) must be easy on an iPhone screen. Test early.
- **Legal:** all airlines, airports and brands are fictional; no real names or logos.
- **Rework from the prototype.** The prototype is audited (keep / refactor / rewrite) before new features are added.

---

## 19. Parked for Later

Decided later, not now:
- **Starting airport:** what the player's own airport starts with (current prototype: an empty field with one runway, €50,000 and one airline deal, prototype_reference §6.1)
  - *Starting land (provisional, 2026-11-13):* about 2.4 × 0.8 km (6 × 2 land pieces of 400 m). Room for the 2,000 m runway with its safety strip, a parallel taxiway, one row of stands, a small terminal and the landside. Revisit when the starting airport is decided.
- **Day/night lighting**
- **Pause and speed controls**
- **Upgrade-in-progress details:** what a station does and shows while it is being upgraded
- **Incident handling** in the first-person view

The full parking lot is in [master_plan.md](master_plan.md) §8.

---

## 20. Open Questions

### Idle
1. Department heads (§3.3): yes or no?

### Progression
2. How does reputation work and what does it unlock? (current prototype: star rating, §11)

### Systems
3. Staff upgrades: training, promotion, pay, specialization? (current prototype: §9)
4. Demolishing: cost, refund, or both? (current prototype: 50 % refund of the build price, prototype_reference §7.6)
5. Negotiations: how do dialogue choices and deal terms interact? (current prototype: §10)

### Other
6. Tutorial: role, length, what carries over.
7. Target player (casual vs. strategy fan).
8. Working title.

---

## Glossary (German → English)

| German | English |
|---|---|
| Gänge | corridors, walkways |
| Warteräume | waiting areas, gate lounges |
| Rollsteig / Rollband | moving walkway |
| Fluggastbrücke | jet bridge |
| Vorfeld | apron |
| Rollweg | taxiway |
| Start- und Landebahn | runway |
| Passkontrolle | passport control |
| Zoll | customs |
| Gepäckausgabe | baggage claim |
