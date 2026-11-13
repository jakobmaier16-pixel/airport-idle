"""Builds every landside start-kit piece, exports one .glb per piece and renders the overview.

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/landside/landside_pieces.py [--no-render]
Needs the textures first (art/ground/ground_textures.py, art/ground/markings_atlas.py,
art/landside/landside_textures.py).

Writes:
  assets/models/landside/<piece>.glb   objects <piece>, <piece>_markings (if any), <piece>_lodfar
  art/landside/landside_pieces.blend   all pieces laid out side by side, labelled
  art/previews/landside/landside_pieces.png   top-down overview (1280 × 720)
  prints the budget table (triangles LOD0 / lodfar, materials) for the PR.

Materials are exported by name only (no images): Godot replaces them with the shared
assets/materials/<name>.tres on import. `<piece>_markings` must get cast_shadow = off.
"""
import math
import os
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import landside_kit as K  # noqa: E402

MODELS = os.path.join(K.ROOT, "assets", "models", "landside")
PREVIEWS = os.path.join(K.ROOT, "art", "previews", "landside")
BLEND = os.path.join(K.HERE, "landside_pieces.blend")


def setup_scene() -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    return scene


def setup_render(scene: bpy.types.Scene, samples: int = 32) -> None:
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(1.0)
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(35))  # ~40° elevation, from the south-west
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.66, 0.82, 1.0)   # cool sky light (art_direction §5)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"


def export_glb(objs: list, name: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODELS, name + ".glb"), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="EXPORT", export_image_format="NONE",
        export_vertex_color="ACTIVE", export_normals=True, export_texcoords=True)


def label(scene, text: str, x: float, y: float, size: float, mat) -> None:
    cu = bpy.data.curves.new("label_" + text, "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    obj = bpy.data.objects.new("label_" + text, cu)
    obj.location = (x, y, 0.02)
    obj.data.materials.append(mat)
    scene.collection.objects.link(obj)


# Overview layout: rows of pieces (top-down), name under each.
ROWS = [
    ["road_country_straight", "road_country_tjunction", "road_country_tjunction_giveway",
     "road_oneway_2lane_straight", "road_oneway_2lane_arrows", "road_oneway_corner"],
    ["curb_plain_segment", "curb_plain_segment_arrows", "curb_dropoff_segment", "zebra_crossing",
     "curb_taxi_rank_4", "curb_bus_bay"],
    ["carpark_module", "carpark_end_aisle", "carpark_barrier_gate", "bus_shelter", "sidewalk_tile",
     "sidewalk_edge", "sidewalk_corner", "sidewalk_edge_lowered_4m"],
]
GAP = 5.0


def main() -> None:
    scene = setup_scene()
    mats = K.make_materials()
    os.makedirs(MODELS, exist_ok=True)
    pieces = {p.name: p for p in K.all_pieces()}
    objects = {}
    print("\nBUDGET  piece | footprint (cells) | tris LOD0 (incl. markings) | tris lodfar | materials")
    for name, p in pieces.items():
        objs = K.build_objects(p, mats)
        export_glb(objs, name)
        objects[name] = objs
        cells = (p.size[0] / 2) * (p.size[1] / 2)
        t0 = p.lod0.tris() + p.marks.tris()
        mat_names = sorted(set(p.lod0.mat_names) | set(p.marks.mat_names))
        print(f"BUDGET  {name} | {int(p.size[0] / 2)}x{int(p.size[1] / 2)} | {t0} ({t0 / cells:.1f}/cell)"
              f" | {p.far.tris()} | {len(mat_names)}: {', '.join(mat_names)}")

    if "--no-render" in sys.argv:
        return
    # Lay the pieces out for the overview (lodfar hidden).
    label_mat = K.flat("label", "#E6E6E2", 0.6)
    ground = K.MB()
    y = 0.0
    row_x0 = -64.0
    for row in ROWS:
        depth = max(pieces[n].size[1] for n in row)
        x = row_x0
        for n in row:
            sx, sy = pieces[n].size
            cx, cy = x + sx / 2, y - depth / 2
            for o in objects[n]:
                o.location = (cx, cy, 0.0)
                if o.name.endswith("_lodfar"):
                    o.hide_render = True
                    o.hide_viewport = True
            short = n.replace("road_", "").replace("sidewalk_", "sw_").replace("carpark_", "cp_")
            label(scene, short, cx, y - depth - 2.6, 1.15, label_mat)
            x += max(sx, len(short) * 0.75) + GAP
        y -= depth + GAP + 3.0
    K.rect(ground, -200, -200, 200, 200, -0.01, "grass")
    ground.build("overview_grass", mats)
    setup_render(scene, 24)
    cam_data = bpy.data.cameras.new("cam_pieces")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 142.0
    cam = bpy.data.objects.new("cam_pieces", cam_data)
    cam.location = (6.0, -32.0, 200.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
    os.makedirs(PREVIEWS, exist_ok=True)
    scene.render.filepath = os.path.join(PREVIEWS, "landside_pieces.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)


if __name__ == "__main__":
    main()
