"""Generates the terminal texture sets (shared library, docs/art_direction.md §3/§4).

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/terminal/terminal_textures.py
Writes (PNG):
- assets/textures/terrazzo_dark/terrazzo_dark_{albedo,orm}.png  1024², tile = 4 m (uv1_scale 0.5):
  4 × 4 large-format terrazzo tiles of 1 m with thin joints, light chips #9A9C9C on #4A4C4E.
- assets/textures/wood_oak/wood_oak_{albedo,orm}.png  1024², tile = 2 m (uv1_scale 1.0):
  calm light-oak grain running along U (= the slat direction, world X).
- assets/textures/emissive_lights/emissive_lights_{albedo,emission}.png  512² atlas (see ATLAS):
  warm light, cool light, green exit sign, red fire-extinguisher sign (not lit), door numbers 1-8
  (signal yellow on anthracite, only the digit glows).
Seeds are fixed, so the files are reproducible.
"""
import os
import sys

import numpy as np

sys.dont_write_bytecode = True  # no __pycache__ in art/
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ground"))
import atlas_text as T  # noqa: E402
from ground_textures import band_noise, hex_rgb, SIZE  # noqa: E402
from tex_io import ROOT, save_png  # noqa: E402

TEX = os.path.join(ROOT, "assets", "textures")
EMI = 512
# Atlas cells in px (x, y, w, h), y down. terminal_kit.py reads the same table for its UVs.
ATLAS = {
    "light_warm": (0, 0, 128, 128),
    "light_cool": (128, 0, 128, 128),
    "dark": (256, 0, 128, 128),
    "steel": (384, 0, 128, 128),
    "exit": (0, 128, 256, 128),
    "fire": (256, 128, 128, 128),
}
for _i in range(8):
    ATLAS[f"door_{_i + 1}"] = ((_i % 4) * 128, 256 + (_i // 4) * 128, 128, 128)


def write(name: str, maps: dict) -> None:
    for m, img in maps.items():
        save_png(os.path.join(TEX, name, f"{name}_{m}.png"), np.clip(img, 0.0, 1.0))


def make_terrazzo() -> None:
    rng = np.random.default_rng(505)
    px_per_m = SIZE / 4.0
    base = hex_rgb("#4A4C4E")
    chip = hex_rgb("#9A9C9C")
    dark = hex_rgb("#2F3133")
    tone = band_noise(rng, 1, 3) * 0.015
    fine = band_noise(rng, 150, 400)
    fine2 = band_noise(rng, 90, 260)
    img = np.ones((SIZE, SIZE, 3)) * base
    light = fine > 1.75                   # ~4 % light marble chips (8-20 mm)
    darkc = fine2 < -1.9                  # ~3 % dark chips
    img[light] = chip * (0.92 + 0.08 * rng.random((light.sum(), 1)))
    img[darkc] = dark
    # Per-tile tone (real terrazzo tiles differ a little), 1 m tiles.
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    tile = (yy // int(px_per_m)) * 4 + (xx // int(px_per_m))
    per_tile = rng.normal(0, 0.012, 16)[tile]
    img *= (1.0 + tone + per_tile)[..., None]
    # Joints: 2 px (~8 mm) grout, slightly darker, on the tile borders (wraps seamlessly).
    m = np.mod(xx, px_per_m)
    n = np.mod(yy, px_per_m)
    joint = (np.minimum(m, px_per_m - m) < 1.0) | (np.minimum(n, px_per_m - n) < 1.0)
    img[joint] *= 0.72
    orm = np.zeros((SIZE, SIZE, 3))
    orm[..., 0] = np.where(joint, 0.8, 1.0)
    orm[..., 1] = np.clip(0.35 + band_noise(rng, 4, 16) * 0.03 + np.where(joint, 0.3, 0.0), 0, 1)
    orm[..., 2] = 0.0
    write("terrazzo_dark", {"albedo": img, "orm": orm})


def aniso_noise(rng, kx_max: float, ky_lo: float, ky_hi: float) -> np.ndarray:
    """Periodic noise: low frequency along x (grain runs along U), higher across (y)."""
    white = rng.standard_normal((SIZE, SIZE))
    f = np.fft.fft2(white)
    ky = np.abs(np.fft.fftfreq(SIZE) * SIZE)[:, None]
    kx = np.abs(np.fft.fftfreq(SIZE) * SIZE)[None, :]
    mask = (kx <= kx_max) & (ky >= ky_lo) & (ky <= ky_hi)
    out = np.real(np.fft.ifft2(f * mask))
    return out / (out.std() + 1e-9)


def make_oak() -> None:
    rng = np.random.default_rng(606)
    base = hex_rgb("#C9A57A")
    grain = aniso_noise(rng, 6, 30, 160)       # long fibres along U
    rings = aniso_noise(rng, 3, 8, 30)         # broad flame / ring bands
    pores = aniso_noise(rng, 40, 200, 500)     # fine pores
    v = 1.0 + grain * 0.035 + rings * 0.04 + pores * 0.015
    img = base[None, None, :] * v[..., None]
    img[..., 2] *= 1.0 - rings * 0.01          # bands a touch warmer
    orm = np.zeros((SIZE, SIZE, 3))
    orm[..., 0] = 1.0
    orm[..., 1] = np.clip(0.55 + pores * 0.04, 0, 1)
    write("wood_oak", {"albedo": img, "orm": orm})


def _seg(mask, p0, p1, r) -> None:
    """Thick line segment into a boolean mask (px, y down)."""
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w]
    p0, p1 = np.array(p0, float), np.array(p1, float)
    d = p1 - p0
    t = np.clip(((xx - p0[0]) * d[0] + (yy - p0[1]) * d[1]) / max(d @ d, 1e-9), 0, 1)
    dist = np.hypot(xx - (p0[0] + t * d[0]), yy - (p0[1] + t * d[1]))
    mask |= dist <= r


def make_emissive() -> None:
    alb = np.zeros((EMI, EMI, 3))
    emi = np.zeros((EMI, EMI, 3))

    def fill(cell, colour, glow=None):
        x, y, w, h = ATLAS[cell]
        alb[y:y + h, x:x + w] = colour
        if glow is not None:
            emi[y:y + h, x:x + w] = glow

    fill("light_warm", hex_rgb("#F2E4CC"), np.array([1.0, 0.82, 0.6]))     # ~3000 K
    fill("light_cool", hex_rgb("#E6ECF0"), np.array([0.86, 0.92, 1.0]))
    fill("dark", hex_rgb("#2E3236"))
    fill("steel", hex_rgb("#8A9096"))
    # Exit sign (ISO 7010 style, simplified): green field, white running figure, door, arrow.
    x, y, w, h = ATLAS["exit"]
    green = hex_rgb("#2F8A4E")
    white = hex_rgb("#E6E6E2")
    sign = np.zeros((h, w), bool)
    _seg(sign, (150, 22), (150, 106), 3)       # door frame
    _seg(sign, (150, 22), (196, 22), 3)
    _seg(sign, (196, 22), (196, 106), 3)
    yy, xx = np.mgrid[0:h, 0:w]
    sign |= np.hypot(xx - 120, yy - 30) < 9    # head
    _seg(sign, (116, 44), (104, 72), 7)        # torso
    _seg(sign, (114, 50), (132, 60), 4)        # arm front
    _seg(sign, (112, 50), (94, 56), 4)         # arm back
    _seg(sign, (104, 72), (124, 86), 5)        # front leg
    _seg(sign, (124, 86), (122, 106), 4)
    _seg(sign, (104, 72), (92, 92), 5)         # back leg
    _seg(sign, (92, 92), (76, 96), 4)
    _seg(sign, (22, 64), (66, 64), 6)          # arrow
    _seg(sign, (22, 64), (40, 46), 6)
    _seg(sign, (22, 64), (40, 82), 6)
    border = (xx < 4) | (xx >= w - 4) | (yy < 4) | (yy >= h - 4)
    cell = np.where(sign[..., None], white, green)
    cell[border] = white
    alb[y:y + h, x:x + w] = cell
    emi[y:y + h, x:x + w] = cell * 0.9
    # Fire extinguisher sign (not lit): red field, white extinguisher shape.
    x, y, w, h = ATLAS["fire"]
    red = hex_rgb("#C8382E")
    m = np.zeros((h, w), bool)
    _seg(m, (64, 46), (64, 108), 20)           # body
    _seg(m, (64, 28), (64, 40), 6)             # valve
    _seg(m, (64, 30), (92, 40), 4)             # hose
    _seg(m, (92, 40), (98, 70), 4)
    alb[y:y + h, x:x + w] = np.where(m[..., None], white, red)
    # Door numbers: signal yellow digit on anthracite; only the digit glows.
    yellow = hex_rgb("#E8B830")
    for i in range(8):
        x, y, w, h = ATLAS[f"door_{i + 1}"]
        ink = T.text_mask(str(i + 1), w, h, pad=22, bold=2.0)
        alb[y:y + h, x:x + w] = hex_rgb("#2E3236") * (1 - ink[..., None]) + yellow * ink[..., None]
        emi[y:y + h, x:x + w] = yellow * ink[..., None]
    write("emissive_lights", {"albedo": alb, "emission": emi})


if __name__ == "__main__":
    make_terrazzo()
    make_oak()
    make_emissive()
    print("terminal textures written")
