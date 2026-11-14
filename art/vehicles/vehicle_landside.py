"""Vehicle previews in the approved landside start layout.

Run headless (after art/landside/landside_preview.py has written its .blend):
  BPY=$(tools/setup_blender.sh) && "$BPY" art/vehicles/vehicle_landside.py [--only landside,taxirank,top]

Opens art/landside/landside_preview.blend, swaps the placeholder dummy cars for the vehicle kit
(linked duplicates = one mesh per type, colour per object, like MultiMesh instances in Godot) and
renders into art/previews/vehicles/ (1280 × 720, Cycles):
  vehicles_landside.png  eye level at the curb by the zebra, looking west to the Kiss & Fly: van and
                         estate dropping off, through traffic, parked cars across the road
  vehicles_taxirank.png  eye level at the taxi rank
  vehicles_psign.png     driver's view on the west leg: German "P" sign (Zeichen 314) before the car park
  vehicles_top.png       top-down over the car park as in the build view: LOD0 west of the walkway,
                         `_lodfar` east of it
The landside .blend itself is not changed (saved as art/vehicles/vehicle_landside.blend).
"""
import math
import os
import random
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "landside"))
import vehicle_kit as V  # noqa: E402
import vehicle_pieces as VP  # noqa: E402
import landside_kit as K  # noqa: E402

SRC = os.path.join(HERE, "..", "landside", "landside_preview.blend")
BLEND = os.path.join(HERE, "vehicle_landside.blend")
PREVIEWS = VP.PREVIEWS

bpy.ops.wm.open_mainfile(filepath=SRC)
scene = bpy.context.scene
for o in [o for o in bpy.data.objects if o.name.startswith("prop_car")]:
    bpy.data.objects.remove(o)
layout = bpy.data.collections["layout"]
# The parking sign became the real German Zeichen 314 (0.6 m) after this .blend was saved: swap it in.
_sign = K.sign_parking().lod0.build("sign_parking_z314", {m: bpy.data.materials[m] for m in ("markings", "metal_light")},
                                    bpy.data.collections.new("sign_library"))
for o in [o for o in layout.objects if o.name.startswith("sign_parking")]:
    o.data = _sign.data
lib = bpy.data.collections.new("vehicle_library")
mats = VP.make_materials()
cars = VP.build_all(mats, lib)                      # not linked to the scene: library only
count: dict = {}


def car(kind: str, x: float, y: float, rot: float, colour: str | None = None, far: bool = False,
        lights: float = 0.0) -> None:
    """rot: heading in degrees, 0 = nose towards -Y (the model's own forward)."""
    src = cars[kind][1 if far else 0]
    count[kind] = count.get(kind, 0) + 1
    o = bpy.data.objects.new(f"veh_{kind}{'_far' if far else ''}.{count[kind]:03d}", src.data)
    o.location = (x, y, 0.0)
    o.rotation_euler = (0, 0, math.radians(rot + 180.0))          # the models point their nose to +Y
    VP.set_paint(o, kind, colour, lights)
    layout.objects.link(o)


rng = random.Random(7)
PAINT_NAMES = [p[0] for p in V.PAINTS]
PAINT_W = [p[3] for p in V.PAINTS]
KINDS, KIND_W = ["car_small", "car_estate", "car_suv", "van"], [36, 26, 32, 6]


def random_car() -> tuple:
    return rng.choices(KINDS, KIND_W)[0], rng.choices(PAINT_NAMES, PAINT_W)[0]


# --- Car park: 8 modules × 2 rows, bays 2.5 × 5 m along Y on both sides of a 6 m aisle ----------------
WALK_X = 44
for row_y in (28, 44):
    for mx in (27, 37, 51, 61, 71, 81, 91, 101):
        for j in range(4):
            bx = mx - 5 + 1.25 + 2.5 * j
            for side in (-1, 1):
                if rng.random() < 0.62:
                    kind, colour = random_car()
                    by = row_y + side * 5.5
                    nose_out = rng.random() < 0.88                # most drive in forwards
                    rot = (0 if side < 0 else 180) if nose_out else (180 if side < 0 else 0)
                    car(kind, bx + rng.uniform(-0.12, 0.12), by + rng.uniform(-0.15, 0.15),
                        rot + rng.uniform(-2.5, 2.5), colour, far=mx > WALK_X)

# --- Curb: van and an estate in the Kiss & Fly pockets, taxis at the rank, traffic -----------------
KF = (28, 65)
for i, (kind, colour) in ((0, ("van", None)), (2, ("car_estate", "white"))):
    cx, cy, h = K.kf_car_pose(i, 2.5)
    car(kind, KF[0] + cx, KF[1] + cy, h + 90, colour)
for x in (99.4, 105.4, 111.4):
    car("car_taxi", x, 66.2, 90)
car("car_suv", 64.0, 58.25, 90, "anthracite", lights=0.5)          # through traffic, DRL on
car("car_small", 79.0, 61.75, 90, "dark_red", lights=0.5)
car("car_estate", 28.0, 58.25, 90, "blue_grey", lights=0.5)
car("car_estate", 10.5, 35.5, 270, "silver", lights=0.5)          # leaving through the exit
car("car_small", 2.25, 46.0, 180, "white", lights=0.5)             # west leg, northbound
car("car_estate", 70.0, 2.25, 90, "black", lights=0.5)             # country road
car("car_suv", 30.0, 5.75, 270, "blue_grey", lights=0.5)

# Build-view labels on the aisle of the south row.
lab = K.flat("label_white", "#E6E6E2", 0.6)
for text, x in (("LOD0", 31.5), ("_lodfar", 61.0)):
    cu = bpy.data.curves.new("lab", "FONT")
    cu.body = text
    cu.size = 1.6
    cu.align_x = "CENTER"
    o = bpy.data.objects.new("label_" + text, cu)
    o.location = (x, 27.3, 0.02)
    o.data.materials.append(lab)
    layout.objects.link(o)


CURB_CAM = (45.5, 69.2, 0.15 + 1.7)      # terminal side of the zebra, at the curb


def camera(name: str, loc: tuple, target: tuple | None = None, lens: float = 24.0,
           ortho: float | None = None):
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
    "landside": camera("cam_veh_landside", CURB_CAM, (24.0, 64.0, 0.5), lens=28.0),
    "taxirank": camera("cam_veh_taxirank", (118.5, 71.2, 0.15 + 1.7), (96.0, 64.5, 0.7), lens=28.0),
    "top": camera("cam_veh_top", (46.0, 36.0, 200.0), ortho=50.0),
    "psign": camera("cam_veh_psign", (2.2, 9.0, 1.3), (9.0, 24.0, 1.6), lens=30.0),
}
# Scale dummies standing right in front of the curb camera would hide the cars: leave them out here.
for o in [o for o in layout.objects if o.name.startswith("prop_person")]:
    if math.dist(o.location[:2], CURB_CAM[:2]) < 9.0:
        o.hide_render = True
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
os.makedirs(PREVIEWS, exist_ok=True)
scene.cycles.samples = 40
only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else list(cams)
for name in only:
    scene.camera = cams[name]
    scene.render.filepath = os.path.join(PREVIEWS, f"vehicles_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)
