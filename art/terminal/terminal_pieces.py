"""Builds every terminal shell kit piece, exports one .glb per piece and renders the overview.

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/terminal/terminal_pieces.py
(run terminal_textures.py first if the textures are missing)
Writes assets/models/terminal/<piece>.glb, art/terminal/terminal_pieces.blend and
art/previews/terminal/terminal_pieces.png, and prints the budget table (triangles, materials).
Materials are exported by name only (no images): Godot replaces them with the shared
assets/materials/<name>.tres on import (art_direction §4).
"""
import math
import os
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "landside"))
import terminal_kit as T  # noqa: E402
import landside_pieces as P  # noqa: E402  (scene / render / export helpers)

MODELS = os.path.join(T.K.ROOT, "assets", "models", "terminal")
PREVIEWS = os.path.join(T.K.ROOT, "art", "previews", "terminal")
BLEND = os.path.join(HERE, "terminal_pieces.blend")

# Overview: (piece, x, y, z, rot_x_deg, rot_z_deg). Facades in the back row, flat pieces in front.
LAYOUT = [
    ("terminal_facade_glass", -21, 0, 0, 0, 0),
    ("terminal_facade_door", -7, 0, 0, 0, 0),
    ("terminal_canopy", -7, 0, 0, 0, 0),
    ("terminal_door_sign_1", -1, -13, 1.2, 0, 0),
    ("terminal_facade_closed", 7, 0, 0, 0, 0),
    ("terminal_corner_outer", 12, -12, 0, 0, 0),
    ("terminal_facade_glass", 21, 0, 0, 0, 0),
    ("terminal_corner_inner", 15, -12, 0, 0, 180),
    ("terminal_floor_bay", -21, -22, 0, 0, 0),
    ("terminal_ceiling_bay", -7, -22, T.CEIL_Z, 180, 0),      # flipped: slats face up
    ("terminal_roof_bay", 7, -22, -T.ROOF_Z, 0, 0),           # lowered to the ground
    ("terminal_join", 21, -22, -T.ROOF_Z, 0, 0),
    ("terminal_column", 21, -18, 0, 0, 0),
    ("terminal_fire_cabinet", 24, -16, 0, 0, 0),
    ("terminal_exit_sign", 26, -16, 2.0, 0, 0),
]
LABELS = [("glass", -21, -1.5), ("door + canopy", -7, -11.5), ("closed", 7, -1.5),
          ("glass", 21, -1.5), ("corners", 13.5, -14), ("door sign", -1, -15), ("floor", -21, -29.5), ("ceiling (flipped)", -7, -29.5),
          ("roof", 7, -29.5), ("join, column, props", 21, -29.5)]


def main() -> None:
    scene = P.setup_scene()
    mats = T.make_materials()
    os.makedirs(MODELS, exist_ok=True)
    lib = bpy.data.collections.new("pieces")
    scene.collection.children.link(lib)
    lib.hide_render = True
    objs_by = {}
    print(f"{'piece':28s} {'LOD0 tris':>9s} {'far tris':>8s}  materials")
    for p in T.all_pieces():
        objs = T.build_objects(p, mats, lib)
        objs_by[p.name] = objs
        P.export_glb(objs, p.name)
        mat_names = sorted({m.name for o in objs for m in o.data.materials})
        print(f"{p.name:28s} {p.lod0.tris():9d} {p.far.tris():8d}  {len(mat_names)} {','.join(mat_names)}")
    # Overview render: linked duplicates of LOD0.
    lay = bpy.data.collections.new("overview")
    scene.collection.children.link(lay)
    for name, x, y, z, rx, rz in LAYOUT:
        for o in objs_by[name]:
            if o.name.endswith("_lodfar"):
                continue
            d = bpy.data.objects.new(o.name + "_ov", o.data)
            d.location = (x, y, z)
            d.rotation_euler = (math.radians(rx), 0, math.radians(rz))
            lay.objects.link(d)
    ground = T.K.MB()
    T.K.rect(ground, -60, -60, 60, 40, -0.01, "concrete")
    ground.build("ground", mats, lay)
    for text, x, y in LABELS:
        P.label(scene, text, x, y, 1.1, mats["metal_dark"])
    P.setup_render(scene, 48)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 30
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (3.0, -64.0, 28.0)
    cam.rotation_euler = (math.radians(66), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    os.makedirs(PREVIEWS, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
    if "--no-render" not in sys.argv:
        scene.render.filepath = os.path.join(PREVIEWS, "terminal_pieces.png")
        bpy.ops.render.render(write_still=True)


# The landside helpers export into their own folder; point them at ours.
P.MODELS = MODELS

if __name__ == "__main__":
    main()
