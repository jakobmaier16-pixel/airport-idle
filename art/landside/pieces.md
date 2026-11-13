# Landside start kit: pieces

Modular landside pieces for the start layout (regional airport, cool Nordic, quiet realism).
Built by `landside_kit.py` (geometry), exported by `landside_pieces.py`, assembled in
`landside_preview.py`. Exports: `assets/models/landside/<piece>.glb`.

## Conventions

- 1 cell = 2 m, real metres. Origin = ground centre of the footprint, +Z up in Blender
  (+Y up in the .glb), front = -Y. Rotate in 90° steps.
- Each .glb holds `<piece>` (LOD0), `<piece>_markings` (flat paint, if any) and `<piece>_lodfar`.
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
| `curb_dropoff_segment` | 12 × 6 | curb road ±X, 4 Kiss & Fly bays of 6 m (white) | longer curb → two levels with ramps (bigger footprint) |
| `curb_taxi_rank_4` | 12 × 6 | curb road ±X, 4 taxi bays of 6 m (yellow) | 12 bays (longer) → taxi holding area (needs free cells) |
| `zebra_crossing` | 4 × 6 | curb road ±X; 4 m zebra across all lanes; lowered curb on +Y | — |
| `curb_bus_bay` | 12 × 9 | curb road ±X **plus** 6 m terminal sidewalk; bay recessed 3 m (16 m + 4 m tapers, one 12 m bus) | second bay → bus station |
| `bus_shelter` | 3 × 1 | stands on the sidewalk (its z = 0 is the sidewalk top), open to -Y | shelter + display upgrade is the bus stop's same-footprint level |
| `sidewalk_tile` | 1 × 1 | paved, raised, no curb | — |
| `sidewalk_edge` | 1 × 1 | curb on -Y | — |
| `sidewalk_corner` | 1 × 1 | curbs on -Y and -X | — |
| `sidewalk_edge_lowered_4m` | 2 × 1 | curb on -Y lowered to 3 cm + 1 m ramp (zebra landing) | — |
| `carpark_module` | 5 × 8 | 6 m aisle along Y with 4 bays (2.5 × 5 m) each side; repeat along ±X | multi-storey garage on the same footprint |
| `carpark_end_aisle` | 3 × 8 | 6 m cross aisle that links the module aisles at the ends | same |
| `carpark_barrier_gate` | 4 × 6 | entry lane (y -6..-1, +X = in), 2 m island, exit lane (y 1..6); -X side to the road, +X side to the car park | more lanes, pay stations |

## Start layout (preview)

`landside_preview.py`: country road along y 0..8; loop up the west leg (x 0..8), east along the
terminal on the curb road (y 56..68), down the east leg (x 136..144). Curb road from west to east:
arrows, Kiss & Fly (4 bays), zebra, plain, bus bay + shelter, plain, taxi rank (4), arrows.
Car park x 16..108 × y 20..52: 8 modules × 2 rows = 128 bays, cross aisles at both ends, gate from
the west leg. Terminal (y ≥ 74) is a placeholder box with two doors (x 36 and x 108).

## Deviations from the 2D layout (grid snapping)

- Car-park sidewalk 4 m instead of 3 m (3 m is not a whole number of cells).
- Terminal sidewalk 6 m tiles + the curb road's 0.5 m raised strip = 6.5 m.
- Car park 92 × 32 m with 128 bays (8 modules of 10 m + two 6 m cross aisles); ~140 would need a
  wider lot.
- The west leg's edge line runs through across the car-park gate mouth (no road piece with an
  opening yet).
