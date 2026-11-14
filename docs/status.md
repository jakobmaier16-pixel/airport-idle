# Status (both lanes)

Each lead updates its own section at the **end of every session**: what is done, what runs, what is
next, and what it needs from the other lane. Short. Details live in PRs, issues and `decisions.md`.

## Code lane (updated 2026-11-14)
- **Done:** step 6.5 real scale: chunked grid, sparse paths, zones, save v10, ground flag texture and
  materials (#39), map 2,200 × 1,600, real runway and stands, 12-wide taxiway brush, centreline taxi
  routes and real taxi timing (#48), landside pieces in the game (#47).
- **Device test 2026-11-14:** see `decisions.md`. Bugs found: planes turn on the spot and drive over
  grass; taxiway brush can paint over the landside road and is hard to control; zoom pulls to the map
  centre; gate shows "Needs an aircraft stand behind" but still places; building on the landside
  teleports the camera; landside look poor in the game (road/zebra z-fighting, fence holes, raised
  grass blocks).
- **Next:** strip the game to the core (decisions 2026-11-14), then fix the bugs above in what remains.

## Visual lane
- (Visual lead: add your section here at the end of your next session.)
- **Open for the visual lane:** #44 real-size planes. New: the visual lane brings its own assets into
  the game and checks in-game screenshots against its previews (landside look, see handoff issue).
