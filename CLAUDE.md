# AirportIdle

A free, strategic airport management game with idle elements for iPhone and iPad.
The player builds their own airport freeform on a grid and grows it from a regional field into a hub.

## Design doc first

Read `docs/game_design.md` before working on any feature. It is the source of truth for *what*
we build. If a request conflicts with the design doc, point it out instead of silently deviating.
Items marked **(open)** are undecided — ask before inventing an answer.
When a decision is made, update the design doc.

## Key decisions

- **Platforms:** iOS / iPadOS only, distributed via the App Store. No Android, no desktop release.
  The Mac is used only for development and testing.
- **Devices:** iPad is the primary device and gets the best experience; iPhone must stay fully playable.
- **Orientation:** landscape only, in both views.
- **Language:** English only.
- **Monetization:** none. No ads, no in-app purchases.
- **Realism first:** the airport must *work* like a real one (zones, flows, staff, schedules).
- **Building:** grid-based, freeform layout with predesigned, rotatable buildings.
- **Grid scale:** compressed, not 1:1. Terminal and landside stay near-realistic (cell = 2 m to start);
  airside (runways, taxiways, aprons) is scaled down so the whole airport fits on a playable map.
  The cell size must stay a single, easy-to-change value.
- **Two camera views** (a HUD button switches between them):
  - *Manager view:* fixed tilted camera that follows the manager and **never rotates**
    (like League of Legends). Do not add camera rotation. Everything except building happens here
    (walking, passengers, staff, stations, statistics); the camera must always show enough to play.
    Small pinch zoom (scroll wheel on the Mac): only the distance changes, within tight limits.
  - *Build view:* top-down / bird's-eye. All building and layout planning happens here, and only here. One-finger drag pans
    (unless a tool uses it, e.g. dragging a building or painting zones), two fingers pan and zoom;
    zoom is limited and the camera stays inside the map.
- **Simulation keeps running in the build view.** No pause for now.
- **Input (manager view):** the floating joystick only appears when one finger touches the **left half**
  of the screen. The right half stays free for tapping things. A two-finger pinch anywhere zooms and
  must never trigger the joystick. WASD / arrow keys also work for testing on the Mac.
- **Offline income:** minimal. Nothing for breaks under 36 h; after 36 h+ away, 4 h of income once.
- **Fictional world:** all airlines and airports are fictional. No real names or logos.
- **Art:** simple low-poly models.
- **Safe areas:** all UI must stay inside the safe area (notch, Dynamic Island, home indicator).
  Use `scenes/ui/safe_area_container.gd` as the root for HUD elements.

## Performance architecture (rule for every feature)

Target: smooth on older iPhones. Plan this in from the start (design doc §18).

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

- Build in small, playable steps, starting with the MVP (design doc §16).
- Update `docs/game_design.md` whenever a design decision is made.

## Folder structure

```
scenes/<feature>/     one folder per feature: <name>.tscn + <name>.gd side by side
  main/               entry point (main scene); switches between manager view and build view
  manager/            the manager (player character)
  camera/             manager_camera (tilted follow) and build_camera (top-down)
  build/              build view logic: placing buildings (preview, rotate, place / cancel)
  buildings/          building visuals: BuildingLayer draws every simulated building
  passengers/         PassengerLayer: draws passengers near the camera (one MultiMesh)
  planes/             PlaneLayer + PlaneVisual: planes taxiing in, parked, pushing back
  ground/             map ground, sized from the grid
  ui/                 HUD, view button, joystick, safe area container
scripts/autoload/     global singletons:
                        Airport       -> simulation root: grid, zones, buildings (cell size lives here)
                        SaveGame      -> autosave / load of the airport (user://savegame.json)
                        TouchGestures -> touch / mouse / trackpad -> drag, tap, pinch signals
scripts/simulation/   pure simulation data classes (no nodes, no visuals): AirportGrid, Building,
                      PassengerFlow, Passenger, Station, WalkwayNetwork, FlightSchedule, Flight
scripts/resources/    custom Resource classes (data definitions), e.g. BuildingType
data/buildings/       one BuildingType .tres per building (edit footprint, name, look in the Inspector)
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
- **After every export, press Run in Xcode.** Opening the app on the device runs the previous build.
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
  Check new `class_name`s against built-in classes.
- Autoloads are not available to scripts run with `--script`; that's why tests run as a scene
  (`tests/test_runner.tscn`). Wait one frame in a test scene's `_ready()` before adding nodes to the root.
- Containers lay out newly shown buttons one frame later: tests must `await press(...)`
  (it waits a frame), never tap a button in the same frame it became visible.
- The Mac save game lives in `~/Library/Application Support/Godot/app_userdata/AirportIdle/`.
  Test builds have a two-tap "Reset" button in the build menu.
- Changing a building's size or zone rule can make old saves invalid: such buildings are skipped
  on load (with a warning). Bump `SaveGame.FORMAT_VERSION` only if the file format itself changes.
