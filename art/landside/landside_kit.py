"""Landside start kit: geometry helpers, shared materials and one builder per modular piece.

Used by landside_pieces.py (exports every piece as .glb) and landside_preview.py (assembles the
approved start layout). Sizes, connections and upgrade paths: pieces.md.

Conventions (docs/art_direction.md §2, §7):
- Real metres, 1 cell = 2 m. Origin at the ground centre of the footprint, +Z up, front = -Y.
- Road surface at z = 0. Sidewalks are raised 0.15 m (CURB_H) behind a 0.2 m concrete curb stone.
- World-scale UVs: 1 UV unit = 2 m. Markings are paint: no thickness, 1 mm above their surface,
  in a separate `<piece>_markings` object that casts no shadow (cast_shadow off in Godot).
- Every piece has LOD0 (`<piece>`, plus `<piece>_markings`) and a very cheap `<piece>_lodfar`.
"""
import math
import os
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ground"))
import markings_layout as L  # noqa: E402
from tex_io import ROOT  # noqa: E402

TEX = os.path.join(ROOT, "assets", "textures")
UV_PER_M = 0.5
UV1_SCALE = {"grass": 0.125, "asphalt": 0.25, "concrete": 0.2, "paving": 0.5}  # as the .tres files

CURB_H = 0.15           # raised curb / sidewalk height
CURB_LOW = 0.03         # lowered curb at crossings
CURB_W = 0.2            # concrete curb stone width
Z_MARK = 0.001          # paint above its surface (max 2 mm with layers)
Z_LAYER = 0.0005

# Line widths (m). Road lines follow German practice, rounded so they read from the build view.
EDGE_W = 0.2            # road edge line
DIVIDER_W = 0.15        # lane divider / centre line (broken)
LANE_BOUNDARY_W = 0.25  # broken line between through lanes and the curbside lane
BAY_W = 0.12            # parking / kiss & fly / taxi bay lines
GIVEWAY_W = 0.5
ONEWAY_PERIOD = 4.0     # one-way lane divider: 2 m dash, 2 m gap
COUNTRY_PERIOD = 8.0    # country road centre line: 4 m dash, 4 m gap
ZEBRA_WIDTH = 4.0       # crossing width (bar length)


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h: str) -> tuple:
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (1, 3, 5))


def tint(h: str) -> tuple:
    """Vertex colour that turns the white atlas paint into palette colour `h`."""
    return tuple(min(1.0, c / w) for c, w in zip(hex_lin(h), hex_lin(L.WHITE))) + (1.0,)


WHITE = (1.0, 1.0, 1.0, 1.0)
YELLOW = tint(L.YELLOW)
RED = tint(L.RED)


# --- Materials (mirror assets/materials/*.tres) -------------------------------------------------
def _img(path: str, non_color: bool) -> bpy.types.Image:
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def _tiled(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    s = UV1_SCALE[name]
    mapping.inputs["Scale"].default_value = (s, s, 1.0)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])

    def tex(map_name: str, non_color: bool) -> bpy.types.Node:
        n = nodes.new("ShaderNodeTexImage")
        n.image = _img(os.path.join(TEX, name, f"{name}_{map_name}.png"), non_color)
        links.new(mapping.outputs["Vector"], n.inputs["Vector"])
        return n

    albedo, normal, orm = tex("albedo", False), tex("normal", True), tex("orm", True)
    sep = nodes.new("ShaderNodeSeparateColor")
    links.new(orm.outputs["Color"], sep.inputs["Color"])
    ao_mul = nodes.new("ShaderNodeMix")
    ao_mul.data_type = "RGBA"
    ao_mul.blend_type = "MULTIPLY"
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


def _markings() -> bpy.types.Material:
    mat = bpy.data.materials.new("markings")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    t = nodes.new("ShaderNodeTexImage")
    t.image = _img(os.path.join(TEX, "markings", "markings_albedo.png"), False)
    t.image.alpha_mode = "STRAIGHT"
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


def flat(name: str, hex_colour: str, roughness: float, metallic: float = 0.0,
         alpha: float = 1.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*hex_lin(hex_colour), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Alpha"].default_value = alpha
    mat.diffuse_color = (*hex_lin(hex_colour), alpha)
    return mat


def make_materials() -> dict:
    """The shared library (art_direction §4). Names = assets/materials/<name>.tres, so Godot can
    swap the shared material in by name on import."""
    mats = {n: _tiled(n) for n in ("grass", "asphalt", "concrete", "paving")}
    mats["markings"] = _markings()
    mats["metal_dark"] = flat("metal_dark", "#2E3236", 0.45, 1.0)
    mats["metal_light"] = flat("metal_light", "#8A9096", 0.35, 1.0)
    # Godot: alpha-blended, no refraction (art_direction §4). Same in the preview.
    mats["glass"] = flat("glass", "#9FB6BF", 0.05, 0.0, alpha=0.25)
    mats["bark"] = flat("bark", "#5A4A3C", 0.95)
    mats["foliage"] = _vertex_tinted("foliage", "#4F6B3A", 0.9)
    mats["decals"] = _decals()
    return mats


def _vertex_tinted(name: str, hex_colour: str, roughness: float) -> bpy.types.Material:
    """Flat colour × vertex colour (per-instance / per-crown variation, as foliage.tres)."""
    mat = flat(name, hex_colour, roughness)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    vc = nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    mul.inputs[6].default_value = (*hex_lin(hex_colour), 1.0)
    links.new(vc.outputs["Color"], mul.inputs[7])
    links.new(mul.outputs[2], nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def _decals() -> bpy.types.Material:
    mat = bpy.data.materials.new("decals")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    t = nodes.new("ShaderNodeTexImage")
    t.image = _img(os.path.join(TEX, "decals", "decals_albedo.png"), False)
    t.image.alpha_mode = "STRAIGHT"
    links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


# --- Mesh builder -------------------------------------------------------------------------------
class MB:
    """Collects faces (per-loop UVs and colours, one material per face) for one mesh object."""

    def __init__(self) -> None:
        self.verts: list = []
        self.faces: list = []
        self.uvs: list = []
        self.cols: list = []
        self.mat_names: list = []
        self.face_mat: list = []

    def face(self, pts: list, uvs: list, mat: str, col: tuple = WHITE) -> None:
        if mat not in self.mat_names:
            self.mat_names.append(mat)
        i = len(self.verts)
        self.verts += [tuple(p) for p in pts]
        self.faces.append(tuple(range(i, i + len(pts))))
        self.uvs.append(list(uvs))
        self.cols.append([col] * len(pts))
        self.face_mat.append(self.mat_names.index(mat))

    def tris(self) -> int:
        return sum(len(f) - 2 for f in self.faces)

    def build(self, name: str, mats: dict, collection=None) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.uv_layers.new(name="UVMap")
        mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        # Fetch both again: adding a layer reallocates the others (old references go stale).
        uv = mesh.uv_layers["UVMap"]
        ca = mesh.color_attributes["Col"]
        for fi, poly in enumerate(mesh.polygons):
            poly.material_index = self.face_mat[fi]
            for k in range(poly.loop_total):
                uv.data[poly.loop_start + k].uv = self.uvs[fi][k]
                ca.data[poly.loop_start + k].color = self.cols[fi][k]
        for m in self.mat_names:
            mesh.materials.append(mats[m])
        mesh.validate()
        obj = bpy.data.objects.new(name, mesh)
        (collection or bpy.context.scene.collection).objects.link(obj)
        return obj


def _area2(pts: list) -> float:
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                     for i in range(len(pts)))


def top(mb: MB, pts: list, z, mat: str) -> None:
    """Upward-facing convex polygon (any winding) with world-scale UVs. z: float or per-point list."""
    zs = list(z) if isinstance(z, (list, tuple)) else [z] * len(pts)
    order = list(range(len(pts)))
    if _area2(pts) < 0:
        order.reverse()
    p3 = [(pts[i][0], pts[i][1], zs[i]) for i in order]
    mb.face(p3, [(p[0] * UV_PER_M, p[1] * UV_PER_M) for p in p3], mat)


def rect(mb: MB, x0: float, y0: float, x1: float, y1: float, z: float, mat: str) -> None:
    top(mb, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z, mat)


def wall(mb: MB, p0, p1, z0: float, z1: float, mat: str, z0b: float | None = None,
         z1b: float | None = None) -> None:
    """Vertical quad p0 -> p1; its front faces to the RIGHT of the direction p0 -> p1.
    z0/z1 = bottom/top at p0; z0b/z1b at p1 (default the same)."""
    z0b = z0 if z0b is None else z0b
    z1b = z1 if z1b is None else z1b
    length = math.dist(p0, p1)
    pts = [(p0[0], p0[1], z0), (p1[0], p1[1], z0b), (p1[0], p1[1], z1b), (p0[0], p0[1], z1)]
    u0 = (p0[0] + p0[1]) * UV_PER_M
    uvs = [(u0, z0 * UV_PER_M), (u0 + length * UV_PER_M, z0b * UV_PER_M),
           (u0 + length * UV_PER_M, z1b * UV_PER_M), (u0, z1 * UV_PER_M)]
    mb.face(pts, uvs, mat)


def box(mb: MB, x0, y0, z0, x1, y1, z1, mat: str, bottom: bool = False, col: tuple = WHITE,
        uv_point: tuple | None = None, sides: str = "nesw") -> None:
    """Axis-aligned box. Bottom face only when visible from below. `uv_point` maps every corner to
    one UV (solid paint from the markings atlas)."""
    c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    v = [(x, y, z0) for x, y in c] + [(x, y, z1) for x, y in c]
    quads = [(4, 5, 6, 7)]
    if bottom:
        quads.append((0, 3, 2, 1))
    side = {"s": (0, 1, 5, 4), "e": (1, 2, 6, 5), "n": (2, 3, 7, 6), "w": (3, 0, 4, 7)}
    quads += [side[s] for s in "senw" if s in sides]
    for q in quads:
        pts = [v[i] for i in q]
        if uv_point:
            uvs = [uv_point] * 4
        elif q[0] == 4 or q == (0, 3, 2, 1):
            uvs = [(p[0] * UV_PER_M, p[1] * UV_PER_M) for p in pts]
        else:
            uvs = [((p[0] + p[1]) * UV_PER_M, p[2] * UV_PER_M) for p in pts]
        mb.face(pts, uvs, mat, col)


def arc_points(c, r: float, a0: float, a1: float, n: int) -> list:
    return [(c[0] + r * math.cos(a0 + (a1 - a0) * i / n), c[1] + r * math.sin(a0 + (a1 - a0) * i / n))
            for i in range(n + 1)]


# --- Markings -----------------------------------------------------------------------------------
def rect_uv(name) -> tuple:
    x, y, w, h = L.RECTS[name] if isinstance(name, str) else name
    n = float(L.ATLAS)
    return x / n, 1.0 - (y + h) / n, (x + w) / n, 1.0 - y / n


_wl = rect_uv("white_line")
SOLID_UV = (0.5, (_wl[1] + _wl[3]) / 2)  # middle of the solid white strip: plain paint


def line(mb: MB, pts: list, width: float, name: str = "white_line", period: float | None = None,
         offset: float = 0.0, col: tuple = WHITE, z: float = 0.0, layer: int = 0) -> None:
    """Paint strip along a polyline. Dashed strips: `period` = dash + gap in metres (dash first,
    half the period), `offset` shifts the pattern (offset -period/4 centres the dashes)."""
    u0, v0, u1, v1 = rect_uv(name)
    if period is None:
        mpa = None
    elif name == "short_dash":
        mpa = period * 1024.0 / 64.0          # 16 periods across the atlas
    elif name == "zebra":
        mpa = period * 32.0                   # 32 periods across the atlas
    else:
        raise ValueError(name)
    zz = z + Z_MARK + layer * Z_LAYER
    s = [0.0]
    for a, b in zip(pts, pts[1:]):
        s.append(s[-1] + math.dist(a, b))
    normals = []
    for i in range(len(pts)):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy)
        normals.append((-dy / d * width / 2, dx / d * width / 2))
    for i in range(len(pts) - 1):
        if mpa is None:
            ua, ub = 0.25, 0.75
        else:
            ua, ub = (offset + s[i]) / mpa, (offset + s[i + 1]) / mpa
        (ax, ay), (bx, by) = pts[i], pts[i + 1]
        (nax, nay), (nbx, nby) = normals[i], normals[i + 1]
        quad = [(ax - nax, ay - nay, zz), (bx - nbx, by - nby, zz), (bx + nbx, by + nby, zz),
                (ax + nax, ay + nay, zz)]
        mb.face(quad, [(ua, v0), (ub, v0), (ub, v1), (ua, v1)], "markings", col)


def dashed(mb: MB, p0, p1, width: float, period: float, col: tuple = WHITE, z: float = 0.0,
           layer: int = 0) -> None:
    """Broken line centred on its segment (gap of period/4 at both ends), so it looks the same in
    every rotation and lines up with the next piece when the length is a multiple of the period."""
    line(mb, [p0, p1], width, "short_dash", period, -period / 4, col, z, layer)


def paint_poly(mb: MB, pts: list, z: float = 0.0, col: tuple = WHITE, layer: int = 1) -> None:
    order = pts if _area2(pts) > 0 else pts[::-1]
    zz = z + Z_MARK + layer * Z_LAYER
    mb.face([(p[0], p[1], zz) for p in order], [SOLID_UV] * len(order), "markings", col)


def arrow(mb: MB, c, direction: float, length: float = 5.0, z: float = 0.0) -> None:
    """Straight-ahead lane arrow (shaft + head), `direction` in radians."""
    shaft_w, head_w, head_l = 0.3, 1.2, 1.6
    h = length / 2
    local_shaft = [(-h, -shaft_w / 2), (h - head_l, -shaft_w / 2), (h - head_l, shaft_w / 2), (-h, shaft_w / 2)]
    local_head = [(h - head_l, -head_w / 2), (h, 0.0), (h - head_l, head_w / 2)]
    cs, sn = math.cos(direction), math.sin(direction)

    def tr(p):
        return (c[0] + p[0] * cs - p[1] * sn, c[1] + p[0] * sn + p[1] * cs)

    paint_poly(mb, [tr(p) for p in local_shaft], z)
    paint_poly(mb, [tr(p) for p in local_head], z)


def decal(mb: MB, center, angle: float, size_u: float, size_v: float, rect, col: tuple = WHITE,
          z: float = 0.0, layer: int = 1) -> None:
    """Whole atlas rect flat on the ground; `angle` = world direction of the atlas +U axis
    (the atlas "up" / +V points 90° to the left of it)."""
    du = (math.cos(angle), math.sin(angle))
    dv = (-du[1], du[0])
    hu, hv = size_u / 2, size_v / 2
    u0, v0, u1, v1 = rect_uv(rect)
    zz = z + Z_MARK + layer * Z_LAYER
    c = center
    pts = [(c[0] - du[0] * hu - dv[0] * hv, c[1] - du[1] * hu - dv[1] * hv, zz),
           (c[0] + du[0] * hu - dv[0] * hv, c[1] + du[1] * hu - dv[1] * hv, zz),
           (c[0] + du[0] * hu + dv[0] * hv, c[1] + du[1] * hu + dv[1] * hv, zz),
           (c[0] - du[0] * hu + dv[0] * hv, c[1] - du[1] * hu + dv[1] * hv, zz)]
    mb.face(pts, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], "markings", col)


def road_text(mb: MB, lines: list, start, direction: float, col: tuple = WHITE, pitch: float = 0.6,
              line_gap: float = 0.5, z: float = 0.0) -> None:
    """Road lettering read by a driver heading `direction` (radians). Letters are elongated along
    the travel direction (L.ROAD_LETTER = width × length); the first line is nearest the driver,
    centred on `start`."""
    lw, ll = L.ROAD_LETTER
    d = (math.cos(direction), math.sin(direction))
    right = (d[1], -d[0])
    for k, text in enumerate(lines):
        along = k * (ll + line_gap)
        first = -(len(text) - 1) * pitch / 2
        for i, ch in enumerate(text):
            if ch == " ":
                continue
            off = first + i * pitch
            c = (start[0] + d[0] * along + right[0] * off, start[1] + d[1] * along + right[1] * off)
            # Atlas +U (letter's right) = driver's right; atlas +V (letter's top) = travel direction.
            decal(mb, c, math.atan2(right[1], right[0]), lw, ll, L.road_letter_rect(ch), col, z)


def sign_face(mb: MB, p0, p1, z0: float, z1: float, rect, col: tuple = WHITE) -> None:
    """Vertical atlas quad, readable from the side to the RIGHT of p0 -> p1."""
    u0, v0, u1, v1 = rect_uv(rect)
    mb.face([(p0[0], p0[1], z0), (p1[0], p1[1], z0), (p1[0], p1[1], z1), (p0[0], p0[1], z1)],
            [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], "markings", col)


def face_out(mb: MB, pts: list, mat: str, out: tuple) -> None:
    """Planar polygon (3D points) wound so its normal points along `out`; world-scale UVs."""
    a, b, c = pts[0], pts[1], pts[2]
    n = ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
         (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
         (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    if n[0] * out[0] + n[1] * out[1] + n[2] * out[2] < 0:
        pts = pts[::-1]
    if abs(out[2]) > 0.5:
        uvs = [(p[0] * UV_PER_M, p[1] * UV_PER_M) for p in pts]
    else:
        uvs = [((p[0] + p[1]) * UV_PER_M, p[2] * UV_PER_M) for p in pts]
    mb.face(pts, uvs, mat)


def cylinder(mb: MB, cx: float, cy: float, z0: float, z1: float, r0: float, mat: str, n: int = 8,
             r1: float | None = None, cap: bool = True) -> None:
    """Upright n-sided cylinder (or cone frustum with r1), open bottom."""
    r1 = r0 if r1 is None else r1
    ring = [(math.cos(2 * math.pi * (i + 0.5) / n), math.sin(2 * math.pi * (i + 0.5) / n)) for i in range(n)]
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        mb.face([(cx + a[0] * r0, cy + a[1] * r0, z0), (cx + b[0] * r0, cy + b[1] * r0, z0),
                 (cx + b[0] * r1, cy + b[1] * r1, z1), (cx + a[0] * r1, cy + a[1] * r1, z1)],
                [(i / n, z0 * UV_PER_M), ((i + 1) / n, z0 * UV_PER_M), ((i + 1) / n, z1 * UV_PER_M),
                 (i / n, z1 * UV_PER_M)], mat)
    if cap:
        top(mb, [(cx + a[0] * r1, cy + a[1] * r1) for a in ring], z1, mat)


def offset_polyline(pts: list, d: float) -> list:
    """Offset a polyline by d to its LEFT. Interior corners are mitred; the end points stay on
    the vertical lines x = pts[0].x and x = pts[-1].x (piece borders)."""
    lines = []
    for a, b in zip(pts, pts[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        n = (-dy / ln * d, dx / ln * d)
        lines.append(((a[0] + n[0], a[1] + n[1]), (dx, dy)))

    def at_x(line_, x):
        (px, py), (dx, dy) = line_
        return (x, py + (x - px) / dx * dy)

    out = [at_x(lines[0], pts[0][0])]
    for (p, u), (q, v) in zip(lines, lines[1:]):
        den = u[0] * v[1] - u[1] * v[0]
        t = ((q[0] - p[0]) * v[1] - (q[1] - p[1]) * v[0]) / den
        out.append((p[0] + u[0] * t, p[1] + u[1] * t))
    out.append(at_x(lines[-1], pts[-1][0]))
    return out


# --- Pieces -------------------------------------------------------------------------------------
class Piece:
    def __init__(self, name: str, size: tuple, desc: str) -> None:
        self.name = name
        self.size = size              # metres (x, y)
        self.desc = desc
        self.lod0 = MB()
        self.marks = MB()
        self.far = MB()


def _road_straight(name: str, length: float, period: float, desc: str) -> Piece:
    """8 m wide asphalt band along X: 7 m carriageway between edge lines, 0.5 m shoulders."""
    p = Piece(name, (length, 8.0), desc)
    h = length / 2
    rect(p.lod0, -h, -4, h, 4, 0.0, "asphalt")
    for y in (-3.5, 3.5):
        line(p.marks, [(-h, y), (h, y)], EDGE_W)
    dashed(p.marks, (-h, 0), (h, 0), DIVIDER_W, period)
    rect(p.far, -h, -4, h, 4, 0.0, "asphalt")
    return p


def road_country_straight() -> Piece:
    return _road_straight("road_country_straight", 8.0, COUNTRY_PERIOD,
                          "two-way country road, 2 × 3.5 m, broken centre line")


def road_oneway_2lane_straight(arrows: bool = False) -> Piece:
    name = "road_oneway_2lane_arrows" if arrows else "road_oneway_2lane_straight"
    p = _road_straight(name, 8.0, ONEWAY_PERIOD, "one-way road, 2 × 3.5 m, traffic towards +X"
                       + (", lane arrows" if arrows else ""))
    if arrows:
        for y in (-1.75, 1.75):
            arrow(p.marks, (0, y), 0.0)
    return p


def road_oneway_corner() -> Piece:
    """90° turn of the one-way road: quarter ring, radii 8-16 m around the (+8, -8) corner.
    Connects at the west half of the -Y edge and the north half of the +X edge."""
    p = Piece("road_oneway_corner", (16.0, 16.0), "one-way road, 90° turn, centre radius 12 m")
    c = (8.0, -8.0)
    n = 12
    inner = arc_points(c, 8.0, math.pi, math.pi / 2, n)
    outer = arc_points(c, 16.0, math.pi, math.pi / 2, n)
    for i in range(n):
        top(p.lod0, [inner[i], outer[i], outer[i + 1], inner[i + 1]], 0.0, "asphalt")
    for r in (8.5, 15.5):
        line(p.marks, arc_points(c, r, math.pi, math.pi / 2, n), EDGE_W)
    arc_len = 12.0 * math.pi / 2
    period = arc_len / round(arc_len / ONEWAY_PERIOD)
    line(p.marks, arc_points(c, 12.0, math.pi, math.pi / 2, n), DIVIDER_W, "short_dash", period,
         -period / 4)
    inner6 = arc_points(c, 8.0, math.pi, math.pi / 2, 4)
    outer6 = arc_points(c, 16.0, math.pi, math.pi / 2, 4)
    for i in range(4):
        top(p.far, [inner6[i], outer6[i], outer6[i + 1], inner6[i + 1]], 0.0, "asphalt")
    return p


def road_country_tjunction(giveway: bool) -> Piece:
    """Country road along X (y -8..0) with an 8 m one-way road leaving to +Y (x -4..4),
    6 m corner radii. `giveway`: broken give-way line across the side road (traffic leaving it)."""
    name = "road_country_tjunction_giveway" if giveway else "road_country_tjunction"
    p = Piece(name, (24.0, 16.0), "T-junction: country road + one-way side road"
              + (" (exit, give-way line)" if giveway else " (entry)"))
    rect(p.lod0, -12, -8, 12, 0, 0.0, "asphalt")
    rect(p.lod0, -4, 0, 4, 8, 0.0, "asphalt")
    n = 8
    for sx in (-1, 1):
        # Fillet: fan from the inner corner (±4, 0) to the arc of radius 6 around (±10, 6).
        a0 = -math.pi / 2
        a1 = 0.0 if sx < 0 else -math.pi
        arc = arc_points((sx * 10.0, 6.0), 6.0, a0, a1, n)
        for i in range(n):
            top(p.lod0, [(sx * 4.0, 0.0), arc[i], arc[i + 1]], 0.0, "asphalt")
        edge = arc_points((sx * 10.0, 6.0), 6.5, a0, a1, n)
        line(p.marks, [(sx * 12.0, -0.5)] + edge + [(sx * 3.5, 8.0)], EDGE_W)
    line(p.marks, [(-12, -7.5), (12, -7.5)], EDGE_W)
    dashed(p.marks, (-12, -4), (12, -4), DIVIDER_W, COUNTRY_PERIOD)
    line(p.marks, [(0, 4), (0, 8)], DIVIDER_W, "short_dash", ONEWAY_PERIOD, -ONEWAY_PERIOD / 4)
    if giveway:
        line(p.marks, [(-3.5, 0.6), (3.5, 0.6)], GIVEWAY_W, "short_dash", 1.0, -0.25)
    rect(p.far, -12, -8, 12, 0, 0.0, "asphalt")
    rect(p.far, -4, 0, 4, 8, 0.0, "asphalt")
    return p


# Curb road cross-section (local y, piece 12 m deep, y -6..6), traffic towards +X:
#   -6.0 .. -5.5  shoulder (the car-park sidewalk's curb sits at -6)
#   -5.5 ..  1.5  two through lanes, 3.5 m each (edge line at -5.5, divider at -2)
#    1.5 ..  5.0  curbside lane 3.5 m (bays), 5.0 .. 5.5 gutter
#    5.5 ..  6.0  raised curb strip: 0.2 m curb stone + 0.3 m paving (joins the terminal sidewalk)
CURB_Y = 5.5
LANE_B = 1.5


def _curb_base(p: Piece, length: float, through_marks: bool = True, boundary: tuple = WHITE,
               gap: tuple | None = None) -> None:
    h = length / 2
    rect(p.lod0, -h, -6, h, CURB_Y, 0.0, "asphalt")
    _raised_strip(p.lod0, -h, h)
    if through_marks:
        segs = [(-h, h)] if gap is None else [(-h, gap[0]), (gap[1], h)]
        for a, b in segs:
            line(p.marks, [(a, -5.5), (b, -5.5)], EDGE_W)
        if gap is None:
            dashed(p.marks, (-h, -2), (h, -2), DIVIDER_W, ONEWAY_PERIOD)
            dashed(p.marks, (-h, LANE_B), (h, LANE_B), LANE_BOUNDARY_W, ONEWAY_PERIOD, boundary)
    rect(p.far, -h, -6, h, CURB_Y, 0.0, "asphalt")
    rect(p.far, -h, CURB_Y, h, 6, CURB_H, "paving")


def _raised_strip(mb: MB, x0: float, x1: float, low: tuple | None = None) -> None:
    """Curb stone + paving strip on y 5.5..6. `low` = (xa, xb): lowered curb for a crossing."""
    spans = [(x0, x1)] if low is None else [(x0, low[0]), (low[1], x1)]
    s0, s1 = CURB_Y, CURB_Y + CURB_W
    for a, b in spans:
        rect(mb, a, s0, b, s1, CURB_H, "concrete")
        rect(mb, a, s1, b, 6.0, CURB_H, "paving")
        wall(mb, (a, s0), (b, s0), 0.0, CURB_H, "concrete")      # faces -Y (the road)
    if low:
        a, b = low
        rect(mb, a, s0, b, s1, CURB_LOW, "concrete")
        top(mb, [(a, s1), (b, s1), (b, 6.0), (a, 6.0)], [CURB_LOW, CURB_LOW, CURB_H, CURB_H], "paving")
        wall(mb, (a, s0), (b, s0), 0.0, CURB_LOW, "concrete")
        # Side faces where the full-height strip meets the lowered one.
        wall(mb, (a, s0), (a, s1), CURB_LOW, CURB_H, "concrete")            # faces +X
        wall(mb, (b, s1), (b, s0), CURB_LOW, CURB_H, "concrete")            # faces -X
        mb.face([(a, 6.0, CURB_H), (a, s1, CURB_H), (a, s1, CURB_LOW)],
                [(0, 0), (0.15, 0), (0.15, 0.1)], "paving")
        mb.face([(b, s1, CURB_LOW), (b, s1, CURB_H), (b, 6.0, CURB_H)],
                [(0, 0), (0.15, 0), (0.15, 0.1)], "paving")


def curb_plain_segment(arrows: bool = False) -> Piece:
    name = "curb_plain_segment_arrows" if arrows else "curb_plain_segment"
    p = Piece(name, (8.0, 12.0), "curb road: 2 through lanes + curbside lane, raised curb"
              + (", lane arrows" if arrows else ""))
    _curb_base(p, 8.0)
    if arrows:
        for y in (-3.75, -0.25):
            arrow(p.marks, (0, y), 0.0)
    return p


def _bays(p: Piece, length: float, bay: float, col: tuple) -> None:
    h = length / 2
    n = int(round(length / bay))
    for i in range(n + 1):
        x = -h + i * bay
        w = BAY_W if 0 < i < n else BAY_W / 2                 # end lines: half, the neighbour adds the rest
        xc = x + (w / 2 if i == 0 else -w / 2 if i == n else 0.0)
        line(p.marks, [(xc, LANE_B + LANE_BOUNDARY_W / 2), (xc, CURB_Y)], w, col=col)


# Kiss & Fly: sawtooth (echelon) bays, recessed into the sidewalk. Each pocket: a curb running
# into the sidewalk at 25° (the car stops along it, nose in), then a steep step back to the curb
# line. The next pocket starts at the curb line again, so every car drives in AND out forwards
# without waiting for the car in front (as at real drop-off curbs and sawtooth bus stations).
KF_PITCH = 8.0           # 3 pockets per 24 m piece
KF_DIAG = 5.5            # length along X of the angled curb
KF_ANGLE = 25.0          # car axis to the curb line
KF_RECESS = KF_DIAG * math.tan(math.radians(KF_ANGLE))   # ~2.56 m into the sidewalk


def kf_curb(cy: float) -> list:
    pts = [(-12.0, cy)]
    for i in range(3):
        x0 = -12.0 + KF_PITCH * i
        pts += [(x0 + KF_DIAG, cy + KF_RECESS), (x0 + KF_PITCH, cy)]
    return pts


def kf_car_pose(i: int, cy: float) -> tuple:
    """(x, y, heading°) of a 4.5 × 1.8 m car standing in pocket i (piece coords)."""
    a = math.radians(KF_ANGLE)
    x0 = -12.0 + KF_PITCH * i
    t = 3.2                                    # car centre this far along the angled curb
    nx, ny = math.sin(a), -math.cos(a)         # from the curb towards the road
    return (x0 + t * math.cos(a) + nx * 1.3, cy + t * math.sin(a) + ny * 1.3, KF_ANGLE)


def curb_dropoff_segment() -> Piece:
    """Curb road + 6 m terminal sidewalk (piece 18 m deep, y -9..9, like curb_bus_bay) with three
    Kiss & Fly sawtooth pockets. "KISS &" / "FLY" stacked in each pocket, read in driving direction."""
    p = Piece("curb_dropoff_segment", (24.0, 18.0),
              "curb road + sidewalk with 3 Kiss & Fly sawtooth bays (drive in and out forwards)")
    cy = 2.5
    curb = kf_curb(cy)
    rect(p.lod0, -12, -9, 12, cy, 0.0, "asphalt")
    off = offset_polyline(curb, CURB_W)
    for i in range(len(curb) - 1):
        top(p.lod0, [curb[i], curb[i + 1], (curb[i + 1][0], cy), (curb[i][0], cy)], 0.0, "asphalt")
        top(p.lod0, [curb[i], curb[i + 1], off[i + 1], off[i]], CURB_H, "concrete")
        wall(p.lod0, curb[i], curb[i + 1], 0.0, CURB_H, "concrete")
        top(p.lod0, [off[i], off[i + 1], (off[i + 1][0], 9.0), (off[i][0], 9.0)], CURB_H, "paving")
    line(p.marks, [(-12, -8.5), (12, -8.5)], EDGE_W)
    dashed(p.marks, (-12, -5), (12, -5), DIVIDER_W, ONEWAY_PERIOD)
    dashed(p.marks, (-12, -1.5), (12, -1.5), LANE_BOUNDARY_W, ONEWAY_PERIOD)
    for i in range(3):
        x0 = -12.0 + KF_PITCH * i
        road_text(p.marks, ["KISS &", "FLY"], (x0 + 1.5, 0.95), 0.0, pitch=0.55)
    rect(p.far, -12, -9, 12, cy, 0.0, "asphalt")
    rect(p.far, -12, cy, 12, 9.0, CURB_H, "paving")
    return p


def curb_taxi_rank_4() -> Piece:
    p = Piece("curb_taxi_rank_4", (24.0, 12.0), "curb road with a 4-bay taxi rank (6 m, yellow), TAXI in each bay")
    _curb_base(p, 24.0, boundary=YELLOW)
    _bays(p, 24.0, 6.0, YELLOW)
    for i in range(4):
        road_text(p.marks, ["TAXI"], (-12.0 + 6.0 * i + 3.0, 3.5), 0.0, YELLOW)
    return p


def zebra_crossing() -> Piece:
    """Curb road with a 4 m zebra across all lanes and a lowered curb on the terminal side."""
    p = Piece("zebra_crossing", (8.0, 12.0), "curb road with a 4 m zebra crossing, lowered curb")
    zw = ZEBRA_WIDTH / 2
    rect(p.lod0, -4, -6, 4, CURB_Y, 0.0, "asphalt")
    _raised_strip(p.lod0, -4, 4, low=(-zw, zw))
    line(p.marks, [(-4, -5.5), (-zw - 0.5, -5.5)], EDGE_W)
    line(p.marks, [(zw + 0.5, -5.5), (4, -5.5)], EDGE_W)
    # Bars run along the traffic (U = walking direction). 11 bars of 0.5 m from y -5.5 to 5.0.
    line(p.marks, [(0, -5.5), (0, 5.0)], ZEBRA_WIDTH, "zebra", L.ZEBRA_PERIOD, 0.0)
    rect(p.far, -4, -6, 4, CURB_Y, 0.0, "asphalt")
    rect(p.far, -4, CURB_Y, 4, 6, CURB_H, "paving")
    return p


# Bus bay: shallow recess (real bays are at most ~3 m deep; a 12 m bus needs a 2.55 m wide stand,
# the 0.5 m gutter and the edge of the curbside lane give the rest).
BAY_RECESS = 1.5
BAY_ENTRY, BAY_EXIT = 6.0, 4.0                       # taper lengths (1 : 4 and 1 : 2.7)
SHELTER_POS = (1.0, 2.5 + BAY_RECESS + 1.2 + 0.65)   # bus_shelter origin in curb_bus_bay coords
BUS_POS = (1.0, 2.5 + BAY_RECESS - 0.25 - 1.275)     # where a 12 m bus stops (front door at x ~ 6)


def curb_bus_bay() -> Piece:
    """Curb road + 6 m terminal sidewalk (piece 18 m deep, y -9..9) with a bus bay recessed 1.5 m:
    6 m entry taper, 14 m stand, 4 m exit taper. The shelter goes at SHELTER_POS: 1.2 m boarding
    strip in front of it, 2.5 m clear walkway behind it. Tactile boarding field at the front door."""
    p = Piece("curb_bus_bay", (24.0, 18.0), "curb road + sidewalk with a shallow recessed bus bay (one 12 m bus)")
    cy = 2.5          # normal curb line (= 5.5 in the 12 m curb pieces)
    ry = cy + BAY_RECESS
    xa, xb = -12.0 + BAY_ENTRY, 12.0 - BAY_EXIT
    curb = [(-12.0, cy), (xa, ry), (xb, ry), (12.0, cy)]
    rect(p.lod0, -12, -9, 12, cy, 0.0, "asphalt")
    top(p.lod0, curb, 0.0, "asphalt")
    off = offset_polyline(curb, CURB_W)
    for i in range(3):
        top(p.lod0, [curb[i], curb[i + 1], off[i + 1], off[i]], CURB_H, "concrete")
        wall(p.lod0, curb[i], curb[i + 1], 0.0, CURB_H, "concrete")
        top(p.lod0, [off[i], off[i + 1], (off[i + 1][0], 9.0), (off[i][0], 9.0)], CURB_H, "paving")
    # Markings: through lanes as in the curb pieces (local y = curb piece y - 3).
    line(p.marks, [(-12, -8.5), (12, -8.5)], EDGE_W)
    dashed(p.marks, (-12, -5), (12, -5), DIVIDER_W, ONEWAY_PERIOD)
    dashed(p.marks, (-12, -1.5), (12, -1.5), LANE_BOUNDARY_W, ONEWAY_PERIOD)
    dashed(p.marks, (-12, cy - 0.15), (12, cy - 0.15), LANE_BOUNDARY_W, ONEWAY_PERIOD)
    road_text(p.marks, ["BUS"], (xa + 1.3, (cy - 0.3 + ry) / 2), 0.0, pitch=0.6)
    # Tactile boarding field (studs, 1.2 × 0.6 m) at the front door + ribbed guide strip to the
    # building line, as at real accessible stops.
    door_x = 6.0
    z = CURB_H
    for dx in (-0.3, 0.3):
        decal(p.marks, (door_x + dx, ry + CURB_W + 0.35), 0.0, 0.6, 0.6, "tactile_dots", z=z)
    for k in range(6):
        decal(p.marks, (door_x, ry + CURB_W + 0.95 + 0.6 * k), 0.0, 0.6, 0.6, "tactile_ribs", z=z)
    rect(p.far, -12, -9, 12, cy, 0.0, "asphalt")
    top(p.far, curb, 0.0, "asphalt")
    rect(p.far, -12, ry, 12, 9.0, CURB_H, "paving")
    top(p.far, [curb[0], curb[1], (-12.0, ry)], CURB_H, "paving")
    top(p.far, [curb[2], curb[3], (12.0, ry)], CURB_H, "paving")
    return p


# Sidewalk tiles: 2 × 2 m, top at CURB_H. Curb stones sit on the tile's open edges (-Y first).
def sidewalk_tile(kind: str) -> Piece:
    names = {"tile": "sidewalk_tile", "edge": "sidewalk_edge", "corner": "sidewalk_corner"}
    descs = {"tile": "sidewalk, paved, no curb", "edge": "sidewalk with curb on -Y",
             "corner": "sidewalk with curb on -Y and -X"}
    p = Piece(names[kind], (2.0, 2.0), descs[kind])
    e = -1.0 + CURB_W
    if kind == "tile":
        rect(p.lod0, -1, -1, 1, 1, CURB_H, "paving")
    elif kind == "edge":
        rect(p.lod0, -1, -1, 1, e, CURB_H, "concrete")
        rect(p.lod0, -1, e, 1, 1, CURB_H, "paving")
        wall(p.lod0, (-1, -1), (1, -1), 0.0, CURB_H, "concrete")
    else:
        rect(p.lod0, -1, -1, 1, e, CURB_H, "concrete")
        rect(p.lod0, -1, e, e, 1, CURB_H, "concrete")
        rect(p.lod0, e, e, 1, 1, CURB_H, "paving")
        wall(p.lod0, (-1, -1), (1, -1), 0.0, CURB_H, "concrete")
        wall(p.lod0, (-1, 1), (-1, -1), 0.0, CURB_H, "concrete")
    rect(p.far, -1, -1, 1, 1, CURB_H, "paving")
    return p


def _tactile_crossing(mb: MB, y: float, z: float) -> None:
    """Ribbed direction field (2.4 × 0.6 m) whose ribs point across the road (along Y)."""
    for k in range(4):
        decal(mb, (-0.9 + 0.6 * k, y), 0.0, 0.6, 0.6, "tactile_ribs", z=z)


def sidewalk_edge_lowered_4m() -> Piece:
    """4 × 2 m sidewalk edge with the curb lowered to 3 cm for a crossing; 1 m ramp behind it,
    then a tactile direction field pointing across the road."""
    p = Piece("sidewalk_edge_lowered_4m", (4.0, 2.0), "sidewalk edge, curb lowered to 3 cm, tactile field (crossing)")
    e = -1.0 + CURB_W
    r = e + 1.0
    rect(p.lod0, -2, -1, 2, e, CURB_LOW, "concrete")
    wall(p.lod0, (-2, -1), (2, -1), 0.0, CURB_LOW, "concrete")
    top(p.lod0, [(-2, e), (2, e), (2, r), (-2, r)], [CURB_LOW, CURB_LOW, CURB_H, CURB_H], "paving")
    rect(p.lod0, -2, r, 2, 1, CURB_H, "paving")
    for x, sgn in ((-2.0, 1), (2.0, -1)):
        # Side faces towards the full-height neighbours (front faces into the lowered area).
        pts = [(x, -1.0, CURB_LOW), (x, e, CURB_LOW), (x, r, CURB_H), (x, -1.0, CURB_H)]
        face_out(p.lod0, pts, "concrete", (sgn, 0, 0))
    _tactile_crossing(p.marks, r + 0.35, CURB_H)
    rect(p.far, -2, -1, 2, 1, CURB_H, "paving")
    return p


def sidewalk_tactile_landing() -> Piece:
    """4 × 2 m plain sidewalk with a tactile direction field on its -Y edge: the landing behind a
    lowered curb strip (terminal side of the zebra)."""
    p = Piece("sidewalk_tactile_landing", (4.0, 2.0), "sidewalk with tactile direction field (zebra landing)")
    rect(p.lod0, -2, -1, 2, 1, CURB_H, "paving")
    _tactile_crossing(p.marks, -0.65, CURB_H)
    rect(p.far, -2, -1, 2, 1, CURB_H, "paving")
    return p


def carpark_module() -> Piece:
    """One aisle (6 m) with a row of 2.5 × 5 m bays on both sides: 10 m long = 4 bays per row."""
    p = Piece("carpark_module", (10.0, 16.0), "car park: 6 m aisle + 4 bays (2.5 × 5 m) each side")
    rect(p.lod0, -5, -8, 5, 8, 0.0, "asphalt")
    for i in range(5):
        x = -5 + 2.5 * i
        w = BAY_W if 0 < i < 4 else BAY_W / 2
        xc = x + (w / 2 if i == 0 else -w / 2 if i == 4 else 0.0)
        line(p.marks, [(xc, -8), (xc, -3)], w)
        line(p.marks, [(xc, 3), (xc, 8)], w)
    rect(p.far, -5, -8, 5, 8, 0.0, "asphalt")
    return p


def carpark_end_aisle() -> Piece:
    p = Piece("carpark_end_aisle", (6.0, 16.0), "car park: 6 m cross aisle that links the module aisles")
    rect(p.lod0, -3, -8, 3, 8, 0.0, "asphalt")
    rect(p.far, -3, -8, 3, 8, 0.0, "asphalt")
    return p


def carpark_walkway(end: bool) -> Piece:
    """Pedestrian walkway through one module row (4 × 16 m, between two modules): raised island
    with a 2 m concrete path between 1 m grass strips in the bay zones (the island curb is the
    wheel stop), lowered curbs and a zebra across the 6 m aisle. `end`: closing face on -Y."""
    name = "carpark_walkway_end" if end else "carpark_walkway"
    p = Piece(name, (4.0, 16.0), "car park walkway: path island + zebra across the aisle"
              + (", closed -Y end" if end else ""))
    g = p.lod0
    rect(g, -2, -3, 2, 3, 0.0, "asphalt")
    low_end = 3.0 + CURB_W
    ramp_end = low_end + 1.0
    for s in (1, -1):
        def P(x, y):
            return (x, y * s)
        for x0, x1 in ((-2.0, -1.0), (1.0, 2.0)):                       # grass strips
            top(g, [P(x0, 3), P(x1, 3), P(x1, 8), P(x0, 8)], CURB_H, "grass")
            face_out(g, [(*P(x0, 3), 0.0), (*P(x1, 3), 0.0), (*P(x1, 3), CURB_H), (*P(x0, 3), CURB_H)],
                     "concrete", (0, -s, 0))
        for x, nx in ((-2.0, -1), (2.0, 1)):                           # island sides (wheel stops)
            face_out(g, [(*P(x, 3), 0.0), (*P(x, 8), 0.0), (*P(x, 8), CURB_H), (*P(x, 3), CURB_H)],
                     "concrete", (nx, 0, 0))
        # Path: lowered curb at the aisle, 1 m ramp, then flat.
        top(g, [P(-1, 3), P(1, 3), P(1, low_end), P(-1, low_end)], CURB_LOW, "concrete")
        top(g, [P(-1, low_end), P(1, low_end), P(1, ramp_end), P(-1, ramp_end)],
            [CURB_LOW, CURB_LOW, CURB_H, CURB_H], "concrete")
        top(g, [P(-1, ramp_end), P(1, ramp_end), P(1, 8), P(-1, 8)], CURB_H, "concrete")
        face_out(g, [(*P(-1, 3), 0.0), (*P(1, 3), 0.0), (*P(1, 3), CURB_LOW), (*P(-1, 3), CURB_LOW)],
                 "concrete", (0, -s, 0))
        for x, nx in ((-1.0, 1), (1.0, -1)):                           # grass edge above the ramp
            face_out(g, [(*P(x, 3), CURB_LOW), (*P(x, low_end), CURB_LOW), (*P(x, ramp_end), CURB_H),
                         (*P(x, 3), CURB_H)], "concrete", (nx, 0, 0))
    if end:
        face_out(g, [(-2, -8, 0.0), (2, -8, 0.0), (2, -8, CURB_H), (-2, -8, CURB_H)], "concrete", (0, -1, 0))
    line(p.marks, [(0, -2.75), (0, 2.75)], 2.0, "zebra", L.ZEBRA_PERIOD, 0.0)
    rect(p.far, -2, -3, 2, 3, 0.0, "asphalt")
    rect(p.far, -2, 3, 2, 8, CURB_H, "grass")
    rect(p.far, -2, -8, 2, -3, CURB_H, "grass")
    rect(p.far, -1, 3, 1, 8, CURB_H + 0.001, "concrete")
    rect(p.far, -1, -8, 1, -3, CURB_H + 0.001, "concrete")
    return p


def _boom(mb: MB, x: float, y0: float, y1: float) -> None:
    """Red / white striped boom (0.5 m stripes) along Y at height 0.85-0.95 m."""
    n = int(round(abs(y1 - y0) / 0.5))
    step = (y1 - y0) / n
    for i in range(n):
        a, b = sorted((y0 + i * step, y0 + (i + 1) * step))
        sides = "ew" + (("s" if y1 < y0 else "n") if i == n - 1 else "")  # cap only at the tip
        box(mb, x - 0.04, a, 0.85, x + 0.04, b, 0.95, "markings", bottom=True,
            col=RED if i % 2 else WHITE, uv_point=SOLID_UV, sides=sides)


def carpark_barrier_gate() -> Piece:
    """Car park entry + exit, driving direction +X = in. Entry lane y -6..-1, 2 m island with the
    ticket posts and barrier housings, exit lane y 1..6. Booms 4.9 m. The -X side meets the road
    with 2 m corner radii (footprint y -8..8); pair it with road_oneway_2lane_access."""
    p = Piece("carpark_barrier_gate", (8.0, 16.0), "car park entry/exit: 2 lanes, island, ticket posts, 2 booms")
    g = p.lod0
    rect(g, -4, -6, 4, -1, 0.0, "asphalt")
    rect(g, -4, 1, 4, 6, 0.0, "asphalt")
    rect(g, -4, -1, -3, 1, 0.0, "asphalt")
    rect(g, 3, -1, 4, 1, 0.0, "asphalt")
    for s in (1, -1):                                         # corner radii at the road
        arc = arc_points((-2.0, 8.0 * s), 2.0, math.pi, math.pi * (1.5 if s > 0 else 0.5), 4)
        for i in range(4):
            top(g, [(-4.0, 6.0 * s), arc[i], arc[i + 1]], 0.0, "asphalt")
    box(g, -3, -1, 0.0, 3, 1, CURB_H, "concrete")            # island
    # Entry (south lane, heading +X): ticket post before the boom, on the driver's (left) side.
    box(g, -1.9, -0.85, CURB_H, -1.5, -0.5, 1.35, "metal_dark")
    box(g, -1.88, -0.87, 0.95, -1.52, -0.85, 1.25, "markings", sides="s",
        uv_point=SOLID_UV, col=YELLOW)                                       # ticket panel
    box(g, 0.3, -0.85, CURB_H, 0.7, -0.45, 1.05, "metal_dark")                 # boom housing
    _boom(g, 0.5, -0.85, -5.75)
    # Exit (north lane, heading -X): mirrored.
    box(g, 1.5, 0.5, CURB_H, 1.9, 0.85, 1.35, "metal_dark")
    box(g, 1.52, 0.85, 0.95, 1.88, 0.87, 1.25, "markings", sides="n", uv_point=SOLID_UV, col=YELLOW)
    box(g, -0.7, 0.45, CURB_H, -0.3, 0.85, 1.05, "metal_dark")
    _boom(g, -0.5, 0.85, 5.75)
    # Stop lines 1 m before each boom, entry arrow, EXIT lettering, give-way line onto the road.
    line(p.marks, [(-0.6, -5.8), (-0.6, -1.0)], 0.3)
    line(p.marks, [(0.6, 1.0), (0.6, 5.8)], 0.3)
    arrow(p.marks, (-2.6, -3.5), 0.0, length=2.4)
    road_text(p.marks, ["EXIT"], (3.0, 3.5), math.pi)
    line(p.marks, [(-3.6, 1.0), (-3.6, 6.4)], GIVEWAY_W, "short_dash", 1.0, -0.25)
    rect(p.far, -4, -6, 4, 6, 0.0, "asphalt")
    rect(p.far, -3, -1, 3, 1, CURB_H + 0.001, "concrete")
    return p


def road_oneway_2lane_access() -> Piece:
    """One-way road with an access on its right (-Y) side over the whole 16 m: the edge line
    becomes a broken junction line, so cars can turn in and out (pairs with the barrier gate)."""
    p = Piece("road_oneway_2lane_access", (16.0, 8.0), "one-way road, access opening on the right side (car park gate)")
    rect(p.lod0, -8, -4, 8, 4, 0.0, "asphalt")
    line(p.marks, [(-8, 3.5), (8, 3.5)], EDGE_W)
    line(p.marks, [(-8, -3.5), (8, -3.5)], LANE_BOUNDARY_W, "short_dash", 2.0, -0.5)
    dashed(p.marks, (-8, 0), (8, 0), DIVIDER_W, ONEWAY_PERIOD)
    rect(p.far, -8, -4, 8, 4, 0.0, "asphalt")
    return p


def bus_shelter() -> Piece:
    """Glass + anthracite shelter, 5 × 1.3 m, open towards -Y (the bus bay). Footprint 6 × 2 m;
    its z = 0 is the sidewalk surface. Placed by curb_bus_bay at SHELTER_POS. Bench, departure
    display, stop sign."""
    p = Piece("bus_shelter", (6.0, 2.0), "bus shelter: glass + dark metal, bench, display, stop sign")
    s = p.lod0
    box(s, -2.5, -0.65, 2.4, 2.5, 0.65, 2.55, "metal_dark", bottom=True)        # roof
    for x in (-2.38, 2.3):
        for y in (-0.5, 0.42):
            box(s, x, y, 0.0, x + 0.08, y + 0.08, 2.4, "metal_dark")            # posts
    box(s, -2.3, 0.44, 0.0, 2.3, 0.48, 0.1, "metal_dark")                     # bottom rail
    s.face([(-2.3, 0.46, 0.1), (2.3, 0.46, 0.1), (2.3, 0.46, 2.4), (-2.3, 0.46, 2.4)],
           [(0, 0), (1, 0), (1, 1), (0, 1)], "glass")                          # back pane
    for x in (-2.34, 2.34):
        s.face([(x, -0.42, 0.1), (x, 0.42, 0.1), (x, 0.42, 2.4), (x, -0.42, 2.4)],
               [(0, 0), (1, 0), (1, 1), (0, 1)], "glass")                      # side panes
    box(s, -1.2, 0.05, 0.42, 1.2, 0.4, 0.47, "metal_light", bottom=True)       # bench seat
    for x in (-1.0, 0.95):
        box(s, x, 0.25, 0.0, x + 0.05, 0.4, 0.42, "metal_light")               # bench legs
    box(s, -0.45, -0.6, 2.0, 0.45, -0.5, 2.4, "metal_dark", bottom=True)        # display housing
    s.face([(-0.4, -0.601, 2.04), (0.4, -0.601, 2.04), (0.4, -0.601, 2.34), (-0.4, -0.601, 2.34)],
           [(0, 0), (1, 0), (1, 1), (0, 1)], "metal_light")                    # display face
    box(s, 2.75, -0.65, 0.0, 2.81, -0.59, 2.7, "metal_light")                   # stop sign pole
    # Stop sign: yellow disc with a green "H" (fictional regional style), both faces.
    ring = [(2.78 + 0.25 * math.cos(2 * math.pi * k / 12), 2.42 + 0.25 * math.sin(2 * math.pi * k / 12)) for k in range(12)]
    for yy, sgn in ((-0.665, -1), (-0.575, 1)):
        face_pts = [(x_, yy, z_) for x_, z_ in ring]
        s.face(face_pts if sgn > 0 else face_pts[::-1], [SOLID_UV] * 12, "markings", tint(BUS_SIGN_YELLOW))
        lw = 0.22
        u0, v0, u1, v1 = rect_uv(L.road_letter_rect("H"))
        xa, xb = (2.78 - lw / 2, 2.78 + lw / 2) if sgn < 0 else (2.78 + lw / 2, 2.78 - lw / 2)
        yl = yy + 0.002 * sgn
        s.face([(xa, yl, 2.42 - 0.13), (xb, yl, 2.42 - 0.13), (xb, yl, 2.42 + 0.13), (xa, yl, 2.42 + 0.13)],
               [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], "markings", tint(BUS_SIGN_GREEN))
    box(p.far, -2.5, -0.65, 0.0, 2.5, 0.65, 2.55, "metal_dark")
    return p


BUS_SIGN_YELLOW = "#E8B830"
BUS_SIGN_GREEN = "#2F7D4F"
WAYFINDING_YELLOW = "#E8B830"


def _letters(mb: MB, text: str, x0: float, y: float, zc: float, h: float, col: tuple, facing: int = -1) -> float:
    """Upright sign letters from the road-letter atlas cells, natural proportions (the cells are
    pre-squeezed 2.6 : 1, so a quad of width h / 1.18 un-squeezes them). Returns the end x."""
    w = h * L.ROAD_LETTER_CELL[0] / L.ROAD_LETTER_CELL[1] * 2.6
    x = x0
    for ch in text:
        if ch != " ":
            u0, v0, u1, v1 = rect_uv(L.road_letter_rect(ch))
            mb.face([(x, y, zc - h / 2), (x + w, y, zc - h / 2), (x + w, y, zc + h / 2), (x, y, zc + h / 2)],
                    [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], "markings", col)
        x += w * 0.92
    return x


def _sign_arrow(mb: MB, xc: float, y: float, zc: float, size: float, left: bool, col: tuple) -> None:
    s_ = -1 if left else 1
    pts = [(-0.5, -0.08), (0.1, -0.08), (0.1, -0.25), (0.5, 0.0), (0.1, 0.25), (0.1, 0.08), (-0.5, 0.08)]
    p3 = [(xc + s_ * px * size, y, zc + pz * size) for px, pz in pts]
    shaft = [p3[0], p3[1], p3[5], p3[6]]
    head = [p3[2], p3[3], p3[4]]
    for poly in (shaft, head):
        if left:
            poly = poly[::-1]
        mb.face(poly, [SOLID_UV] * len(poly), "markings", col)


def sign_wayfinding() -> Piece:
    """Airport wayfinding sign (yellow / anthracite), readable from -Y: P <-, BUS ->, TAXI ->."""
    p = Piece("sign_wayfinding", (1.4, 0.2), "wayfinding sign 1.2 × 0.9 m: P, BUS, TAXI with arrows")
    g = p.lod0
    for x in (-0.5, 0.44):
        box(g, x, 0.0, 0.0, x + 0.06, 0.06, 2.9, "metal_dark")
    box(g, -0.62, -0.03, 2.0, 0.62, 0.0, 2.92, "metal_dark", sides="nesw", bottom=True)
    dark = tint("#2E3236")
    yel = tint(WAYFINDING_YELLOW)
    for k, (text, left) in enumerate((("P", True), ("BUS", False), ("TAXI", False))):
        zc = 2.77 - k * 0.3
        y = -0.031
        g.face([(-0.58, y, zc - 0.13), (0.58, y, zc - 0.13), (0.58, y, zc + 0.13), (-0.58, y, zc + 0.13)],
               [SOLID_UV] * 4, "markings", yel)
        _letters(g, text, -0.5 if not left else -0.08, y - 0.001, zc, 0.17, dark)
        _sign_arrow(g, 0.38 if not left else -0.36, y - 0.001, zc, 0.3, left, dark)
    return p


def tree_deciduous() -> Piece:
    """Low-poly deciduous tree, ~8 m: trunk + two crowns (subdivided icosahedra), crown colours
    differ slightly (vertex colour). Drawn as MultiMesh in the game; _lodfar = flat crown disc."""
    p = Piece("tree_deciduous", (5.0, 5.0), "tree ~8 m, trunk + 2 crowns")
    cylinder(p.lod0, 0, 0, 0.0, 3.4, 0.16, "bark", n=6, r1=0.1, cap=False)
    for c, r, col in (((0.0, 0.0, 5.2), 2.4, (1.0, 1.0, 1.0, 1.0)), ((0.6, -0.4, 6.6), 1.7, (1.12, 1.15, 1.0, 1.0))):
        _ico(p.lod0, c, r, (1.0, 1.0, 0.85), "foliage", col)
    hexa = [(2.3 * math.cos(2 * math.pi * k / 6), 2.3 * math.sin(2 * math.pi * k / 6)) for k in range(6)]
    top(p.far, hexa, 0.05, "foliage")
    return p


def hedge_2m() -> Piece:
    """Clipped hedge, 2 × 0.8 m, 1.1 m high (planted islands, car park edges)."""
    p = Piece("hedge_2m", (2.0, 0.8), "hedge 2 × 0.8 × 1.1 m")
    box(p.lod0, -1.0, -0.4, 0.0, 1.0, 0.4, 1.1, "foliage", col=(0.85, 0.9, 0.85, 1.0))
    rect(p.far, -1.0, -0.4, 1.0, 0.4, 0.05, "foliage")
    return p


def _ico(mb: MB, c, r: float, scale: tuple, mat: str, col: tuple) -> None:
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
         (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
         (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]

    def norm(a):
        ln = math.sqrt(sum(x * x for x in a))
        return tuple(x / ln for x in a)

    v = [norm(a) for a in v]
    tris = []
    for a, b, cc in f:                                   # one subdivision: 80 triangles
        ab = norm(tuple((v[a][i] + v[b][i]) / 2 for i in range(3)))
        bc = norm(tuple((v[b][i] + v[cc][i]) / 2 for i in range(3)))
        ca = norm(tuple((v[cc][i] + v[a][i]) / 2 for i in range(3)))
        tris += [(v[a], ab, ca), (ab, v[b], bc), (ca, bc, v[cc]), (ab, bc, ca)]
    import random as _r
    rng = _r.Random(11)
    for tri in tris:
        pts = []
        for q in tri:
            jitter = 1.0 + 0.08 * math.sin(q[0] * 7.1 + q[1] * 5.3 + q[2] * 3.7)
            pts.append((c[0] + q[0] * r * scale[0] * jitter, c[1] + q[1] * r * scale[1] * jitter,
                        c[2] + q[2] * r * scale[2] * jitter))
        shade = 0.9 + 0.2 * rng.random()
        mb.face(pts, [(0, 0)] * 3, mat, tuple(min(1.5, k * shade) for k in col[:3]) + (1.0,))


def _wear(name: str, size: tuple, desc: str) -> Piece:
    from landside_textures import DECALS
    p = Piece(name, size, desc)
    rect_px = DECALS[name.replace("decal_", "")][0]
    x, y, w, h = rect_px
    n = 512.0
    u0, v0, u1, v1 = x / n, 1 - (y + h) / n, (x + w) / n, 1 - y / n
    hx, hy = size[0] / 2, size[1] / 2
    z = Z_MARK + 2 * Z_LAYER
    p.marks.face([(-hx, -hy, z), (hx, -hy, z), (hx, hy, z), (-hx, hy, z)],
                 [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], "decals")
    return p


def wear_decals() -> list:
    return [_wear("decal_oil_stain", (1.2, 1.2), "oil stain (bay centre)"),
            _wear("decal_patch", (2.0, 2.0), "asphalt repair patch"),
            _wear("decal_drain_grate", (0.5, 1.0), "gully grate in the gutter"),
            _wear("decal_tyre_marks", (6.0, 0.7), "faint tyre marks (barrier, curbs)")]


# --- Small props (hidden in the build view: no _lodfar, use visibility_range_end) --------------
def bollard() -> Piece:
    """Round steel anti-ram bollard, 0.9 m high, 0.2 m diameter, light reflective band.
    Line along the terminal curb: one every 1.5 m (1.3 m clear), 0.75 m behind the curb face."""
    p = Piece("bollard", (0.2, 0.2), "steel bollard Ø 0.2 × 0.9 m (anti-ram line)")
    cylinder(p.lod0, 0, 0, 0.0, 0.72, 0.1, "metal_dark", cap=False)
    cylinder(p.lod0, 0, 0, 0.72, 0.78, 0.1, "metal_light", cap=False)
    cylinder(p.lod0, 0, 0, 0.78, 0.9, 0.1, "metal_dark")
    return p


def light_mast() -> Piece:
    """Car park / street light: 10 m galvanised mast, two flat LED heads on a crossarm."""
    p = Piece("light_mast", (0.4, 0.4), "light mast 10 m, two LED heads")
    cylinder(p.lod0, 0, 0, 0.0, 9.6, 0.11, "metal_light", n=6, r1=0.06, cap=False)
    box(p.lod0, -0.9, -0.04, 9.55, 0.9, 0.04, 9.65, "metal_light", bottom=True)
    for x in (-1.25, 0.55):
        box(p.lod0, x, -0.22, 9.5, x + 0.7, 0.22, 9.62, "metal_dark", bottom=True)
    return p


def fence_panel_2m() -> Piece:
    """2 m welded mesh fence panel, 2 m high, post at -X (add fence_post at the end of a run).
    Mesh is the alpha atlas piece on two back-to-back quads (visible from both sides)."""
    p = Piece("fence_panel_2m", (2.0, 0.1), "mesh fence panel 2 × 2 m + post")
    box(p.lod0, -1.03, -0.03, 0.0, -0.97, 0.03, 2.05, "metal_dark")
    sign_face(p.lod0, (-0.97, 0.0), (1.03, 0.0), 0.05, 2.0, "fence_mesh")
    sign_face(p.lod0, (1.03, 0.005), (-0.97, 0.005), 0.05, 2.0, "fence_mesh")
    rect(p.far, -1, -0.05, 1, 0.05, 0.01, "metal_dark")          # thin line for the build view
    return p


def fence_post() -> Piece:
    p = Piece("fence_post", (0.1, 0.1), "fence post (end / corner of a run)")
    box(p.lod0, -0.03, -0.03, 0.0, 0.03, 0.03, 2.05, "metal_dark")
    return p


def fence_gate_pedestrian() -> Piece:
    """4 m fence piece with a 2 m pedestrian opening between two gate posts (open passage)."""
    p = Piece("fence_gate_pedestrian", (4.0, 0.1), "fence: 1 m panels, 2 m pedestrian opening")
    g = p.lod0
    box(g, -2.03, -0.03, 0.0, -1.97, 0.03, 2.05, "metal_dark")
    for x in (-1.06, 0.96):                                        # gate posts
        box(g, x, -0.05, 0.0, x + 0.1, 0.05, 2.2, "metal_dark")
    u0, v0, u1, v1 = rect_uv("fence_mesh")
    um = (u0 + u1) / 2
    for a, b, ua, ub in ((-1.97, -1.06, u0, um), (1.06, 1.97, um, u1)):
        g.face([(a, 0, 0.05), (b, 0, 0.05), (b, 0, 2.0), (a, 0, 2.0)], [(ua, v0), (ub, v0), (ub, v1), (ua, v1)], "markings")
        g.face([(b, 0.005, 0.05), (a, 0.005, 0.05), (a, 0.005, 2.0), (b, 0.005, 2.0)],
               [(ub, v0), (ua, v0), (ua, v1), (ub, v1)], "markings")
    rect(p.far, -2, -0.05, -1, 0.05, 0.01, "metal_dark")
    rect(p.far, 1, -0.05, 2, 0.05, 0.01, "metal_dark")
    return p


def carpark_info_board() -> Piece:
    """Tariff / information board (2 × 1 m face) on two posts, readable from -Y."""
    p = Piece("carpark_info_board", (2.0, 0.2), "car park tariff board 2 × 1 m on posts")
    g = p.lod0
    for x in (-0.8, 0.74):
        box(g, x, 0.0, 0.0, x + 0.06, 0.06, 2.1, "metal_dark")
    box(g, -1.05, -0.02, 1.0, 1.05, 0.0, 2.05, "metal_dark", sides="nesw", bottom=True)
    sign_face(g, (-1.0, -0.021), (1.0, -0.021), 1.03, 2.02, "parking_board")
    return p


def sign_parking() -> Piece:
    """German parking sign (Zeichen 314): blue square, white "P", white border, standard size
    0.6 × 0.6 m, lower edge 2.0 m above ground (StVO clearance over footways), on a 76 mm
    galvanised pole with two clamps. Readable from -Y."""
    p = Piece("sign_parking", (1.0, 0.2), "parking sign Zeichen 314, 0.6 × 0.6 m on pole")
    g = p.lod0
    cylinder(g, 0, 0.05, 0.0, 2.65, 0.038, "metal_light", n=8)
    box(g, -0.30, -0.02, 2.0, 0.30, 0.0, 2.6, "metal_light", sides="nesw", bottom=True)    # sign plate, grey back
    for z in (2.12, 2.48):                                                                # pole clamps
        box(g, -0.05, 0.0, z - 0.02, 0.05, 0.1, z + 0.02, "metal_light", sides="nesw")
    sign_face(g, (-0.30, -0.021), (0.30, -0.021), 2.0, 2.6, "p_sign")
    return p


def pay_station() -> Piece:
    """Pay machine (pay before returning to the car), front = -Y: P header, screen, card panel."""
    p = Piece("pay_station", (0.8, 0.6), "car park pay station 0.7 × 0.45 × 1.8 m")
    g = p.lod0
    box(g, -0.35, -0.22, 0.0, 0.35, 0.22, 1.8, "metal_dark")
    sign_face(g, (-0.2, -0.221), (0.2, -0.221), 1.38, 1.78, "p_sign")
    g.face([(-0.25, -0.222, 1.0), (0.25, -0.222, 1.0), (0.25, -0.222, 1.3), (-0.25, -0.222, 1.3)],
           [SOLID_UV] * 4, "markings", tint("#9FB6BF"))                    # screen
    g.face([(-0.25, -0.222, 0.7), (0.25, -0.222, 0.7), (0.25, -0.222, 0.92), (-0.25, -0.222, 0.92)],
           [SOLID_UV] * 4, "markings", YELLOW)                             # card / ticket panel
    return p


def all_pieces() -> list:
    return [
        road_country_straight(), road_country_tjunction(False), road_country_tjunction(True),
        road_oneway_2lane_straight(False), road_oneway_2lane_straight(True), road_oneway_corner(),
        road_oneway_2lane_access(),
        curb_plain_segment(False), curb_plain_segment(True), curb_dropoff_segment(), zebra_crossing(),
        curb_bus_bay(), curb_taxi_rank_4(),
        sidewalk_tile("tile"), sidewalk_tile("edge"), sidewalk_tile("corner"), sidewalk_edge_lowered_4m(),
        sidewalk_tactile_landing(),
        carpark_module(), carpark_end_aisle(), carpark_walkway(False), carpark_walkway(True),
        carpark_barrier_gate(), bus_shelter(),
        bollard(), light_mast(), fence_panel_2m(), fence_post(), fence_gate_pedestrian(),
        carpark_info_board(), sign_parking(), pay_station(), sign_wayfinding(),
        tree_deciduous(), hedge_2m(),
    ] + wear_decals()


def build_objects(piece: Piece, mats: dict, collection=None) -> list:
    """LOD0 (+ markings) and lodfar (if any) as objects at the origin. Markings cast no shadow."""
    objs = [piece.lod0.build(piece.name, mats, collection)] if piece.lod0.faces else []
    if piece.marks.faces:
        m = piece.marks.build(piece.name + ("_markings" if objs else ""), mats, collection)
        m.visible_shadow = False
        objs.append(m)
    if piece.far.faces:
        objs.append(piece.far.build(piece.name + "_lodfar", mats, collection))
    return objs
