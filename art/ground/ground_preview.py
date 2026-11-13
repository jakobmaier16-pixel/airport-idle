"""Preview scene for the ground materials: rebuilds the approved layout at real scale.

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/ground/ground_preview.py
Needs the textures first (ground_textures.py, markings_atlas.py). Writes
art/ground/ground_preview.blend and renders (1280 × 720, Cycles) into art/previews/ground/:
  ground_top.png      top-down, whole layout
  ground_eye.png      eye level (1.7 m) on the apron, looking at stand 32
  ground_markings.png close top-down crop of the stand markings
  ground_crossing.png close top-down crop of the zebra crossing and the passenger path
  ground_designator.png  runway designator turned to the approach direction (pilot's reading)

World axes (metres): +X east, +Y north, +Z up. Runway 09 along X, threshold at x = -150.
Not a game asset: the plane boxes are scale dummies only. The game builds its ground in stage 3
(shader / meshes in Godot); this scene shows how the textures and atlas pieces fit together.
"""
import math
import os
import sys

import bpy
import numpy as np

sys.dont_write_bytecode = True  # no __pycache__ in art/
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import markings_layout as L  # noqa: E402
from tex_io import ROOT  # noqa: E402

PREVIEWS = os.path.join(ROOT, "art", "previews", "ground")
BLEND = os.path.join(ROOT, "art", "ground", "ground_preview.blend")
TEX = os.path.join(ROOT, "assets", "textures")
UV_PER_M = 0.5            # world-scale UVs: 1 UV unit = 2 m (docs/art_direction.md §7)
UV1_SCALE = {"grass": 0.125, "asphalt": 0.25, "concrete": 0.2}  # same as the .tres materials

# Pavements are flush with each other (z = 0); grass sits 1 cm lower. Markings are paint: no
# thickness, 0.5 mm above the pavement plus 0.5 mm per layer (max layer 2 -> 1.5 mm). Layers only
# separate overlapping pieces (coplanar overlaps render black spots in Cycles).
Z_GRASS, Z_PAVE, Z_MARK, Z_LAYER = -0.01, 0.0, 0.0005, 0.0005


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h: str) -> tuple:
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (1, 3, 5))


# --- Scene reset --------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"


# --- Materials ----------------------------------------------------------------------------------
def load_image(path: str, non_color: bool) -> bpy.types.Image:
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def tiled_material(name: str) -> bpy.types.Material:
    """Mirror of assets/materials/<name>.tres: albedo, normal, ORM, uv1_scale."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    s = UV1_SCALE[name]
    mapping.inputs["Scale"].default_value = (s, s, 1.0)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])

    def tex(map_name: str, non_color: bool) -> bpy.types.Node:
        n = nodes.new("ShaderNodeTexImage")
        n.image = load_image(os.path.join(TEX, name, f"{name}_{map_name}.png"), non_color)
        n.extension = "REPEAT"
        links.new(mapping.outputs["Vector"], n.inputs["Vector"])
        return n

    albedo, normal, orm = tex("albedo", False), tex("normal", True), tex("orm", True)
    sep = nodes.new("ShaderNodeSeparateColor")
    links.new(orm.outputs["Color"], sep.inputs["Color"])
    # Godot applies AO to ambient light only; multiplying it in here is close enough for a preview.
    ao_mul = nodes.new("ShaderNodeMix")
    ao_mul.data_type = "RGBA"
    ao_mul.blend_type = "MULTIPLY"  # Mix sockets by index: 6/7 = colour A/B, output 2 = colour
    ao_mul.inputs["Factor"].default_value = 1.0
    links.new(albedo.outputs["Color"], ao_mul.inputs[6])
    links.new(sep.outputs["Red"], ao_mul.inputs[7])
    links.new(ao_mul.outputs[2], bsdf.inputs["Base Color"])
    links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(normal.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def markings_material() -> bpy.types.Material:
    """Mirror of assets/materials/markings.tres: atlas albedo × vertex colour, alpha blended."""
    mat = bpy.data.materials.new("markings")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    t = nodes.new("ShaderNodeTexImage")
    t.image = load_image(os.path.join(TEX, "markings", "markings_albedo.png"), False)
    t.image.alpha_mode = "STRAIGHT"
    t.extension = "REPEAT"
    vc = nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(t.outputs["Color"], mul.inputs[6])
    links.new(vc.outputs["Color"], mul.inputs[7])
    links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def flat_material(name: str, hex_colour: str, roughness: float) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*hex_lin(hex_colour), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


MATS = {n: tiled_material(n) for n in ("grass", "asphalt", "concrete")}
MATS["markings"] = markings_material()
MATS["dummy"] = flat_material("plane_dummy", "#8A9096", 0.5)


# --- Mesh builder: one object per material, quads with UVs and vertex colours ------------------
class Batch:
    def __init__(self) -> None:
        self.verts: list = []
        self.faces: list = []
        self.uvs: list = []
        self.cols: list = []

    def quad(self, corners: list, uvs: list, z: float, col: tuple = (1, 1, 1, 1)) -> None:
        """corners/uvs in order bottom-left, bottom-right, top-right, top-left of the texture."""
        i = len(self.verts)
        self.verts += [(c[0], c[1], z) for c in corners]
        self.faces.append((i, i + 1, i + 2, i + 3))
        self.uvs += uvs
        self.cols += [col] * 4

    def build(self, name: str, mat: bpy.types.Material) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        uv = mesh.uv_layers.new(name="UVMap")
        for li, loop in enumerate(mesh.loops):
            uv.data[li].uv = self.uvs[loop.vertex_index]
        ca = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for vi, c in enumerate(self.cols):
            ca.data[vi].color = c
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        return obj


batches = {k: Batch() for k in ("grass", "asphalt", "concrete", "markings")}


def area(batch: str, x0: float, y0: float, x1: float, y1: float, z: float) -> None:
    """Axis-aligned paved area with world-scale UVs."""
    c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    batches[batch].quad(c, [(x * UV_PER_M, y * UV_PER_M) for x, y in c], z)


def rect_uv(name_or_rect) -> tuple:
    x, y, w, h = L.RECTS[name_or_rect] if isinstance(name_or_rect, str) else name_or_rect
    n = float(L.ATLAS)
    return x / n, 1.0 - (y + h) / n, (x + w) / n, 1.0 - y / n  # u0, v0 (bottom), u1, v1 (top)


def v2(a) -> np.ndarray:
    return np.array(a, dtype=float)


def strip(p0, p1, width: float, name: str, metres_per_atlas: float | None = None,
          offset_m: float = 0.0, col: tuple = (1, 1, 1, 1), layer: int = 0) -> None:
    """A line along p0 -> p1 using a full-width atlas strip. Dashed strips repeat along U."""
    p0, p1 = v2(p0), v2(p1)
    d = p1 - p0
    length = float(np.linalg.norm(d))
    d /= length
    n = np.array([-d[1], d[0]]) * width / 2
    u0, v0, u1, v1 = rect_uv(name)
    if metres_per_atlas is None:      # solid: sample the middle of the strip
        ua, ub = 0.25, 0.75
    else:
        ua = offset_m / metres_per_atlas
        ub = (offset_m + length) / metres_per_atlas
    c = [p0 - n, p1 - n, p1 + n, p0 + n]
    batches["markings"].quad(c, [(ua, v0), (ub, v0), (ub, v1), (ua, v1)], Z_MARK + layer * Z_LAYER, col)


def piece(center, dir_u, size_u: float, size_v: float, rect, col: tuple = (1, 1, 1, 1),
          layer: int = 0) -> None:
    """Whole atlas rect onto a quad; dir_u = world direction of the atlas +x axis."""
    c, du = v2(center), v2(dir_u) / np.linalg.norm(dir_u)
    dv = np.array([-du[1], du[0]])  # atlas "up" is 90° left of +x
    hu, hv = du * size_u / 2, dv * size_v / 2
    u0, v0, u1, v1 = rect_uv(rect)
    corners = [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
    batches["markings"].quad(corners, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)],
                             Z_MARK + layer * Z_LAYER, col)


def curve(center, a, b, name: str, layer: int = 1) -> None:
    """Quarter taxi-line curve: arc centre at `center`, from center + a·R to center + b·R."""
    size = L.CURVES[name][2]
    c, a, b = v2(center), v2(a), v2(b)
    u0, v0, u1, v1 = rect_uv(name)
    corners = [c, c + a * size, c + (a + b) * size, c + b * size]
    batches["markings"].quad(corners, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], Z_MARK + layer * Z_LAYER)


def text(chars: str, center, up, height: float, spacing: float, col=(1, 1, 1, 1),
         layer: int = 0) -> None:
    """Characters from the atlas, read with `up` pointing away from the reader (glyph bottoms
    toward the reader). Runway designators: `up` = landing direction, bottoms toward the threshold."""
    up = v2(up) / np.linalg.norm(up)
    right = np.array([up[1], -up[0]])
    k = height / L.DIGIT[1]
    cw, ch = L.GLYPH_CELL[0] / L.GLYPH_PX_PER_M * k, L.GLYPH_CELL[1] / L.GLYPH_PX_PER_M * k
    first = -(len(chars) - 1) * spacing / 2
    for i, c in enumerate(chars):
        piece(v2(center) + right * (first + i * spacing), right, cw, ch, L.glyph_rect(c), col, layer)


YELLOW_TINT = tuple(min(1.0, y / w) for y, w in zip(hex_lin(L.YELLOW), hex_lin(L.WHITE))) + (1.0,)

# --- Layout (approved 2D layout, real scale) ----------------------------------------------------
RW_HALF = L.RUNWAY_WIDTH / 2
TW_HALF = L.TAXIWAY_WIDTH / 2
THRESHOLD_X = -150.0
TAXI_Y = 90.0                         # parallel taxiway centreline
STANDS = {50.0: "31", 90.0: "32", 130.0: "11"}  # stand centre x -> label (11 = terminal stand)
STAND_Y0, STAND_Y1 = 104.0, 150.0     # 46 m deep
STOP_Y = 146.0                        # nose wheel stop; a 38 m plane ends at y = 108
APRON = (25.0, TAXI_Y + TW_HALF, 155.0, 170.0)
ROAD_Y0, ROAD_Y1 = 155.0, 163.0       # apron service road (2 lanes)
TERMINAL_Y = 165.0                    # dashed terminal edge
CROSS_X = 114.0                       # zebra crossing, straight in front of a terminal door
PATH_Y0, PATH_Y1 = 151.0, 154.0       # passenger path lines (3 m apart), 1 m outside the red line
PATH_END_X = 43.0                     # forward-left door area of remote stand 31 (door ~x 48, y 141)
FAR = 420.0

# Ground and pavements.
area("grass", -400, -250, 450, 300, Z_GRASS)
area("asphalt", THRESHOLD_X, -RW_HALF, FAR, RW_HALF, Z_PAVE)                      # runway
area("asphalt", -TW_HALF, RW_HALF, TW_HALF, TAXI_Y - TW_HALF, Z_PAVE)             # connector
area("asphalt", -260, TAXI_Y - TW_HALF, FAR, TAXI_Y + TW_HALF, Z_PAVE)            # parallel taxiway
area("concrete", APRON[0], APRON[1], APRON[2], ROAD_Y0, Z_PAVE)                  # apron
area("asphalt", APRON[0], ROAD_Y0, APRON[2], ROAD_Y1, Z_PAVE)                      # service road
area("concrete", APRON[0], ROAD_Y1, APRON[2], APRON[3], Z_PAVE)                   # terminal frontage

# Runway 09: edge lines, threshold bars, designator, centreline.
edge = RW_HALF - L.EDGE_LINE_W / 2
for y in (-edge, edge):
    strip((THRESHOLD_X, y), (FAR, y), L.EDGE_LINE_W, "white_line")
bar_len, bar_w = L.THRESHOLD_BAR
bar_x = THRESHOLD_X + 6.0 + bar_len / 2           # bars start 6 m after the threshold
gap = (RW_HALF - 3.0 - 1.8 - 6 * bar_w) / 5       # 6 bars per side, 3 m from the edge
for i in range(6):
    y = 1.8 + bar_w / 2 + i * (bar_w + gap)
    for s in (-1, 1):
        piece((bar_x, s * y), (1, 0), bar_len, bar_w, "threshold_bar")
digit_x = THRESHOLD_X + 6.0 + bar_len + 12.0 + L.DIGIT[1] / 2
text("09", (digit_x, 0.0), (1, 0), L.DIGIT[1], 5.0)
cl_start = digit_x + L.DIGIT[1] / 2 + 12.0
strip((cl_start, 0), (FAR, 0), L.CENTRELINE_W, "centre_dash", L.CENTRE_DASH_PERIOD_M)

# Taxiway centrelines: connector lead-off, T-junction curves, parallel taxiway.
strip((0, 0), (0, TAXI_Y - 20), L.TAXI_LINE_W, "yellow_line", layer=1)  # crosses the runway centreline
curve((-20, TAXI_Y - 20), (1, 0), (0, 1), "taxi_curve_r20")
curve((20, TAXI_Y - 20), (-1, 0), (0, 1), "taxi_curve_r20")
strip((-260, TAXI_Y), (FAR, TAXI_Y), L.TAXI_LINE_W, "yellow_line")

# Stands: lead-in curve + line, stop bar, label box, red safety lines.
for sx, label in STANDS.items():
    curve((sx - 20, TAXI_Y + 20), (1, 0), (0, -1), "taxi_curve_r20")
    strip((sx, TAXI_Y + 20), (sx, STOP_Y - L.STOP_BAR[1] / 2), L.TAXI_LINE_W, "yellow_line")
    piece((sx, STOP_Y), (1, 0), *L.STOP_BAR, "stop_bar", layer=1)
    box = (sx + 5.0, 113.0)
    piece(box, (1, 0), *L.LABEL_BOX, "label_box")
    text(label, box, (0, 1), 1.4, 0.75, YELLOW_TINT, layer=1)
for x in sorted({sx + s * 20 for sx in STANDS for s in (-1, 1)}):
    strip((x, STAND_Y0), (x, STAND_Y1), L.SAFETY_LINE_W, "red_line")
strip((min(STANDS) - 20, STAND_Y1), (max(STANDS) + 20, STAND_Y1), L.SAFETY_LINE_W, "red_line", layer=1)

# Service road: edge lines and dashed lane divider, interrupted at the crossing.
cross_w = L.ZEBRA_W / 2
cx0, cx1 = CROSS_X - cross_w, CROSS_X + cross_w
stop_w0, stop_e0 = cx0 - L.STOP_LINE_GAP, cx1 + L.STOP_LINE_GAP   # stop lines 2 m before the zebra
road_mid = (ROAD_Y0 + ROAD_Y1) / 2
edge_s, edge_n = ROAD_Y0 + 0.3, ROAD_Y1 - 0.3
for y in (edge_s, edge_n):
    strip((APRON[0], y), (cx0, y), L.ROAD_LINE_W, "white_line")
    strip((cx1, y), (APRON[2], y), L.ROAD_LINE_W, "white_line")
strip((APRON[0], road_mid), (stop_w0, road_mid), L.ROAD_LINE_W, "short_dash", L.SHORT_DASH_STRIP_M)
strip((stop_e0, road_mid), (APRON[2], road_mid), L.ROAD_LINE_W, "short_dash", L.SHORT_DASH_STRIP_M)
strip((110, TERMINAL_Y), (150, TERMINAL_Y), L.ROAD_LINE_W, "short_dash", L.SHORT_DASH_STRIP_M)

# Passenger route (real-airport layout): terminal door -> straight zebra at a right angle across
# the road -> vehicle stop lines on both approaches (right-hand traffic: eastbound in the south
# lane, westbound in the north lane) -> passenger path of two white lines, straight to the
# forward-left door area of remote stand 31, outside the red stand safety line.
strip((CROSS_X, ROAD_Y1), (CROSS_X, ROAD_Y0), L.ZEBRA_W, "zebra", L.ZEBRA_STRIP_M)
strip((stop_w0, edge_s + L.ROAD_LINE_W / 2), (stop_w0, road_mid), L.STOP_LINE_W, "white_line")
strip((stop_e0, road_mid), (stop_e0, edge_n - L.ROAD_LINE_W / 2), L.STOP_LINE_W, "white_line")
strip((cx1, PATH_Y0), (PATH_END_X, PATH_Y0), L.ROAD_LINE_W, "white_line")   # south line
strip((cx0, PATH_Y1), (PATH_END_X, PATH_Y1), L.ROAD_LINE_W, "white_line")   # north line, open at the zebra
strip((cx1, PATH_Y0), (cx1, ROAD_Y0), L.ROAD_LINE_W, "white_line", layer=1)  # closes the east end

objects = {k: b.build(f"ground_preview_{k}", MATS[k]) for k, b in batches.items()}
objects["markings"].visible_shadow = False  # paint: casts no shadow (cast_shadow off in Godot too)


# --- Plane dummies (narrow-body, 38 m long × 36 m span) -----------------------------------------
def box(name: str, cx: float, cy: float, z0: float, sx: float, sy: float, sz: float) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    hx, hy = sx / 2, sy / 2
    v = [(cx + x, cy + y, z) for z in (z0, z0 + sz) for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy))]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh.from_pydata(v, [], f)
    mesh.materials.append(MATS["dummy"])
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return obj


dummies = []
for sx in (50.0, 130.0):
    nose, length = STOP_Y, 38.0
    dummies += [
        box(f"plane_dummy_{int(sx)}_body", sx, nose - length / 2, 1.2, 4.0, length, 4.0),
        box(f"plane_dummy_{int(sx)}_wing", sx, nose - length / 2 - 1.0, 2.2, 36.0, 5.0, 0.4),
        box(f"plane_dummy_{int(sx)}_tail", sx, nose - length + 3.0, 5.2, 0.4, 5.0, 6.5),
        box(f"plane_dummy_{int(sx)}_stab", sx, nose - length + 2.0, 5.0, 12.0, 3.0, 0.3),
    ]

# --- Light and world ----------------------------------------------------------------------------
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

# --- Render settings ----------------------------------------------------------------------------
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "None"


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
        d = v2(target) - v2(loc)
        yaw = math.atan2(d[1], d[0]) - math.pi / 2
        pitch = math.atan2(d[2], math.hypot(d[0], d[1]))
        cam.rotation_euler = (math.pi / 2 + pitch, 0.0, yaw)
    scene.collection.objects.link(cam)
    return cam


cams = {
    "ground_top": camera("cam_top", (16.5, 75.0, 500.0), ortho=380.0),
    "ground_eye": camera("cam_eye", (99.0, 153.0, 1.7), target=(89.0, 137.0, 0.0), lens=20.0),
    "ground_markings": camera("cam_markings", (98.0, 134.0, 300.0), ortho=90.0),
    "ground_crossing": camera("cam_crossing", (82.0, 156.0, 300.0), ortho=92.0),
    # Turned so the landing direction (east) points up: what a pilot on approach to 09 sees.
    "ground_designator": camera("cam_designator", (-112.0, 0.0, 300.0), ortho=90.0),
}
cams["ground_designator"].rotation_euler = (0.0, 0.0, math.radians(-90))

os.makedirs(PREVIEWS, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the source
bpy.ops.wm.save_as_mainfile(filepath=BLEND, relative_remap=True)
only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else list(cams)
for name in only:
    scene.camera = cams[name]
    for d in dummies:
        d.hide_render = name == "ground_markings"   # keep the stand markings visible
    scene.render.filepath = os.path.join(PREVIEWS, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)
