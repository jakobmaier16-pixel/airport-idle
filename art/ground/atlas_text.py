"""Rasterises text with Blender's built-in font (no extra libraries, same result on every machine).

The text becomes a Blender text object, is converted to triangles, and the triangles are
scan-converted with 4 × 4 supersampling into a coverage mask (1 = ink, 0 = empty).
"""
import bpy
import numpy as np

SS = 4  # supersampling per axis


def text_triangles(text: str) -> tuple:
    """Triangles of `text` in font units (x right, y up), one line, left aligned."""
    cu = bpy.data.curves.new("atlas_text", "FONT")
    cu.body = text
    cu.size = 1.0
    ob = bpy.data.objects.new("atlas_text", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    verts = np.array([v.co[:2] for v in me.vertices], dtype=np.float64)
    tris = np.array([t.vertices[:] for t in me.loop_triangles], dtype=np.int64)
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    return verts, tris


def raster(verts: np.ndarray, tris: np.ndarray, w: int, h: int, bold: float = 0.0) -> np.ndarray:
    """Coverage (h, w) of triangles already given in pixel units (x right, y DOWN).
    `bold` (px) thickens the strokes (the built-in font is a regular weight)."""
    sw, sh = w * SS, h * SS
    ink = np.zeros((sh, sw), dtype=bool)
    v = verts * SS
    for a, b, c in tris:
        pa, pb, pc = v[a], v[b], v[c]
        x0 = max(int(np.floor(min(pa[0], pb[0], pc[0]))), 0)
        x1 = min(int(np.ceil(max(pa[0], pb[0], pc[0]))) + 1, sw)
        y0 = max(int(np.floor(min(pa[1], pb[1], pc[1]))), 0)
        y1 = min(int(np.ceil(max(pa[1], pb[1], pc[1]))) + 1, sh)
        if x0 >= x1 or y0 >= y1:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float64) + 0.5

        def edge(p, q):
            return (q[0] - p[0]) * (yy - p[1]) - (q[1] - p[1]) * (xx - p[0])

        e0, e1, e2 = edge(pa, pb), edge(pb, pc), edge(pc, pa)
        inside = ((e0 >= 0) & (e1 >= 0) & (e2 >= 0)) | ((e0 <= 0) & (e1 <= 0) & (e2 <= 0))
        ink[y0:y1, x0:x1] |= inside
    r = int(round(bold * SS))
    if r > 0:
        grown = ink.copy()
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    grown |= np.roll(ink, (dy, dx), axis=(0, 1))
        ink = grown
    return ink.reshape(h, SS, w, SS).mean(axis=(1, 3))


_CAP = {}


def cap_height() -> float:
    """Height of a capital letter in font units (baseline at y = 0)."""
    if "h" not in _CAP:
        v, _ = text_triangles("H")
        _CAP["h"] = float(v[:, 1].max())
    return _CAP["h"]


def text_mask(text: str, w: int, h: int, mode: str = "fit", pad: float = 1.0,
              bold: float = 0.0, align: str = "center", cap_px: float | None = None,
              squeeze: float = 1.0) -> np.ndarray:
    """Coverage of `text` in a w × h px box (upper-case text).
    mode "fit": keep the font's proportions, scaled to the box (or to `cap_px` capital height, so
    several lines share one letter size); "fill": stretch to the box; "tall": fill the height and
    make the letter `squeeze` times narrower than the font (elongated road-marking letters)."""
    verts, tris = text_triangles(text)
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    cap = cap_height()
    lo_y, hi_y = 0.0, cap                                  # capital box, ignores accents / descenders
    size = np.array([hi[0] - lo[0], hi_y - lo_y])
    bw, bh = w - 2 * pad - 2 * bold, h - 2 * pad - 2 * bold
    if mode == "fill":
        sx, sy = bw / size[0], bh / size[1]
    elif mode == "tall":                                    # fill the height, squeeze the width
        sy = bh / size[1]
        sx = min(sy / squeeze, bw / size[0])
    elif cap_px is not None:
        sx = sy = min(cap_px / cap, bw / size[0])
    else:
        sx = sy = min(bw / size[0], bh / size[1])
    out_w, out_h = size[0] * sx, size[1] * sy
    ox = {"left": pad + bold, "center": (w - out_w) / 2, "right": w - pad - bold - out_w}[align]
    oy = (h - out_h) / 2
    px = np.stack([(verts[:, 0] - lo[0]) * sx + ox, (hi_y - verts[:, 1]) * sy + oy], axis=1)
    return raster(px, tris, w, h, bold)
