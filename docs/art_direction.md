# Art Direction

The visual rules for AirportIdle. Every asset follows this file; the artist agent stops and asks
if something here is missing. Decided with Jakob on 2026-11-13. Change it only with his OK.

## 1. Look in one sentence

A calm, **cool Nordic** airport: anthracite and glass, dark stone floors, light wood as the one
warm contrast. **Quiet realism:** real proportions and real materials, but calm surfaces with little
texture noise, so the build view (top-down) stays readable and the iPhone stays fast.

- Real-world references for mood (not to copy): Oslo Gardermoen, Copenhagen T3, Bergen.
- Fictional world: no real logos, brands or airport names on any asset.
- Readability beats detail: from the build view a player must tell road, sidewalk, apron and
  building apart at a glance. Value contrast (light / dark) does this, not texture.

## 2. Scale

- **1 grid cell = 2 m** (landside and terminal). The value lives in one place in code; models are
  built in **real metres** around it, so a 2 × 3 building is 4 m × 6 m.
- **Airside is compressed** (runways, taxiways, aprons): their footprint follows the grid, but
  planes, vehicles and people keep real size. Never scale a person or a door to fit.
- Reference sizes: person 1.75 m, door 2.2 m high, ceiling 3.5 m (landside halls 6–8 m),
  lane width 3.5 m, curb 0.15 m, parking bay 2.5 × 5 m, bus 12 m.
- Blender: units metric, scale 1.0, **+Z up in Blender, exported as glTF +Y up** (default).
  Origin at the **ground centre of the footprint**, facing −Y in Blender (= −Z / "forward" in Godot).

## 3. Colour palette

Base values are albedo (sRGB). Keep albedo between ~0.04 (darkest) and ~0.85 (brightest):
nothing pure black or pure white, or PBR lighting looks fake.

| Role | Name | Hex |
|---|---|---|
| Facade, frames, dark metal | Anthracite | `#2E3236` |
| Panels, columns, light metal | Steel grey | `#8A9096` |
| Concrete (walls, apron) | Concrete | `#A3A39E` |
| Interior floor | Dark terrazzo | `#4A4C4E` (light chips `#9A9C9C`) |
| Warm contrast (ceilings, benches, counters) | Light oak | `#C9A57A` |
| Road | Asphalt | `#3A3B3C` |
| Grass | Nordic grass | `#5E7A48` |
| Glass tint | Glass | `#9FB6BF`, mostly transparent |
| Wayfinding, markings (road, apron) | Signal yellow | `#E8B830` |
| Road markings, zebra | Marking white | `#E6E6E2` |
| Status: problem / alert only | Signal red | `#C8382E` |

Rule: **one accent per area.** Yellow is for wayfinding and markings only; red only for warnings.
Airline colours (fictional) live on planes, counters and signs, not on the building.

## 4. Materials (shared library)

Few shared materials, reused by every asset. Each is a Godot `StandardMaterial3D` saved as
`assets/materials/<name>.tres`; models reference them by name and Godot swaps them in on import
(so one change updates every building). No per-model custom materials without the lead's OK.

| Material | Use | Maps | Notes |
|---|---|---|---|
| `concrete` | walls, curbs, apron slabs | albedo, normal, ORM | slab joints come from the mesh/UVs, not the texture |
| `terrazzo_dark` | interior floors | albedo, ORM | roughness ~0.35, subtle reflection |
| `glass` | windows, facades, railings | none (flat colour) | transparent, roughness 0.05, **no refraction**, depth draw off; few large panes |
| `metal_dark` | frames, mullions, posts | none | metallic 1, roughness 0.45, anthracite |
| `metal_light` | panels, signs, poles | none | metallic 1, roughness 0.35, steel grey |
| `asphalt` | roads, parking | albedo, normal, ORM | fine grain only |
| `grass` | verges, airfield | albedo, normal | tiled, with slight colour variation |
| `wood_oak` | ceiling slats, benches, counters | albedo, ORM | the only warm material |
| `markings` | road/apron lines, zebra, signs | trim sheet (albedo + alpha) | one atlas for all lines and symbols |
| `emissive_lights` | window glow, lamp heads, signs at night | albedo + emission | night is faked with this (see §5) |
| `trim_building` | door frames, vents, skirting, small details | trim sheet | one 1024² atlas shared by all buildings |

- **Textures:** tileable, **1024² max** (512² for small trims), compressed as **ASTC**
  (`VRAM Compressed`, mipmaps on). Normal maps flagged as normal maps on import.
- **ORM** = occlusion (R), roughness (G), metallic (B) in one texture: one sample instead of three.
- No 4K textures, no unique textures per building, no texture painting on single assets.

## 5. Light (hybrid)

The day-night cycle (`scenes/day_night/`) moves a real sun, so only what doesn't move is baked.

- **Outside:** one `DirectionalLight3D` (the sun) with shadows; shadow distance kept short in the
  manager view. Sky / ambient colour comes from DayNight.
- **Baked:** **ambient occlusion** in every model (in the `ORM` red channel or a second UV
  lightmap), and **interior light** of the terminal baked with `LightmapGI` once halls exist.
- **Night:** no extra real lights. Windows, lamp heads and signs switch to `emissive_lights`
  (DayNight raises their energy at dusk). At most **one** real `OmniLight3D` near the manager if a
  scene needs it.
- **No** real-time GI (SDFGI / VoxelGI), no screen-space reflections, no volumetric fog: the
  Mobile renderer either lacks them or they cost too much on an A12.
- Light mood: cool daylight (slightly blue sky light, neutral-white sun), warm interior lights
  (~3000 K look) at night as the contrast.

## 6. Budgets

Target: **A12 iPhone (XS / XR), 60 fps** in both views. Whole frame: ≤ **300 k triangles visible**,
≤ **250 draw calls**, ≤ **200 MB** texture memory. Per asset type (LOD0, triangles):

| Asset type | LOD0 tris | LOD1 | LOD2 / far | Materials | Textures |
|---|---|---|---|---|---|
| Ground tile / road piece (per cell) | ≤ 50 | — | — | 1 | shared only |
| Small prop (bench, bin, bollard, sign) | ≤ 500 | ≤ 150 | hidden | 1–2 | shared only |
| Furniture repeated many times (seats, counters) | ≤ 800 | ≤ 250 | hidden | 1–2 | shared; drawn as **MultiMesh** |
| Vehicle (car, bus, ground vehicle) | ≤ 3 k | ≤ 800 | ≤ 150 | 2–3 | shared + 1 × 512² livery |
| Building (per 2 × 2 m cell of footprint) | ≤ 1.5 k | ≤ 400 | box | ≤ 4 | shared only |
| Terminal hall shell (whole) | ≤ 20 k | ≤ 6 k | ≤ 1 k | ≤ 5 | shared only |
| Plane | ≤ 8 k | ≤ 2 k | ≤ 400 | 3 | shared + 1 × 1024² livery atlas |
| Person (passenger, staff) | ≤ 1.5 k | ≤ 400 | billboard / capsule | 1 | 1 × 256² atlas |

- **LOD:** Godot builds mesh LODs automatically on import; we only model LOD-far by hand where a
  box/billboard is better. Use `visibility_range_end` so small props disappear in the build view.
- **MultiMesh** for everything repeated more than ~10 times (seats, bollards, parking lines, trees).
- Every visual PR lists triangles, material count and texture sizes per asset.

## 7. Modelling rules

- Build in real metres on the 2 m grid; snap walls and edges to 0.5 m where possible.
- Low-poly with bevels baked into the normal/AO, not modelled (except big visible edges: 1 segment).
- No hidden faces (undersides, inside walls), no n-gons in the export, apply all transforms.
- UV: tileable materials use world-scale UVs (**1 UV unit = 2 m**), so textures line up across
  assets. UV2 only if the asset gets a lightmap.
- Ground pieces must tile seamlessly in all 4 rotations; road edges meet at cell borders.
- Collision: none in the model. Gameplay doesn't need it; the manager walks on the grid.

## 8. Naming and files

- Everything `snake_case`, English. Pattern: `<area>_<thing>[_<variant>]`, e.g.
  `ground_asphalt`, `road_straight_2lane`, `landside_bus_stop`, `checkin_counter_single`.
- Sources: `art/<area>/<name>.py` (bpy script, the source of truth) + `art/<area>/<name>.blend`.
- Exports: `assets/models/<area>/<name>.glb`. Materials: `assets/materials/<name>.tres`.
  Textures: `assets/textures/<material>/<material>_<map>.png` (`_albedo`, `_normal`, `_orm`, `_emission`).
- Previews: `art/previews/<task>/<name>_top.png` and `<name>_eye.png` (top-down and eye level, 1280 × 720).
- Mesh object names inside the `.blend` = file name; LOD-far meshes end in `_lodfar`.
- Area names in use: `ground`, `landside`, `terminal`, `checkin`, `security`, `gate`, `apron`,
  `planes`, `vehicles`, `people`, `props`.

## 9. Pipeline per asset (the three stages)

1. **2D layout sketch:** top-down plan on the grid with sizes. Jakob approves.
2. **3D model + previews:** bpy script → `.blend` + `.glb` + preview renders + budget table. Jakob approves.
3. **In the game:** scene / building look wired up (code-lane task if a hook is missing), screenshot
   via `tools/screenshots.sh`, then a look-check on the iPhone. Jakob approves and merges.
