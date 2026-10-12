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
- **Language:** English only.
- **Monetization:** none. No ads, no in-app purchases.
- **Realism first:** the airport must work like a real one (zones, flows, staff, schedules).
- **Building:** grid-based, freeform layout with predesigned, rotatable buildings.
- **Two camera views:**
  - *Manager view:* fixed tilted camera that follows the manager and **never rotates**
    (like League of Legends). Do not add camera rotation.
  - *Build view:* top-down / bird's-eye, used for all building and planning.
- **Offline income:** minimal. Nothing for breaks under 36 h; after 36 h+ away, 4 h of income once.
- **Fictional world:** all airlines and airports are fictional. No real names or logos.
- **Art:** simple low-poly models. Performance on older iPhones matters (instancing, LOD, few lights).
- **Orientation:** portrait only.
- **Input (manager view):** a floating on-screen joystick that appears wherever the player touches
  the screen (one-thumb play). WASD and the arrow keys also work for testing on the Mac.
- **Safe areas:** all UI must stay inside the iPhone safe area (notch, Dynamic Island, home indicator).
  Use `scenes/ui/safe_area_container.gd` as the root for HUD elements.

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
  main/               game world, entry point (main scene)
  player/             player character
  camera/             follow camera
  ui/                 HUD, joystick, menus
scripts/autoload/     global singletons (save game, economy, ...)
scripts/resources/    custom Resource classes (data definitions)
assets/               models/, textures/, materials/, audio/, fonts/
```

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

- Before every commit, check that the project loads without errors:
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120
  ```
  The output must contain no `ERROR` or `SCRIPT ERROR` lines.
- Make small, focused commits with descriptive messages.
- Do not commit the `.godot/` folder or export builds. **Do** commit the `*.uid` files next to
  scripts and shaders; Godot uses them to keep references stable.

## Gotchas

- When writing `.tscn` files by hand, a node that sets a Node-typed `@export` (e.g. `target`)
  must list it in its header: `node_paths=PackedStringArray("target")`. Otherwise the
  reference silently stays `null`.
- Godot 4.7 has a built-in `VirtualJoystick` class; our joystick is `TouchJoystick`.
  Check new `class_name`s against built-in classes.
