"""Generates the tileable `paving` texture set (sidewalks: small grey concrete pavers).

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/landside/landside_textures.py
Writes assets/textures/paving/paving_{albedo,normal,orm}.png (1024², PNG).

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


if __name__ == "__main__":
    make_paving()
