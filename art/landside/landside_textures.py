"""Generates the tileable `paving` texture set (sidewalks: small grey concrete pavers).

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/landside/landside_textures.py
Writes assets/textures/paving/paving_{albedo,normal,orm}.png (1024², PNG) and
assets/textures/decals/decals_albedo.png (512², RGBA: subtle wear, see DECALS).

Tile = 4 m (material uv1_scale = 2 m / 4 m = 0.5). Pavers 0.25 × 0.125 m in running bond
(64 × 32 px, every second row shifted by half a paver), so the tile repeats seamlessly.
Value sits between asphalt (dark) and the concrete curb stone (light): road, sidewalk and curb read
apart from the build view by brightness alone (docs/art_direction.md §1). Seeds are fixed.
"""
import os
import sys

import numpy as np

sys.dont_write_bytecode = True  # no __pycache__ in art/
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ground"))
from ground_textures import band_noise, hex_rgb, normal_from_height, write_set, SIZE  # noqa: E402
from tex_io import ROOT, save_png  # noqa: E402

TILE_M = 4.0
PAVER_PX = (64, 32)  # 0.25 × 0.125 m at 256 px/m
BASE = "#8C8D8A"


def make_paving() -> None:
    rng = np.random.default_rng(404)
    base = hex_rgb(BASE)
    pw, ph = PAVER_PX
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64) + 0.5
    row = (yy // ph).astype(int)
    xs = xx + (row % 2) * (pw / 2)                 # running bond
    col = (xs // pw).astype(int) % (SIZE // pw)
    # Distance (px) to the nearest joint, inside each paver.
    dx = np.minimum(np.mod(xs, pw), pw - np.mod(xs, pw))
    dy = np.minimum(np.mod(yy, ph), ph - np.mod(yy, ph))
    d = np.minimum(dx, dy)
    joint = np.clip(1.6 - d, 0.0, 1.0)             # ~3 mm joint, anti-aliased
    bevel = np.clip(1.0 - (d - 1.0) / 3.0, 0.0, 1.0)  # small chamfer on each paver edge

    # Per-paver tone (index into a periodic random table, so the tile still wraps).
    rows = SIZE // ph
    table = rng.normal(0.0, 1.0, (rows, SIZE // pw))
    tone = table[row % rows, col]

    mottle = band_noise(rng, 1, 4)
    fine = band_noise(rng, 160, 450)
    lum = 1.0 + 0.025 * tone + 0.015 * mottle + 0.03 * fine
    lum = lum * (1.0 - 0.06 * bevel) * (1.0 - 0.35 * joint)
    albedo = base[None, None, :] * lum[..., None]

    height = 0.3 * fine - 4.0 * bevel - 4.0 * joint
    normal = normal_from_height(height, 0.5)
    ao = 1.0 - 0.3 * joint - 0.06 * bevel
    rough = 0.86 + 0.02 * fine + 0.06 * joint
    orm = np.stack([ao, rough, np.zeros_like(ao)], axis=-1)
    write_set("paving", albedo, normal, orm)


# Wear decals (`decals` material, 512² RGBA, alpha blended, flush, no shadow). Rects (x, y, w, h),
# y from the top; real size = what one rect is mapped onto.
DECALS = {
    "oil_stain":   ((4, 4, 120, 120), (1.2, 1.2)),     # soft dark stain, bay centres
    "patch":       ((132, 4, 120, 120), (2.0, 2.0)),   # darker repaired asphalt, sealed joint
    "drain_grate": ((260, 4, 60, 120), (0.5, 1.0)),    # cast-iron gully grate in the gutter
    "tyre_marks":  ((4, 132, 504, 60), (6.0, 0.7)),    # two faint rubber streaks
}


def make_decals() -> None:
    n = 512
    rng = np.random.default_rng(505)
    rgb = np.zeros((n, n, 3)) + hex_rgb("#1E1F20")
    alpha = np.zeros((n, n))

    def grid(rect):
        x, y, w, h = rect
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
        return x, y, w, h, xx / w, yy / h

    def noise(h, w, scale):
        f = rng.standard_normal((h // scale + 2, w // scale + 2))
        return np.kron(f, np.ones((scale, scale)))[:h, :w]

    x, y, w, h, u, v = grid(DECALS["oil_stain"][0])
    r = np.hypot(u - 0.5, (v - 0.5) * 1.3)
    blob = np.clip(1.0 - r / 0.42, 0, 1) ** 1.5
    alpha[y:y + h, x:x + w] = np.clip(blob * (0.35 + 0.08 * noise(h, w, 6)), 0, 0.45)

    x, y, w, h, u, v = grid(DECALS["patch"][0])
    edge = np.minimum.reduce([u, v, 1 - u, 1 - v])
    inside = np.clip((edge - 0.02) * 60, 0, 1)
    rgb[y:y + h, x:x + w] = hex_rgb("#2C2D2E") * (1 + 0.04 * noise(h, w, 3))[..., None]
    seal = np.clip(1 - np.abs(edge - 0.02) * 120, 0, 1)
    rgb[y:y + h, x:x + w] *= (1 - 0.35 * seal)[..., None]
    alpha[y:y + h, x:x + w] = np.maximum(inside * 0.85, seal)

    x, y, w, h, u, v = grid(DECALS["drain_grate"][0])
    rgb[y:y + h, x:x + w] = hex_rgb("#2A2B2C")
    frame = np.minimum.reduce([u, v, 1 - u, 1 - v]) < 0.08
    slots = (np.mod(v * 12, 1.0) < 0.55) & (np.abs(u - 0.5) < 0.36) & ~frame
    rgb[y:y + h, x:x + w][slots] = hex_rgb("#0E0F10")
    alpha[y:y + h, x:x + w] = 1.0

    x, y, w, h, u, v = grid(DECALS["tyre_marks"][0])
    streak = sum(np.exp(-((v - c - 0.04 * np.sin(u * 6.0)) / 0.07) ** 2) for c in (0.3, 0.7))
    fade = np.clip(np.minimum(u, 1 - u) * 5, 0, 1)
    alpha[y:y + h, x:x + w] = np.clip(streak * fade * (0.22 + 0.06 * noise(h, w, 8)), 0, 0.3)

    out = np.concatenate([rgb, alpha[..., None]], axis=-1)
    save_png(os.path.join(ROOT, "assets", "textures", "decals", "decals_albedo.png"), np.clip(out, 0, 1))


if __name__ == "__main__":
    make_paving()
    make_decals()
