"""Builds the five vehicle types, exports one .glb per type, prints the budget table and renders
the studio previews.

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/vehicles/vehicle_pieces.py [--no-render] [--only lineup,front34]
Needs the atlas first (art/vehicles/vehicle_textures.py).

Writes:
  assets/models/vehicles/<type>.glb    objects <type> (LOD0) and <type>_lodfar (build view)
  art/vehicles/vehicle_pieces.blend    the studio scenes
  art/previews/vehicles/vehicles_{lineup,front34,rear34,colours}.png  (Cycles)

Materials are exported by name only: `vehicle` (assets/materials/vehicle.tres, ShaderMaterial,
paint from the MultiMesh instance colour) and the shared `glass`.
"""
import math
import os
import sys

import bpy
import bmesh  # noqa: I100  (only importable after bpy in the pip build)

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "landside"))
import vehicle_kit as V  # noqa: E402
import landside_kit as K  # noqa: E402
import landside_pieces as LP  # noqa: E402  (scene / render setup shared with the landside previews)

MODELS = os.path.join(K.ROOT, "assets", "models", "vehicles")
PREVIEWS = os.path.join(K.ROOT, "art", "previews", "vehicles")
TEX = os.path.join(K.ROOT, "assets", "textures", "vehicle")
BLEND = os.path.join(HERE, "vehicle_pieces.blend")


# --- Materials (mirror assets/materials/vehicle.tres and glass.tres) ------------------------------
def vehicle_material() -> bpy.types.Material:
    """Preview twin of vehicle.gdshader: albedo × mix(1, paint, mask); paint = object colour
    (= MultiMesh instance colour in Godot), its alpha = metallic flake; emission × 'lights_on'."""
    if "vehicle" in bpy.data.materials:
        return bpy.data.materials["vehicle"]
    mat = bpy.data.materials.new("vehicle")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    alb = nodes.new("ShaderNodeTexImage")
    alb.image = bpy.data.images.load(os.path.join(TEX, "vehicle_albedo.png"), check_existing=True)
    alb.image.alpha_mode = "CHANNEL_PACKED"
    rme = nodes.new("ShaderNodeTexImage")
    rme.image = bpy.data.images.load(os.path.join(TEX, "vehicle_rme.png"), check_existing=True)
    rme.image.colorspace_settings.name = "Non-Color"
    for t in (alb, rme):
        t.interpolation = "Linear"
    info = nodes.new("ShaderNodeObjectInfo")
    paint = nodes.new("ShaderNodeMix")
    paint.data_type = "RGBA"
    paint.inputs[6].default_value = (1, 1, 1, 1)
    links.new(alb.outputs["Alpha"], paint.inputs["Factor"])
    links.new(info.outputs["Color"], paint.inputs[7])
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(alb.outputs["Color"], mul.inputs[6])
    links.new(paint.outputs[2], mul.inputs[7])
    links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    sep = nodes.new("ShaderNodeSeparateColor")
    links.new(rme.outputs["Color"], sep.inputs["Color"])
    links.new(sep.outputs["Red"], bsdf.inputs["Roughness"])
    flake = nodes.new("ShaderNodeMath")
    flake.operation = "MULTIPLY"
    links.new(alb.outputs["Alpha"], flake.inputs[0])
    links.new(info.outputs["Alpha"], flake.inputs[1])
    flake2 = nodes.new("ShaderNodeMath")
    flake2.operation = "MULTIPLY_ADD"
    flake2.inputs[1].default_value = 0.5
    links.new(flake.outputs[0], flake2.inputs[0])
    links.new(sep.outputs["Green"], flake2.inputs[2])
    links.new(flake2.outputs[0], bsdf.inputs["Metallic"])
    lights = nodes.new("ShaderNodeAttribute")
    lights.attribute_type = "OBJECT"
    lights.attribute_name = "lights_on"
    em = nodes.new("ShaderNodeMath")
    em.operation = "MULTIPLY"
    links.new(sep.outputs["Blue"], em.inputs[0])
    links.new(lights.outputs["Fac"], em.inputs[1])
    em2 = nodes.new("ShaderNodeMath")
    em2.operation = "MULTIPLY"
    em2.inputs[1].default_value = 6.0
    links.new(em.outputs[0], em2.inputs[0])
    links.new(alb.outputs["Color"], bsdf.inputs["Emission Color"])
    links.new(em2.outputs[0], bsdf.inputs["Emission Strength"])
    return mat


def make_materials() -> dict:
    mats = {"vehicle": vehicle_material()}
    # Tinted car glass (glass_vehicle.tres): darker than the building glass, interiors still show.
    mats["glass_vehicle"] = bpy.data.materials.get("glass_vehicle") or K.flat("glass_vehicle", "#33434B", 0.04,
                                                                               0.0, alpha=0.55)
    return mats


def paint_for(name: str, colour: str | None = None) -> tuple:
    """(linear rgb, flake) for a type: fixed paint for taxi / van, else a PAINTS entry by name."""
    if name in V.FIXED_PAINT:
        _, h, fl = V.FIXED_PAINT[name]
    else:
        _, h, fl, _ = next(p for p in V.PAINTS if p[0] == (colour or "silver"))
    return K.hex_lin(h), fl


def set_paint(obj, name: str, colour: str | None = None, lights: float = 0.0) -> None:
    lin, fl = paint_for(name, colour)
    obj.color = (*lin, fl)
    obj["lights_on"] = lights


def smooth(obj) -> None:
    """Weld the loft (MB writes every face with its own corners), then smooth shading with hard
    edges above 40°: rounded shoulders and roofs without extra triangles."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.shade_smooth()
    obj.data.set_sharp_from_angle(angle=math.radians(40))


def build_all(mats: dict, collection=None) -> dict:
    """{type: (lod0 object, lodfar object, Car)}"""
    out = {}
    for name in V.TYPES:
        car = V.Car(name).build()
        o0 = car.lod0.build(name, mats, collection)
        o1 = car.far.build(name + "_lodfar", mats, collection)
        for o in (o0, o1):
            smooth(o)
            set_paint(o, name)
        out[name] = (o0, o1, car)
    return out


def export_glb(objs: list, name: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODELS, name + ".glb"), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="EXPORT", export_image_format="NONE",
        export_vertex_color="ACTIVE", export_normals=True, export_texcoords=True)


def instance(src, name: str, loc: tuple, rot_deg: float = 0.0, collection=None):
    """rot_deg: heading, 0 = nose towards -Y (the models themselves point their nose to +Y)."""
    o = bpy.data.objects.new(name, src.data)
    o.location = loc
    o.rotation_euler = (0, 0, math.radians(rot_deg + 180.0))
    (collection or bpy.context.scene.collection).objects.link(o)
    return o


def person(mats: dict) -> bpy.types.Object:
    """1.80 m scale figure (dark silhouette)."""
    mats.setdefault("person", K.flat("person_dark", "#3A3E44", 0.8))
    mb = K.MB()
    K.box(mb, -0.17, -0.09, 0.0, -0.03, 0.09, 0.86, "person")       # legs
    K.box(mb, 0.03, -0.09, 0.0, 0.17, 0.09, 0.86, "person")
    K.box(mb, -0.21, -0.12, 0.86, 0.21, 0.12, 1.50, "person")       # torso
    K.box(mb, -0.29, -0.06, 0.90, -0.21, 0.06, 1.46, "person")      # arms
    K.box(mb, 0.21, -0.06, 0.90, 0.29, 0.06, 1.46, "person")
    K.box(mb, -0.05, -0.05, 1.50, 0.05, 0.05, 1.57, "person")       # neck
    K.cylinder(mb, 0.0, 0.0, 1.57, 1.80, 0.105, "person", n=10)     # head, top at 1.80 m
    return mb.build("person_1m80", mats)


def label(text: str, loc: tuple, size: float, mat, rot=(math.pi / 2, 0, math.pi / 2)) -> None:
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    o = bpy.data.objects.new("label_" + text[:12], cu)
    o.location = loc
    o.rotation_euler = rot
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)


def unlit(name: str, hex_colour: str, strength: float) -> bpy.types.Material:
    """Emission-only backdrop: shows no cast shadows, so the side views stay readable."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*K.hex_lin(hex_colour), 1.0)
    em.inputs["Strength"].default_value = strength
    mat.node_tree.links.new(em.outputs[0], nodes["Material Output"].inputs["Surface"])
    return mat


def camera(name: str, loc: tuple, target: tuple, lens: float = 35.0, ortho: float | None = None):
    cam_data = bpy.data.cameras.new(name)
    cam_data.clip_end = 500.0
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        cam_data.lens = lens
    cam = bpy.data.objects.new(name, cam_data)
    cam.location = loc
    d = [t - l for t, l in zip(target, loc)]
    yaw = math.atan2(d[1], d[0]) - math.pi / 2
    pitch = math.atan2(d[2], math.hypot(d[0], d[1]))
    cam.rotation_euler = (math.pi / 2 + pitch, 0.0, yaw)
    bpy.context.scene.collection.objects.link(cam)
    return cam


def hide(obj, hidden: bool = True) -> None:
    obj.hide_render = hidden
    obj.hide_viewport = hidden


def main() -> None:
    scene = LP.setup_scene()
    mats = make_materials()
    os.makedirs(MODELS, exist_ok=True)
    lib = bpy.data.collections.new("vehicle_library")
    scene.collection.children.link(lib)
    cars = build_all(mats, lib)
    print("\nBUDGET  type | L × W × H (m) | wheelbase | tris LOD0 | tris lodfar | materials")
    for name, (o0, o1, car) in cars.items():
        export_glb([o0, o1], name)
        s = car.s
        mat_names = sorted(set(car.lod0.mat_names))
        far_mats = sorted(set(car.far.mat_names))
        print(f"BUDGET  {name} | {s['L']} × {s['W']} × {s['H']} | {s['wb']} | {car.lod0.tris()} | "
              f"{car.far.tris()} | {len(mat_names)}: {', '.join(mat_names)} / far {', '.join(far_mats)}")
        xs = [v.co.x for v in o0.data.vertices]
        ys = [v.co.y for v in o0.data.vertices]
        zs = [v.co.z for v in o0.data.vertices]
        print(f"MEASURE {name}: x {min(xs):.3f}..{max(xs):.3f}  y {min(ys):.3f}..{max(ys):.3f}  "
              f"z {min(zs):.3f}..{max(zs):.3f}")
    for o in lib.objects:
        hide(o)
    if "--no-render" in sys.argv:
        return
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    LP.setup_render(scene, 48)
    scene.render.resolution_percentage = 100
    label_mat = K.flat("label_dark", "#2E3236", 0.6)
    grid_mat = unlit("grid_line", "#8A8E92", 0.9)
    board_mat = unlit("board", "#E4E6E3", 0.9)
    floor_mat = K.flat("studio_floor", "#8E9094", 0.8)
    mats.update({"grid": grid_mat, "board": board_mat, "floor": floor_mat})
    sun = scene.objects["sun"]
    renders = {}

    # --- Lineup: side-on, same scale, 1 m grid board behind, 1.80 m person ---------------------------
    col = bpy.data.collections.new("lineup")
    scene.collection.children.link(col)
    rows = [(0.0, ["car_small", "car_estate", "car_suv"]), (3.2, ["car_taxi", "van"])]
    board = K.MB()
    y_lo, y_hi = -14.0, 14.0
    K.box(board, -3.2, y_lo, -5.0, -3.0, y_hi, 11.0, "board", sides="e")
    for zr, _ in rows:
        K.box(board, -3.0, y_lo, zr - 0.05, 3.0, y_hi, zr, "floor")
    for i in range(int(y_lo), int(y_hi) + 1):
        K.box(board, -2.99, i - 0.006, -0.05, -2.98, i + 0.006, 6.0, "grid", sides="e")
    for zi in range(0, 7):
        K.box(board, -2.99, y_lo, zi - 0.006, -2.98, y_hi, zi + 0.006, "grid", sides="e")
    board.build("lineup_board", mats, col).visible_shadow = False
    for zr, names in rows:
        y = -9.2
        for name in names:
            o0, _, car = cars[name]
            L = car.L
            inst = instance(o0, "lineup_" + name, (0.0, y + L / 2, zr), 0.0, col)
            set_paint(inst, name, "silver" if name != "car_suv" else "dark_blue")
            s = car.s
            label(f"{s['label']}: {s['L']:.2f} x {s['W']:.2f} x {s['H']:.2f} m, wheelbase {s['wb']:.2f} m",
                  (-2.95, y + L / 2, zr + 2.25 if zr == 0 else zr + 2.3), 0.22, label_mat)
            y += L + 1.2
        if zr == 0:
            p = person(mats)
            for c in p.users_collection:
                c.objects.unlink(p)
            col.objects.link(p)
            p.location = (0.0, y + 0.4, 0.0)
            p.rotation_euler = (0, 0, math.radians(90))
            label("person 1.80 m", (-2.95, y + 0.4, 2.0), 0.22, label_mat)
    renders["lineup"] = (camera("cam_lineup", (30.0, -0.4, 2.75), (0.0, -0.4, 2.75), ortho=20.0), col)

    # --- 3/4 views: two staggered rows, each car turned 35° towards the camera -------------------
    col34 = bpy.data.collections.new("three_quarter")
    scene.collection.children.link(col34)
    X0 = 100.0
    ground = K.MB()
    K.box(ground, X0 - 30, -30, -0.05, X0 + 40, 30, 0.0, "floor")
    ground.build("studio_ground", mats, col34)
    slots = [(0.0, 0.0), (3.6, 0.0), (7.2, 0.0), (1.8, 5.6), (5.6, 5.6)]   # small, estate, SUV / taxi, van
    front_objs, rear_objs = [], []
    for i, name in enumerate(V.TYPES):
        o0, _, car = cars[name]
        paint = ["white", "silver", "dark_blue", None, None][i]
        x, y = X0 + slots[i][0], slots[i][1]
        a = instance(o0, "qf_" + name, (x, y, 0.0), 35.0, col34)
        b = instance(o0, "qr_" + name, (x, y, 0.0), 215.0, col34)
        set_paint(a, name, paint)
        set_paint(b, name, paint)
        front_objs.append(a)
        rear_objs.append(b)
    mid = X0 + 3.7
    renders["front34"] = (camera("cam_front34", (mid, -17.0, 4.6), (mid, 2.4, 0.55), lens=50.0), col34)
    renders["rear34"] = (camera("cam_rear34", (mid, -17.0, 4.6), (mid, 2.4, 0.55), lens=50.0), col34)
    if "--detail" in sys.argv:
        renders["detail"] = (camera("cam_detail", (X0 - 0.4, -5.2, 1.3), (X0 + 0.3, 0.0, 0.6), lens=40.0), col34)

    # --- Colours: the estate in every paint colour, two rows ---------------------------------------
    colc = bpy.data.collections.new("colours")
    scene.collection.children.link(colc)
    X1 = 200.0
    g2 = K.MB()
    K.box(g2, X1 - 20, -20, -0.05, X1 + 40, 30, 0.0, "floor")
    g2.build("colour_ground", mats, colc)
    o0, _, car = cars["car_estate"]
    for i, (cname, _, _, wgt) in enumerate(V.PAINTS):                    # side by side in 2.5 m bays
        x = X1 + i * 2.5
        inst = instance(o0, "c_" + cname, (x, 0.0, 0.0), 0.0, colc)
        set_paint(inst, "car_estate", cname)
        label(f"{cname.replace('_', ' ')}\n{wgt} %", (x, -3.1, 0.01), 0.3, label_mat, (0, 0, 0))
    renders["colours"] = (camera("cam_colours", (X1 + 10.0, -15.5, 6.0), (X1 + 10.0, 0.0, 0.0), lens=21.0), colc)

    sun_rot = {"lineup": (math.radians(55), 0, math.radians(70)),
               "front34": (math.radians(50), 0, math.radians(-30)),
               "rear34": (math.radians(50), 0, math.radians(-30)),
               "colours": (math.radians(50), 0, math.radians(-25)),
               "detail": (math.radians(50), 0, math.radians(-30))}
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
    os.makedirs(PREVIEWS, exist_ok=True)
    for key, (cam, c) in renders.items():
        if only and key not in only:
            continue
        for other in renders.values():
            other[1].hide_render = other[1] is not c
        for o in front_objs:
            o.hide_render = key == "rear34"
        for o in rear_objs:
            o.hide_render = key in ("front34", "detail")
        sun.rotation_euler = sun_rot[key]
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEWS, f"vehicles_{key}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


if __name__ == "__main__":
    main()
