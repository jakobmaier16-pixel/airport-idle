# Roadmap

> Updated by the lead after every merged pull request. Order and steps: tech_architecture.md §17.
> Nothing is built unless it is in **Now** (master_plan.md §6).

## Code lane

### Now
- Step 6.5 · Real scale (Jakob, 2026-11-13: after step 6, before electricity). Airside at real size, no compression:
  stand ~20 × 23 cells, wide-body stand ~35 × 40, taxiway ~12 cells wide, runway 23 cells wide at full
  length (starting length open); a much larger map unlocked piece by piece. Build view draws the whole
  airport cheaply; manager view loads only the manager's area. Plane visuals at real size. Old saves with
  the small stand / runway footprints must keep loading. Needs a plan first (grid, zones, pathfinding,
  drawing and save size at this map size).

### Next
- Step 7 · Electricity

### Done
- 2026-11-13 · Visual 3 · Landside start kit stage 2: 3D pieces, fence, signs, trees, previews (#25)
- Step 6 · Daily timetable and growing demand (done 2026-11-13)
- 2026-11-13 · Visual 2 · Ground stage 2: textures, markings atlas, materials, previews (#19)
- 2026-11-13 · Visual 1 · Art direction (#17)
- Step 5 · Passenger journey as recipes (done 2026-11-13)
- Step 4 · Automatic zones and areas (done 2026-11-13)

### Later (vertical slice)
- Step 8 · Security upgrade ladder up to CT scanners, visible in 3D
- Step 9 · Milestone (first tier)
- Step 10 · UI: separate panels, statistics in the top-down view
- Then: Phase 2 gate, 5–10 outside players

## Visual lane

Merged only by Jakob. Order: docs/art_direction.md first.

### Now
2. Ground · stage 3 (in the game) waits for the code-lane task below
3. Arrival area: stage 2 done (#25); stage 3 (in the game) waits for the code-lane task below
4. Look-probe on Jakob's iPhone (ground + landside in the game), then decide together how to go on

### Handoffs to the code lane
Open GitHub issues with the label `handoff` (the code lead picks them up, Jakob doesn't relay):
- #33 Ground textures and markings in the game
- #34 Landside pieces in the game + iOS look-probe

### Later
4. Terminal shell
5. Check-in
6. Security (incl. CT stage for code step 8)
7. Gate
8. Apron and plane
9. Furnishings (escalators as decor only until floors exist)

## Done
- 2026-11-13 · Step 3 · Saving: names instead of numbers, migrations, flights and passengers saved too
- 2026-11-13 · Step 2 · The brain as one object (fresh brain on every reset)
- 2026-11-13 · Agent workflow: roles, GitHub Actions tests, cloud test setup, this roadmap
- 2026-11-07 · Step 1 · Safety net: seeded randomness, device benchmark, save migrations
