# Game Design — Airport Manager (working title)

> Status: Draft v0.5 · Last updated: 2026-10-12
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

### 7.2 Zones (realism rule)
- The airport has a **landside (public)** zone and an **airside (secure)** zone.
- **Security is the only way** for passengers to get from landside to airside. Once through security, you are in the secure zone.
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
  - Drag with one finger to move, pinch to zoom. Zoom is limited so the game stays playable; the camera cannot leave the map.
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

The smallest version that proves the core idea:

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