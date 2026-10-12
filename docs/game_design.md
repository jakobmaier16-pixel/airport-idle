# Game Design — Airport Manager (working title)

> Status: Draft v0.16 · Last updated: 2026-10-12
> This document is the source of truth for *what* we are building. Code follows the design, not the other way round.
> Decisions marked **(open)** are not final — see [Open Questions](#19-open-questions).

---

## 1. Pitch

A **free, strategic airport management game with idle elements** for iPhone and iPad.

You play an airport manager whose dream is to run a huge hub like Munich or Dubai. After a short introduction at an existing regional airport, you build **your own airport completely freeform** — terminal, security, gates, aprons, runways, parking — and grow it from a small regional field into a world-class hub. Passengers flow through your airport on their own and generate money; your job is to think, plan, negotiate with airlines, manage staff, and keep rebuilding a better airport.

**The defining moment:** you just reached a milestone, and now you upgrade employees and stations and restructure your layout. The whole game is built to deliver that moment again and again.

Inspirations: *Builderment*, *Idle Train Empire*, *Airplane Inc.*, *TheoTown*.

---

## 2. Design Pillars

1. **Realistic.** The airport works like a real one: secure and non-secure zones, real passenger flows, staff, schedules, delays, weather. If it wouldn't work in reality, it shouldn't work in the game.
2. **Freeform and strategic.** Nothing about the layout is fixed. Placement, routing and bottlenecks are the main thing the player thinks about.
3. **Progress by playing, not waiting.** Almost no timers. Small upgrades are instant; only big upgrades take 1–10 minutes. Offline income is minimal.
4. **The milestone moment.** Every milestone should feel special and give the player something new to rebuild around — never just a flat "+10% income".
5. **Fair and free.** No ads, no in-app purchases, no paywalls. No monetization is planned for now.
6. **The player feels:** thoughtful, clever, powerful (free to demolish and rebuild), a collector, and a bit of an architect.

---

## 3. Platform & Tech

| Item | Decision |
|---|---|
| Platform | iOS / iPadOS (Apple App Store) |
| Devices | **iPad is the primary device** and should give the best experience. iPhone must stay fully playable. |
| Orientation | **Landscape only**, in both views |
| Engine | Godot |
| Tools | VS Code (code written with Claude Code), Xcode (iOS export), Blender (3D models) |
| Language | English only (for now) |
| Online | Offline single-player for now. Player comparisons / leaderboards maybe later. |
| Monetization | None for now |
| Play time | **No cap.** The game should support open-ended play. |

---

## 4. Core Loop

```
 Passengers arrive ─► flow through your stations ─► generate money + data
        ▲                                                   │
        │                                                   ▼
 Airlines add flights ◄── better airport attracts ◄── Spend: build, upgrade,
 (negotiated deals)        better airlines/routes      hire, restructure layout
                                                            │
                                                            ▼
                                             Check statistics, find bottlenecks
                                                            │
                                                            ▼
                                     Reach milestone ─► special unlock ─► rethink layout
```

**Moment to moment** the player:
- builds, plans and rearranges the airport — **build view** (top-down), the only place where building happens
- everything else happens in the **manager view** (fixed tilted follow camera):
  - walks around the airport as the manager (what walking does in gameplay is still **(open)**)
  - watches passengers move and spots problems
  - opens statistics to find bottlenecks (security? boarding? marketing?)
  - hires, assigns and develops staff, manages stations
  - negotiates deals with airlines (fees, slots, gates)

**What "idle" means here:** passengers flow and earn money automatically while the player manages. Progress happens while playing, not while away.

---

## 5. Time & Offline Rules

- **While playing:** full simulation, all income. The simulation **keeps running in the build view** — there is no pause (for now).
- **Offline:** no income for breaks under 36 hours. After **36 hours or more** away, the player receives **4 hours' worth of income** once. (Similar in spirit to Clash of Clans — a small welcome back, not a reason to stay away.)
- **Saving:** automatic — after every change and when the app goes to the background. No manual save button.
- **Upgrades:** small upgrades are instant. Big upgrades take **1–10 minutes** with **visible construction on site**.

---

## 6. Tutorial / Intro

- Set at a **fictional regional airport inspired by Memmingen**.
- Goal: **clearly show what kind of game this is** and what the player can achieve at their own airport.
- After the intro, the player builds their own airport.
- Role in the tutorial, length, starting site and anything that carries over: **(open)** — we will design this once the core game exists.

---

## 7. Building System

### 7.1 Grid and buildings
- The map is built on a **grid**.
- **Compressed scale, not 1:1.** Realism means things *work* like a real airport, not that they are life-size.
  - **Terminal and landside** stay close to realistic proportions, because that is where the manager walks around in the manager view. One grid cell = **2 m** to start; the cell size must stay easy to change.
  - **Airside** (runways, taxiways, aprons, stands) is **scaled down** so the whole airport fits on a playable map.
- **Map size:** 64 × 64 cells (128 × 128 m) for now. It will be enlarged when airside (stands, runways) comes in.
- The player places **predesigned buildings / modules**: check-in, information desk, shops, restaurants, security, passport control, gates, baggage systems, etc.
- Buildings can be **rotated** freely (in grid steps).
- Buildings are connected by **corridors** and **waiting areas** (holding rooms, gate lounges) that the player draws on the grid.

### 7.1a Placing a building (build view)
1. Pick a building from the **build menu**.
2. A **preview** appears on the map. **Drag it** with a finger to move it; it snaps cell by cell, so small corrections are easy. Or **tap** the map to jump it there. Dragging anywhere else still moves the camera.
3. **Rotate** in 90° steps with a button.
4. **Place** or **Cancel** with buttons. The preview is **green** when the spot is free and **red** when it isn't; Place only works on green.

- Buildings cannot overlap each other or leave the map.
- Each building has a **front side** (e.g. where passengers queue at check-in), shown on the model.
- **Building costs money** (§11.5). If there isn't enough, the building can't be placed and the hint shows the price.
- If a spot is not allowed, a short hint says why (space taken, wrong zone, …).
- MVP building sizes (provisional, easy to change per building):

| Building | Cells | Meters | Zone rule |
|---|---|---|---|
| Entrance | 4 × 2 | 8 × 4 | landside |
| Check-in | 5 × 3 | 10 × 6 | landside |
| Security | 5 × 3 | 10 × 6 | border: front faces landside, back faces airside |
| Gate | 5 × 5 | 10 × 10 | airside (waiting area included) |
| Aircraft stand | 12 × 12 | 24 × 24 | airside (scaled down, see §7.1); flat, can be walked on |
| Shop (duty free / retail) | 3 × 3 | 6 × 6 | airside |
| Café | 4 × 3 | 8 × 6 | landside or airside |
| Baggage claim | 6 × 4 | 12 × 8 | border: front faces landside, back faces airside (like security, used the other way) |

### 7.1b Walkways (corridors and halls)
- Corridors and halls are drawn as **walkway floor**: pick *Walkway* and drag a rectangle (or tap a cell); *Remove* erases walkway.
- **Any width.** Width will matter once passengers walk: narrow walkways get crowded and slow passengers down. A realistic corridor is at least 2 cells (4 m) wide.
- **Buildings can stand on walkway** (e.g. check-in desks inside a hall). Cells under a building are not walkable.
- Walkways belong to the zone they are painted in. Passengers only walk on walkways and can only get from landside to airside **through security** (§7.2).
- **Access sides:** passengers enter and leave buildings only on their access sides.

| Building | Access side(s) |
|---|---|
| Entrance | back (into the terminal); the front faces outside |
| Check-in | front (queue area) |
| Security | front (landside) and back (airside) |
| Gate | front (walkway) and back (aircraft stand) |
| Shop, café | front (walkway) |
| Baggage claim | back (airside, from the gates) and front (landside, to the exit) |
| Aircraft stand | reached through a gate |

- A building is **connected** when each access side touches at least one free walkway cell (the gate's back: an aircraft stand). Unconnected buildings can still be placed (build first, connect after) and show a hint such as "Needs a walkway in front".
- **Waiting areas:** for the MVP the waiting area is part of the gate. Separate holding rooms come later.

### 7.2 Zones (realism rule)
- The airport has a **landside (public)** zone and an **airside (secure)** zone.
- **Security is the only way** for passengers to get from landside to airside. Once through security, you are in the secure zone.
- **The player paints the zones** in the build view: pick *Airside* or *Landside* and drag a rectangle (or tap a single cell). Every cell starts as landside.
- Each building has a **zone rule** (see the table in §7.1a). Security sits **on the border**: the row in front of it must be landside, the row behind it airside.
- Cells that a building's zone rule depends on cannot be painted to the other zone while the building stands.
- Zones are shown as a tint on the ground (airside darker / grey-blue).
- Further realistic zone rules (e.g. passport control for non-Schengen, arrivals separated from departures) follow the same principle.

### 7.3 Staff-only paths
- Passengers use the public routes.
- Separate **staff-only corridors** exist that only staff (and the manager) can use.

### 7.4 Floors
- **Multiple floors** are planned (e.g. departures upstairs, arrivals downstairs).
- Not part of the first playable version (see §16).

### 7.5 Whole airport
The player builds everything:
- **Landside:** access roads, entrance, parking lots, drop-off, public transport stops
- **Terminal:** all passenger and staff areas
- **Airside:** runways, taxiways, aprons, aircraft stands, gates with jet bridges or bus gates

Only the direction from which passengers arrive at the map edge may be fixed.

### 7.6 Demolish and rebuild
- Everything can be demolished, **including during operations**.
- Demolishing has a cost and/or partial refund (exact rule **(open)**).

### 7.7 Layout quality matters
This is the main strategic layer. Bad layouts cause:
- long walking distances
- queues and bottlenecks
- unhappy passengers who spend less
- missed flights and delays, which hurt airline relationships


### 7.8 Station upgrades (MVP, item 7)
- Upgrades are **managing**, so they happen in the **manager view**: tap a station to open its panel (level, counters/lanes, time per passenger, queue, running cost) and press *Upgrade*.
- **Small upgrades are instant; big ones take time** with visible construction (§5). The station keeps working meanwhile; a label shows the time left.
- First upgrade paths (placeholders, tunable per building type):

| Station | Level 2 (instant) | Level 3 (1 min construction) |
|---|---|---|
| Check-in | +1 counter (3 → 4) · €2,500 · +€10/min | +1 counter (4 → 5) · €4,000 · +€10/min |
| Security | +1 lane (2 → 3) · €4,000 · +€15/min | Faster scanners (−25 % time per passenger) · €6,000 · +€10/min |

- Gates and entrances have no upgrades yet. Whether the manager must walk to a station to manage it is still **(open)** (§19 Q10); for now any visible station can be tapped.

---

## 8. Passengers

### 8.1 Flows
All of them, phased in over time:
- **Departures:** entrance → check-in / bag drop → security → (passport control) → shops / lounges → gate → plane
- **Arrivals:** plane → (passport control) → baggage claim → exit / transport
- **Transfers:** plane → transfer security → gate → plane
- **Baggage:** check-in → baggage system → plane, and plane → baggage claim

### 8.2 Passenger types
Different types with different needs, behavior and spending. This creates a real strategic choice: **quantity vs. quality**.

| Type | Volume | Spending | Needs (examples) |
|---|---|---|---|
| Families / holiday | High | Low–medium | Space, food, family facilities, patience-tolerant |
| Low-cost travelers | Very high | Low | Fast and cheap, little time in terminal |
| Business travelers | Low | High | Speed, lounges, fast-track security, premium shops |
| Transfer passengers | Medium | Medium | Short transfer times, good signage |

### 8.3 Visual representation
- Passengers are visible and walk through the airport.
- To keep performance good on older iPhones, passengers are **simple, low-detail 3D figures** (with instancing / level of detail as needed). Crowds may be simplified when zoomed out.

### 8.4 First passenger flow (MVP, item 4)
Placeholder rules until flights exist (§16 item 5). All numbers are tunable.
- **Arrival:** passengers arrive for a specific flight (§8.5), at a connected entrance — only once a **complete route** exists: Entrance → Check-in → Security → Gate with stand.
- **Walking:** only on walkway cells, ~1.3 m/s (realistic walking speed), each passenger with a small sideways offset so crowds don't walk in one line.
- **Choices:** check-in and security by the best mix of short queue and short distance; the gate of their flight.
- **Queues:** visible lines in front of the station. Check-in: 3 counters, ~8 s per passenger. Security: 2 lanes, ~6 s. (Compressed time; a real check-in takes 1–2 min.)
- **Security is the only link** between landside and airside walkways; passengers cannot reach airside any other way.
- **Gate:** passengers wait inside the gate until their flight boards (§8.5).
- **Simulation vs. visuals:** passengers are simulated as data at 10 steps per second for the whole airport; figures are drawn only near the camera, in one batch (MultiMesh), with smooth movement between steps.
- A **status line** shows passengers in the airport, departed and missed, or what is missing for a complete route.

### 8.5 First flights (MVP, item 5)
Placeholder schedule until airlines and deals exist (§10). All numbers are tunable (compressed game time).
- **Schedule:** every gate with a stand gets one departure every **3 minutes**. The first flight at a new gate departs 4½ minutes after the gate becomes usable.
- **Timeline of a flight** (before departure): passengers arrive at the entrance from 4:20 to 2:20 (early enough for a shop or café, §8.6) · the plane taxis onto the stand at 2:10 (15 s) · **boarding** opens at 1:30, about 1 passenger per second walks from the gate onto the plane · at 0:00 the doors close and the plane pushes back.
- **Missed flights:** passengers not on board when the doors close miss the flight and leave the airport. They are counted — slow layouts cause missed flights (§7.7).
- **Aircraft:** a narrow-body plane with 180 seats, scaled down like the airside (§7.1); parks nose-in at the stand, facing the gate. For now 12–20 booked passengers per flight, so a small airport can handle it; real demand comes with airlines (§10).
- **Fictional** airline code "AX" and flight numbers (§18).
- If a gate stops being usable (e.g. its walkway is removed), its flight is **cancelled** and its passengers leave.
- A **departures board** shows the next flights: number, gate, status (scheduled, plane arriving, at stand, boarding) and time to departure.


### 8.6 Shops and cafés (first version)
Placeholder numbers, tunable per building type.
- After security, a passenger with **enough time** (at least 45 s to spare before boarding opens) visits a shop or café with **70 % probability** — the nearest one with free space.
- **Capacity:** a shop holds 8 customers, a café 12. Full places are skipped.
- **Time inside:** shop 20–40 s, café 30–60 s. When boarding is about to open, customers leave early (**final call**) — shopping must not make passengers miss flights.
- **Spending:** shop €20–40, café €8–16 per customer. The airport earns a **30 % concession share** (§11.1: shops, restaurants, duty free).
- Customers inside are not drawn (like passengers waiting inside a gate).
- Station panel and statistics show customers inside and the airport's income from each place over the last 5 minutes.
- Costs: Shop €3,500 build · €5/min running. Café €3,000 · €6/min. Low running costs because, like at real airports, the tenant runs the shop (staff, goods); the airport pays utilities and maintenance and earns the concession share.


### 8.7 Passenger types (first version)
Placeholder numbers, tunable in `data/passengers/`. Transfer passengers come with arriving flights.

| | Families / holiday | Low-cost travellers | Business travellers |
|---|---|---|---|
| Figure colors | warm orange / yellow | blue / teal | dark grey / navy |
| Arrive before departure | 4:20–3:00 (early) | 4:00–2:30 | 3:20–2:20 (late) |
| Walking speed | 1.1 m/s | 1.3 m/s | 1.4 m/s |
| Check-in | 40 % slower (bags, children) | 60 % skip it (online, hand luggage) | 30 % faster (priority) |
| Security | 30 % slower | normal | 20 % faster (frequent flyers) |
| Visit a shop / café | 80 % | 40 % | 60 % |
| Spending | ×0.8 | ×0.6 | ×2 (premium) |

- **Every flight has a route type** that sets its passenger mix (§10 "routes matter"): **Holiday** 70 % families / 20 % low-cost / 10 % business · **Low-cost** 15 / 80 / 5 · **Business** 10 / 30 / 60. Routes are random for now; later airlines and deals decide them.
- The departures board shows the route; statistics show how many passengers of each type are in the airport.
- Patience and satisfaction per type (§8.2 "needs") come later.


### 8.8 Arriving passengers (first version)
- **Every flight is a turnaround:** the plane arrives with 12–20 passengers (types by the route's mix). Once parked, they **deplane through the gate** (~1 per second) before boarding opens.
- Arrivals walk airside to a **baggage claim**, wait for their bag, then leave through its landside front (customs) and exit the airport at an **entrance**.
- **Bags** come off the belt 30–90 s after the plane parks. Passengers with hand luggage only walk straight through. Checked bag: families 100 %, low-cost 30 %, business 40 %.
- **Baggage claim** €6,000 · €30/min. It sits on the border like security, used the other way round (airside → landside).
- **Income:** €5 terminal fee per arriving passenger when they leave the airport.
- **Required:** without a connected baggage claim, arriving passengers have no way out, so no flights operate; the status line says what is missing.
- Status line: departed, arrived and missed passengers. Arrival and departure flows still share the same walkways; separating them (§7.2) comes later.

---

## 9. Staff

- **Individual employees** with names, skills and experience.
- **Experience grows per station:** someone who has worked check-in for a long time is faster there than a new hire.
- Staff is assigned to stations; staff count and quality affect throughput.
- Upgrading staff (training, promotion, pay, specialization): concrete mechanics **(open)**.

---

## 10. Airlines, Flights & Deals

- The player **attracts airlines** and their flights. The player does **not** own planes.
- All airlines are **fictional** (inspired by real types: flag carrier, low-cost, holiday charter, long-haul, cargo later).
- **Negotiations** use **dialogue choices** plus **adjustable deal terms**: fees, slots, gates.
- Deals are **directly linked to the airport's real performance**: on-time rate, turnaround speed, passenger satisfaction, capacity. A well-run airport gets better deals.
- **Routes matter**, as in reality:
  - Holiday routes bring families and seasonal peaks
  - Business routes bring high spenders at peak hours
  - Long-haul routes need bigger stands, gates and runways, and bring higher income
  - Hub/transfer routes need good transfer flows

---

## 11. Economy

### 11.1 Income
- Airline fees (per passenger, per landing, per slot)
- Shops, restaurants, duty free
- Parking
- Rented space (lounges, airline offices, ads in the terminal)
- Fast-track / premium services

### 11.2 Costs
- Salaries
- Maintenance
- Utilities (electricity, cleaning)
- Construction and demolition

### 11.3 Failure
- **Bankruptcy is possible.** What exactly happens (game over, loan, restructuring) is **(open)**.

### 11.4 Second currency
- A second value like **reputation** is likely needed (e.g. to unlock better airlines or airport tiers). Design **(open)**.


### 11.5 First economy (MVP, item 6)
Currency: **euro (€)**. All numbers are placeholders, tunable per building (compressed game time).
- **Starting money:** €50,000.
- **Income** when a flight's doors close: **€15 per departing passenger** (passenger fee paid by the airline) and **€300 per flight** (landing / turnaround fee).
- **Construction:** Entrance €2,000 · Check-in €3,000 · Security €5,000 · Gate €4,000 · Aircraft stand €6,000 · Walkway €20 per cell. Painting zones is free. Removing walkway is free and refunds nothing (demolishing rules are still open, §19).
- **Running costs per minute** (staff, maintenance, utilities): Entrance €10 · Check-in €30 · Security €40 · Gate €25 · Stand €15 · Walkway €0.05 per cell. Charged continuously while the game runs.
- **Display:** balance and profit per minute (last 60 s) at the top of the info panel; red when negative.
- **Negative balance** is allowed for now: what bankruptcy means is still open (§11.3, §19).
- **Not in the MVP yet:** shop income, parking, salaries per employee, upgrades (§16 item 7).

---

## 12. Realism Systems

All of these are wanted. They will be added in phases, not all at once:
- Flight schedules
- Delays (with knock-on effects)
- Weather
- Night curfews
- Security incidents
- Seasons (holiday peaks, quiet months)

---

## 13. Statistics & Management UI

The manager can **always** open diagrams and statistics, for example:
- Queue lengths and waiting times per station
- Bottleneck finder: where are passengers getting stuck?
- Income and costs by source
- Passenger satisfaction by type
- On-time performance per airline
- Staff performance per station

This is a core tool, not an extra: the player's thinking happens here.

### 13.1 First statistics panel (MVP, item 8)
- A **Stats** button in the manager view opens the panel (statistics are managing, §15).
- One row per station, measured over the **last 5 minutes**: queue now, longest queue, average wait in the queue, and how busy the counters / lanes were (%). Gates show how many passengers are waiting.
- **Bottleneck finder:** the station with the longest average wait is highlighted ("Bottleneck: Security · avg wait 41 s"), so the player sees where an upgrade pays off.
- Updated twice per second; the simulation records the numbers as data at every station.

---

## 14. Progression & Milestones

- **Airport tiers** might be something like regional → national → international → hub **(open)**.
- Reaching a milestone should feel **special**, not a standard multiplier. Reward types we want (all of them):
  - **New mechanic** unlocks (night flights, cargo, long-haul, a second terminal)
  - **New land** to expand into
  - **A new major airline** signs, with a cinematic first landing
  - **Special events** (first wide-body jet, VIP or state visit)
- One airport for the whole game. More airports: maybe later, not now.
- **No playtime limit.**

---

## 15. Camera, Look & Feel

### Camera
A button switches between the two views.

- **Manager view:** fixed tilted camera, like *League of Legends*. It follows the manager from a fixed angle and **never rotates**. **Everything except building happens here:** walking, watching passengers, managing staff and stations, statistics. The camera must always show enough to play comfortably.
  - **Zoom:** a small zoom range — pinch with two fingers (scroll wheel on the Mac). Only the distance changes, within tight limits so it always stays playable. The angle stays fixed.
- **Build view:** top-down / bird's-eye. **All** building and layout planning happens here, and only here.
  - Drag with one finger to move, pinch to zoom; two fingers also move the view. While a tool uses one-finger drags (e.g. painting zones), only two fingers move the view. Zoom is limited so the game stays playable; the camera cannot leave the map.
  - When zoomed out, crowds are shown simplified (fewer figures, simple shapes). See §18.
- What walking as the manager does in gameplay: **(open)**.

### Controls (manager view, landscape)
- **Left half of the screen:** one finger shows a floating joystick under the thumb to walk.
- **Right half of the screen:** stays free for tapping things (stations, staff, passengers — later).
- **Two-finger pinch anywhere** zooms and **never** triggers the joystick.

### Art style
- Start with **simple, realistic low-poly** models (achievable without 3D experience).
- Upgrade to more detailed/realistic models later if we want.

---

## 16. First Playable Version (MVP)

The smallest version that proves the core idea. **Status (2026-10-13): all 8 items are built and playable** (placeholder numbers and visuals).

1. One floor, one grid, landside + airside zone
2. Place and rotate: entrance, check-in, security, gate, aircraft stand
3. Draw corridors / waiting areas to connect them
4. Passengers walk **entrance → check-in → security → gate → plane**
5. Planes arrive on a simple schedule and depart with passengers
6. Money comes in per passenger; simple running costs
7. Upgrade at least one station
8. A basic statistics panel (queue length per station)

After that, features grow with play time and milestones: shops, staff, passenger types, airlines and deals, arrivals, baggage, floors, realism systems.

---

## 17. Not in Scope (for now)

- Ads and in-app purchases
- Multiplayer, leaderboards, online features
- Multiple airports
- Languages other than English
- Android

---

## 18. Risks & Notes

- **Scope is large.** Freeform building + realistic simulation + 3D on mobile is ambitious. We build in small, playable steps (MVP first).
- **Performance:** hundreds of walking passengers on older iPhones. Keep models simple; plan for instancing and crowd simplification. See the performance architecture below.
- **Touch controls:** freeform building with multiple floors must be easy with a finger on an iPhone screen. Test early.
- **Legal:** all airlines and airports are fictional — no real names or logos.

### Performance architecture (rule for all features)
**Target: smooth on older iPhones.** This is planned in from the start, not optimized later.

1. **Simulation and visuals are strictly separate.** The simulation (passengers, stations, money, queues) runs as **pure data** for the whole airport at all times. It never depends on what is on screen.
2. **Visuals only exist where the camera can see them.** In the manager view, only passengers and objects near the camera get 3D figures and animations; everything else is simulated as data only.
3. **Use Godot's built-in tools:** frustum culling, visibility ranges and level of detail (LOD) for buildings and objects.
4. **Build view:** zoom is limited so the game stays playable. When zoomed out, crowds are simplified (fewer figures, simple shapes).

---

## 19. Open Questions

### Intro & start
1. Tutorial: what is the player's role, how long is it, does anything carry over?
2. What does the player's own airport start with: empty field, small airstrip, or run-down regional airport?

### Progression
3. What are the airport tiers called, and what unlocks each one?
4. Which specific special reward goes with which milestone?
5. How does the second currency (reputation?) work and what does it unlock?

### Systems
6. Staff upgrades: training, promotion, pay, specialization — which, and how?
7. Bankruptcy: game over, loan, or restructuring?
8. Demolishing: cost, refund, or both?
9. Negotiations: how do dialogue choices and deal terms interact in detail?

### Player & feel
10. What does walking around as the manager actually do in gameplay?
11. Who is the target player (casual vs. strategy fan)? This affects difficulty and UI depth.
12. Working title / final game name.

### Glossary
- **Gänge** → corridors / walkways
- **Warteräume** → waiting areas, holding rooms, gate lounges