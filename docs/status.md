# Status (both lanes)

Each lead updates its own section at the **end of every session**: what is done, what runs, what is
next, and what it needs from the other lane. Short. Details live in PRs, issues and `decisions.md`.

## Code lane (updated 2026-11-14, late)
- **Stripped to the core (decisions 2026-11-14):** passengers, money, airlines, staff, shops, stars,
  tiers, cargo, land buying, clock and day/night removed (#52, #53, #58; `docs/removed_features.md`).
  Kept: build (grid, zones, walkways, 12-wide taxiway brush, landside pieces), runway, taxiways,
  stands, terminal + gates, fixed timetable (one turnaround per gate every 360 s, first landing ~16 s),
  planes landing, taxiing on centrelines, push-back arc, take-off. Save format v12.
- **Device-test fixes merged:** push-back arc (#55), taxiway brush + centreline markings (#56),
  zoom about the fingers + gate hint + "Plane taxiway" label (#54), build menu never stuck (#60),
  realism pass: road/grass z-fighting, fence MSAA, AgX lighting, haze (#62), plane on the ground (#63).
- **Device test 2 (build 4b4da9c):** core works; main complaint: in-game look far below the Blender
  previews. Code lane did the technical part (#62); model-limited items are on #51.
- **New way of working (decisions 2026-11-14, late night):** many small projects, each in its own
  small test world; board: `docs/worlds.md`. In progress: world list and asset viewer.
- **Next:** Jakob's first pass through the asset viewer (verdict per asset), then the Building rules
  world. Still open from the realism pass: check lighting, fence and the car park from far away on the phone.
  Small follow-ups: HUD `next_flight_text()` per frame (throttle), weak countdown assertion in test_11,
  stale docs (art_direction DayNight mentions, prototype_reference clock).
- **Parked:** time scale (clock vs real-speed planes) to be rethought before the clock returns.

## Visual lane
- (Visual lead: add your section here at the end of your next session.)
- **New for the visual lane (decisions 2026-11-14, late night):** work in small projects; every asset
  goes into the asset viewer and is judged there by Jakob on the device (see CLAUDE.md "Small projects
  and test worlds" and `docs/worlds.md`).
- **Open for the visual lane:** #44 real-size planes. New: the visual lane brings its own assets into
  the game and checks in-game screenshots against its previews (landside look, see handoff issue).
