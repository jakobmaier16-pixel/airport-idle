# AirportIdle

A 3D idle game about running an airport.

## Key decisions

- **Engine:** Godot 4.7, GDScript only, **Mobile** renderer, Jolt Physics.
- **Platforms:** iPhone and iPad only, distributed via the App Store. No Android, no desktop release.
  The Mac is used only for development and testing.
- **Orientation:** portrait only.
- **Camera:** follows the player character from a fixed tilted angle and **never rotates**
  (like League of Legends). Do not add camera rotation.
- **Input:** a floating on-screen joystick that appears wherever the player touches the screen
  (one-thumb play). WASD and the arrow keys also work for testing on the Mac.
- **Safe areas:** all UI must stay inside the iPhone safe area (notch, Dynamic Island, home indicator).
  Use `scenes/ui/safe_area_container.gd` as the root for HUD elements.
- **Godot binary:** `/Applications/Godot.app/Contents/MacOS/Godot`

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
- Do not commit the `.godot/` folder or export builds.
