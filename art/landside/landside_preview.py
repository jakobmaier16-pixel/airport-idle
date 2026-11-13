"""Preview scene: the approved landside start layout, assembled from the start-kit pieces.

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/landside/landside_preview.py [--only top,eye]
Needs the textures (art/ground/*, art/landside/landside_textures.py). Writes
art/landside/landside_preview.blend and renders (1280 × 720, Cycles) into art/previews/landside/:
  landside_top.png      top-down, whole layout
  landside_eye.png      eye level (1.7 m) on the terminal sidewalk, looking east along the curb
  landside_busstop.png  eye level at the bus bay: shelter, bus, recessed curb
  landside_carpark.png  eye level at the barrier gate, looking into the car park
  landside_walkway.png  pedestrian route: car park walkway -> fence gate -> zebra -> terminal door

World axes (metres, 1 cell = 2 m): +X east, +Y north. Country road along y 0..8; one-way loop up the
west leg (x 0..8), east along the terminal curb, down the east leg (x 136..144). Car park
x 16..112, y 20..52, fenced, gate from the west leg, pedestrian exit + walkway at x 42..46. The terminal (y >= 74) is a placeholder box with two doors, not modelled.
Cars, bus and people are scale dummies from preview_props/.
"""
import math
import os
import random
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "preview_props"))
import landside_kit as K  # noqa: E402
import landside_pieces as P  # noqa: E402  (scene / render helpers; its main() only runs as a script)
import preview_props as PP  # noqa: E402

PREVIEWS = os.path.join(K.ROOT, "art", "previews", "landside")
BLEND = os.path.join(HERE, "landside_preview.blend")

scene = P.setup_scene()
mats = K.make_materials()
mats.update(PP.make_materials())
mats["placeholder"] = K.flat("terminal_placeholder", "#B4B8BB", 0.8)
mats["door"] = K.flat("terminal_door", "#2E3236", 0.3)

# One mesh per piece, placed as linked duplicates (they share the mesh, like instances in Godot).
pieces = {p.name: p for p in K.all_pieces()}
meshes: dict = {}
lib = bpy.data.collections.new("piece_library")      # originals, not rendered
for name, p in pieces.items():
    objs = K.build_objects(p, mats, lib)
    meshes[name] = [(o.data, o.name.endswith("_markings")) for o in objs if not o.name.endswith("_lodfar")]
layout = bpy.data.collections.new("layout")
scene.collection.children.link(layout)
count = {}


def place(name: str, x: float, y: float, rot: float = 0.0, z: float = 0.0) -> None:
    count[name] = count.get(name, 0) + 1
    for mesh, is_mark in meshes[name]:
        o = bpy.data.objects.new(f"{mesh.name}.{count[name]:03d}", mesh)
        o.location = (x, y, z)
        o.rotation_euler = (0.0, 0.0, math.radians(rot))
        o.visible_shadow = not is_mark
        layout.objects.link(o)


# --- Roads --------------------------------------------------------------------------------------
place("road_country_tjunction", 4, 8)                       # loop entry (west)
place("road_country_tjunction_giveway", 140, 8)             # loop exit (east)
for x in list(range(-36, -8, 8)) + list(range(20, 128, 8)) + list(range(156, 188, 8)):
    place("road_country_straight", x, 4)
place("road_oneway_2lane_straight", 4, 20, 90)              # west leg, northbound
place("road_oneway_2lane_access", 4, 32, 90)                # opening to the car park gate (east side)
place("road_oneway_2lane_arrows", 4, 44, 90)
for y in (20, 28, 36, 44):                                  # east leg, southbound
    place("road_oneway_2lane_arrows" if y == 36 else "road_oneway_2lane_straight", 140, y, -90)
place("road_oneway_corner", 8, 56)
place("road_oneway_corner", 136, 56, -90)

# --- Curb road along the terminal (eastbound), y 56..68 ------------------------------------------
place("curb_dropoff_segment", 28, 62)
place("zebra_crossing", 52 - 8, 62)                         # zebra x 42..46, in line with door 1
place("curb_plain_segment_arrows", 52, 62)
place("curb_plain_segment", 60, 62)
BUS_BAY = (76, 65)
place("curb_bus_bay", *BUS_BAY)
place("bus_shelter", BUS_BAY[0] + K.SHELTER_POS[0], BUS_BAY[1] + K.SHELTER_POS[1], 0, K.CURB_H)
place("curb_plain_segment", 92, 62)
place("curb_taxi_rank_4", 108, 62)
place("curb_plain_segment_arrows", 124, 62)
DOORS = (44, 108)

# --- Car park: 8 modules × 2 rows (128 bays), walkway, cross aisles, gate, fence ----------------
WALK_X = 44
for row_y in (28, 44):
    for x in (27, 37, 51, 61, 71, 81, 91, 101):
        place("carpark_module", x, row_y)
    place("carpark_walkway_end" if row_y == 28 else "carpark_walkway", WALK_X, row_y)
    place("carpark_end_aisle", 19, row_y)
    place("carpark_end_aisle", 109, row_y)
place("carpark_barrier_gate", 12, 32)
FENCE_N = 51.9                                              # just in front of the sidewalk curb
for x in range(17, 112, 2):
    place("fence_panel_2m", x, 20)                          # south
for y in range(21, 52, 2):
    place("fence_panel_2m", 112, y, 90)                     # east
for x in range(17, 112, 2):
    if not WALK_X - 2 < x < WALK_X + 2:
        place("fence_panel_2m", x, FENCE_N, 180)            # north (towards the terminal)
place("fence_gate_pedestrian", WALK_X, FENCE_N, 180)        # pedestrian exit, in line with the zebra
for y in list(range(21, 24, 2)) + list(range(41, 52, 2)):
    place("fence_panel_2m", 16, y, -90)                     # west, open only at the vehicle gate
place("fence_post", 16, 40)
place("carpark_info_board", 13.0, 22.8, -90)                # faces drivers turning in
place("sign_parking", 9.3, 17.0)                            # P sign before the access, facing traffic
place("pay_station", WALK_X + 3.3, 53.4, -90, K.CURB_H)     # beside the pedestrian exit

# --- Street furniture -----------------------------------------------------------------------------
# Anti-ram bollards along the terminal curb: 1.5 m apart, 0.75 m behind the curb face, with a gap
# centred on the zebra; none along the bus stand (boarding edge), they follow the bay tapers.
bx0, by0 = BUS_BAY
entry_x0, entry_x1 = bx0 - 12, bx0 - 12 + K.BAY_ENTRY
exit_x0, exit_x1 = bx0 + 12 - K.BAY_EXIT, bx0 + 12
x = WALK_X + 0.75 - 1.5 * 19
while x < 128:
    if entry_x0 <= x <= entry_x1:
        cy = 67.5 + (x - entry_x0) / K.BAY_ENTRY * K.BAY_RECESS
    elif exit_x0 <= x <= exit_x1:
        cy = 67.5 + (exit_x1 - x) / K.BAY_EXIT * K.BAY_RECESS
    elif entry_x1 < x < exit_x0:
        x += 1.5
        continue
    else:
        cy = 67.5
    place("bollard", x, cy + 0.75, 0, K.CURB_H)
    x += 1.5
for x in (24, 62, 96, 124):                                 # street lights, car-park sidewalk
    place("light_mast", x, 55.3, 0, K.CURB_H)
for x in (30, 64, 98):                                      # car park, outside the south fence
    place("light_mast", x, 19.0)
place("light_mast", 113.0, 36.0)
place("light_mast", WALK_X + 1.5, 22.5, 0, K.CURB_H)        # on the walkway islands
place("light_mast", WALK_X + 1.5, 49.5, 0, K.CURB_H)

# --- Sidewalk tiles (auto curbs: a curb stone wherever the neighbour is not raised) --------------
tiles = set()
for x in range(16, 128, 2):                     # car-park sidewalk, y 52..56
    for y in (52, 54):
        tiles.add((x, y))
for x in range(0, 144, 2):                      # terminal sidewalk, y 68..74
    for y in (68, 70, 72):
        if not 64 <= x < 88:                    # the bus bay piece brings its own sidewalk
            tiles.add((x, y))
for x in list(range(0, 16, 2)) + list(range(128, 144, 2)):
    for y in (64, 66):                          # above the corners
        tiles.add((x, y))
lowered = {(WALK_X - 2, 54), (WALK_X, 54)}      # car-park side of the zebra: one 4 m lowered piece
landing = {(WALK_X - 2, 68), (WALK_X, 68)}      # terminal side: tactile landing
raised = set(tiles)
raised |= {(x, y) for x in range(64, 88, 2) for y in (68, 70, 72)}   # bus bay sidewalk
raised |= {(x, 74) for x in range(20, 124, 2)}                       # terminal
raised |= {(WALK_X - 2, 50), (WALK_X, 50)}                            # walkway island


def open_sides(x: int, y: int) -> str:
    s = ""
    for side, (dx, dy) in (("s", (0, -2)), ("e", (2, 0)), ("n", (0, 2)), ("w", (-2, 0))):
        if (x + dx, y + dy) in raised:
            continue
        if side == "s" and y == 68 and 16 <= x < 128:
            continue                            # the curb pieces' raised strip continues here
        s += side
    return s


EDGE_ROT = {"s": 0, "e": 90, "n": 180, "w": -90}
CORNER_ROT = {"sw": 0, "se": 90, "ne": 180, "nw": -90}
for (x, y) in sorted(tiles - lowered - landing):
    s = open_sides(x, y)
    cx, cy = x + 1, y + 1
    if not s:
        place("sidewalk_tile", cx, cy)
    elif len(s) == 1:
        place("sidewalk_edge", cx, cy, EDGE_ROT[s])
    else:
        key = {"se": "se", "sw": "sw", "en": "ne", "nw": "nw"}[s]
        place("sidewalk_corner", cx, cy, CORNER_ROT[key])
place("sidewalk_edge_lowered_4m", WALK_X, 55, 180)
place("sidewalk_tactile_landing", WALK_X, 69)

# --- Grass and terminal placeholder --------------------------------------------------------------
extra = K.MB()
K.rect(extra, -120, -80, 260, 200, -0.01, "grass")
extra.build("preview_grass", mats, layout)
term = K.MB()
K.box(term, 20, 74, 0.0, 124, 104, 12.0, "placeholder")
for dx in DOORS:                                # two door positions (4 m wide, 2.2 m high)
    term.face([(dx - 2, 73.98, K.CURB_H), (dx + 2, 73.98, K.CURB_H), (dx + 2, 73.98, 2.35),
               (dx - 2, 73.98, 2.35)], [(0, 0)] * 4, "door")
term.build("terminal_placeholder", mats, layout)
outline = K.MB()
K.line(outline, [(20, 74.15), (124, 74.15)], 0.2, "short_dash", 2.0, 0.0, z=K.CURB_H)
outline.build("terminal_outline", mats, layout).visible_shadow = False

# --- Scale dummies -------------------------------------------------------------------------------
prop_meshes = {}
for colour in PP.CAR_COLOURS:
    prop_meshes[colour] = PP.car(colour).build("dummy_" + colour, mats, lib).data
prop_meshes["bus"] = PP.bus().build("dummy_bus", mats, lib).data
for coat in PP.PERSON_COLOURS:
    prop_meshes[coat] = PP.person(coat).build("dummy_" + coat, mats, lib).data


def prop(kind: str, x: float, y: float, rot: float = 0.0, z: float = 0.0) -> None:
    o = bpy.data.objects.new("prop_" + kind, prop_meshes[kind])
    o.location = (x, y, z)
    o.rotation_euler = (0, 0, math.radians(rot))
    layout.objects.link(o)


rng = random.Random(7)
colours = ["car_silver", "car_anthracite", "car_ivory"]
for row_y in (28, 44):
    for mx in (27, 37, 51, 61, 71, 81, 91, 101):
        for j in range(4):
            bx = mx - 5 + 1.25 + 2.5 * j
            for side in (-1, 1):
                if rng.random() < 0.62:
                    by = row_y + side * 5.5
                    prop(rng.choice(colours), bx + rng.uniform(-0.1, 0.1), by + rng.uniform(-0.2, 0.2),
                         90 if side < 0 else -90)
for x, c in ((25.0, "car_silver"), (37.0, "car_anthracite")):       # Kiss & Fly (bays 2 and 4)
    prop(c, x, 66.2)
for x in (99.2, 105.2, 111.2):                                       # taxis
    prop("car_ivory", x, 66.2)
prop("bus", BUS_BAY[0] + K.BUS_POS[0], BUS_BAY[1] + K.BUS_POS[1])
prop("car_anthracite", 64.0, 58.25)                                  # through traffic
prop("car_silver", 10.5, 35.5, 180)                                  # leaving through the exit
prop("car_silver", 2.25, 46.0, 90)                                   # west leg
prop("car_anthracite", 70.0, 2.25)                                   # country road, eastbound
prop("car_silver", 30.0, 5.75, 180)                                  # westbound
coats = list(PP.PERSON_COLOURS)
people = [  # (x, y, z, heading): along the route car park -> walkway -> zebra -> door 1, and at the stops
    (44.0, 30.5, 0.15, 90), (43.6, 40.0, 0.15, 90), (44.3, 53.8, 0.15, 90), (43.7, 60.5, 0.0, 90),
    (44.8, 71.0, 0.15, 95), (30.5, 70.2, 0.15, 180), (26.0, 68.4, 0.15, 270), (76.0, 70.0, 0.15, 270),
    (78.3, 70.1, 0.15, 250), (102.0, 69.2, 0.15, 0), (36.0, 72.6, 0.15, 10),
]
for i, (x, y, z, h) in enumerate(people):
    prop(coats[i % len(coats)], x, y, h - 90, z)


# --- Render ---------------------------------------------------------------------------------------
P.setup_render(scene, 32)


def camera(name: str, loc: tuple, target: tuple | None = None, ortho: float | None = None,
           lens: float = 24.0) -> bpy.types.Object:
    cam_data = bpy.data.cameras.new(name)
    cam_data.clip_end = 2000.0
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        cam_data.lens = lens
    cam = bpy.data.objects.new(name, cam_data)
    cam.location = loc
    if target:
        d = [t - l for t, l in zip(target, loc)]
        yaw = math.atan2(d[1], d[0]) - math.pi / 2
        pitch = math.atan2(d[2], math.hypot(d[0], d[1]))
        cam.rotation_euler = (math.pi / 2 + pitch, 0.0, yaw)
    scene.collection.objects.link(cam)
    return cam


cams = {
    "landside_top": camera("cam_top", (72.0, 50.0, 300.0), ortho=190.0),
    "landside_eye": camera("cam_eye", (18.0, 69.8, 0.15 + 1.7), target=(90.0, 66.0, 1.1), lens=30.0),
    "landside_busstop": camera("cam_busstop", (87.0, 72.8, 0.15 + 1.7), target=(75.0, 70.0, 1.0), lens=24.0),
    "landside_carpark": camera("cam_carpark", (8.8, 27.4, 1.7), target=(40.0, 33.0, 0.4), lens=22.0),
    "landside_walkway": camera("cam_walkway", (44.0, 31.0, 0.15 + 1.7), target=(44.0, 74.0, 1.6), lens=24.0),
}
os.makedirs(PREVIEWS, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else list(cams)
for name in only:
    key = name if name.startswith("landside_") else "landside_" + name
    scene.camera = cams[key]
    scene.render.filepath = os.path.join(PREVIEWS, f"{key}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)
