"""Generates the tileable ground textures (grass, asphalt, concrete).

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/ground/ground_textures.py
Writes assets/textures/<material>/<material>_{albedo,normal,orm}.png (1024², PNG).

All noise is made in frequency space (filtered white noise + inverse FFT), so every map is
periodic and tiles seamlessly by construction. Seeds are fixed: re-running gives the same files.
"Quiet realism" (docs/art_direction.md §1): low-contrast variation, nothing that fights the
top-down build view.

Tile sizes (world metres covered by one 1024² texture; the material's uv1_scale = 2 m / tile):
  grass     16 m  -> uv1_scale 0.125
  asphalt    8 m  -> uv1_scale 0.25
  concrete  10 m  -> uv1_scale 0.2   (2 × 2 slabs of 5 m, joints baked in: ground-tile exception)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tex_io import ROOT, save_png  # noqa: E402

SIZE = 1024
TILE_M = {"grass": 16.0, "asphalt": 8.0, "concrete": 10.0}


def hex_rgb(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def band_noise(rng: np.random.Generator, lo: float, hi: float) -> np.ndarray:
    """Periodic noise with energy between lo and hi cycles per tile, normalised to std 1."""
    white = rng.standard_normal((SIZE, SIZE))
    f = np.fft.rfft2(white)
    ky = np.fft.fftfreq(SIZE) * SIZE
    kx = np.fft.rfftfreq(SIZE) * SIZE
    k = np.sqrt(ky[:, None] ** 2 + kx[None, :] ** 2)
    # Smooth band: Gaussian falloff outside [lo, hi] avoids ringing.
    w = np.ones_like(k)
    w = np.where(k < lo, np.exp(-((lo - k) / max(lo * 0.5, 0.5)) ** 2), w)
    w = np.where(k > hi, np.exp(-((k - hi) / max(hi * 0.5, 0.5)) ** 2), w)
    w[0, 0] = 0.0
    n = np.fft.irfft2(f * w, s=(SIZE, SIZE))
    return (n - n.mean()) / (n.std() + 1e-9)


def normal_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    """Tangent-space normal map (OpenGL / Y+ convention, as Godot and Blender expect)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    # Image rows go down, texture V goes up: flip the Y gradient sign.
    dy = -(np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    n = np.stack([-dx * strength, -dy * strength, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def periodic_dist_to_lines(coord: np.ndarray, period: float) -> np.ndarray:
    """Distance (px) to the nearest multiple of `period`, wrapping at the tile edge."""
    m = np.mod(coord, period)
    return np.minimum(m, period - m)


def write_set(name: str, albedo: np.ndarray, normal: np.ndarray, orm: np.ndarray) -> None:
    folder = os.path.join(ROOT, "assets", "textures", name)
    save_png(os.path.join(folder, f"{name}_albedo.png"), np.clip(albedo, 0.0, 1.0))
    save_png(os.path.join(folder, f"{name}_normal.png"), np.clip(normal, 0.0, 1.0))
    save_png(os.path.join(folder, f"{name}_orm.png"), np.clip(orm, 0.0, 1.0))
    print(f"{name}: albedo mean {albedo.mean(axis=(0, 1)).round(3)}")


def make_grass() -> None:
    rng = np.random.default_rng(101)
    base = hex_rgb("#5E7A48")
    patches = band_noise(rng, 1, 4)        # 4-16 m patches: gentle mowing / moisture variation
    mid = band_noise(rng, 12, 40)          # tufts
    fine = band_noise(rng, 150, 400)       # blades
    lum = 1.0 + 0.03 * patches + 0.03 * mid + 0.035 * fine
    # Slight hue drift: drier (yellower) patches against fresher ones.
    hue = band_noise(rng, 1, 3)
    tint = np.stack([1.0 + 0.025 * hue, 1.0 + 0.006 * hue, 1.0 - 0.02 * hue], axis=-1)
    albedo = base[None, None, :] * lum[..., None] * tint
    height = 0.6 * mid + 1.0 * fine
    normal = normal_from_height(height, 0.35)
    ao = 1.0 - 0.06 * np.clip(-mid, 0, None) - 0.04 * np.clip(-fine, 0, None)
    rough = 0.92 + 0.03 * fine
    orm = np.stack([ao, rough, np.zeros_like(ao)], axis=-1)
    write_set("grass", albedo, normal, orm)


def make_asphalt() -> None:
    rng = np.random.default_rng(202)
    base = hex_rgb("#3A3B3C")
    wear = band_noise(rng, 1, 3)           # very soft tone variation over the 8 m tile
    grain = band_noise(rng, 200, 512)      # fine aggregate
    # Sparse light stones: thresholded fine noise, kept small and dim.
    stones = np.clip(band_noise(rng, 120, 300) - 2.2, 0, None)
    lum = 1.0 + 0.035 * wear + 0.05 * grain + 0.18 * stones
    albedo = base[None, None, :] * lum[..., None]
    height = grain + 1.5 * stones
    normal = normal_from_height(height, 0.25)
    ao = 1.0 - 0.05 * np.clip(-grain, 0, None)
    rough = 0.88 - 0.05 * stones + 0.02 * grain
    orm = np.stack([ao, rough, np.zeros_like(ao)], axis=-1)
    write_set("asphalt", albedo, normal, orm)


def make_concrete() -> None:
    rng = np.random.default_rng(303)
    base = hex_rgb("#A3A39E")
    px_per_m = SIZE / TILE_M["concrete"]   # 102.4 px/m
    slab = SIZE / 2.0                      # 5 m slabs, 2 × 2 per tile
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64) + 0.5
    # Joints sit on the tile edges and the tile centre lines, so the tile repeats seamlessly.
    d = np.minimum(periodic_dist_to_lines(xx, slab), periodic_dist_to_lines(yy, slab))
    joint_half = 0.012 * px_per_m          # 2.4 cm wide sawn joint
    joint = np.clip(joint_half + 0.75 - d, 0.0, 1.0)      # 1 inside, AA edge
    halo = np.exp(-(d / (0.06 * px_per_m)) ** 2)          # faint darkening next to the joint

    # Per-slab tone: each of the 4 slabs gets a tiny offset (cast on different days).
    sx = (xx // slab).astype(int) % 2
    sy = (yy // slab).astype(int) % 2
    slab_tone = np.array([[0.012, -0.010], [-0.006, 0.014]])[sy, sx]

    mottle = band_noise(rng, 2, 8)
    fine = band_noise(rng, 150, 450)
    lum = 1.0 + slab_tone + 0.014 * mottle + 0.025 * fine
    lum = lum * (1.0 - 0.06 * halo) * (1.0 - 0.32 * joint)
    albedo = base[None, None, :] * lum[..., None]

    height = 0.4 * fine - 6.0 * np.clip(joint_half + 1.5 - d, 0.0, None) / (joint_half + 1.5)
    normal = normal_from_height(height, 0.6)
    ao = 1.0 - 0.35 * joint - 0.08 * halo
    rough = 0.82 + 0.02 * fine + 0.08 * joint
    orm = np.stack([ao, rough, np.zeros_like(ao)], axis=-1)
    write_set("concrete", albedo, normal, orm)


if __name__ == "__main__":
    make_grass()
    make_asphalt()
    make_concrete()
