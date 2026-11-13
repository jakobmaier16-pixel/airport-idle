# Landside start kit: pieces

Modular landside pieces for the start layout (regional airport, cool Nordic, quiet realism).
Built by `landside_kit.py` (geometry), exported by `landside_pieces.py`, assembled in
`landside_preview.py`. Exports: `assets/models/landside/<piece>.glb`.

## Conventions

- 1 cell = 2 m, real metres. Origin = ground centre of the footprint, +Z up in Blender
  (+Y up in the .glb), front = -Y. Rotate in 90° steps.
- Each .glb holds `<piece>` (LOD0), `<piece>_markings` (flat paint, if any) and `<piece>_lodfar`.
  Small props (bollard, light mast, signs, pay station, fence post) have no `_lodfar`: they are
  hidden in the build view (`visibility_range_end`, art_direction §6). Fence panels keep a flat line.
  **Godot (stage 3):** `_markings` gets `cast_shadow = off`; `_lodfar` is shown in the build view
  (visibility ranges), LOD0 in the manager view. Materials are exported by name only and replaced by
  `assets/materials/<name>.tres` on import.
- Road surface z = 0; sidewalks are raised 0.15 m behind a 0.2 m concrete curb stone; a lowered curb
  (crossings) is 0.03 m. Markings: 1 mm above their surface, from the shared markings atlas.
- Pieces sit on the grass ground plane; empty parts of a footprint show the ground.
- Broken lines are centred on each piece, so pieces line up in any rotation when their length is a
  multiple of the dash period (one-way 4 m, country road 8 m).

## Road cross-sections

| Road | Width | Layout (from -Y) |
|---|---|---|
| Country road (two-way) | 8 m piece | 0.5 m shoulder, 2 × 3.5 m lanes, broken centre line (4 m dash / 4 m gap), 0.5 m shoulder |
| One-way loop road | 8 m piece | as above, lane divider 2 m dash / 2 m gap, arrows on `_arrows` pieces |
| Curb road (terminal front) | 12 m piece | 0.5 m shoulder, 2 × 3.5 m through lanes, 3.5 m curbside lane + 0.5 m gutter, 0.5 m raised strip (curb stone + paving) |

The curb road's through lanes sit on the same 8 m band as the loop road (first 8 m from -Y), so
`road_oneway_corner` connects straight into it.

## Pieces

| Piece | Footprint (cells) | Connects | Later upgrades |
|---|---|---|---|
| `road_country_straight` | 4 × 4 | country road on ±X | more lanes, then motorway link (wider footprint) |
| `road_country_tjunction` | 12 × 8 | country road ±X; one-way road +Y (x -4..4); entry (no give-way) | junction with turn lanes / roundabout |
| `road_country_tjunction_giveway` | 12 × 8 | same; give-way line across the side road (exit) | as above |
| `road_oneway_2lane_straight` | 4 × 4 | one-way road ±X (traffic +X) | — |
| `road_oneway_2lane_arrows` | 4 × 4 | same, lane arrows | — |
| `road_oneway_corner` | 8 × 8 | -Y edge west half, +X edge north half (90° turn, radius 8–16 m) | — |
| `curb_plain_segment` | 4 × 6 | curb road ±X; terminal sidewalk on +Y; car-park sidewalk on -Y | longer curb |
| `curb_plain_segment_arrows` | 4 × 6 | same, arrows in the through lanes | — |
| `curb_dropoff_segment` | 12 × 9 | curb road ±X **plus** 6 m terminal sidewalk; 3 Kiss & Fly sawtooth pockets (8 m pitch, curb at 25°, 2.56 m into the sidewalk): every car drives in and out forwards, never blocked by the car in front; "KISS &" / "FLY" stacked in each pocket, read in driving direction | longer curb → two levels with ramps (bigger footprint) |
| `curb_taxi_rank_4` | 12 × 6 | curb road ±X, 4 taxi bays of 6 m (yellow), "TAXI" in each bay | 12 bays (longer) → taxi holding area (needs free cells) |
| `zebra_crossing` | 4 × 6 | curb road ±X; 4 m zebra across all lanes; lowered curb on +Y | — |
| `curb_bus_bay` | 12 × 9 | curb road ±X **plus** 6 m terminal sidewalk; bay recessed 1.5 m (6 m entry taper, 14 m stand, 4 m exit taper), "BUS", tactile boarding field + guide strip at the front door | second bay → bus station |
| `bus_shelter` | 3 × 1 | 5 × 1.3 m, open to -Y; placed by the bus bay at `SHELTER_POS` (1.2 m boarding strip in front, 2.5 m clear walkway behind) | shelter + display is the bus stop's same-footprint level |
| `sidewalk_tile` | 1 × 1 | paved, raised, no curb | — |
| `sidewalk_edge` | 1 × 1 | curb on -Y | — |
| `sidewalk_corner` | 1 × 1 | curbs on -Y and -X | — |
| `sidewalk_edge_lowered_4m` | 2 × 1 | curb on -Y lowered to 3 cm + 1 m ramp + tactile direction field (zebra landing, car-park side) | — |
| `sidewalk_tactile_landing` | 2 × 1 | plain sidewalk with tactile direction field on -Y (zebra landing behind the curb road's lowered strip) | — |
| `carpark_module` | 5 × 8 | 6 m aisle along Y with 4 bays (2.5 × 5 m) each side; repeat along ±X | multi-storey garage on the same footprint |
| `carpark_end_aisle` | 3 × 8 | 6 m cross aisle that links the module aisles at the ends | same |
| `carpark_walkway` / `_end` | 2 × 8 | pedestrian walkway between two modules: raised island, 2 m concrete path between 1 m grass strips (island curb = wheel stop), lowered curbs and zebra across the aisle; `_end` closes the -Y end | covered walkway in the garage |
| `carpark_barrier_gate` | 4 × 8 | entry lane (+X = in), 2 m island, exit lane with "EXIT" and a give-way line; 2 m corner radii on the -X (road) side | more lanes, pay-on-exit lanes |
| `road_oneway_2lane_access` | 8 × 4 | one-way road whose right (-Y) edge line becomes a broken junction line over 16 m: the mouth of the car park gate | — |

Why sawtooth and not 45–60° herringbone: angled bays at 45–60° need ~5.3 m of depth and are left
by reversing into the traffic lane. A drop-off curb must be left forwards, so real airports use
shallow sawtooth (echelon) pockets; the 25° angle fits into the curbside lane plus a 2.56 m recess.

### Props

| Prop | Size | Use |
|---|---|---|
| `bollard` | Ø 0.2 × 0.9 m, steel, reflective band | anti-ram line along the terminal curb: every 1.5 m (1.3 m clear), 0.75 m behind the curb face; gap centred on the zebra; none along the bus stand (boarding edge) |
| `light_mast` | 10 m, two LED heads | car park perimeter and walkway islands, street lights on the car-park sidewalk |
| `fence_panel_2m` | 2 × 2 m welded mesh + post at -X | car park fence (runs end with `fence_post`) |
| `fence_post` | 2.05 m | end / corner of a fence run |
| `fence_gate_pedestrian` | 4 m, 2 m opening | pedestrian exit in the car park fence, in line with the walkway and the zebra |
| `carpark_info_board` | 2 × 1 m face on posts | tariffs and opening hours at the car park entry (readable from -Y) |
| `sign_parking` | 0.9 m "P" on a 3 m pole | before the car park access on the loop road |
| `pay_station` | 0.7 × 0.45 × 1.8 m | pay machine next to the pedestrian exit (pay before returning to the car) |
| `sign_wayfinding` | 1.2 × 0.9 m on posts | yellow / anthracite airport wayfinding: P ←, BUS →, TAXI → |
| `tree_deciduous` | ~8 m, 172 tris | car park islands, perimeter, road verges; MultiMesh, random yaw / scale 0.6–1.2; `_lodfar` = flat crown disc |
| `hedge_2m` | 2 × 0.8 × 1.1 m | outside the south fence, along the west fence |
| `decal_oil_stain`, `decal_patch`, `decal_tyre_marks`, `decal_drain_grate` | 1.2 / 2 / 6 × 0.7 / 0.5 × 1 m | subtle wear, material `decals` (512² RGBA), flush, **cast_shadow off**; scattered per placement, hidden in the build view |

The bus stop sign on the shelter is a yellow disc with a green "H" (fictional regional style).

## Settings for the in-game stage (Godot)

**Fence (mobile, no shimmering):**
- Posts are geometry (`metal_dark`), the mesh is the `fence_mesh` atlas piece on two back-to-back quads.
- Give the fence its own material copy of `markings` with **Transparency = Alpha Scissor**
  (threshold ~0.5) and **Alpha Antialiasing = Alpha to Coverage** (keeps thin wires smooth with MSAA
  on iPhone; without MSAA use "Alpha to Coverage + Alpha Edge Blend"). Mipmaps on (the atlas
  imports with mipmaps; the wires fade to a semi-transparent tone instead of flickering).
  Alpha scissor writes depth, so no sorting problems with many panels.
- Visibility: mesh panels `visibility_range_end` ≈ 60 m with a fade (`visibility_range_fade_mode`
  = Self, margin ~10 m) in the manager view. The build view shows only `fence_*_lodfar` (flat line).
- Draw runs as a MultiMesh (one per car park).

**Other:**
- `*_markings` objects and the wear decals: `cast_shadow = off`.
- Barrier booms use the markings atlas as solid paint: alpha scissor too.
- Small props (bollards, masts, signs, pay station, decals): `visibility_range_end` ~80 m, hidden in
  the build view; bollards, fence, trees, hedges, oil stains as MultiMesh.
- `foliage` uses vertex colour (crown variation); per-instance tint via MultiMesh colour.

## Start layout (preview)

`landside_preview.py`: country road along y 0..8; loop up the west leg (x 0..8), east along the
terminal on the curb road (y 56..68), down the east leg (x 136..144). Curb road from west to east:
Kiss & Fly (4 bays), zebra, arrows, plain, bus bay + shelter, plain, taxi rank (4), arrows.
Car park x 16..112 × y 20..52, fenced: 8 modules × 2 rows = 128 bays, a walkway at x 42..46, cross
aisles at both ends, vehicle gate from the west leg (info board before it, "P" sign on the loop road).
Pedestrian route: walkway → fence gate (x 42..46) → car-park sidewalk (pay station) → zebra →
terminal door 1, all on one straight line with lowered curbs and tactile fields. Terminal (y ≥ 74) is
a placeholder box with two doors (x 44 and x 108). Bollards along the terminal curb, light masts in
and around the car park.

## Deviations from the 2D layout (grid snapping)

- Car-park sidewalk 4 m instead of 3 m (3 m is not a whole number of cells).
- Terminal sidewalk 6 m tiles + the curb road's 0.5 m raised strip = 6.5 m.
- Car park 96 × 32 m with 128 bays (8 modules of 10 m, a 4 m walkway, two 6 m cross aisles);
  ~140 would need a wider lot.
- "P" signs are white on anthracite (art_direction palette), not the blue of the German road sign.
