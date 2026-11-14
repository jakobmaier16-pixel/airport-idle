# Vehicle kit: passenger cars, taxi, panel van

Five fictional vehicle types for car parks, the curb and the roads. Proportions come from real
vehicle classes (no brand shapes copied, no logos or badges, plain fictional plates without a
country band). Built by `vehicle_kit.py` (geometry), atlas by `vehicle_textures.py`
(layout `vehicle_atlas.py`), exported and rendered by `vehicle_pieces.py`, placed in the landside
start layout by `vehicle_landside.py`.

Rebuild: `BPY=$(tools/setup_blender.sh)`, then `"$BPY" art/vehicles/vehicle_textures.py`,
`"$BPY" art/vehicles/vehicle_pieces.py`, `"$BPY" art/vehicles/vehicle_landside.py`.

## Types and dimensions

| Type (`.glb`) | Real class | L × W × H (m) | Wheelbase | Overhang front / rear | Wheel Ø | Ground clearance |
|---|---|---|---|---|---|---|
| `car_small` | hatchback, 5 doors (Polo class) | 4.07 × 1.75 × 1.45 | 2.56 | 0.83 / 0.68 | 0.63 | 0.15 |
| `car_estate` | estate (Passat Variant class) | 4.92 × 1.85 × 1.50 | 2.84 | 1.03 / 1.05 | 0.68 | 0.15 |
| `car_suv` | compact SUV (Tiguan class) | 4.54 × 1.86 × 1.67 | 2.68 | 0.91 / 0.95 | 0.74 | 0.20 |
| `car_taxi` | executive saloon (E-class size) | 4.95 × 1.85 × 1.47 | 2.94 | 0.84 / 1.17 | 0.67 | 0.14 |
| `van` | panel van (Transporter class) | 5.05 × 1.90 × 1.99 | 3.00 | 0.95 / 1.10 | 0.69 | 0.19 |

W excludes the mirrors (as in the spec sheets; mirrors add ~0.2 m per side). H includes roof rails
(estate, SUV) and the roof vent (van); the taxi sign adds 0.15 m and the shark-fin antenna 3–6 cm.

Shape notes: modern fronts: bonnet edge 0.77–0.80 m, cowl ~1.0 m, nearly upright rounded fascia with
wide flat headlamps along the bonnet edge (wrapping into the wing), grille between, bumper with
intake and plate below. The small car has its own face: shorter bonnet, more upright, round lamps,
small grille; near-vertical hatch with a roof spoiler. Taxi roof sign 0.50 × 0.15 × 0.13 m above the
B pillar / front seats. Windscreen rake ~30° from horizontal on the cars, ~50° on the van (short bonnet, steep
screen, tall box); hatch and estate tailgates near vertical, SUV tailgate sloped (~50°), taxi
three-box with a boot deck. SUV: dark cladding on arches, sills and lower bumpers. Van: sliding door
(right, kerb side) with rail, dark bumpers with a rear step, side step, cab windows only, tall
vertical tail lamps, third brake light, roof vent.

Details on every type: tinted glass with A/B/C pillars (D on estate and SUV), headlamps with
housing, lens, LED strip and indicator, tail lamps, third brake light, reflectors / rear fog in the
bumper, shut lines (doors, bonnet, tailgate / boot), door handles, fuel flap (right side), mirrors
with indicator, wipers (rear wiper on hatch, estate, SUV), grille and intakes, plates front and
rear, exhaust (left), tyres with sidewall, rims with spokes, wheel arch liners, shark-fin antenna,
quiet road grime on the lower body. Interior silhouettes: seats with headrests, dashboard,
steering wheel, door cards, headliner, luggage cover / parcel shelf, van bulkhead.

## Files and pieces

- `assets/models/vehicles/<type>.glb` holds `<type>` (LOD0, manager view) and `<type>_lodfar`
  (build view).
- Origin = ground centre of the footprint, real metres, nose towards **-Z in Godot** (built nose
  +Y in Blender; the glTF exporter turns +Y into -Z). Wheels touch y = 0.
- Atlas: `assets/textures/vehicle/vehicle_albedo.png` (512², RGBA, A = paint mask) and
  `vehicle_rme.png` (512², R roughness, G metallic, B emission mask). VRAM compressed, mipmaps on.

## Budgets

| Type | LOD0 tris | `_lodfar` tris | Materials LOD0 | Materials far | Textures |
|---|---|---|---|---|---|
| `car_small` | 1952 | 110 | 2 (`vehicle`, `glass_vehicle`) | 1 (`vehicle`) | shared atlas 2 × 512² |
| `car_estate` | 2128 | 110 | 2 | 1 | shared |
| `car_suv` | 2100 | 110 | 2 | 1 | shared |
| `car_taxi` | 2084 | 112 | 2 | 1 | shared |
| `van` | 1686 | 86 | 2 | 1 | shared |

art_direction §6 (vehicle): LOD0 ≤ 3 k, LOD1 ≤ 800 (Godot generates it on import, `generate_lods`),
far ≤ 150 (task: ≤ 120), 2–3 materials, shared textures + one 512² set.

## Materials

- `vehicle` (`assets/materials/vehicle.tres`, ShaderMaterial, `vehicle.gdshader`): one opaque
  material for body, trim, tyres, rims, lamps, plates and interior.
  `ALBEDO = atlas.rgb × mix(1, paint, atlas.a)`, so only paint areas take the instance colour.
  Metallic flake: instance colour alpha × `flake_metallic` (0.5) on paint. Emission (lamp lenses,
  taxi sign) × `INSTANCE_CUSTOM.r` × `light_energy`.
- `glass_vehicle` (`assets/materials/glass_vehicle.tres`): tinted car glass, alpha-blended, no
  refraction, depth draw off, double-sided (like `glass`, but darker: `#33434B`, alpha 0.55).
  The shared `glass` (alpha 0.25, light blue) let the cars look empty and see-through.

## Paint colours

Instance colour = the sRGB colour below, **alpha = metallic flake** (0 solid, 1 metallic). The shader
converts sRGB to linear itself, so pass `Color("#hex", flake)` straight in. Weights are rough shares
of the European car fleet (grey / black / white lead, then silver and blue; bright colours rare);
pick with a weighted random from `Airport.rng` or a visual-only rng.

| Name | sRGB | Flake | Weight % |
|---|---|---|---|
| white | `#D8DAD8` | 0.0 | 19 |
| silver | `#A3A7AB` | 1.0 | 14 |
| black | `#232426` | 0.4 | 20 |
| anthracite | `#3D4145` | 0.8 | 21 |
| dark blue | `#1F2D47` | 0.6 | 9 |
| blue grey | `#5C6A77` | 0.6 | 6 |
| dark red | `#561618` | 0.4 | 5 |
| dark green | `#2A3C33` | 0.5 | 3 |
| beige | `#BBAE93` | 0.3 | 3 |

Fixed paints (same system, always this colour): taxi light ivory RAL 1015 `#E6D2B5` (flake 0),
van white `#D8DAD8` (flake 0). Black and white stay off pure 0 / 1 (art_direction §3).

Suggested type mix in the car park: small 36 %, estate 26 %, SUV 32 %, van 6 %.

## Godot settings (stage 3, code lane)

- **One MultiMesh per type and per LOD** (`MultiMeshInstance3D`), `transform_format = 3D`,
  `use_colors = true` (paint), `use_custom_data = true` (lamps). Mesh = the `<type>` or
  `<type>_lodfar` mesh from the .glb; materials swapped by name to `assets/materials/<name>.tres`
  as the landside layer already does.
- `set_instance_color(i, Color("#hex", flake))`; `set_instance_custom_data(i, Color(lights, 0, 0, 0))`
  with lights 0 = parked, 1 = driving (DRL / tail lamps; taxi sign lit). Parked cars stay dark at night.
- Manager view: LOD0 MultiMesh with `visibility_range_end` ≈ 120 m (fade margin 10 m), shadows on.
  Build view: only `_lodfar`, `cast_shadow` off (it is a top-down silhouette with dark glass).
- The glass surface is alpha-blended: instances inside one MultiMesh are not sorted. Overlapping
  car windows blend in buffer order; with one tint colour this is not visible in the renders.
- Heading: the nose is -Z, so `look_at(target)` / `Basis.looking_at(dir)` point the car the right way.
- Wheel rotation is not modelled separately (static parked / curb cars). Moving traffic later can
  use a separate wheel MultiMesh; ask the visual lane.
- Untested in Godot yet: the instance colour multiply on COLOR (vertex colour is white in the
  models) and INSTANCE_CUSTOM. Check both on the device in stage 3.

## Previews (`art/previews/vehicles/`)

| File | Shows |
|---|---|
| `vehicles_lineup.png` | all five side-on, same scale, 1 m grid, 1.80 m person |
| `vehicles_front34.png` / `vehicles_rear34.png` | 3/4 views: lamps, mirrors, plates, exhaust |
| `vehicles_colours.png` | the estate in all nine paint colours, with weights |
| `vehicles_landside.png` | eye level at the curb: van and estate in the Kiss & Fly, traffic, car park |
| `vehicles_taxirank.png` | eye level at the taxi rank |
| `vehicles_psign.png` | driver's view on the loop road: German "P" sign (Zeichen 314) before the car park |
| `vehicles_top.png` | car park top-down as in the build view: LOD0 west of the walkway, `_lodfar` east |
