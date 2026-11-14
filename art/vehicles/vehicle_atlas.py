"""Layout of the shared vehicle atlas (512 × 512 px): image regions and solid swatches.

Pure data (no bpy): used by vehicle_textures.py (paints the atlas) and vehicle_kit.py (UVs).
Two textures share this layout:
  vehicle_albedo.png  RGB = albedo (sRGB), A = paint mask (1 = tinted by the instance paint colour)
  vehicle_rme.png     R = roughness, G = metallic, B = emission mask (lights on at night / driving)
Rects are (x, y, w, h) in pixels, y from the TOP of the image.
"""
ATLAS = 512
CELL = 32  # swatch size: big enough that mipmaps don't bleed neighbours at normal distances

RECTS = {
    # Wheels (tyre sidewall + rim, seen from outside), 128 px discs.
    "wheel_alloy5": (0, 0, 128, 128),        # small car, estate: 5 double spokes
    "wheel_alloy_multi": (128, 0, 128, 128),  # SUV: 10 spokes, larger rim
    "wheel_turbine": (256, 0, 128, 128),      # taxi: closed multi-spoke (fleet wheel)
    "wheel_steel": (384, 0, 128, 128),        # van: black steel wheel, 6 holes
    # Body paint: subtle wear gradient (clean top, faint road grime towards the sills). u = length, v = height.
    "paint_body": (0, 128, 128, 128),
    # Lights. Outside the lamp outline the pixels are paint (mask 1), so lamps can have any shape.
    "head_a": (128, 128, 128, 48),            # small car / estate: projector + LED strip
    "head_b": (256, 128, 128, 48),            # taxi / SUV: twin projectors, slimmer
    "head_van": (384, 128, 128, 48),          # van: tall reflector lamp
    "tail_a": (128, 176, 128, 48),            # small car / SUV
    "tail_b": (256, 176, 128, 48),            # estate / taxi: wide, two-part
    "tail_van": (384, 176, 48, 80),           # van: vertical stack (red / amber / white / red)
    "taxi_sign": (128, 224, 128, 32),         # yellow roof sign with black TAXI
    "door_number": (256, 224, 32, 32),        # taxi number decal (black on paint)
    "fuel_flap": (288, 224, 32, 32),          # paint with a fine shut line
    "handle": (320, 224, 32, 16),             # door handle: paint bar over a dark recess
    "fog_round": (352, 224, 32, 32),          # round fog lamp in a black bezel
    "grille_honey": (0, 256, 128, 64),        # honeycomb mesh, gloss black frame
    "grille_bars": (128, 256, 128, 64),       # horizontal slats, chrome frame (taxi / estate)
    "grille_van": (256, 256, 128, 64),        # wide slats, dark plastic
    "intake_mesh": (384, 256, 128, 64),       # lower bumper intake
    "plate_0": (0, 320, 128, 28),             # fictional plain plates, no country band
    "plate_1": (128, 320, 128, 28),
    "plate_2": (256, 320, 128, 28),
    "plate_3": (384, 320, 128, 28),
    "tail_bar": (0, 352, 128, 16),            # light bar across a tailgate (SUV)
    "rear_reflector": (128, 352, 32, 16),     # red reflector / rear fog in the bumper
}
PLATE_TEXT = ["KL 482 R", "MV 2093", "HR 715 A", "TS 117 B"]

# Solid swatches: name -> (albedo sRGB hex, paint mask, roughness, metallic, emission)
SWATCHES = {
    "paint": ("#FFFFFF", 1, 0.28, 0.0, 0.0),         # clean paint (mirror caps, small painted parts)
    "paint_seam": ("#5E5E5E", 1, 0.5, 0.0, 0.0),     # shut lines: darkened paint, never black
    "paint_low": ("#D2D0CB", 1, 0.4, 0.0, 0.0),      # lower sill, behind the wheels (road grime)
    "trim_black": ("#1D1E20", 0, 0.6, 0.0, 0.0),     # textured black plastic
    "trim_gloss": ("#131416", 0, 0.12, 0.0, 0.0),    # piano black (B pillars, window seals)
    "chrome": ("#C9CCCF", 0, 0.12, 1.0, 0.0),
    "rubber": ("#1C1C1D", 0, 0.92, 0.0, 0.0),        # tyre tread, seals
    "cladding": ("#2A2C2E", 0, 0.75, 0.0, 0.0),      # SUV arches/sills, van bumpers
    "underbody": ("#18191A", 0, 0.9, 0.0, 0.0),
    "liner": ("#141515", 0, 0.95, 0.0, 0.0),         # wheel arch liners
    "interior": ("#2A2B2D", 0, 0.9, 0.0, 0.0),       # door cards, floor
    "seat": ("#323336", 0, 0.85, 0.0, 0.0),
    "dash": ("#1F2022", 0, 0.7, 0.0, 0.0),
    "headliner": ("#55575A", 0, 0.9, 0.0, 0.0),
    "glass_far": ("#26323A", 0, 0.1, 0.0, 0.0),      # opaque glass of the _lodfar meshes
    "lens": ("#BFC8CF", 0, 0.05, 0.3, 0.0),
    "red_light": ("#9A1C18", 0, 0.15, 0.0, 1.0),     # third brake light
    "amber": ("#D27A1E", 0, 0.15, 0.0, 1.0),         # side repeaters, mirror indicators
    "reflector": ("#7A1714", 0, 0.3, 0.0, 0.0),
    "exhaust": ("#8E9194", 0, 0.3, 1.0, 0.0),
    "exhaust_in": ("#0E0E0E", 0, 0.9, 0.0, 0.0),
    "mirror_glass": ("#A5AEB4", 0, 0.05, 1.0, 0.0),
    "step_metal": ("#5C5F62", 0, 0.5, 0.8, 0.0),
    "taxi_yellow": ("#E8C33A", 0, 0.35, 0.0, 0.6),
    "plate_back": ("#1A1B1C", 0, 0.6, 0.0, 0.0),
    "brake_disc": ("#55585B", 0, 0.45, 0.8, 0.0),
}
_ORDER = list(SWATCHES)
SWATCH_Y0 = 384
PER_ROW = ATLAS // CELL


def swatch_rect(name: str) -> tuple:
    i = _ORDER.index(name)
    return ((i % PER_ROW) * CELL, SWATCH_Y0 + (i // PER_ROW) * CELL, CELL, CELL)


def uv_rect(name: str) -> tuple:
    """(u0, v0, u1, v1) of a region in UV space (v up, Blender / glTF after export)."""
    x, y, w, h = RECTS[name] if name in RECTS else swatch_rect(name)
    n = float(ATLAS)
    return x / n, 1.0 - (y + h) / n, (x + w) / n, 1.0 - y / n


def uv_in(name: str, fu: float, fv: float, inset: float = 1.5) -> tuple:
    """UV at fraction (fu, fv) of a region (fv = 0 at the bottom), kept `inset` px inside."""
    u0, v0, u1, v1 = uv_rect(name)
    e = inset / ATLAS
    fu = min(max(fu, 0.0), 1.0)
    fv = min(max(fv, 0.0), 1.0)
    return u0 + e + (u1 - u0 - 2 * e) * fu, v0 + e + (v1 - v0 - 2 * e) * fv


def uv_swatch(name: str) -> tuple:
    return uv_in(name, 0.5, 0.5)
