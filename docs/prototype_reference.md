# Prototype Reference — Airport Manager (working title)

> **Describes what the prototype does today. Not the final design. The design is in [game_design.md](game_design.md).**
>
> Formerly the design doc v0.20 (2026-10-13). Section numbers are unchanged, so code comments that cite "design doc §N" point here.

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
  - walks around the airport as the manager, managing stations on the spot (§15.1)
  - watches passengers move and spots problems
  - opens statistics to find bottlenecks (security? boarding? marketing?)
  - hires, assigns and develops staff, manages stations
  - negotiates deals with airlines (fees, slots, gates)

**What "idle" means here:** passengers flow and earn money automatically while the player manages. Progress happens while playing, not while away.

---

## 5. Time & Offline Rules

- **While playing:** full simulation, all income. The simulation **keeps running in the build view** — there is no pause (for now).
- **Offline:** no income for breaks under 36 hours. After **36 hours or more** away, the player receives **4 hours' worth of income** once. (Similar in spirit to Clash of Clans — a small welcome back, not a reason to stay away.)
- **Offline income, implemented:** "income" = the airport's average profit per minute over roughly the last 10 minutes of play (never negative). The save stores the time it was written; on loading after 36 h or more, 4 hours of that profit is paid once and a welcome-back notice says how much.
- **Saving:** automatic — after every change, every 30 seconds while playing, and when the app goes to the background. No manual save button.
- **Upgrades:** small upgrades are instant. Big upgrades take **1–10 minutes** with **visible construction on site**.

---

## 6. Tutorial / Intro

- Set at a **fictional regional airport inspired by Memmingen**.
- Goal: **clearly show what kind of game this is** and what the player can achieve at their own airport.
- After the intro, the player builds their own airport.
- Role in the tutorial, length, starting site and anything that carries over: **(open)** — we will design this once the core game exists.

### 6.1 Getting started goals (first version)
Decided 2026-10-13. The story intro above stays open; until it exists, a short goal line guides a new player through their first airport.
- **The player's own airport starts as an empty field** (closes §19 Q2 for now): 48 × 48 cells of land (§14.1), €50,000 and one airline deal (§10.1).
- One line under the top buttons shows the next goal, e.g. "Goal 3/10: Build a Check-in facing the entrance's walkway". Goals, in order: security with a walkway behind it (airside) · entrance on a walkway · check-in · security on the border · gate with a stand · baggage claim · hire staff · first departure · sign a second airline · reach National.
- The line always shows the first goal that isn't met (a goal undone by demolishing comes back). "Hide" removes it for good (saved). It disappears when all goals are done, and while a panel on the right is open.

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
- If a spot is not allowed, a short hint says why (space taken, no free row beside a border building, …).
- MVP building sizes (provisional, easy to change per building):

| Building | Cells | Meters | Zone rule |
|---|---|---|---|
| Entrance | 4 × 2 | 8 × 4 | landside |
| Check-in | 5 × 3 | 10 × 6 | landside |
| Security | 5 × 3 | 10 × 6 | border: front faces landside, back faces airside |
| Gate | 5 × 5 | 10 × 10 | airside (waiting area included) |
| Aircraft stand | 20 × 23 | 40 × 46 | airside, real scale since 2026-11-14 (was 12 × 12); flat, can be walked on |
| Shop (duty free / retail) | 3 × 3 | 6 × 6 | airside |
| Café | 4 × 3 | 8 × 6 | landside or airside |
| Baggage claim | 6 × 4 | 12 × 8 | border: front faces landside, back faces airside (like security, used the other way) |
| Transfer security | 4 × 3 | 8 × 6 | airside |

### 7.1b Walkways (corridors and halls)
- Corridors and halls are drawn as **walkway floor**: pick *Walkway* and drag a rectangle (or tap a cell); *Remove* erases walkway.
- **Any width.** Width will matter once passengers walk: narrow walkways get crowded and slow passengers down. A realistic corridor is at least 2 cells (4 m) wide.
- **Buildings can stand on walkway** (e.g. check-in desks inside a hall). Cells under a building are not walkable.
- Walkways belong to the zone the zone map computes for them (§7.2). Passengers only walk on walkways and can only get from landside to airside **through security** (§7.2).
- **Access sides:** passengers enter and leave buildings only on their access sides.

| Building | Access side(s) |
|---|---|
| Entrance | back (into the terminal); the front faces outside |
| Check-in | front (queue area) |
| Security | front (landside) and back (airside) |
| Gate | front (walkway) and back (aircraft stand) |
| Shop, café | front (walkway) |
| Baggage claim | back (airside, from the gates) and front (landside, to the exit) |
| Transfer security | front (in) and back (out), both airside walkway |
| Aircraft stand | reached through a gate |

- A building is **connected** when each access side touches at least one free walkway cell (the gate's back: an aircraft stand). Unconnected buildings can still be placed (build first, connect after) and show a hint such as "Needs a walkway in front".
- **Waiting areas:** for the MVP the waiting area is part of the gate. Separate holding rooms come later.

### 7.2 Zones (realism rule)
- The airport has a **landside (public)** zone and an **airside (secure)** zone.
- **Security is the only way** for passengers to get from landside to airside. Once through security, you are in the secure zone.
- **Zones are computed, not painted** (since step 4b): the game walks from the entrance along the walkways; what it reaches without passing security is landside, what is behind security's back row is airside. Taxiways, stands, runways and other airside-rule buildings are airside by rule; empty ground is landside.
- Each building has a **zone rule** (see the table in §7.1a). It is no longer a placement check: airside buildings can be placed anywhere and show "Not connected" until the airside reaches them. Security needs a free row on both sides. Transfer security is not a border.
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

### 7.5a Runways and taxiways (first version)
Placeholder numbers, tunable. Compressed like the rest of the airside.
- **Runway** (Airside, 1,000 × 23 cells = 2 km, €400,000 · €20/min; was 52 × 6): planes land on it and take off from it. **A new airport already has one** (the field came with it): south of the map centre, free, on land the airport owns from the start. More runways can be built later.
- **Taxiways** are painted like walkways (build view: *Taxiway*, airside only, €30 per cell, €0.05/min): dark asphalt with a yellow centre line. **A stand only works if a taxiway connects one of its sides to a runway**; otherwise its gate gets no flights and the stand shows "Needs a taxiway to a runway". *Remove* clears walkways and taxiways.
- **Planes follow the taxiways:** an arriving plane descends onto the runway, rolls out, turns onto the taxiway and taxis to its stand; a departing plane taxis back, rolls down the runway and climbs away.
- **Runway capacity:** every landing and every take-off occupies a runway for its roll plus a 10 s margin (real-scale runway, step 7c: about 30 s for a landing, 35 s for a take-off on the showcase; the old flat 20 s is gone). An arriving plane that finds its runway busy holds before landing — an arrival delay the airport caused, which also delays its next departure (the turnaround is fixed). A departing plane pushes back on time, taxis to the runway and waits at the holding point until the runway is free; punctuality counts the push-back, as real statistics do. Busy airports need a second runway.
- **Turnaround buffer:** a plane may land up to 20 s late without delaying its departure (the time at the stand absorbs it); only longer waits push the departure back. Gates (and cargo terminals) that open at the same time share the 3-minute slot evenly so their runway movements interleave.
- The regional airport's land (§14.1) reaches down to the runway, so the first taxiways can be painted.

### 7.6 Demolish and rebuild
- Everything can be demolished, **including during operations**.
- **Refund: 50 % of the build price** (decided 2026-10-13). Money spent on upgrades is not refunded. Removing walkway is free and refunds nothing.
- In the build view: pick *Demolish*, tap a building (shown in red with its refund), confirm with *Demolish*.
- **During operation:** passengers at the building go to another station of the same kind (shop customers carry on); flights at a demolished gate or stand are cancelled; staff working there are dismissed. Cells only that building needed can be repainted.

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

- Gates and entrances have no upgrades yet. Managing a station (hire, dismiss, upgrade) happens **on the spot**: the manager must walk to it (§15.1).

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


### 8.9 Transfer passengers (first version)
- Some arriving passengers **connect to another flight**: Business routes 25 %, Holiday 10 %, Low-cost 5 % (low-cost airlines rarely sell connections).
- They deplane at the gate, **skip baggage claim** (bags are transferred), go through **transfer security**, may visit a shop if there is time, and board their **connecting flight** — one that departs at least 2½ minutes after they deplane.
- Not on board when the doors close = **missed connection** (counted as missed).
- **Transfer security** (airside, 4 × 3): in at the front, out at the back; 2 lanes, staffed like security (€10/min per officer). €4,000 · €8/min. Upgrade: +1 lane €3,000.
- **Without a working transfer security the airport sells no connections:** all arriving passengers end their journey here.
- Statistics show passengers transferring now and successful connections.


### 8.10 Passenger satisfaction (first version)
Placeholder numbers, tunable.
- Every passenger has a **mood** (0–100 %) that starts at 100 % and drops when the airport treats them badly:
  - **Long queues:** −0.5 per second in a check-in or security queue beyond their patience (families 60 s, low-cost 90 s, business 30 s).
  - **Long walks:** −0.1 per meter beyond 150 m walked inside the airport.
  - **Waiting for bags:** −0.3 per second at the belt beyond 60 s.
  - **No way through:** −1 per second while they can't find a way to their next station.
  - **Missed flight:** mood 0, and the journey counts three times (people remember the trip that went wrong).
- A visit to a shop or café **cheers them up** (+5). Unhappy customers **spend less**: from 50 % of the normal amount at mood 0 to 110 % at mood 100.
- When a journey ends (boarded, left the airport, missed the flight), the mood goes into the airport's **satisfaction**: the average of the last 60 journeys, also per passenger type. A new airport starts at 75 % (the first journeys are blended with that).
- **Statistics** show satisfaction overall and per type, and the **main complaint** (the reason that cost the most mood over the last few minutes).
- Satisfaction feeds the airport's **reputation** (§11.7).

---

## 9. Staff

- **Individual employees** with names, skills and experience.
- **Experience grows per station:** someone who has worked check-in for a long time is faster there than a new hire.
- Staff is assigned to stations; staff count and quality affect throughput.
- Upgrading staff (training, promotion, pay, specialization): §9.2.


### 9.1 First staff system
Placeholder numbers, tunable.
- **Every check-in counter and security lane needs one employee**; without staff it stays closed. Gates and baggage claim run without staff for now; shops are run by their tenants.
- **Employees** are individuals with fictional names. Salary: check-in agent €8/min, security officer €10/min. Salaries replace most of the stations' running costs (check-in €6/min, security €10/min for the building itself).
- **Experience per station type:** a new employee is 25 % slower than the standard time; every passenger served at that station type makes them faster, up to 15 % faster (expert) after 150 passengers. Levels: New · Trained · Experienced · Expert.
- **Managing** happens in the station panel (manager view), on the spot (§15.1): staff list with levels, *Hire* and *Dismiss*. Unstaffed stations show "Needs staff".
- Training and promotion: §9.2.

### 9.2 Training and promotion (first version)
Decided 2026-10-13 (closes §19 Q6 for now). Placeholder numbers, tunable.
- **Specialization** is the experience per station type (§9.1): an expert at security is a beginner at check-in.
- **Training** (station panel, on the spot): sends the least experienced employee there to a course. €400, 45 seconds away from the counter (it stays closed meanwhile), then +40 passengers of experience at that station type (about one level). One trainee per station at a time; experts don't need it.
- **Promotion:** an expert can be promoted to **supervisor** (+€4/min salary). A supervisor still runs a counter, and everyone else at that station works 5 % faster. One supervisor per station.
- **Pay** stays fixed per job for now; pay raises only come with promotion.

---

## 10. Airlines, Flights & Deals

- The player **attracts airlines** and their flights. The player does **not** own planes.
- All airlines are **fictional** (inspired by real types: flag carrier, low-cost, holiday charter, long-haul, cargo later).
- **Negotiations** use **dialogue choices** plus **adjustable deal terms**: fees, slots, gates.
  Decided 2026-10-13: airlines send **offer cards** (route type, flights per hour, fee per passenger). The player adjusts the terms with **sliders** and picks a **tone** (firm / friendly / flexible). The airline's chance to accept depends on the terms, the airport's reputation and how happy that airline is. Signed airlines complain, and finally leave, when the airport's performance drops. Details: §10.1.
- Deals are **directly linked to the airport's real performance**: on-time rate, turnaround speed, passenger satisfaction, capacity. A well-run airport gets better deals.
- **Routes matter**, as in reality:
  - Holiday routes bring families and seasonal peaks
  - Business routes bring high spenders at peak hours
  - Long-haul routes need bigger stands, gates and runways, and bring higher income
  - Hub/transfer routes need good transfer flows


### 10.1 Airlines and deals (first version)
Placeholder numbers, tunable. All names are fictional.
- **Gates are capacity, airlines are demand.** Every gate offers a turnaround slot every 3 minutes (20 flights per hour). Flights only come from **signed airlines**; each deal says how many **flights per hour** the airline wants and what it pays **per passenger**. The schedule fills each gate slot with the airline that is most "owed" a flight. Too few gates for the signed flights = **refused flights**, which make airlines unhappy. More gates than flights = idle gates.
- **Airlines** (each has a route type that sets its passenger mix, an expected fee, a minimum star rating and a personality):

  | Airline | Route | Expects | From | Likes | Dislikes |
  |---|---|---|---|---|---|
  | Velora Regional | Holiday | €15 | start | friendly | firm |
  | Zippa | Low-cost | €9 | 1 ★ | firm | flexible |
  | Budjet | Low-cost | €8 | 1½ ★ | firm | friendly |
  | Sunkiss Charter | Holiday | €13 | 2 ★ | flexible | firm |
  | Lagoona Air | Holiday | €14 | 2½ ★ | flexible | friendly |
  | Brisk Express | Business | €18 | 3 ★ | firm | flexible |
  | Norvane Airways | Business | €20 | 3½ ★ | friendly | flexible |
  | Corvista Airlines | Business | €24 | 4 ★ | friendly | firm |

- **A new airport starts with one deal:** Velora Regional, 20 flights per hour at €15 — exactly one gate's worth. Every further gate needs another airline.
- **Offers** arrive every 4–7 minutes (the first after 2 minutes) from airlines whose minimum rating the airport meets; at most 3 are open, each expires after 10 minutes. A notice announces them.
- **Negotiating** (Airlines panel, from anywhere): the offer card shows the airline's terms and a line from their representative that hints at their personality. The player sets the **fee per passenger** and the **flights per hour** (up to what they asked for) with − / + buttons, sees the **chance they agree**, and answers in one of three tones:
  - *Firm:* "These are my terms." · *Friendly:* "Let's build something together." · *Flexible:* "We'll work around your schedule."
- **Chance to agree:** 75 % at their expected fee; −15 points per 10 % above it, +15 per 10 % below. −5 points per 10 % fewer flights than asked. +5 points per star above their minimum. +15 points for the tone they like, −15 for the one they dislike. Clamped to 0–100 %.
- **If they say no**, but the chance was at least 25 %, they come back once with a **counter-offer** halfway between the two fees, which the player can sign or decline. Otherwise they walk away and don't offer again for 15 minutes.
- **Airline happiness** (starts at 75 %) follows their recent flights: on time 100, late 50, minus the share of their passengers who missed the flight; a refused flight counts as 0. Below 40 % the airline complains (notice); below 25 % it **ends the deal** and leaves.
- The player can **end a deal** at any time (two taps).
- Planes carry their airline's tail color; flight numbers use the airline code (e.g. ZP 214).


### 10.2 Long-haul flights (first version)
Placeholder numbers, tunable. Unlocked at **International** (§14.1).
- **Wide-body stand** (Airside, 35 × 40 cells, €60,000 · €70/min; was 16 × 16): the only stand big enough for wide-body planes. Narrow-body planes can use it too, but a wide-body airline gets it first.
- **Long-haul airlines** fly only wide-body planes, so they need a gate with a wide-body stand behind it; without one, their flights are refused (and they get unhappy).

  | Airline | Expects | From | Likes | Dislikes |
  |---|---|---|---|---|
  | Orynth Pacific | €32 | International, 3½ ★ | friendly | firm |
  | Valtair Intercontinental | €35 | International, 4 ★ | firm | flexible |

- **Wide-body planes** are 1.4 × bigger (four engines), carry **twice the passengers** and deplane through two doors (2 per second).
- **Long-haul route:** 35 % families, 15 % low-cost, 50 % business; 30 % of arriving passengers connect (§8.9).
- Reaching International brings an offer from Orynth Pacific at once.


### 10.3 Cargo (first version)
Placeholder numbers, tunable. Unlocked at **National** (§14.1).
- **Cargo terminal** (Airside, 8 × 5, €12,000 · €15/min): a warehouse with an aircraft stand behind it, like a gate for freight. It needs **cargo handlers** (€9/min each, 4 places; upgrade +2 places €5,000) and its stand needs a taxiway to a runway.
- **Cargo airlines** fly freighters to cargo terminals only (never to passenger gates). Each flight brings and takes 30–50 tonnes, which the handlers unload and load while the plane is parked: each handler moves 0.25 t per second (experience makes them faster, like all staff).
- **Income:** the deal's fee per tonne handled, plus the landing fee. If the freight isn't handled by departure time the plane waits up to 60 s (the airport's delay); after that it leaves with what was loaded.
- Cargo airlines (they only make offers once the airport has a cargo terminal):

  | Airline | Expects | From | Likes | Dislikes |
  |---|---|---|---|---|
  | Paqet Air Cargo | €20/t | National, 2½ ★ | firm | friendly |
  | Trevan Freight | €24/t | National, 3½ ★ | flexible | firm |

- Freighters are grey with their airline's tail; the departures board shows them as "Cargo". Statistics list cargo income.


### 10.4 Contract renewals (first version)
Placeholder numbers, tunable.
- Every deal (also the starting one) runs for **one game day** (96 real minutes). **Ten minutes before it ends**, the airline asks to renew; the renewal appears with the offers and is negotiated the same way (fee, flights, tone; the airline's own terms are the reference).
- The terms follow the airline's **happiness** (§10.1): 70 % or more — 2 more flights per hour and a 10 % higher fee; 45–70 % — the same terms; below 45 % — 15 % lower fee.
- A renewal keeps the airline's happiness and history and starts a new contract. Turned down or not answered in time, the airline keeps flying until the contract ends, then **leaves**.
- The airlines panel shows each contract's remaining time.

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
- **Bankruptcy is possible, but there is no hard game over** (decided 2026-10-13). Below €0 the bank covers the gap with a **loan** that costs interest. If the debt grows past the credit limit, the bank **restructures** the airport: it sells buildings until the debt is covered and the airport's reputation drops. Details: §11.6.

### 11.4 Second currency
- **Reputation = a 1–5 star rating** (decided 2026-10-13), computed from **passenger satisfaction** (§8.10) and the **on-time rate** of departures. It is not spent: it unlocks better airlines and deals (§10) and, together with passenger numbers, the airport tiers (§14). Details: §11.7.


### 11.5 First economy (MVP, item 6)
Currency: **euro (€)**. All numbers are placeholders, tunable per building (compressed game time).
- **Starting money:** €50,000.
- **Income** when a flight's doors close: **€15 per departing passenger** (passenger fee paid by the airline) and **€300 per flight** (landing / turnaround fee).
- **Construction:** Entrance €2,000 · Check-in €3,000 · Security €5,000 · Gate €4,000 · Aircraft stand €18,000 (was €6,000) · Walkway €20 per cell. Removing walkway is free and refunds nothing (demolishing rules are still open, §19).
- **Running costs per minute** (staff, maintenance, utilities): Entrance €10 · Check-in €30 · Security €40 · Gate €25 · Stand €15 · Walkway €0.05 per cell. Charged continuously while the game runs.
- **Display:** balance and profit per minute (last 60 s) at the top of the info panel; red when negative.
- **Negative balance** is a bank loan (§11.6).
- **Not in the MVP yet:** shop income, parking, salaries per employee, upgrades (§16 item 7).


### 11.8 Car park, lounge and fast track (first version)
Placeholder numbers, tunable. Real airports earn a big share of their money outside the airline fees.
- **Car park** (landside, 8 × 6, €8,000 · €8/min, front onto a landside walkway): 35 % of passengers travel by car. With a connected car park, departing car travellers arrive there instead of at the entrance (they park for their trip); arriving car travellers (returning from their trip) leave through it and **pay €8** on the way out. Without a car park everyone uses the entrance (taxi, train).
- **Lounge** (airside, 5 × 3, €10,000 · €20/min, 16 guests): business travellers with time to spare (80 %) wait in the lounge instead of a shop until their final call. The airport runs it: **€12 per guest**, and guests gain +10 mood.
- **Fast track** (security, a one-off €5,000 from the station panel): business travellers go to the front of the queue and pay **€5** each. Everyone else waits a little longer.
- Statistics list the car park and lounge with their income.


### 11.6 Bank loan and restructuring (first version)
Placeholder numbers, tunable.
- **A negative balance is a bank loan.** Interest: 1 % of the debt per minute, charged like a running cost (it shows in profit per minute). Nothing can be built or upgraded while the money isn't there.
- **Credit limit:** €20,000 plus 25 % of what the airport is worth (build prices plus upgrades paid for).
- **Over the limit for 2 minutes** and the bank **restructures** the airport: it sells buildings at the demolish refund (50 %) until the debt is covered — shops, cafés and transfer security first, then second (third, …) buildings of a kind, newest first. It never sells the last entrance, check-in, security, gate, stand or baggage claim, so a small working airport always remains. Whatever is still owed is written off.
- After a restructuring the reputation loses **1 star**, which fades over 10 minutes.
- HUD: a red line under the money shows the loan, the limit and the interest, and a countdown while over the limit. A notice says what the bank sold.


### 11.7 Reputation (first version)
Placeholder numbers, tunable.
- **Star rating, 1–5** (shown in half stars under the money, with satisfaction and on-time rate next to it).
- Score = 70 % satisfaction (§8.10) + 30 % on-time rate. Score 0.5 or less = 1 star, 0.95 or more = 5 stars, linear in between. A new airport has about 3½ stars.
- **On-time rate:** share of recent departures (about the last 10) that left at most 10 s late (compressed time).
- **Delays:** at departure time a flight **holds its doors** for its passengers who are already airside (walking to the gate, in a shop, at transfer security) or still boarding, at most 30 s; then it leaves without them. Passengers still landside are not waited for. The departures board shows "Delayed".
- **Effect now:** passengers per flight scale with the rating, from 60 % at 1 star to 140 % at 5 stars (people avoid badly run airports). Later: airlines and deals (§10.1) and airport tiers (§14) depend on it.

---

## 12. Realism Systems

All of these are wanted. They will be added in phases, not all at once:
- Flight schedules
- Delays (with knock-on effects)
- Weather (removed 2026-11-13)
- Night curfews
- Security incidents (removed 2026-11-13)
- Seasons (holiday peaks, quiet months)

### 12.1 Time of day (first version)
Placeholder numbers, tunable.
- **Clock:** one real second is 15 game seconds (a 3-minute gate turnaround stands for ~45 minutes), so a day lasts 96 real minutes. A new airport opens at 06:00 on day 1. The HUD shows "Day 3 · 06:45" next to the top buttons; the clock is saved.
- **Demand by hour:** passengers per flight follow the day: a morning rush (06–09, up to 130 %), a normal day, an evening rush (17–20), and a quiet night (00–04, 40 %). Flights keep their schedule at night (night curfews come later, possibly as a tier rule).
- **Light:** the sun climbs and sets (warm low light in the morning and evening), nights are dim and blue but still readable. The sun keeps its compass direction, like the camera.
- Seasons: §12.2. Night curfews: §12.4. (Weather, security incidents, VIP visits and the first-landing cutscene were removed on 2026-11-13.)

### 12.2 Seasons (first version)
Placeholder numbers, tunable.
- **Seasons** last 2 game days each (~3 real hours): Spring → Summer → Autumn → Winter. A new airport starts in spring. Demand by route type: Holiday 100 / **135** / 100 / **75 %**, Low-cost 100 / 115 / 100 / 90 %, Business 100 / 90 / 105 / 105 %, Long-haul 100 %.
- **Knock-on delays:** a plane can only arrive at a stand once the previous plane has left it, so one late flight can delay the next one at that gate.
- The HUD shows the season next to the clock.

### 12.4 Night curfew (first version)
- Until the airport is a **Hub**, no plane lands or takes off between **00:00 and 05:00** (noise rules, 20 real minutes per game day). Gate slots in those hours stay empty, and airlines don't count them as owed flights. Passengers already in the airport finish their journeys.
- The clock shows "Curfew", and the departures board says when flights start again.
- **Hub** status brings **night flights**: the curfew ends (§14.1).

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

### 13.2 Statistics tabs (first version)
- The statistics panel has four tabs: **Stations** (§13.1), **Money**, **Airlines** and **Messages**. Below them: passengers by type, satisfaction and main complaint (§8.10), and the progress to the next tier (§14.1).
- **Money:** income by source (airline fees, arrival fees, shops & cafés, lounge, parking, fast track) and costs by source (buildings & walkways, salaries, loan interest) over the last 5 minutes and per minute, with totals and the profit. Construction and refunds are one-offs and not listed.
- **Airlines:** per signed airline: flights per hour, flights flown, on-time share (only delays the airport caused), happiness and fee.
- **Messages:** the last 30 notices (offers, weather, incidents, VIPs, milestones…) with the game time, newest first, so nothing important is missed.
- The table scrolls when it is longer than the screen.

---

## 14. Progression & Milestones

- **Airport tiers:** Regional → National → International → Hub (decided 2026-10-13, details §14.1).
- Reaching a milestone should feel **special**, not a standard multiplier. Reward types we want (all of them):
  - **New mechanic** unlocks (night flights, cargo, long-haul, a second terminal)
  - **New land** to expand into
  - **A new major airline** signs, with a cinematic first landing
  - **Special events** (first wide-body jet, VIP or state visit)
- One airport for the whole game. More airports: maybe later, not now.
- **No playtime limit.**


### 14.1 Airport tiers (first version)
Decided 2026-10-13 (closes §19 Q3 and Q4 for now). Placeholder numbers, tunable.
- **Passengers** = departing passengers (including transfers) plus arriving passengers who left the airport, counted over the whole game.

  | Tier | Reached with | Rewards |
  |---|---|---|
  | **Regional** | start | 48 columns of land in the middle of the map, from the north edge of the terminal area down to the runway; every basic building |
  | **National** | 1,000 passengers and 3 ★ | **new land** (the whole 64 × 64 map), **transfer security** (connections, §8.9), **cargo** (§10.3), and a major airline (Norvane Airways) makes an offer at once |
  | **International** | 6,000 passengers and 3½ ★ | **long-haul flights**: a wide-body stand and long-haul airlines with big planes (§10.2) |
  | **Hub** | 25,000 passengers, 4 ★ and 600 transfers | **hub status**: airlines route twice as many connections through the airport, **night flights** (no curfew, §12.4), and a premium airline (Corvista Airlines) makes an offer |

- Pace (balance check, 2026-10-13): a new one-gate airport with the starter airline serves ~900 passengers per hour and earns ~€100/min, so National comes after 30–60 minutes depending on how quickly the player adds a second airline and gate.
- Reaching a tier is a **milestone moment**: a big panel names the new tier and lists what it unlocked ("Let's build!").
- Land the airport doesn't own yet is shaded darker; nothing can be built or painted there ("Unlocked at National airport"). Buildings already standing there (old saves) stay.
- The tier is shown next to the star rating; the statistics panel shows the progress towards the next tier.

---

## 15. Camera, Look & Feel

### Camera
A button switches between the two views.

- **Manager view: first person** (changed 2026-10-13; before: a fixed tilted camera like *League of Legends*). The player sees what the manager sees, from eye height (1.7 m), and looks around freely. **Everything except building happens here:** walking, watching passengers, managing staff and stations, statistics. The overview of the whole airport is the build view's job.
  - Looking up and down is limited (70° down to watch queues, 35° up), so the view never flips.
  - No zoom in the manager view.
- **Build view:** top-down / bird's-eye. **All** building and layout planning happens here, and only here.
  - Drag with one finger to move, pinch to zoom; two fingers also move the view. While a tool uses one-finger drags (e.g. painting walkways), only two fingers move the view. Zoom is limited so the game stays playable; the camera cannot leave the map.
  - When zoomed out, crowds are shown simplified (fewer figures, simple shapes). See §18.
- What walking as the manager does in gameplay: decided, see §15.1.

### 15.1 Managing on the spot (first version)
Placeholder numbers, tunable.
- Tapping a station opens its panel **from anywhere** (information), but **hiring, dismissing and upgrading need the manager within 10 m** of the building. Far away, the buttons say "Walk closer to manage (34 m away)".
- **The manager's presence helps:** within 6 m of a staffed station, staff need 10 % less time per passenger, and passengers in its queue lose only half the usual mood (someone keeps them informed). A green "Manager here · +10 %" hint floats above the station; its panel says so too.
- Statistics, airlines and building work from anywhere.

### Controls (manager view, landscape)
- **Left half of the screen:** one finger shows a floating joystick under the thumb to walk — forward is where the manager looks; sideways steps sideways.
- **Right half of the screen:** drag to look around (left/right turns, up/down tilts); a short tap still opens the station under the finger.
- Both thumbs work at the same time (walk and look), like mobile first-person games. Each finger is its own gesture; there is no pinch in the manager view.
- Mac (testing): WASD / arrow keys walk relative to the view, dragging with the mouse on the right half looks around.

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
2. ~~What does the player's own airport start with: empty field, small airstrip, or run-down regional airport?~~ For now: empty field, §6.1.

### Progression
3. ~~What are the airport tiers called, and what unlocks each one?~~ Decided: §14.1.
4. ~~Which specific special reward goes with which milestone?~~ Decided for the four tiers: §14.1 (more special events later).
5. ~~How does the second currency (reputation?) work and what does it unlock?~~ Decided: star rating, §11.7.

### Systems
6. ~~Staff upgrades: training, promotion, pay, specialization — which, and how?~~ Decided: §9.2.
7. ~~Bankruptcy: game over, loan, or restructuring?~~ Decided: loan, then restructuring, §11.6.
8. ~~Negotiations: how do dialogue choices and deal terms interact in detail?~~ Decided: offer cards + sliders + tone, §10.1.

### Player & feel
9. ~~What does walking around as the manager actually do in gameplay?~~ Decided: manage stations on the spot, §15.1.
10. Who is the target player (casual vs. strategy fan)? This affects difficulty and UI depth.
11. Working title / final game name.

### Glossary
- **Gänge** → corridors / walkways
- **Warteräume** → waiting areas, holding rooms, gate lounges