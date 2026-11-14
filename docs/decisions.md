# Decisions (shared memory of both lanes)

Every decision Jakob makes goes here **immediately**, newest first, with the date and in his words
(translated to English where needed). Both leads read this file at the start of every session.
`game_design.md` holds the resulting design; this file is the trail of what Jakob said and when.

## 2026-11-14 (night, device test 2)
- **Landside pieces stay as they are** (35 placeable pieces). The lead's proposal to draw roads,
  sidewalks and car parks like the taxiway tool is **rejected**.
- **Main complaint: the in-game quality is far worse than the visual lane's Blender previews.**
  The gap between preview and game must close; realism in the game is the priority.
- Device test 2 results: first landing, push-back arc, zoom ok; gate hint, taxiway tool and landside
  building ok after an app restart (build menu could get stuck → fixed). Landside look unchanged.

## 2026-11-14 (evening)
- **The clock goes out for now (option c).** Reason: the clock ran 15× faster than the planes, which
  move at real speed (Jakob likes that speed), so a landing took ~9 game minutes. Until time is
  rethought cleanly there is no time of day; the HUD shows only "next flight in X s". Day/night lighting
  goes with it (fixed daylight).
- Lead decisions for the strip (not objected): cargo terminal and freighters out; baggage claim out;
  the whole map is buildable (no land buying while there is no money).

## 2026-11-14 (device test, iPhone 13 Pro)
- **Strip the game down to the basics.** Remove passengers, money and airline deals. Keep the clock
  only if it is cleanly built; otherwise remove it too. Also out (lead's core proposal, not objected):
  staff, demand growth, stars / reputation, tiers / progression, shops.
- **What stays (core):** map and building, runway, taxiways, stands, terminal with gate, a simple fixed
  timetable, planes that land, taxi and take off, the clock.
- **Removed features are deleted from the code**, not switched off. Each keeps a short description of
  how it worked in `docs/removed_features.md`, plus the last commit that still had it. Needed again in
  about a week or later.
- **No "understood?" check-ins before tasks.** The lead just builds.
- **UI / safe area:** done properly at the very end. Until then: everything needed for a test must be tappable.
- **iPad:** not tested at this stage (maybe in about a week).
- **Prices / balancing:** at the very end.
- **Plane speed:** feels right (nice slow-down).
- **Look:** 0.5 / 10 in the game. Convincing so far only: concrete slabs, maybe paving and road.
  Realism must be visible (e.g. no raised square grass blocks at the car park).
- **Workflow:** information got lost between chats and sessions. Shared memory in the repo
  (`docs/decisions.md`, `docs/status.md`); the visual lane brings its own assets into the game.

## 2026-11-13
- Starting land provisional 2.4 × 0.8 km ("use it if realistic").
- Real scale details: map ~4.4 × 3.2 km; runway 2,000 m, ~3,200 m with International; land pieces
  ~400 m, adjacent only, some tier-gated; old small stands/runway removed on load with full refund;
  taxi time from the real route, timetable plans it per stand; real walking distances, moving walkways
  later; two plane classes by wingspan, a stand takes its own class or smaller.
- No own save game needed for tests; tests always use the showcase airport.
- A `playtest` agent prepares device tests on request.
- Real scale everywhere, 1 cell = 2 m (was: compressed airside).
- Removed: weather, incidents, VIP visits, first-landing cutscene.
