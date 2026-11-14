"""Assembles the example L-shaped hall from the terminal kit next to the landside start layout and
renders the previews.

Run headless (after landside_preview.py has written art/landside/landside_preview.blend):
  BPY=$(tools/setup_blender.sh) && "$BPY" art/terminal/terminal_preview.py [--only top,outside,...]
Writes art/terminal/terminal_preview.blend and art/previews/terminal/terminal_{top,outside,inside}.png.

The hall: 72 × 36 m main hall (x 26..98, y 74..110) + 24 × 24 m extension (x 98..122, y 74..98),
on the 12 m column grid. Door 1 is the bay x 38..50 (centre x 44 = the landside zebra line),
door 2 is the first extension bay. `assemble()` is the reference for the code lane (kit.md).
"""
import math
import os
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terminal_kit as T  # noqa: E402

ROOT = T.K.ROOT
LANDSIDE_BLEND = os.path.join(ROOT, "art", "landside", "landside_preview.blend")
BLEND = os.path.join(HERE, "terminal_preview.blend")
PREVIEWS = os.path.join(ROOT, "art", "previews", "terminal")
X0, Y0 = 26.0, 74.0

# Bays (i, j) in 12 m units from (X0, Y0) -> hall part (an extension is a part of its own).
BAYS = {(i, j): "main" for i in range(6) for j in range(3)}
BAYS.update({(i, j): "ext" for i in (6, 7) for j in (0, 1)})
# Facade per open bay side; everything else is glass.
FACADE = {(1, 0, "s"): "door", (6, 0, "s"): "door",
          (0, 0, "w"): "closed", (0, 2, "w"): "closed", (7, 0, "e"): "closed", (7, 1, "e"): "closed"}
DOOR_NUMBERS = {(1, 0, "s"): 1, (6, 0, "s"): 2}
SIDES = {"s": ((0, -1), 0), "e": ((1, 0), 90), "n": ((0, 1), 180), "w": ((-1, 0), -90)}


def assemble() -> list:
    """(piece, x, y, rot_deg) for the whole shell. Bay pieces are never rotated (slat direction)."""
    out = []
    for (i, j), part in BAYS.items():
        cx, cy = X0 + T.BAY * (i + 0.5), Y0 + T.BAY * (j + 0.5)
        for piece in ("terminal_floor_bay", "terminal_ceiling_bay", "terminal_roof_bay"):
            out.append((piece, cx, cy, 0))
        for side, ((dx, dy), rot) in SIDES.items():
            ex, ey = cx + dx * T.H, cy + dy * T.H
            nb = BAYS.get((i + dx, j + dy))
            if nb is None:
                kind = FACADE.get((i, j, side), "glass")
                out.append((f"terminal_facade_{kind}", ex, ey, rot))
                if side == "s" and j == 0:                       # landside front: canopy
                    out.append(("terminal_canopy", ex, ey, rot))
                    if (i, j, side) in DOOR_NUMBERS:
                        out.append((f"terminal_door_sign_{DOOR_NUMBERS[(i, j, side)]}", ex, ey - 9.2,
                                    rot))
            elif nb != part and side in ("e", "n"):              # one join per shared edge
                out.append(("terminal_join", ex, ey, rot))
    # Grid points: column (inset towards the hall) and corner pieces.
    pts = {(i + a, j + b) for (i, j) in BAYS for a in (0, 1) for b in (0, 1)}
    for gi, gj in sorted(pts):
        quads = {(qx, qy): (gi + (0 if qx > 0 else -1), gj + (0 if qy > 0 else -1)) in BAYS
                 for qx in (-1, 1) for qy in (-1, 1)}
        present = [q for q, v in quads.items() if v]
        sx = sum(q[0] for q in present)
        sy = sum(q[1] for q in present)
        inset = (T.COLUMN_INSET * (sx > 0) - T.COLUMN_INSET * (sx < 0),
                 T.COLUMN_INSET * (sy > 0) - T.COLUMN_INSET * (sy < 0))
        x, y = X0 + T.BAY * gi, Y0 + T.BAY * gj
        out.append(("terminal_column", x + inset[0], y + inset[1], 0))
        if len(present) == 1:
            rot = {(1, 1): 0, (-1, 1): 90, (-1, -1): 180, (1, -1): -90}[present[0]]
            out.append(("terminal_corner_outer", x, y, rot))
        elif len(present) == 3:
            missing = next(q for q, v in quads.items() if not v)
            rot = {(-1, -1): 0, (1, -1): 90, (1, 1): 180, (-1, 1): -90}[missing]
            out.append(("terminal_corner_inner", x, y, rot))
    return out


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=LANDSIDE_BLEND)
    scene = bpy.context.scene
    for name in ("terminal_placeholder", "terminal_outline"):
        o = bpy.data.objects.get(name)
        if o:
            bpy.data.objects.remove(o)
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o)
    existing = {n: bpy.data.materials[n] for n in ("concrete", "metal_dark", "metal_light", "glass")}
    mats = T.make_materials(existing)
    lib = bpy.data.collections.new("terminal_library")
    meshes = {}
    for p in T.all_pieces():
        meshes[p.name] = [o.data for o in T.build_objects(p, mats, lib) if not o.name.endswith("_lodfar")]
    hall = bpy.data.collections.new("terminal_hall")
    scene.collection.children.link(hall)
    roofs = []
    for name, x, y, rot in assemble():
        for mesh in meshes[name]:
            o = bpy.data.objects.new(mesh.name + "_inst", mesh)
            z = T.CANOPY_Z if name.startswith("terminal_door_sign") else 0.0
            o.location = (x, y, z)
            o.rotation_euler = (0, 0, math.radians(rot))
            hall.objects.link(o)
            if name in ("terminal_roof_bay", "terminal_ceiling_bay", "terminal_join"):
                roofs.append(o)
    # People for scale (meshes from the landside preview's dummies).
    people = sorted(m.name for m in bpy.data.meshes if m.name.startswith("dummy_person"))
    spots = [(40.0, 88.0, 20), (41.0, 88.6, 200), (52.0, 95.0, 90), (60.0, 84.0, 0), (33.0, 79.0, 180),
             (70.0, 92.0, 270), (46.5, 80.5, 95), (43.2, 77.0, 90), (55.0, 101.0, 0), (36.0, 72.0, 0),
             (47.0, 70.5, 180), (52.5, 72.8, 90)]
    for k, (x, y, h) in enumerate(spots):
        o = bpy.data.objects.new("person", bpy.data.meshes[people[k % len(people)]])
        o.location = (x, y, T.FLOOR_Z)
        o.rotation_euler = (0, 0, math.radians(h - 90))
        hall.objects.link(o)

    def camera(name, loc, target=None, ortho=None, lens=24.0):
        cd = bpy.data.cameras.new(name)
        cd.clip_end = 2000.0
        if ortho:
            cd.type = "ORTHO"
            cd.ortho_scale = ortho
        else:
            cd.lens = lens
        cam = bpy.data.objects.new(name, cd)
        cam.location = loc
        if target:
            d = [t - l for t, l in zip(target, loc)]
            cam.rotation_euler = (math.pi / 2 + math.atan2(d[2], math.hypot(d[0], d[1])), 0.0,
                                  math.atan2(d[1], d[0]) - math.pi / 2)
        scene.collection.objects.link(cam)
        return cam

    eye = T.FLOOR_Z + 1.7
    cams = {
        "top": camera("cam_top", (74.0, 88.0, 300.0), ortho=128.0),
        "outside": camera("cam_outside", (53.0, 68.4, eye), target=(43.0, 74.5, 3.2), lens=20.0),
        "inside": camera("cam_inside", (33.0, 103.0, eye), target=(46.0, 74.0, 3.2), lens=20.0),
    }
    os.makedirs(PREVIEWS, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else list(cams)
    for key in only:
        for o in roofs:                       # top view: roof and ceiling cut away
            o.hide_render = key == "top"
        scene.camera = cams[key]
        scene.render.filepath = os.path.join(PREVIEWS, f"terminal_{key}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


if __name__ == "__main__":
    main()
