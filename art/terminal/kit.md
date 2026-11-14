# Terminal shell kit

Modular shell for player-drawn terminal halls (game_design §8.0): halls are drawn on a **12 m column
grid (6 × 6 cells per bay)**, any rectangle, L-shape or extension; the shell is assembled
automatically from these pieces. Cool Nordic, quiet realism, one floor.

Built by `terminal_kit.py` (geometry + materials), exported by `terminal_pieces.py`, assembled in
`terminal_preview.py` (its `assemble()` is the reference algorithm for the code lane, issue #41).
Textures: `terminal_textures.py`. Exports: `assets/models/terminal/<piece>.glb`.

## Conventions

- Same as the landside kit (`art/landside/pieces.md`): real metres, 1 cell = 2 m, +Z up in Blender
  (+Y up in the .glb), front / outside = -Y, rotate in 90° steps. Each .glb holds `<piece>` (LOD0)
  and, where the build view needs it, `<piece>_lodfar`.
- Heights: hall floor **z 0.15** (= terminal sidewalk, barrier-free), ceiling **10 m** (clear height),
  roof **12 m**, parapet / attic band **12.4 m**. Doors 2.5 m clear, service door 2.25 m.
- Facade boundary line = the bay edge. Glass sits 0.1 m outside it, mullions -0.25..+0.05 m,
  attic band and corner posts 0.3 m outside it. Hall pieces never cross the boundary line inward
  except the wind lobby (4.5 m) and interior trims (≤ 0.1 m).

## Pieces

| Piece | Kind / footprint | Origin | LOD0 tris | far tris | Materials |
|---|---|---|---|---|---|
| `terminal_floor_bay` | bay 6 × 6 cells | bay centre, ground | 16 | 2 | terrazzo_dark, metal_light, metal_dark |
| `terminal_ceiling_bay` | bay 6 × 6 | bay centre | 296 | — (hidden) | wood_oak, metal_dark, metal_light, emissive_lights |
| `terminal_roof_bay` | bay 6 × 6 | bay centre | 22 | 2 | concrete, metal_dark, metal_light |
| `terminal_column` | grid point | point, ground | 98 | — (hidden) | wood_oak, metal_dark |
| `terminal_facade_glass` | edge, 6 cells | edge middle, ground | 106 | 4 | glass, metal_dark |
| `terminal_facade_closed` | edge, 6 cells | edge middle | 166 | 4 | metal_dark, metal_light, concrete, emissive_lights |
| `terminal_facade_door` | edge, 6 cells (+ 4.5 m lobby inside) | edge middle | 326 | 4 | glass, metal_dark, metal_light, emissive_lights |
| `terminal_corner_outer` | grid point | point | 6 | 6 | metal_dark |
| `terminal_corner_inner` | grid point | point | 6 | — | metal_dark |
| `terminal_join` | edge, 6 cells | edge middle | 14 | 2 | metal_dark, metal_light |
| `terminal_canopy` | edge, 6 × 5 cells outside | edge middle | 134 | 2 | metal_light, metal_dark, emissive_lights |
| `terminal_door_sign_1` … `_8` | prop | hanger top | 28 | — | emissive_lights, metal_dark |
| `terminal_exit_sign` | prop | wall plane, sign bottom | 10 | — | emissive_lights |
| `terminal_fire_cabinet` | prop | wall plane, floor | 14 | — | metal_light, metal_dark, emissive_lights |

Example L-hall (72 × 36 m + 24 × 24 m, 22 bays, 34 columns, 22 facades, 8 canopies):
**14.9 k tris LOD0** (shell alone 13.8 k; budget ≤ 20 k), **226 tris far** (≤ 1 k), ~19 tris per cell.
Textures: terrazzo_dark and wood_oak 1024² (albedo + ORM), emissive_lights 512² (albedo + emission).

What the pieces contain:
- **floor:** terrazzo (1 m tiles baked in the 4 m texture), stainless movement joints on the -X and
  -Y bay edges only (each bay owns two edges, so joints never double), one cleaning drain.
- **ceiling:** dark backing at 10 m, 20 oak slats (0.25 m, 0.6 m pitch, along X), two linear lights
  (y = ±3, continuous across bays), linear air diffuser, 8 pendant sprinklers, 2 sign hanging points
  (drop rods at x = ±1.5, y = -1.8, rod end at z 9.4: the code lane hangs wayfinding there).
- **roof:** roof surface, roof drain, smoke-vent hatch.
- **column:** Ø 0.6 m, vertical-grain oak cladding, steel base shoe + base plate, steel head ring.
- **facade_glass:** mullions every 2 m, transoms at 3.3 / 6.65 m, plinth, skirting, attic band,
  dark ceiling header inside. The mullions on the bay borders are half mullions (two neighbours make
  one), so runs join without seams or z-fighting.
- **facade_closed:** anthracite panels 2 × 2.4 m with 2 cm joints, steel service door with handle and
  concrete step outside, concrete wall inside, exit sign over the door, fire cabinet + sign.
- **facade_door:** 4 m entrance, automatic sliding doors (2 × 1.25 m leaves, 2.5 m clear), operator
  box with radar sensor, flush threshold; **wind lobby** 4 m wide × 4.5 m deep (glass sides, roof with
  downlights, inner door set, entrance grid mat, exit sign over the inner doors).
- **canopy:** deck at 6 m (soffit), 10 m cantilever from the facade line = 6.5 m sidewalk + 3.5 m
  curbside lane, front fascia with lip, 2 tension rods to the attic band, back brackets, gutter at
  the facade + downpipe (at x = -5.75) into a drain shoe, 6 recessed downlights.

## Assembly rules (code lane)

Hall = a set of bays (i, j) on the 12 m grid; every bay knows its hall part (the original hall or
an extension). Positions below are in world metres, bay (i, j) spans x0 + 12 i … +12, y0 + 12 j … +12.

1. **Every bay:** `floor_bay`, `ceiling_bay`, `roof_bay` at the bay centre, **rotation 0 always**
   (the slat direction and the floor joint edges must stay the same everywhere).
2. **Every bay side:** neighbour bay missing → a facade on that edge, the player's choice
   (`glass` default, `closed`, `door`). Rotation by outside direction: -Y 0°, +X 90°, +Y 180°,
   -X -90° (piece origin = middle of the edge).
   Neighbour present but of another hall part → `terminal_join` (once per shared edge).
   Neighbour of the same part → nothing.
3. **Every grid point touching the hall:** count the four surrounding quadrants that are hall.
   - 4 → `terminal_column` at the point.
   - 1 → `terminal_corner_outer`, rotated so the hall quadrant is local +X+Y
     (hall at +X+Y 0°, -X+Y 90°, -X-Y 180°, +X-Y -90°).
   - 3 → `terminal_corner_inner`, rotated so the missing quadrant is local -X-Y
     (missing -X-Y 0°, +X-Y 90°, +X+Y 180°, -X+Y -90°).
   - 2 adjacent → straight wall, no corner piece. 2 diagonal → not allowed when drawing (or treat as
     two outer corners; the posts overlap cleanly).
   - Columns on the perimeter (counts 1-3) are **inset 0.6 m** towards the hall:
     `inset = 0.6 × sign(sum of the present quadrant directions)` per axis (inner corner: diagonally
     away from the missing quadrant). This keeps them behind the glass.
4. **Canopy:** on facade edges facing the landside curb (and wherever the player wants it), same
   origin and rotation as the facade. It lines up with the landside kit: facade line at y = 74 in the
   start layout, canopy front at y = 64 = 0.5 m into the curbside lane, over the full 6.5 m sidewalk.
5. **Door number:** `terminal_door_sign_<n>` under the canopy in front of a `facade_door`: local
   offset (0, -9.2, 6.0) from the edge origin, same rotation. Door 1 of the start layout = the bay
   x 38..50 (centre x 44, in line with the zebra and the car-park walkway).
6. Props for later stations: `terminal_exit_sign` (above every emergency exit / service door; the
   facades already carry their own), `terminal_fire_cabinet` (every ~25 m of walking distance, on
   columns or closed walls).

## In-game settings (Godot)

- Materials are exported by name and replaced by `assets/materials/<name>.tres`
  (new: `terrazzo_dark`, `wood_oak`, `emissive_lights`). `emissive_lights` is an atlas
  (`terminal_textures.py` → `ATLAS`): warm/cool light, exit sign, fire sign (unlit), door numbers.
  DayNight raises its `emission_energy_multiplier` at dusk; exit signs are always lit in reality,
  so a day value of ~1 is right.
- **MultiMesh** per hall: floor, ceiling, roof, column, glass facade, corner posts and canopies
  repeat many times (one MultiMesh per piece type and hall; ~10 draw calls for a whole hall).
- **Build view:** show `floor_bay_lodfar`, `roof_bay_lodfar`, `facade_*_lodfar`, `corner_outer_lodfar`,
  `join_lodfar`, `canopy_lodfar`; hide ceilings, columns, inner corners, signs and props. When the
  player edits a hall, hide the roof (and its lodfar) so the column grid shows (see `terminal_top.png`).
- **Manager view:** LOD0 only for the bays in the manager's area; `visibility_range_end` ~80 m for
  the props (signs, cabinets); the shell itself stays as long as the area is loaded. Ceilings and wind-lobby roofs: `cast_shadow = off` (they never see the sun).
- Glass stays alpha-blended (art_direction §4); one big pane per bay keeps the sorting cheap.
- Interior light: `LightmapGI` bake once halls exist (art_direction §5); UV2 is not in the export
  yet (Godot can generate it on import: `meshes/light_baking = Static Lightmaps`).

## Deviations / open points

- `trim_building` (art_direction §4) does not exist yet; small details (vents, door frames, grilles)
  are geometry in `metal_light` / `metal_dark` instead. Signs use the `emissive_lights` atlas, also
  for the unlit red fire sign (one shared sign atlas instead of a new material).
- Roof surface uses `concrete` (light, reads well from the build view; its baked 5 m joints look like
  roof pavers). A dedicated roof membrane material can come later.
- Mullion pitch 2 m (task: 1.5-2 m): it lands on the cell grid. Sliding doors instead of a revolving
  door (step-free, cheaper, common in Nordic regional terminals).
- Facade-only "end" pieces are not needed: a facade run always ends at a corner post or continues.
