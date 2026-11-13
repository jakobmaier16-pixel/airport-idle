# art/

Blender sources for 3D assets: `art/<area>/` holds the Python script (bpy) and the `.blend`.
Godot ignores this folder (`.gdignore`); it never imports `.blend` files, so no machine needs Blender
to open the project. Exported `.glb` files go to `assets/models/<area>/` and are what the game uses.
Preview renders live in `art/previews/<task>/`.

Headless Blender: `BPY=$(tools/setup_blender.sh) && "$BPY" art/<area>/<script>.py`
Look and budgets: `docs/art_direction.md`. Role: `.claude/agents/artist.md`.
