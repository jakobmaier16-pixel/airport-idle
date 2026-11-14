"""Paints the shared vehicle atlas (layout: vehicle_atlas.py).

Run headless:  BPY=$(tools/setup_blender.sh) && "$BPY" art/vehicles/vehicle_textures.py
Writes assets/textures/vehicle/vehicle_albedo.png (512², RGBA: A = paint mask) and
assets/textures/vehicle/vehicle_rme.png (512², R roughness, G metallic, B emission mask).

Everything is drawn procedurally (4 × 4 supersampled shapes), seeds are fixed. No brand shapes,
no logos, no real plate format: plates are plain white with a fictional "AB 123 C" pattern.
"""
import math
import os
import sys

import numpy as np

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "ground"))
import vehicle_atlas as A  # noqa: E402
from atlas_text import text_mask  # noqa: E402
from tex_io import ROOT, save_png  # noqa: E402

OUT = os.path.join(ROOT, "assets", "textures", "vehicle")
N = A.ATLAS
SS = 4

alb = np.zeros((N, N, 3), np.float32)
mask = np.zeros((N, N), np.float32)
rough = np.full((N, N), 0.6, np.float32)
metal = np.zeros((N, N), np.float32)
emit = np.zeros((N, N), np.float32)


def rgb(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)], np.float32)


def grid(name: str):
    """Supersampled pixel-centre coordinates of a region: x, y in region pixels (y down)."""
    x, y, w, h = A.RECTS[name]
    xs = (np.arange(w * SS) + 0.5) / SS
    ys = (np.arange(h * SS) + 0.5) / SS
    return np.meshgrid(xs, ys)


def put(name: str, inside: np.ndarray, colour, m: float, r: float, mt: float = 0.0, e: float = 0.0) -> None:
    """Blend a supersampled boolean shape into region `name`. colour: hex or (h, w, 3) array."""
    x, y, w, h = A.RECTS[name]
    cov = inside.reshape(h, SS, w, SS).mean(axis=(1, 3)).astype(np.float32)
    sl = (slice(y, y + h), slice(x, x + w))
    c = rgb(colour) if isinstance(colour, str) else colour
    alb[sl] = alb[sl] * (1 - cov[..., None]) + c * cov[..., None]
    for arr, val in ((mask, m), (rough, r), (metal, mt), (emit, e)):
        arr[sl] = arr[sl] * (1 - cov) + val * cov


def fill(name: str, colour: str, m: float, r: float, mt: float = 0.0, e: float = 0.0) -> None:
    gx, _ = grid(name)
    put(name, np.ones_like(gx, bool), colour, m, r, mt, e)


def poly(gx, gy, pts) -> np.ndarray:
    """Inside a convex polygon (any winding)."""
    inside_pos = np.ones_like(gx, bool)
    inside_neg = np.ones_like(gx, bool)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
        cr = (x1 - x0) * (gy - y0) - (y1 - y0) * (gx - x0)
        inside_pos &= cr >= 0
        inside_neg &= cr <= 0
    return inside_pos | inside_neg


def ellipse(gx, gy, cx, cy, rx, ry) -> np.ndarray:
    return ((gx - cx) / rx) ** 2 + ((gy - cy) / ry) ** 2 <= 1.0


def rectm(gx, gy, x0, y0, x1, y1) -> np.ndarray:
    return (gx >= x0) & (gx <= x1) & (gy >= y0) & (gy <= y1)


def text(name: str, s: str, box: tuple, colour: str, m: float, r: float, e: float = 0.0,
         bold: float = 0.0) -> None:
    """Text into box (x, y, w, h) relative to the region."""
    rx, ry, rw, rh = A.RECTS[name]
    bx, by, bw, bh = box
    cov = text_mask(s, bw, bh, pad=0.5, bold=bold)
    sl = (slice(ry + by, ry + by + bh), slice(rx + bx, rx + bx + bw))
    c = rgb(colour)
    alb[sl] = alb[sl] * (1 - cov[..., None]) + c * cov[..., None]
    for arr, val in ((mask, m), (rough, r), (metal, 0.0), (emit, e)):
        arr[sl] = arr[sl] * (1 - cov) + val * cov


# --- Swatches -----------------------------------------------------------------------------------
def swatches() -> None:
    for name, (h, m, r, mt, e) in A.SWATCHES.items():
        x, y, w, hh = A.swatch_rect(name)
        sl = (slice(y, y + hh), slice(x, x + w))
        alb[sl] = rgb(h)
        mask[sl], rough[sl], metal[sl], emit[sl] = m, r, mt, e


def paint_body() -> None:
    """Clean paint at the top, a faint road-grime film over the lowest third (quiet wear)."""
    x, y, w, h = A.RECTS["paint_body"]
    rng = np.random.default_rng(31)
    v = (np.arange(h) + 0.5) / h                       # 0 = top of the car, 1 = ground
    grime = np.clip((v - 0.62) / 0.38, 0, 1) ** 1.6
    noise = rng.normal(0, 1, (h // 8 + 1, w // 8 + 1)).repeat(8, 0).repeat(8, 1)[:h, :w]
    k = np.ones((5, 5)) / 25.0
    pad = np.pad(noise, 2, mode="edge")
    smooth = sum(pad[i:i + h, j:j + w] * k[i, j] for i in range(5) for j in range(5))
    tint = np.array([0.95, 0.92, 0.86], np.float32)
    base = 1.0 - 0.15 * grime[:, None] + 0.012 * smooth * (0.4 + grime[:, None])
    col = base[..., None] * (1 - (1 - tint) * grime[:, None, None])
    sl = (slice(y, y + h), slice(x, x + w))
    alb[sl] = np.clip(col, 0, 1)
    mask[sl] = 1.0
    rough[sl] = 0.28 + 0.2 * grime[:, None]
    metal[sl] = 0.0


# --- Wheels -------------------------------------------------------------------------------------
def wheel(name: str, rim: float, kind: str) -> None:
    gx, gy = grid(name)
    _, _, w, h = A.RECTS[name]
    dx, dy = (gx - w / 2) / (w / 2), (gy - h / 2) / (h / 2)
    r = np.hypot(dx, dy)
    a = np.arctan2(dy, dx)
    fill(name, "#1E1E1F", 0, 0.9)
    # Tyre: tread shoulder darker, one faint moulded ring on the sidewall (no lettering, no brand).
    put(name, (r > rim) & (r <= 1.0), "#232324", 0, 0.88)
    put(name, (r > 0.93) & (r <= 1.0), "#18181A", 0, 0.92)
    put(name, (np.abs(r - (rim + (1 - rim) * 0.55)) < 0.012), "#2B2B2C", 0, 0.85)
    put(name, (r > rim - 0.015) & (r <= rim + 0.01), "#151516", 0, 0.9)          # bead seat shadow
    inner = rim - 0.05
    # Behind the spokes: dark barrel, brake disc and a caliper.
    put(name, r <= inner, "#121213", 0, 0.9)
    put(name, (r <= inner * 0.82) & (r > inner * 0.30), "#4E5154", 0, 0.45, 0.8)
    cal = (np.abs(a - math.radians(-35)) < 0.42) & (r > inner * 0.55) & (r < inner * 0.86)
    put(name, cal, "#2C2E30", 0, 0.6)
    if kind == "steel":
        put(name, (r > inner) & (r <= rim - 0.015), "#34373A", 0, 0.45, 0.3)       # rim flange
        disc = (r <= inner)
        holes = np.zeros_like(disc)
        for k in range(6):
            ang = 2 * math.pi * k / 6
            cx, cy = 0.62 * inner * math.cos(ang), 0.62 * inner * math.sin(ang)
            holes |= ((dx - cx) ** 2 + (dy - cy) ** 2) < (0.13 * inner) ** 2
        put(name, disc & ~holes, "#2E3134", 0, 0.5, 0.3)
        put(name, (np.abs(r - inner * 0.42) < 0.03), "#18191A", 0, 0.6)            # pressed ring
        hub = r <= inner * 0.30
        put(name, hub, "#3A3D40", 0, 0.4, 0.6)
        for k in range(6):
            ang = 2 * math.pi * k / 6 + math.pi / 6
            put(name, ((dx - 0.2 * inner * math.cos(ang)) ** 2 + (dy - 0.2 * inner * math.sin(ang)) ** 2)
                < (0.035) ** 2, "#9A9DA0", 0, 0.3, 1.0)
        return
    silver, rs = ("#B4B8BC", 0.3) if kind != "multi" else ("#A9ADB1", 0.28)
    put(name, (r > inner) & (r <= rim - 0.012), silver, 0, rs, 0.9)                 # rim lip
    spokes = np.zeros_like(r, bool)
    if kind == "alloy5":
        for k in range(5):
            c = 2 * math.pi * k / 5 - math.pi / 2
            for off in (-0.13, 0.13):
                d = np.angle(np.exp(1j * (a - c - off * (1 - r / inner * 0.6))))
                spokes |= np.abs(d) < (0.075 + 0.06 * (1 - r / inner))
    elif kind == "multi":
        for k in range(10):
            c = 2 * math.pi * k / 10
            d = np.angle(np.exp(1j * (a - c)))
            spokes |= np.abs(d) < (0.06 + 0.10 * (1 - r / inner))
    else:  # turbine: closed face with many narrow slots
        spokes = np.ones_like(r, bool)
        for k in range(14):
            c = 2 * math.pi * k / 14
            d = np.angle(np.exp(1j * (a - c - 0.35 * r)))
            spokes &= ~((np.abs(d) < 0.09) & (r > inner * 0.5) & (r < inner * 0.93))
    put(name, spokes & (r <= inner) & (r > inner * 0.28), silver, 0, rs, 0.9)
    put(name, (r <= inner * 0.30), "#9DA1A5", 0, 0.3, 0.9)                            # hub face
    put(name, (r <= inner * 0.15), "#3B3E41", 0, 0.35, 0.7)                           # plain centre cap
    for k in range(5):
        ang = 2 * math.pi * k / 5 + math.pi / 10
        put(name, ((dx - 0.22 * inner * math.cos(ang)) ** 2 + (dy - 0.22 * inner * math.sin(ang)) ** 2)
            < 0.028 ** 2, "#2A2C2E", 0, 0.4, 0.8)


# --- Lights ---------------------------------------------------------------------------------------
PAINT = ("#FFFFFF", 1, 0.28)


def headlight(name: str, style: str) -> None:
    gx, gy = grid(name)
    _, _, w, h = A.RECTS[name]
    fill(name, *PAINT)
    if style == "c":                                                                    # rounded lamp (small car)
        shape = ellipse(gx, gy, w / 2, h / 2 + 1, w / 2 - 2, h / 2 - 3) | \
            (ellipse(gx, gy, w * 0.62, h / 2, w * 0.36, h / 2 - 2))
        put(name, shape, "#202224", 0, 0.05, 0.2)
        inner = ellipse(gx, gy, w / 2, h / 2 + 1, w / 2 - 5, h / 2 - 6)
        put(name, inner, "#5E6368", 0, 0.08, 1.0)
        ring = ellipse(gx, gy, w * 0.40, h * 0.54, 15, 15) & ~ellipse(gx, gy, w * 0.40, h * 0.54, 12, 12)
        put(name, ring, "#F4F6F8", 0, 0.05, 0.0, 1.0)                                    # LED ring (DRL)
        put(name, ellipse(gx, gy, w * 0.40, h * 0.54, 9, 9), "#E8ECEF", 0, 0.05, 0.2, 1.0)
        put(name, inner & (gx > w * 0.76), "#D8822A", 0, 0.1)                           # amber indicator
        return
    if style == "van":
        outline = [(2, 4), (w - 2, 2), (w - 2, h - 2), (4, h - 2)]
    elif style == "b":
        outline = [(2, 10), (w - 2, 2), (w - 2, h - 14), (w - 30, h - 2), (2, h - 6)]
    else:
        outline = [(2, 7), (w - 2, 2), (w - 2, h - 10), (w - 34, h - 2), (2, h - 3)]
    shape = poly(gx, gy, outline)
    put(name, shape, "#202224", 0, 0.05, 0.2)                                         # housing rim
    inner = poly(gx, gy, [(x + (3 if x < w / 2 else -3), y + (3 if y < h / 2 else -3)) for x, y in outline])
    put(name, inner, "#5E6368", 0, 0.08, 1.0)                                         # chrome reflector under clear lens
    if style == "van":
        put(name, inner & (gx > w * 0.08) & (gx < w * 0.62) & (gy > 8) & (gy < h - 8), "#B9BEC2", 0, 0.1, 1.0)
        put(name, ellipse(gx, gy, w * 0.35, h * 0.52, 15, 13), "#E6EAEE", 0, 0.05, 0.2, 1.0)
        put(name, inner & (gx > w * 0.70), "#D8822A", 0, 0.1)                       # amber indicator
        put(name, inner & (gy < 9) & (gx < w * 0.68), "#F2F4F6", 0, 0.05, 0.0, 1.0)  # DRL strip
        return
    for i, cx in enumerate((0.30, 0.55) if style == "b" else (0.36,)):
        put(name, ellipse(gx, gy, w * cx, h * 0.56, 12, 12), "#25272A", 0, 0.1)          # projector bezel
        put(name, ellipse(gx, gy, w * cx, h * 0.56, 8.5, 8.5), "#E8ECEF", 0, 0.05, 0.2, 1.0)
    put(name, inner & (gx > w * 0.72), "#9AA0A5", 0, 0.1, 1.0)
    put(name, inner & (gx > w * 0.78) & (gy < h * 0.5), "#D8822A", 0, 0.1)          # amber indicator
    # LED daytime running strip along the upper edge.
    top = [(6, 10 if style == "a" else 13), (w - 6, 6), (w - 6, 11), (6, 15 if style == "a" else 18)]
    put(name, poly(gx, gy, top), "#F4F6F8", 0, 0.05, 0.0, 1.0)


def taillight(name: str, style: str) -> None:
    gx, gy = grid(name)
    _, _, w, h = A.RECTS[name]
    fill(name, *PAINT)
    if style == "van":
        frame = rectm(gx, gy, 3, 2, w - 3, h - 2)
        put(name, frame, "#3A1212", 0, 0.05)
        for (y0, y1, c, e) in ((5, 30, "#B0201A", 1.0), (31, 46, "#D8822A", 0.0),
                               (47, 60, "#DADCDD", 0.0), (61, 76, "#9A1C18", 1.0)):
            put(name, rectm(gx, gy, 6, y0, w - 6, y1), c, 0, 0.08, 0.0, e)
        return
    if style == "b":
        outline = [(2, 2), (w - 2, 4), (w - 2, h - 4), (2, h - 10)]
    else:
        outline = [(2, 2), (w - 2, 3), (w - 2, h - 3), (30, h - 2), (2, h - 12)]
    shape = poly(gx, gy, outline)
    put(name, shape, "#4A0D0C", 0, 0.05)                                               # smoked red lens
    # Light graphic: an LED contour (lit at night) and a white reverse segment (off).
    put(name, shape & poly(gx, gy, [(8, 8), (w - 8, 11), (w - 8, 16), (8, 13)]), "#C8261E", 0, 0.08, 0.0, 1.0)
    put(name, shape & rectm(gx, gy, w - 14, 10, w - 8, h - 9), "#C8261E", 0, 0.08, 0.0, 1.0)
    put(name, shape & rectm(gx, gy, 10, h * 0.55, w * 0.38, h * 0.72), "#D6D8DA", 0, 0.08)
    put(name, shape & rectm(gx, gy, w * 0.42, h * 0.55, w * 0.62, h * 0.72), "#B86A20", 0, 0.08)
    if style == "b":                                                                    # tailgate split
        put(name, rectm(gx, gy, w * 0.30, 0, w * 0.30 + 1.2, h), "#5E5E5E", 1, 0.5)


# --- Other decals --------------------------------------------------------------------------------
def grilles() -> None:
    n = "grille_honey"
    gx, gy = grid(n)
    _, _, w, h = A.RECTS[n]
    fill(n, "#131416", 0, 0.12)
    cells = (np.sin(gx * 0.9) * np.sin(gy * 0.9 + 0.5 * np.sin(gx * 0.45))) > 0.25
    put(n, cells & rectm(gx, gy, 4, 4, w - 4, h - 4), "#2C2E30", 0, 0.45)
    n = "grille_bars"
    gx, gy = grid(n)
    _, _, w, h = A.RECTS[n]
    fill(n, "#C9CCCF", 0, 0.12, 1.0)                                                   # chrome surround
    put(n, rectm(gx, gy, 4, 4, w - 4, h - 4), "#101112", 0, 0.6)
    for k in range(5):
        y0 = 8 + k * 11
        put(n, rectm(gx, gy, 6, y0, w - 6, y0 + 4), "#25272A" if k else "#B4B8BC", 0, 0.2, 0.0 if k else 1.0)
    n = "grille_van"
    gx, gy = grid(n)
    _, _, w, h = A.RECTS[n]
    fill(n, "#2A2C2E", 0, 0.7)
    for k in range(4):
        y0 = 6 + k * 14
        put(n, rectm(gx, gy, 6, y0, w - 6, y0 + 7), "#121314", 0, 0.8)
    n = "intake_mesh"
    gx, gy = grid(n)
    _, _, w, h = A.RECTS[n]
    fill(n, "#1D1E20", 0, 0.6)
    diamonds = (np.abs(((gx + gy) % 8) - 4) < 1.2) | (np.abs(((gx - gy) % 8) - 4) < 1.2)
    put(n, ~diamonds & rectm(gx, gy, 3, 3, w - 3, h - 3), "#0C0C0D", 0, 0.9)


def plates() -> None:
    for i, s in enumerate(A.PLATE_TEXT):
        n = f"plate_{i}"
        gx, gy = grid(n)
        _, _, w, h = A.RECTS[n]
        fill(n, "#141414", 0, 0.5)
        put(n, rectm(gx, gy, 1.5, 1.5, w - 1.5, h - 1.5), "#E2E2DC", 0, 0.45)
        put(n, rectm(gx, gy, 3, 3, w - 3, h - 3) & ~rectm(gx, gy, 4, 4, w - 4, h - 4), "#202020", 0, 0.5)
        text(n, s, (8, 5, w - 16, h - 10), "#141414", 0, 0.5, bold=0.6)


def small() -> None:
    n = "taxi_sign"
    _, _, w, h = A.RECTS[n]
    fill(n, "#E8C33A", 0, 0.35, 0.0, 0.8)
    text(n, "TAXI", (14, 6, w - 28, h - 12), "#151515", 0, 0.4, bold=0.8)
    n = "door_number"
    fill(n, *PAINT)
    text(n, "24", (6, 9, 20, 14), "#1A1A1A", 0, 0.4, bold=0.4)
    n = "fuel_flap"
    gx, gy = grid(n)
    fill(n, *PAINT)
    put(n, ellipse(gx, gy, 16, 16, 14, 14) & ~ellipse(gx, gy, 16, 16, 12.8, 12.8), "#5E5E5E", 1, 0.5)
    put(n, ellipse(gx, gy, 26.5, 16, 1.5, 3.5), "#7A7A7A", 1, 0.5)
    n = "handle"
    gx, gy = grid(n)
    fill(n, *PAINT)
    put(n, ellipse(gx, gy, 16, 8.5, 14, 6.5), "#2A2B2C", 0, 0.7)                      # recess
    put(n, ellipse(gx, gy, 16, 6.5, 13, 3.2), "#F2F2F2", 1, 0.25)                    # paint-coloured handle
    n = "fog_round"
    gx, gy = grid(n)
    fill(n, "#1D1E20", 0, 0.6)
    put(n, ellipse(gx, gy, 16, 16, 11, 11), "#9EA4A9", 0, 0.1, 1.0)
    put(n, ellipse(gx, gy, 16, 16, 8, 8), "#DDE1E4", 0, 0.05)
    n = "tail_bar"
    gx, gy = grid(n)
    _, _, w, h = A.RECTS[n]
    fill(n, "#4A0D0C", 0, 0.05)
    put(n, rectm(gx, gy, 2, 5, w - 2, 10), "#C8261E", 0, 0.08, 0.0, 1.0)
    n = "rear_reflector"
    gx, gy = grid(n)
    fill(n, "#1D1E20", 0, 0.6)
    put(n, rectm(gx, gy, 2, 3, 30, 13), "#8A1A16", 0, 0.3)


def main() -> None:
    swatches()
    paint_body()
    wheel("wheel_alloy5", 0.64, "alloy5")
    wheel("wheel_alloy_multi", 0.62, "multi")
    wheel("wheel_turbine", 0.645, "turbine")
    wheel("wheel_steel", 0.58, "steel")
    headlight("head_a", "a")
    headlight("head_b", "b")
    headlight("head_van", "van")
    headlight("head_c", "c")
    taillight("tail_a", "a")
    taillight("tail_b", "b")
    taillight("tail_van", "van")
    grilles()
    plates()
    small()
    save_png(os.path.join(OUT, "vehicle_albedo.png"), np.dstack([alb, mask]))
    save_png(os.path.join(OUT, "vehicle_rme.png"), np.dstack([rough, metal, emit]))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
