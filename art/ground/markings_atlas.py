"""Generates the ground markings atlas (one trim sheet for every line and symbol).

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/ground/markings_atlas.py
Writes assets/textures/markings/markings_albedo.png (1024², RGBA, straight alpha).
Layout: markings_layout.py (code) and markings_atlas.md (docs).

Markings are flat paint: colour + alpha only. Colours follow ICAO practice (docs/art_direction.md §3):
white runway, yellow taxi / lead-in / stand label, red stand safety lines.
Transparent pixels carry the colour of the nearest marking, so filtering and mipmaps don't
darken the edges.
"""
import os
import sys

import numpy as np

sys.dont_write_bytecode = True  # no __pycache__ in art/
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import markings_layout as L  # noqa: E402
from tex_io import ROOT, save_png  # noqa: E402

N = L.ATLAS
rgb = np.zeros((N, N, 3))
alpha = np.zeros((N, N))
painted = np.zeros((N, N), dtype=bool)  # pixels whose RGB is set (alpha may still be 0)


def col(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def put(rect: tuple, colour: str, a: np.ndarray | float = 1.0) -> None:
    x, y, w, h = rect
    rgb[y:y + h, x:x + w] = col(colour)
    alpha[y:y + h, x:x + w] = np.maximum(alpha[y:y + h, x:x + w], a)
    painted[y:y + h, x:x + w] = True


def coverage(signed_dist_px: np.ndarray) -> np.ndarray:
    """Analytic anti-aliasing: 1 inside, 0 outside, linear across one pixel."""
    return np.clip(0.5 - signed_dist_px, 0.0, 1.0)


def local_grid(rect: tuple) -> tuple:
    x, y, w, h = rect
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    return xx, yy


# --- Solid strips and blocks ------------------------------------------------------------------
put(L.RECTS["white_line"], L.WHITE)
put(L.RECTS["yellow_line"], L.YELLOW)
put(L.RECTS["red_line"], L.RED)
put(L.RECTS["stop_bar"], L.YELLOW)
put(L.RECTS["threshold_bar"], L.WHITE)

# --- Dashed strips (period along U, AA on the dash ends) ---------------------------------------
def dashed(rect: tuple, period_px: float, dash_px: float, colour: str) -> None:
    xx, _ = local_grid(rect)
    m = np.mod(xx, period_px)
    # Signed distance to the dash interval [0, dash_px], wrapping with the period.
    d = np.maximum(-m, m - dash_px)
    d = np.minimum(d, period_px - m)  # distance to the next dash start
    put(rect, colour, coverage(d))


dashed(L.RECTS["centre_dash"], 1024.0,
       1024.0 * L.CENTRELINE_DASH / L.CENTRE_DASH_PERIOD_M, L.WHITE)
dashed(L.RECTS["short_dash"], 1024.0 * L.SHORT_DASH_PERIOD / L.SHORT_DASH_STRIP_M,
       1024.0 * (L.SHORT_DASH_PERIOD / 2) / L.SHORT_DASH_STRIP_M, L.WHITE)
dashed(L.RECTS["zebra"], 1024.0 * L.ZEBRA_PERIOD / L.ZEBRA_STRIP_M,
       1024.0 * (L.ZEBRA_PERIOD / 2) / L.ZEBRA_STRIP_M, L.WHITE)

# --- Stand label box: dark fill, yellow 0.15 m frame --------------------------------------------
rect = L.RECTS["label_box"]
xx, yy = local_grid(rect)
px_per_m = rect[2] / L.LABEL_BOX[0]
frame = 0.15 * px_per_m
edge = np.minimum.reduce([xx, yy, rect[2] - xx, rect[3] - yy])
x, y, w, h = rect
inner = coverage(edge - frame)  # 1 inside the frame band
rgb[y:y + h, x:x + w] = col(L.ANTHRACITE) * (1 - inner[..., None]) + col(L.YELLOW) * inner[..., None]
alpha[y:y + h, x:x + w] = 1.0
painted[y:y + h, x:x + w] = True


# --- Quarter curves of the taxi line -----------------------------------------------------------
for name, (ppm, radius_m, _size_m) in L.CURVES.items():
    rect = L.RECTS[name]
    xx, yy = local_grid(rect)
    # Arc centre at the bottom-left corner of the rect (image coordinates: x = 0, y = h).
    r = np.hypot(xx, rect[3] - yy)
    d = np.abs(r - radius_m * ppm) - L.TAXI_LINE_W * ppm / 2
    a = coverage(d)
    x, y, w, h = rect
    rgb[y:y + h, x:x + w] = col(L.YELLOW)
    alpha[y:y + h, x:x + w] = a
    painted[y:y + h, x:x + w] = True


# --- Designator characters (blocky ICAO-style strokes) -----------------------------------------
STROKE = 0.75  # m
A, B = STROKE / 2, L.DIGIT[0] - STROKE / 2
BOT, TOP, MID = STROKE / 2, L.DIGIT[1] - STROKE / 2, L.DIGIT[1] / 2
# Polylines in glyph metres (x right, y up), stroke centre lines.
GLYPH_STROKES = {
    "0": [[(A, BOT), (B, BOT), (B, TOP), (A, TOP), (A, BOT)]],
    "1": [[(1.9, BOT), (1.9, TOP), (0.7, 7.4)]],
    "2": [[(A, TOP), (B, TOP), (B, 5.2), (A, 1.6), (A, BOT), (B, BOT)]],
    "3": [[(A, TOP), (B, TOP), (B, BOT), (A, BOT)], [(0.9, MID), (B, MID)]],
    "4": [[(2.0, BOT), (2.0, TOP), (A, 3.2), (B, 3.2)]],
    "5": [[(B, TOP), (A, TOP), (A, MID), (B, MID), (B, BOT), (A, BOT)]],
    "6": [[(B, TOP), (A, TOP), (A, BOT), (B, BOT), (B, MID), (A, MID)]],
    "7": [[(A, TOP), (B, TOP), (B, 7.0), (1.2, BOT)]],
    "8": [[(A, BOT), (B, BOT), (B, TOP), (A, TOP), (A, BOT)], [(A, MID), (B, MID)]],
    "9": [[(A, BOT), (B, BOT), (B, TOP), (A, TOP), (A, MID), (B, MID)]],
    "L": [[(A, TOP), (A, BOT), (B, BOT)]],
    "C": [[(B, TOP), (A, TOP), (A, BOT), (B, BOT)]],
    "R": [[(A, BOT), (A, TOP), (B, TOP), (B, MID), (A, MID)], [(1.3, MID), (B, BOT)]],
}


def segment_box_dist(px, py, p0, p1, half_w):
    """Signed distance to a segment drawn with square caps (sharp corners like painted digits)."""
    d = np.array(p1) - np.array(p0)
    length = np.hypot(*d)
    ux, uy = d / length
    rx, ry = px - p0[0], py - p0[1]
    s = rx * ux + ry * uy
    q = -rx * uy + ry * ux
    along = np.abs(s - length / 2) - (length / 2 + half_w)
    across = np.abs(q) - half_w
    outside = np.hypot(np.maximum(along, 0), np.maximum(across, 0))
    return outside + np.minimum(np.maximum(along, across), 0)


for ch in L.GLYPHS:
    rect = L.glyph_rect(ch)
    xx, yy = local_grid(rect)
    ppm = L.GLYPH_PX_PER_M
    gw, gh = L.DIGIT
    # Glyph metres: cell is 3.2 × 9.6 m, glyph box 3 × 9 m centred, y up.
    gx = xx / ppm - (rect[2] / ppm - gw) / 2
    gy = (rect[3] - yy) / ppm - (rect[3] / ppm - gh) / 2
    dist = np.full(xx.shape, 1e9)
    for line in GLYPH_STROKES[ch]:
        for p0, p1 in zip(line[:-1], line[1:]):
            dist = np.minimum(dist, segment_box_dist(gx, gy, p0, p1, STROKE / 2))
    # Clip to the 3 × 9 m glyph box (diagonal caps must not stick out).
    box = np.maximum(np.maximum(-gx, gx - gw), np.maximum(-gy, gy - gh))
    dist = np.maximum(dist, box)
    put(rect, L.WHITE, coverage(dist * ppm))


# --- Bleed colours into the transparent gutters (no dark fringes when filtered) ----------------
for _ in range(16):
    if painted.all():
        break
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        src_p = np.roll(painted, (dy, dx), axis=(0, 1))
        src_c = np.roll(rgb, (dy, dx), axis=(0, 1))
        take = ~painted & src_p
        rgb[take] = src_c[take]
        painted |= take
rgb[~painted] = col(L.WHITE)

out = np.concatenate([rgb, alpha[..., None]], axis=-1)
save_png(os.path.join(ROOT, "assets", "textures", "markings", "markings_albedo.png"), out)
print("markings atlas written, coverage", round(float(alpha.mean()), 3))
