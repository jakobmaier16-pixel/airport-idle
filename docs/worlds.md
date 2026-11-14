# Worlds and small projects (the board)

How we work since 2026-11-14 (`docs/decisions.md`): **many small projects**, each built, tested and
fixed on its own in its own small **test world**. Nothing is joined before Jakob approved the parts.
This board replaces `docs/roadmap.md` for planning. Both leads keep it current.

Status: `planned` → `building` → `ready for Jakob` → `approved` or `rejected` (with the date and his words).

## Kinds of worlds

- **Look:** judge what things look like, in the game's own light, on the phone.
- **Function:** one function or one rule each.
- **Combined:** joins projects, and only ones Jakob has approved. Grows step by step (two parts, then three ...).

A world answers **one question**. A world that needs more than about five check points is split (proposal).

## Worlds

| World | Kind | The question it answers | Status | Jakob's verdict |
|---|---|---|---|---|
| World list | base | Can I pick a world right after the app starts, and switch at any time? | ready for Jakob | |
| Asset viewer | look | How does each single asset look in the game: building, piece, plant, sign, ground, material, plane? | ready for Jakob | |
| Fresh airport | function | Do the build tools work on an empty field? | ready for Jakob | |
| Everything together | combined | The old all-in-one showcase. Kept for the automated tests, **not** for judging. | ready for Jakob | |
| Building rules | function | Where may each building stand, what does it need, what does it do? The rules are set here with Jakob. | planned | |
| Landing and take-off | function | Does a plane land, roll out, line up and take off correctly? | planned | |
| Push-back | function | Is the push-back arc right? | planned | |
| Taxiway tool | function | Is painting and removing taxiways easy to control? | planned | |

## How to add a world / a viewer item

- **A world:** add a `TestWorld.make(...)` to `TestWorlds._create_all()` (id, title, kind, one question, at most five
  checks, a builder that fills the airport through the `Airport` API, start view); give it its own test file.
- **A viewer item:** a `BuildingType` in `data/buildings/catalog.tres` shows up by itself. A thing that is not a
  building yet (wall, ceiling, material) is a `DisplayItem` (scene or material swatch) listed in
  `data/viewer/display_items.tres`. A new `.glb` under `assets/models/` must be one of the two (a test checks).
- `tools/viewer_catalog.sh` prints the numbered list, so Jakob's "No. 12" maps to an id.

## Stations of an asset (proposal)

Each asset passes these stations in order. The next one starts only when Jakob approved the one before:

1. **Size:** real dimensions, judged next to a 1.80 m figure.
2. **Look:** the model with its materials, judged in the asset viewer on the device.
3. **Rules:** where it may stand, what it needs, what it does (Building rules world).
4. **Moving parts:** doors, jet bridge, barrier ..., each in its own small function world.

The asset list with Jakob's verdicts starts with his first pass through the asset viewer.

## The three parts of the game

1. **Content:** everything you see (the stations above).
2. **Game functions:** the rules of play, later the idle loop. Built on approved content.
3. **Controls:** what the player taps and where information is. Comes last (decided 2026-11-14);
   until then every control a test needs must simply be tappable.
