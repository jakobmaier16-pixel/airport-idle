"""Terminal shell kit: shared materials and one builder per modular piece.

Used by terminal_pieces.py (exports every piece as .glb + overview) and terminal_preview.py
(assembles the example L-shaped hall next to the landside start layout). Rules: kit.md.

Conventions (docs/art_direction.md §2, §7, same as the landside kit):
- Real metres, 1 cell = 2 m, column grid = 12 m (6 cells). +Z up, front / outside = -Y.
- Bay pieces (floor, ceiling, roof): origin at the bay centre on the ground, 12 × 12 m.
- Edge pieces (facades, join, canopy): origin on the hall boundary line at the middle of the
  12 m edge, ground level; the hall is on +Y, outside on -Y.
- Point pieces (column, corners): origin at the grid point, ground level.
- Hall floor = sidewalk level (z 0.15, barrier-free), ceiling 10 m, roof 12 m, parapet 12.4 m.
"""
import math
import os
import sys

import bpy

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "landside"))
import landside_kit as K  # noqa: E402  (MB, box, cylinder, flat materials, UV conventions)
from terminal_textures import ATLAS, EMI  # noqa: E402

TEX = K.TEX
BAY = 12.0
H = BAY / 2
FLOOR_Z = K.CURB_H        # 0.15: hall floor level with the terminal sidewalk
CEIL_Z = 10.0             # clear height ~10 m
ROOF_Z = 12.0
PARAPET_Z = 12.4
BAND_D = 0.3              # attic band / corner post depth outside the boundary line
GLASS_Y = -0.1            # glass plane, just outside the boundary line
MUL_W = 0.06              # mullion width (two halves of 0.03 at bay borders)
MUL_Y0, MUL_Y1 = -0.25, 0.05
TRANSOMS = (3.3, 6.65)
COLUMN_R = 0.3
COLUMN_INSET = 0.6        # perimeter columns stand this far inside the boundary line
DOOR_W = 4.0              # entrance: jamb to jamb
DOOR_H = 2.5              # clear opening height (sliding leaves)
LOBBY_D = 4.5             # wind lobby depth
CANOPY_Z = 6.0            # canopy soffit
CANOPY_D = 10.0           # cantilever: 6.5 m sidewalk + 3.5 m curbside lane
SLAT_PITCH, SLAT_W, SLAT_D = 0.6, 0.25, 0.15
UV1 = {"terrazzo_dark": 0.5, "wood_oak": 1.0, "concrete": 0.2}


# --- Materials (mirror assets/materials/*.tres) -------------------------------------------------
def _textured(name: str, emission: bool = False) -> bpy.types.Material:
    """albedo + ORM (terrazzo, oak) or albedo + emission (emissive_lights atlas)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    s = UV1.get(name, 1.0)
    mapping.inputs["Scale"].default_value = (s, s, 1.0)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])

    def tex(m: str, non_color: bool) -> bpy.types.Node:
        n = nodes.new("ShaderNodeTexImage")
        n.image = K._img(os.path.join(TEX, name, f"{name}_{m}.png"), non_color)
        if emission:
            n.interpolation = "Closest"
        links.new(mapping.outputs["Vector"], n.inputs["Vector"])
        return n

    albedo = tex("albedo", False)
    if emission:
        links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
        e = tex("emission", False)
        links.new(e.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0
        bsdf.inputs["Roughness"].default_value = 0.4
        return mat
    orm = tex("orm", True)
    sep = nodes.new("ShaderNodeSeparateColor")
    links.new(orm.outputs["Color"], sep.inputs["Color"])
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(albedo.outputs["Color"], mul.inputs[6])
    links.new(sep.outputs["Red"], mul.inputs[7])
    links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def make_materials(existing: dict | None = None) -> dict:
    """Shared library entries the kit uses. Reuses materials already in `existing` (preview)."""
    mats = dict(existing or {})
    if "concrete" not in mats:
        mats["concrete"] = K._tiled("concrete")
    for n, args in (("metal_dark", ("#2E3236", 0.45, 1.0)), ("metal_light", ("#8A9096", 0.35, 1.0))):
        if n not in mats:
            mats[n] = K.flat(n, *args)
    if "glass" not in mats:
        mats["glass"] = K.flat("glass", "#9FB6BF", 0.05, 0.0, alpha=0.25)
    mats["terrazzo_dark"] = _textured("terrazzo_dark")
    mats["wood_oak"] = _textured("wood_oak")
    mats["emissive_lights"] = _textured("emissive_lights", emission=True)
    return mats


# --- Geometry helpers ---------------------------------------------------------------------------
def cell_uv(cell: str, inset: float = 2.0) -> tuple:
    x, y, w, h = ATLAS[cell]
    return ((x + inset) / EMI, 1.0 - (y + h - inset) / EMI, (x + w - inset) / EMI, 1.0 - (y + inset) / EMI)


def solid_uv(cell: str) -> tuple:
    u0, v0, u1, v1 = cell_uv(cell)
    return ((u0 + u1) / 2, (v0 + v1) / 2)


def sign_face(mb: K.MB, x0, x1, y, z0, z1, cell: str, facing: str = "-y") -> None:
    """Vertical atlas face, readable from `facing` (-y or +y)."""
    u0, v0, u1, v1 = cell_uv(cell)
    uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    if facing == "-y":
        mb.face([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], uvs, "emissive_lights")
    else:
        mb.face([(x1, y, z0), (x0, y, z0), (x0, y, z1), (x1, y, z1)], uvs, "emissive_lights")


def down(mb: K.MB, x0, y0, x1, y1, z, mat: str, uv_point: tuple | None = None) -> None:
    """Downward-facing rectangle (ceilings, soffits)."""
    pts = [(x0, y0, z), (x0, y1, z), (x1, y1, z), (x1, y0, z)]
    uvs = [uv_point] * 4 if uv_point else [(p[0] * K.UV_PER_M, p[1] * K.UV_PER_M) for p in pts]
    mb.face(pts, uvs, mat)


def vquad(mb: K.MB, x0, x1, y, z0, z1, mat: str, facing: str = "-y") -> None:
    """Vertical rectangle in the plane y, facing -y or +y, world-scale UVs."""
    if facing == "-y":
        pts = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    else:
        pts = [(x1, y, z0), (x0, y, z0), (x0, y, z1), (x1, y, z1)]
    mb.face(pts, [(p[0] * K.UV_PER_M, p[2] * K.UV_PER_M) for p in pts], mat)


def xquad(mb: K.MB, x, y0, y1, z0, z1, mat: str, facing: str = "+x") -> None:
    """Vertical rectangle in the plane x, facing +x or -x."""
    if facing == "+x":
        pts = [(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)]
    else:
        pts = [(x, y1, z0), (x, y0, z0), (x, y0, z1), (x, y1, z1)]
    mb.face(pts, [(p[1] * K.UV_PER_M, p[2] * K.UV_PER_M) for p in pts], mat)


def rod(mb: K.MB, p0: tuple, p1: tuple, r: float, mat: str) -> None:
    """Square prism from p0 to p1 (tension rods, hangers), open ends."""
    d = [b - a for a, b in zip(p0, p1)]
    ln = math.sqrt(sum(c * c for c in d))
    d = [c / ln for c in d]
    ref = (0, 0, 1) if abs(d[2]) < 0.9 else (1, 0, 0)
    u = [d[1] * ref[2] - d[2] * ref[1], d[2] * ref[0] - d[0] * ref[2], d[0] * ref[1] - d[1] * ref[0]]
    un = math.sqrt(sum(c * c for c in u))
    u = [c / un * r for c in u]
    v = [d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0]]
    offs = [[u[i] + v[i] for i in range(3)], [-u[i] + v[i] for i in range(3)],
            [-u[i] - v[i] for i in range(3)], [u[i] - v[i] for i in range(3)]]
    for k in range(4):
        a, b = offs[k], offs[(k + 1) % 4]
        pts = [tuple(p0[i] + a[i] for i in range(3)), tuple(p0[i] + b[i] for i in range(3)),
               tuple(p1[i] + b[i] for i in range(3)), tuple(p1[i] + a[i] for i in range(3))]
        mb.face(pts, [(0, 0), (0, 0), (ln * K.UV_PER_M, 0), (ln * K.UV_PER_M, 0)], mat)


def exit_sign(mb: K.MB, x: float, y: float, z: float, facing: str = "+y") -> None:
    """0.4 × 0.2 m backlit exit sign box, 4 cm deep, mounted with its back on the plane y."""
    s = 1 if facing == "+y" else -1
    y1 = y + s * 0.04
    K.box(mb, x - 0.2, min(y, y1), z, x + 0.2, max(y, y1), z + 0.2, "emissive_lights", bottom=True,
          uv_point=solid_uv("dark"), sides="ew")
    sign_face(mb, x - 0.19, x + 0.19, y1, z + 0.01, z + 0.19, "exit", facing)


def fire_cabinet(mb: K.MB, x: float, y: float, facing: str = "+y") -> None:
    """Wall cabinet for a fire extinguisher + hose (0.6 × 0.25 × 0.9 m at 0.9 m) and its sign."""
    s = 1 if facing == "+y" else -1
    y1 = y + s * 0.25
    z0 = FLOOR_Z + 0.9
    K.box(mb, x - 0.3, min(y, y1), z0, x + 0.3, max(y, y1), z0 + 0.9, "metal_light", bottom=True,
          sides="ew" + ("n" if s > 0 else "s"))
    # Door seam: a thin dark line 1 mm proud of the front.
    yf = y1 + s * 0.001
    if s > 0:
        vquad(mb, x - 0.01, x + 0.01, yf, z0 + 0.05, z0 + 0.85, "metal_dark", "+y")
    else:
        vquad(mb, x - 0.01, x + 0.01, yf, z0 + 0.05, z0 + 0.85, "metal_dark", "-y")
    sign_face(mb, x - 0.1, x + 0.1, y + s * 0.002, z0 + 1.0, z0 + 1.2, "fire", facing)


# --- Pieces -------------------------------------------------------------------------------------
class Piece(K.Piece):
    def __init__(self, name: str, kind: str, size: tuple, desc: str) -> None:
        super().__init__(name, size, desc)
        self.kind = kind          # bay / edge / point / prop
        self.smooth_mats: tuple = ()


def floor_bay() -> Piece:
    p = Piece("terminal_floor_bay", "bay", (BAY, BAY), "dark terrazzo floor, 12 × 12 m bay")
    K.rect(p.lod0, -H, -H, H, H, FLOOR_Z, "terrazzo_dark")
    # Movement joints (stainless) only on the -X and -Y borders: every bay owns two of its four
    # edges, so neighbours never double a strip.
    K.rect(p.lod0, -H, -H, H, -H + 0.03, FLOOR_Z + 0.001, "metal_light")
    K.rect(p.lod0, -H, -H + 0.03, -H + 0.03, H, FLOOR_Z + 0.001, "metal_light")
    # Floor drain (cleaning drain, 0.25 m stainless grate) off the column line.
    K.rect(p.lod0, 2.875, 2.875, 3.125, 3.125, FLOOR_Z + 0.001, "metal_light")
    for i in range(4):
        x = 2.905 + i * 0.06
        K.rect(p.lod0, x, 2.9, x + 0.02, 3.1, FLOOR_Z + 0.0015, "metal_dark")
    K.rect(p.far, -H, -H, H, H, FLOOR_Z, "terrazzo_dark")
    return p


def ceiling_bay() -> Piece:
    p = Piece("terminal_ceiling_bay", "bay", (BAY, BAY),
              "oak slat ceiling at 10 m, two linear lights, diffuser, sprinklers, sign hangers")
    mb = p.lod0
    down(mb, -H, -H, H, H, CEIL_Z, "metal_dark")              # dark acoustic backing
    zb = CEIL_Z - SLAT_D
    n = int(BAY / SLAT_PITCH)
    for k in range(n):                                        # slats along X (oak grain along U)
        yc = -H + SLAT_PITCH * (k + 0.5)
        y0, y1 = yc - SLAT_W / 2, yc + SLAT_W / 2
        down(mb, -H, y0, H, y1, zb, "wood_oak")
        vquad(mb, -H, H, y0, zb, CEIL_Z, "wood_oak", "-y")
        vquad(mb, -H, H, y1, zb, CEIL_Z, "wood_oak", "+y")
    # Gaps sit on multiples of 0.6 m from the bay edge: lights at y = ±3, diffuser at y = 0.
    for y in (-3.0, 3.0):
        down(mb, -H, y - 0.1, H, y + 0.1, CEIL_Z - 0.04, "emissive_lights", solid_uv("light_warm"))
    down(mb, -4.0, -0.12, 4.0, 0.12, CEIL_Z - 0.03, "metal_light")       # linear air diffuser
    for i in range(16):                                                   # its slots
        x = -3.9 + i * 0.5
        down(mb, x, -0.08, x + 0.3, 0.08, CEIL_Z - 0.031, "metal_dark")
    # Pendant sprinklers in the gaps (3 × 3 m grid, real spacing).
    for x in (-4.5, -1.5, 1.5, 4.5):
        for y in (-4.8, 1.2):
            K.box(mb, x - 0.03, y - 0.03, zb - 0.06, x + 0.03, y + 0.03, CEIL_Z, "metal_light",
                  bottom=True, sides="nesw")
    # Sign hanging points (unistrut plates + drop rods) where the code lane hangs wayfinding.
    for x in (-1.5, 1.5):
        K.box(mb, x - 0.08, -1.88, zb - 0.02, x + 0.08, -1.72, zb, "metal_dark", bottom=True)
        rod(mb, (x, -1.8, zb - 0.02), (x, -1.8, zb - 0.45), 0.008, "metal_dark")
    return p


def roof_bay() -> Piece:
    p = Piece("terminal_roof_bay", "bay", (BAY, BAY), "flat roof at 12 m with a roof drain")
    K.rect(p.lod0, -H, -H, H, H, ROOF_Z, "concrete")
    K.box(p.lod0, -0.2, -0.2, ROOF_Z, 0.2, 0.2, ROOF_Z + 0.08, "metal_dark")    # roof drain
    K.box(p.lod0, -3.6, 2.4, ROOF_Z, -2.4, 3.6, ROOF_Z + 0.9, "metal_light")    # smoke vent hatch
    K.rect(p.far, -H, -H, H, H, ROOF_Z, "concrete")
    return p


def column() -> Piece:
    p = Piece("terminal_column", "point", (0.7, 0.7),
              "round column, light-oak cladding, steel base shoe + plate and head ring")
    mb = p.lod0
    K.rect(mb, -0.35, -0.35, 0.35, 0.35, FLOOR_Z + 0.012, "metal_dark")         # base plate
    K.cylinder(mb, 0, 0, FLOOR_Z, FLOOR_Z + 0.25, COLUMN_R + 0.015, "metal_dark", n=16, cap=False)
    K.cylinder(mb, 0, 0, FLOOR_Z + 0.25, CEIL_Z - 0.6, COLUMN_R, "wood_oak", n=16, cap=False)
    K.cylinder(mb, 0, 0, CEIL_Z - 0.6, CEIL_Z, COLUMN_R + 0.015, "metal_dark", n=16, cap=False)
    # Cladding grain runs vertically: swap the cylinder UVs (u = height, v = around).
    circ = 2 * math.pi * COLUMN_R * K.UV_PER_M
    for fi, uvs in enumerate(mb.uvs):
        if mb.mat_names[mb.face_mat[fi]] == "wood_oak":
            mb.uvs[fi] = [(v, u * circ) for u, v in uvs]
    p.smooth_mats = ("wood_oak", "metal_dark")
    return p


def _band(mb: K.MB, x0: float = -H, x1: float = H) -> None:
    """Attic band (roof edge) in anthracite + the dark interior ceiling header."""
    K.box(mb, x0, -BAND_D, CEIL_Z, x1, 0.0, PARAPET_Z, "metal_dark", bottom=True, sides="sn")
    K.box(mb, x0, 0.0, CEIL_Z - 0.5, x1, 0.1, CEIL_Z, "metal_dark", bottom=True, sides="n")


def _plinth(mb: K.MB, x0: float, x1: float) -> None:
    K.box(mb, x0, -BAND_D, 0.0, x1, 0.0, 0.3, "metal_dark", sides="s")
    K.box(mb, x0, 0.0, FLOOR_Z, x1, 0.04, FLOOR_Z + 0.1, "metal_dark", sides="n")   # skirting


def _mullion(mb: K.MB, x: float, z0: float, z1: float, w: float = MUL_W) -> None:
    """Mullion centred on x; at the bay border (|x| = 6) only the half inside the piece is
    built, without its border face, so two neighbours form one mullion."""
    x0, x1 = max(x - w / 2, -H), min(x + w / 2, H)
    sides = "sn" + ("" if x1 >= H else "e") + ("" if x0 <= -H else "w")
    K.box(mb, x0, MUL_Y0, z0, x1, MUL_Y1, z1, "metal_dark", sides=sides)


def _transom(mb: K.MB, x0: float, x1: float, z: float) -> None:
    K.box(mb, x0, MUL_Y0 + 0.03, z - 0.03, x1, MUL_Y1 - 0.03, z + 0.03, "metal_dark", bottom=True, sides="sn")


def _curtain_wall(mb: K.MB, door: bool) -> None:
    z0 = 0.3
    xs = [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]
    if door:
        for x in xs:
            if abs(x) == 2.0:
                _mullion(mb, x, FLOOR_Z, CEIL_Z, 0.12)       # door jambs, floor to ceiling
            elif x != 0.0:
                _mullion(mb, x, z0, CEIL_Z)
        _mullion(mb, 0.0, 3.0, CEIL_Z)
        vquad(mb, -H, -2.0, GLASS_Y, z0, CEIL_Z, "glass")
        vquad(mb, 2.0, H, GLASS_Y, z0, CEIL_Z, "glass")
        vquad(mb, -2.0, 2.0, GLASS_Y, 3.0, CEIL_Z, "glass")
        for z in TRANSOMS:
            _transom(mb, -H, H, z)
        _plinth(mb, -H, -2.06)
        _plinth(mb, 2.06, H)
    else:
        for x in xs:
            _mullion(mb, x, z0, CEIL_Z)
        vquad(mb, -H, H, GLASS_Y, z0, CEIL_Z, "glass")
        for z in TRANSOMS:
            _transom(mb, -H, H, z)
        _plinth(mb, -H, H)
    _band(mb)


def _sliding_doors(mb: K.MB, y: float, sensor: str) -> None:
    """Automatic sliding door set between jambs at x = ±2: two fixed side lights (0.75 m) and two
    leaves (1.25 m) closed in the middle, 2.5 m clear height, operator box above."""
    zt = FLOOR_Z + DOOR_H
    vquad(mb, -1.94, 1.94, y, FLOOR_Z, zt, "glass")
    for x0, x1 in ((-1.94, -1.88), (-1.25, -1.19), (-0.03, 0.03), (1.19, 1.25), (1.88, 1.94)):
        K.box(mb, x0, y - 0.04, FLOOR_Z, x1, y + 0.04, zt, "metal_dark", sides="sn")    # stiles
    for x0, x1 in ((-1.94, 1.94),):
        K.box(mb, x0, y - 0.04, FLOOR_Z, x1, y + 0.04, FLOOR_Z + 0.08, "metal_dark", sides="sn")
    K.box(mb, -1.94, y - 0.15, zt, 1.94, y + 0.15, 3.0, "metal_dark", bottom=True, sides="sn")  # operator
    ys = y - 0.16 if sensor == "-y" else y + 0.15
    K.box(mb, -0.15, ys, 2.78, 0.15, ys + 0.01, 2.86, "metal_light", bottom=True, sides="sn")     # radar sensor


def facade_glass() -> Piece:
    p = Piece("terminal_facade_glass", "edge", (BAY, BAND_D),
              "curtain wall: mullions every 2 m, transoms at 3.3 / 6.65 m, attic band to 12.4 m")
    _curtain_wall(p.lod0, door=False)
    vquad(p.far, -H, H, -BAND_D, 0.0, PARAPET_Z, "glass")
    K.rect(p.far, -H, -BAND_D, H, 0.0, PARAPET_Z, "metal_dark")
    return p


def facade_closed() -> Piece:
    p = Piece("terminal_facade_closed", "edge", (BAY, BAND_D),
              "anthracite panels (2 × 2.4 m, 2 cm joints), steel service door, exit sign, fire cabinet")
    mb = p.lod0
    door_x = (2.45, 3.55)
    # Back plane shows through the joints, 7 cm behind the panels.
    vquad(mb, -H, door_x[0] - 0.05, -0.05, 0.3, CEIL_Z, "metal_dark")
    vquad(mb, door_x[1] + 0.05, H, -0.05, 0.3, CEIL_Z, "metal_dark")
    vquad(mb, door_x[0] - 0.05, door_x[1] + 0.05, -0.05, 2.45, CEIL_Z, "metal_dark")
    rows = [0.3 + i * (CEIL_Z - 0.3) / 4 for i in range(5)]
    for i in range(6):
        x0, x1 = -H + 2 * i + 0.01, -H + 2 * i + 2 - 0.01
        for j in range(4):
            z0, z1 = rows[j] + 0.01, rows[j + 1] - 0.01
            if i == 4 and j == 0:            # door panel: only the strip above the door
                vquad(mb, x0, x1, -0.12, 2.5, z1, "metal_dark")
                continue
            vquad(mb, x0, x1, -0.12, z0, z1, "metal_dark")
    # Service door (1.1 × 2.25 m), steel, light frame; concrete step outside (ground z 0).
    K.box(mb, door_x[0] - 0.05, -0.14, FLOOR_Z, door_x[0], 0.06, 2.45, "metal_light", sides="snew")
    K.box(mb, door_x[1], -0.14, FLOOR_Z, door_x[1] + 0.05, 0.06, 2.45, "metal_light", sides="snew")
    K.box(mb, door_x[0] - 0.05, -0.14, 2.4, door_x[1] + 0.05, 0.06, 2.45, "metal_light", bottom=True, sides="sn")
    vquad(mb, door_x[0], door_x[1], -0.1, FLOOR_Z, 2.4, "metal_dark")
    vquad(mb, door_x[0], door_x[1], 0.02, FLOOR_Z, 2.4, "metal_light", "+y")
    K.box(mb, 3.25, -0.14, 1.0, 3.4, -0.1, 1.04, "metal_light", bottom=True, sides="snew")    # handle
    K.box(mb, door_x[0] - 0.3, -1.1, 0.0, door_x[1] + 0.3, -BAND_D, FLOOR_Z, "concrete", sides="sew")
    _plinth(mb, -H, door_x[0] - 0.05)
    _plinth(mb, door_x[1] + 0.05, H)
    # Interior: concrete wall face, exit sign over the door, fire cabinet.
    vquad(mb, -H, door_x[0] - 0.05, 0.04, FLOOR_Z, CEIL_Z - 0.5, "concrete", "+y")
    vquad(mb, door_x[1] + 0.05, H, 0.04, FLOOR_Z, CEIL_Z - 0.5, "concrete", "+y")
    vquad(mb, door_x[0] - 0.05, door_x[1] + 0.05, 0.06, 2.45, CEIL_Z - 0.5, "concrete", "+y")
    exit_sign(mb, 3.0, 0.06, 2.55, "+y")
    fire_cabinet(mb, -3.0, 0.04, "+y")
    _band(mb)
    vquad(p.far, -H, H, -BAND_D, 0.0, PARAPET_Z, "metal_dark")
    K.rect(p.far, -H, -BAND_D, H, 0.0, PARAPET_Z, "metal_dark")
    return p


def facade_door() -> Piece:
    p = Piece("terminal_facade_door", "edge", (BAY, LOBBY_D),
              "curtain wall with a 4 m sliding-door entrance (2.5 m clear) and a 4.5 m wind lobby")
    mb = p.lod0
    _curtain_wall(mb, door=True)
    _sliding_doors(mb, GLASS_Y, "-y")
    K.rect(mb, -2.0, -BAND_D, 2.0, 0.0, FLOOR_Z + 0.002, "metal_light")          # threshold
    # Wind lobby: glass sides, flat roof with downlights, inner door set, entrance grid mat.
    yl = LOBBY_D
    for x in (-2.0, 2.0):
        if x < 0:
            xquad(mb, x, MUL_Y1, yl, FLOOR_Z, 3.0, "glass", "-x")
        else:
            xquad(mb, x, MUL_Y1, yl, FLOOR_Z, 3.0, "glass", "+x")
        K.box(mb, x - 0.05, yl - 0.05, FLOOR_Z, x + 0.05, yl + 0.05, 3.0, "metal_dark", sides="nesw")
        K.box(mb, x - 0.03, 1.5, FLOOR_Z, x + 0.03, 1.56, 3.0, "metal_dark", sides="ew")
    K.box(mb, -2.05, MUL_Y1, 3.0, 2.05, yl + 0.05, 3.25, "metal_dark", sides="new")
    down(mb, -1.95, 0.1, 1.95, yl - 0.05, 3.0, "metal_light")
    for y in (1.2, 3.2):
        down(mb, -0.12, y - 0.12, 0.12, y + 0.12, 2.995, "emissive_lights", solid_uv("light_warm"))
    _sliding_doors(mb, yl, "+y")
    K.rect(mb, -1.9, 0.12, 1.9, yl - 0.2, FLOOR_Z + 0.002, "metal_dark")         # grid mat
    for i in range(1, 19):
        y = 0.12 + i * (yl - 0.32) / 19
        K.rect(mb, -1.9, y - 0.01, 1.9, y + 0.01, FLOOR_Z + 0.003, "metal_light")
    exit_sign(mb, 0.0, yl + 0.05, 3.3, "+y")                                     # above inner doors
    vquad(p.far, -H, H, -BAND_D, 0.0, PARAPET_Z, "glass")
    K.rect(p.far, -H, -BAND_D, H, 0.0, PARAPET_Z, "metal_dark")
    return p


def corner_outer() -> Piece:
    p = Piece("terminal_corner_outer", "point", (BAND_D, BAND_D),
              "corner post for a convex corner; hall in the +X+Y quadrant")
    K.box(p.lod0, -BAND_D, -BAND_D, 0.0, 0.0, 0.0, PARAPET_Z, "metal_dark", sides="sw")
    K.box(p.far, -BAND_D, -BAND_D, 0.0, 0.0, 0.0, PARAPET_Z, "metal_dark", sides="sw")
    return p


def corner_inner() -> Piece:
    p = Piece("terminal_corner_inner", "point", (BAND_D, BAND_D),
              "cover post for a concave corner; outside = the -X-Y quadrant, hall in the other three")
    e = 0.02
    K.box(p.lod0, -BAND_D - e, -BAND_D - e, 0.0, e, e, PARAPET_Z + e, "metal_dark", sides="sw")
    return p


def join() -> Piece:
    p = Piece("terminal_join", "edge", (BAY, 0.5),
              "where an extension meets an existing hall: roof expansion-joint cover + ceiling trim")
    K.box(p.lod0, -H, -0.25, ROOF_Z, H, 0.25, ROOF_Z + 0.12, "metal_light", sides="sn")
    K.box(p.lod0, -H, -0.06, CEIL_Z - SLAT_D - 0.05, H, 0.06, CEIL_Z, "metal_dark", bottom=True, sides="sn")
    K.rect(p.far, -H, -0.25, H, 0.25, ROOF_Z + 0.12, "metal_light")
    return p


def canopy() -> Piece:
    p = Piece("terminal_canopy", "edge", (BAY, CANOPY_D),
              "entrance canopy: 10 m cantilever at 6 m, tension rods, downlights, gutter + downpipe")
    mb = p.lod0
    y0, y1 = -CANOPY_D, MUL_Y0 - 0.01
    zt = CANOPY_Z + 0.45
    K.box(mb, -H, y0, CANOPY_Z, H, y1, zt, "metal_light", sides="")            # deck (top)
    down(mb, -H, y0, H, y1, CANOPY_Z, "metal_light")                           # soffit
    vquad(mb, -H, H, y0, CANOPY_Z - 0.05, zt + 0.1, "metal_dark")              # front fascia + lip
    K.rect(mb, -H, y0, H, y0 + 0.06, zt + 0.1, "metal_dark")
    vquad(mb, -H, H, y0 + 0.06, zt, zt + 0.1, "metal_dark", "+y")
    for x, f in ((-H, "-x"), (H, "+x")):                                       # end fascias
        xquad(mb, x, y0, y1, CANOPY_Z - 0.05, zt, "metal_dark", f)
    # Gutter at the facade (deck falls back), downpipe at the bay start, shoe into a drain.
    K.box(mb, -H, y1 - 0.3, zt, H, y1, zt + 0.15, "metal_dark", sides="s")
    K.cylinder(mb, -H + 0.25, y1 - 0.12, 0.05, CANOPY_Z, 0.06, "metal_dark", n=8, cap=False)
    K.box(mb, -H + 0.15, y1 - 0.25, 0.0, -H + 0.35, y1 - 0.02, 0.12, "metal_dark", sides="sew")
    # Tension rods from the attic band to the front beam, with clevis plates.
    for x in (-3.0, 3.0):
        rod(mb, (x, -BAND_D, 11.6), (x, y0 + 0.4, zt), 0.025, "metal_dark")
        K.box(mb, x - 0.1, -BAND_D - 0.02, 11.45, x + 0.1, -BAND_D, 11.75, "metal_dark", bottom=True,
              sides="sew")
        K.box(mb, x - 0.08, y0 + 0.3, zt, x + 0.08, y0 + 0.5, zt + 0.12, "metal_dark", sides="snew")
    # Back brackets into the facade structure (at the mullion lines).
    for x in (-4.0, 0.0, 4.0):
        K.box(mb, x - 0.05, y1, CANOPY_Z + 0.05, x + 0.05, MUL_Y0, zt - 0.05, "metal_dark", bottom=True, sides="ew")
    # Downlights: 2 rows × 3, recessed in the soffit.
    for x in (-4.0, 0.0, 4.0):
        for y in (-3.0, -7.5):
            down(mb, x - 0.15, y - 0.15, x + 0.15, y + 0.15, CANOPY_Z - 0.003, "emissive_lights",
                 solid_uv("light_warm"))
    K.rect(p.far, -H, y0, H, y1, zt, "metal_light")
    return p


def door_sign(n: int) -> Piece:
    """Backlit door-number box hung under the canopy front (origin = hanger top, at the soffit)."""
    p = Piece(f"terminal_door_sign_{n}", "prop", (1.0, 0.15),
              f"door number {n}: 0.8 × 0.8 m backlit box, hangs 0.3 m under the canopy soffit")
    mb = p.lod0
    z1, z0 = -0.3, -1.1
    K.box(mb, -0.4, -0.075, z0, 0.4, 0.075, z1, "emissive_lights", bottom=True, sides="ew",
          uv_point=solid_uv("dark"))
    sign_face(mb, -0.4, 0.4, -0.076, z0, z1, f"door_{n}", "-y")
    sign_face(mb, -0.4, 0.4, 0.076, z0, z1, f"door_{n}", "+y")
    for x in (-0.3, 0.3):
        rod(mb, (x, 0, z1), (x, 0, 0.0), 0.01, "metal_dark")
    return p


def exit_sign_prop() -> Piece:
    p = Piece("terminal_exit_sign", "prop", (0.4, 0.04),
              "0.4 × 0.2 m backlit exit sign; origin = wall plane, bottom of the sign, reads to -Y")
    exit_sign(p.lod0, 0.0, 0.0, 0.0, "-y")
    return p


def fire_cabinet_prop() -> Piece:
    p = Piece("terminal_fire_cabinet", "prop", (0.6, 0.25),
              "fire extinguisher / hose cabinet + sign; origin = wall plane at floor level, faces -Y")
    fire_cabinet(p.lod0, 0.0, 0.0, "-y")
    # The kit pieces sit on the hall floor (z 0.15); the prop's origin is the floor surface.
    for i, v in enumerate(p.lod0.verts):
        p.lod0.verts[i] = (v[0], v[1], v[2] - FLOOR_Z)
    return p


def all_pieces() -> list:
    return ([floor_bay(), ceiling_bay(), roof_bay(), column(), facade_glass(), facade_closed(),
             facade_door(), corner_outer(), corner_inner(), join(), canopy(), exit_sign_prop(),
             fire_cabinet_prop()] + [door_sign(n) for n in range(1, 9)])


def build_objects(piece: Piece, mats: dict, collection=None) -> list:
    objs = K.build_objects(piece, mats, collection)
    for o in objs:
        if piece.smooth_mats and not o.name.endswith("_lodfar"):
            names = [m.name for m in o.data.materials]
            for poly in o.data.polygons:
                if abs(poly.normal.z) < 0.5 and names[poly.material_index] in piece.smooth_mats:
                    poly.use_smooth = True
    return objs


def tri_count(mb: K.MB) -> int:
    return mb.tris()
