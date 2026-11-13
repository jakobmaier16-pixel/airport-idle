# AirportIdle

A free, realistic airport builder and management game for iPhone and iPad.
The player builds and runs their own airport on one map and grows it from a regional field into a hub.
The airport is the game; idle mechanics support it, they never replace it.

## Design doc first

Read `docs/game_design.md` before working on any feature. It is the source of truth. Items marked
**(open)** or **(proposal)** are not yet decided, so ask first.
If a request conflicts with the design doc, point it out instead of silently deviating.
When a decision is made, update the design doc.

- `docs/master_plan.md`: how we build the app: phases and gates, the day-to-day workflow,
  the parking lot for later ideas, and the decision log.
- `docs/tech_architecture.md`: how the game is built (brain / windows / hands, saving, performance
  budget, testing). Read it before any technical work.
- `docs/prototype_reference.md`: what the current prototype does today, with all its numbers and
  rules. Not the final design. Code comments that cite "design doc §N" use this file's section numbers.

## Key decisions

- **Platforms:** iOS / iPadOS, distributed via the App Store. Android is not a focus now (revisit
  later if easy); no desktop release. The Mac is used only for development and testing.
- **Devices:** iPhone and iPad are both main devices and must both play well.
- **Orientation:** landscape only, in both views.
- **Language:** English only. No multiplayer, no multiple airports.
- **Monetization:** none. No ads, no in-app purchases.
- **Realism first:** the airport must *work* like a real one (zones, flows, staff, schedules).
- **Building:** grid-based, freeform layout with predesigned, rotatable buildings.
- **Zones:** automatic from the buildings; the security building is the landside / airside border.
  Zones are never painted: `ZoneMap` computes them after every layout change and after load.
- **Grid scale:** compressed, not 1:1. Terminal and landside stay near-realistic (cell = 2 m to start);
  airside (runways, taxiways, aprons) is scaled down so the whole airport fits on a playable map.
  The cell size must stay a single, easy-to-change value.
- **Two camera views** (a HUD button switches between them):
  - *Manager view:* **first person** (changed 2026-10-13, was a fixed tilted camera): the player
    sees what the manager sees, from eye height, and looks around by dragging on the right half.
    Here the player enjoys the airport, walks around, and inspects and upgrades stations and staff.
    No zoom; the build view gives the overview. Incident handling here is parked until much later.
  - *Build view:* top-down / bird's-eye. Understand the airport and its passenger flow, read
    statistics, and plan the layout: all building happens here, and only here. One-finger drag pans
    (unless a tool uses it, e.g. dragging a building or painting walkways), two fingers pan and zoom;
    zoom is limited and the camera stays inside the map.
- **Simulation keeps running in the build view.** No pause for now.
- **Input (manager view):** every finger is its own gesture (`TouchGestures.independent_drags`).
  A drag starting on the **left half** is the floating joystick (walk relative to the view); a drag
  on the **right half** looks around; a short touch anywhere is a tap (opens the station under it).
  Both thumbs work at once. WASD / arrow keys and mouse-drag look also work for testing on the Mac.
- **Offline income:** minimal. Nothing for breaks under 36 h; after 36 h+ away, 4 h of income once
  ("income" = average profit per minute over the last ~10 min of play).
- **Saving:** automatic after every change, when the app goes to the background, and a 30 s safety
  save. Every save stores a timestamp (for offline income).
- **Time:** 1 real second = 15 game seconds (a game day is 96 real minutes); a new airport opens at
  06:00 on day 1 and the clock runs all 24 hours.
- **Fictional world:** all airlines and airports are fictional. No real names or logos.
- **Art:** realistic look within the iPhone budget (decided 2026-11-13): few shared PBR materials / trim sheets, baked light, LOD, MultiMesh for repeated furniture, ASTC textures; a look-probe on the device comes first.
- **Safe areas:** all UI must stay inside the safe area (notch, Dynamic Island, home indicator).
  Use `scenes/ui/safe_area_container.gd` as the root for HUD elements.

## Performance architecture (rule for every feature)

Target: smooth on older iPhones. Plan this in from the start (design doc §16).

1. **Simulation and visuals are strictly separate.** The simulation (passengers, stations, money,
   queues) is pure data for the whole airport and runs at all times. Simulation code must not use
   nodes, meshes or anything visual, and must never depend on what is on screen.
2. **Visuals only exist where the camera can see them.** In the manager view, only passengers and
   objects near the camera get 3D figures and animations; everything else is data only.
3. **Use Godot's built-in tools:** frustum culling, visibility ranges (`visibility_range_*`) and LOD
   for buildings and objects; MultiMesh / instancing for crowds.
4. **Build view:** zoom is limited; when zoomed out, crowds are simplified (fewer figures, simple shapes).
5. **Fixed simulation step:** the simulation ticks at 10 Hz (`Airport.SIM_STEP`), not per frame.
   Visuals smooth between steps with `Airport.sim_alpha`. Avoid reference cycles between
   RefCounted simulation objects (they leak); point to the Building instead of the Station.

## Tools

- **Godot 4.7** (GDScript only, **Mobile** renderer, Jolt Physics).
  Binary: `/Applications/Godot.app/Contents/MacOS/Godot`
- **VS Code** with Claude Code for writing code
- **Xcode** for the iOS export
- **Blender** for 3D models

## Working rules

- Build in small, playable steps, starting with the MVP (design doc §15). Order, phases and gates:
  `docs/master_plan.md`.
- Update `docs/game_design.md` whenever a design decision is made.

## Folder structure

```
scenes/<feature>/     one folder per feature: <name>.tscn + <name>.gd side by side
  main/               entry point (main scene); switches between manager view and build view
  manager/            the manager (player character)
  camera/             manager_camera (first person) and build_camera (top-down)
  build/              build view logic: placing buildings (preview, rotate, place / cancel)
  buildings/          building visuals: BuildingLayer draws every simulated building
  passengers/         PassengerLayer: draws passengers near the camera (one MultiMesh)
  planes/             PlaneLayer + PlaneVisual: planes taxiing in, parked, pushing back
  day_night/          DayNight: sun and ambient light by the time of day
  ground/             map ground, sized from the grid
  ui/                 HUD, view button, joystick, safe area container, AirlinesPanel, StarRating
scripts/autoload/     global singletons:
                        Airport       -> thin host (airport_host.gd): owns the AirportWorld brain
                                         (scripts/simulation/airport_brain.gd), steps it, forwards x and signals
                        SaveGame      -> autosave / load of the airport (user://savegame.json)
                        TouchGestures -> touch / mouse / trackpad -> drag, tap, pinch signals
scripts/simulation/   pure simulation data classes (no nodes, no visuals): AirportGrid, Building,
                      PassengerFlow, Passenger, Station, WalkwayNetwork, FlightSchedule, Flight,
                      Economy, Employee, Satisfaction, Reputation, Airlines (+ Airline, AirlineOffer),
                      Progression (tiers), Goals, Clock, Seasons.
                      Advance everything with `Airport.step(delta)`.
scripts/resources/    custom Resource classes (data definitions), e.g. BuildingType
data/buildings/       one BuildingType .tres per building (edit footprint, name, look in the Inspector)
data/passengers/      one PassengerType .tres per passenger type (families, low-cost, business)
data/airlines/        one AirlineType .tres per fictional airline, plus catalog.tres
tests/                automated walkthrough tests (excluded from the app export):
  test_case.gd        base class with player helpers (tap, drag, pinch, place, paint, sim_seconds)
  cases/              test files, run in name order
scripts/dev/          testing aids that ship in debug builds: ShowcaseAirport, BuildStamp
tools/                run_tests.sh, screenshots.sh, export_ios.sh
assets/               models/, textures/, materials/, audio/, fonts/
```

## Input

All touch input goes through the `TouchGestures` autoload; never read raw touch events elsewhere.
UI controls (buttons) consume their touches first, so taps on buttons never reach the map.

## Coding rules

- All code, comments, node names and commit messages are written in **English**.
- Use static typing everywhere: `var speed: float = 5.0`, `func move(dir: Vector2) -> void:`.
- Naming: `snake_case` for files, folders, variables and functions; `PascalCase` for
  `class_name`s and node names; `UPPER_SNAKE_CASE` for constants.
- One script per scene, stored next to the scene file.
- Expose tunable values with `@export` so they can be edited in the inspector.
- Prefer signals and exported node references over long hard-coded node paths between systems.
- Read player input through Input Map actions (`move_left`, `move_right`, `move_up`, `move_down`),
  never through raw key codes.
- Keep mobile performance in mind: avoid per-frame allocations, keep draw calls and lights low.
- Comments explain *why*, not *what*. The user is a Godot beginner, so a short note on
  non-obvious Godot concepts is welcome.

## Workflow

- **Always run the walkthrough tests before every commit and every export:** `tools/run_tests.sh`.
  All tests must pass (exit code 0); engine errors and memory leaks count as failures.
  Gate commits on the script's own exit code (`tools/run_tests.sh && git commit ...`), never on a
  pipe like `run_tests.sh | tail`, which hides failures. Tests must not depend on luck: check
  behaviour over a time span, not at a single random moment.
  `tools/export_ios.sh` runs them itself and refuses to export on a failure.
- **Every new feature or bug fix gets tests** in `tests/cases/` (one file per area, `test_*` methods).
  Test like a player: tap / drag / pinch the real UI through the `TestCase` helpers, and
  fast-forward the simulation with `sim_seconds()`. `test_09_walkthrough` builds a whole airport
  by touch; extend it when the core loop grows (e.g. planes, money).
- **After visual changes** run `tools/screenshots.sh` and look at `build/screenshots/*.png`.
- **Showcase airport** (`scripts/dev/showcase_airport.gd`): test builds open with it on the first
  start after every new export, so the user never has to build by hand to try an update.
  **Every new feature must be added to the showcase** (a test checks every building type is in it).
  The tests and screenshots use the same layout. The "Demo" button (debug builds) reloads it.
- **Randomness is seeded** (tech_architecture.md §3): simulation code rolls only `Airport.rng`
  (shared with PassengerFlow, FlightSchedule and Airlines), never the global
  `randf()` / `randi()`. Purely visual effects (e.g. lightning flashes) may use the global ones.
  Every test runs with a fixed seed from its name; a failure prints a replay line
  (`tools/run_tests.sh --only=<test> --seed=<n>`). `--seed=<n>` runs every test with that seed:
  try a few to catch tests that only pass by luck.
- Tests run with `-- --no-save` and never touch the real save game.
- Make small, focused commits with descriptive messages.
- Do not commit the `.godot/` folder or export builds. **Do** commit the `*.uid` files next to
  scripts and shaders; Godot uses them to keep references stable.

## iOS export

- Export templates for 4.7.2 live in `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.
  They must match the Godot version exactly; reinstall when Godot is updated.
- Preset "iOS" in `export_presets.cfg` (committed). It exports an **Xcode project only**
  (`application/export_project_only=true`); signing and installing happen in Xcode.
- Export with `tools/export_ios.sh` (into `build/ios/`, ignored by Git). It also writes
  `build_info.gd` (ignored by Git), whose stamp (commit + time) the HUD shows at the top of the screen.
- **Before every export, remind the user to quit Xcode (Cmd+Q).** The export replaces the Xcode
  project; if Xcode has it open, it shows a "workspace file has disappeared" warning.
- **After every export, tell the user to reopen `build/ios/AirportIdle.xcodeproj` and press Run.**
  Opening the app on the device runs the previous build.
  If the HUD stamp doesn't match the export, the device is running a stale build.
- `build/.gdignore` keeps Godot from scanning (and packing) the previous export; without it the
  next export fails with "Can't open file from path 'res://build/ios/...'" errors.
- Signing: free Apple ID (Personal Team `X62T6HGHTT`), automatic signing,
  bundle id `com.jakobmaier.airportidle.dev` (`com.jakobmaier.airportidle` was not available).
  Both are set in the preset, so no team selection is needed in Xcode after an export.
  Free-account builds expire after 7 days; re-run from Xcode to renew.
- `application/app_store_team_id` must not be empty (Godot refuses to export).
- **Expected:** Xcode shows a signing error for the **Release** configuration (it uses
  "Apple Distribution", which a free account can't create). Ignore it until the paid Apple Developer
  Program is joined; Debug builds to a device work.
- iOS needs `rendering/textures/vram_compression/import_etc2_astc=true` (already set).
- Minimum hardware: A12 chip (Godot requirement), iOS 15.

## Gotchas

- When writing `.tscn` files by hand, a node that sets a Node-typed `@export` (e.g. `target`)
  must list it in its header: `node_paths=PackedStringArray("target")`. Otherwise the
  reference silently stays `null`.
- Godot 4.7 has a built-in `VirtualJoystick` class; our joystick is `TouchJoystick`.
  Check new `class_name`s against built-in classes. Method names can clash too: a method called
  `sign()` is shadowed by the global math function inside its own class ("Too many arguments").
- `"%s" % some_array` treats the array as the argument list; wrap it: `"%s" % [some_array]`.
- Packed arrays (`PackedFloat32Array` etc.) are values, not references: one read out of a
  Dictionary or Array is a copy, so `(dict["x"] as PackedFloat32Array).append(v)` changes nothing.
  Keep growing lists in plain `Array`s there (they are shared), or write the packed array back.
- The default font has no ★ or → glyphs (stars are drawn by `StarRating`); check new symbols
  with `ThemeDB.fallback_font.has_char()`.
- Autoloads are not available to scripts run with `--script`; that's why tests run as a scene
  (`tests/test_runner.tscn`). Wait one frame in a test scene's `_ready()` before adding nodes to the root.
- GDScript lambdas capture local variables **by value**: `var hit := false; var f := func(): hit = true`
  never changes the outer `hit`. In tests, count inside plain loops, or use an Array/Dictionary
  (those are shared by reference). A check on a value a lambda "set" proves nothing.
- Containers lay out newly shown buttons one frame later: tests must `await press(...)`
  (it waits a frame), never tap a button in the same frame it became visible.
- The Mac save game lives in `~/Library/Application Support/Godot/app_userdata/AirportIdle/`.
  Test builds have a two-tap "Reset" button in the build menu.
- **Saves must keep loading** (tech_architecture.md §13). `tests/saves/` holds example saves as
  players have them: never regenerate or edit them. When the save format changes, add a converter
  to `SaveGame.migrations`, bump `SaveGame.FORMAT_VERSION`, and add an example save of the new
  version next to the old ones. Enums stored as numbers in saves (`AirportGrid.Zone`,
  `BuildingType.Role`, `Progression.Tier`) only get new values at the end.
  A save that can't be loaded is put aside as a `.bak` file, never overwritten.
- Changing a building's size or zone rule can make old saves invalid: such buildings are skipped
  on load (with a warning). Bump `SaveGame.FORMAT_VERSION` only if the file format itself changes.

## Working with agents

- Roles: the **lead** (Claude in the claude.ai chat) plans from `docs/roadmap.md`, writes a spec per
  task and merges; **builder**, **artist**, **reviewer** and **performance** agents are defined in `.claude/agents/`.
  The user decides design questions and tests on the devices.
- One task = one branch (`task/<name>`) = one pull request. Nothing goes to `main` directly.
- **Two lanes:** the code lane (builder; label `code`) and the visual lane (artist; label `visual`).
  **Visual PRs are merged only by Jakob; code PRs by the lead.**
- `art/<area>/` = Blender sources (script + .blend, ignored by Godot); `assets/models/<area>/` = exported `.glb`
  that the game uses. Blender headless: `tools/setup_blender.sh`.
- **GitHub Actions** (`.github/workflows/tests.yml`) runs the full suite on every pull request;
  a red check is never merged.
- **Tests outside the Mac:** `GODOT=$(tools/setup_cloud.sh) TESTS_QUIET=1 tools/run_tests.sh`.
  Agents run only the tests they touch (`--only=`) and leave the full run to GitHub Actions.
- Keep agent output short to save tokens: quiet test runs, read only the files a task needs.
