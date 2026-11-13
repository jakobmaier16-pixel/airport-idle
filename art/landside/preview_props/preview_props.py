"""Scale dummies for the landside previews only (not game assets, never exported to assets/).

car  4.5 × 1.8 × 1.45 m, ≤ 300 tris (body, cabin with dark windows, 4 wheels), 3 neutral colours
bus  12 × 2.55 × 3.1 m
person  1.75 m (cylinder body + head)
"""
import math
import os
import sys

sys.dont_write_bytecode = True  # no __pycache__ in art/
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import landside_kit as K  # noqa: E402

PERSON_COLOURS = {"person_coat_red": "#B23A30", "person_coat_beige": "#C2A77E",
                  "person_coat_blue": "#2F5C93", "person_coat_grey": "#7D8287",
                  "person_coat_yellow": "#D9A62E", "person_coat_green": "#3F7A55",
                  "person_coat_white": "#DADAD6", "person_coat_pink": "#C9788C"}
# Realistic car colour mix (white, silver, grey and black dominate; a few colours).
CAR_COLOURS = {"car_white": "#E2E2DE", "car_silver": "#9A9EA2", "car_grey": "#5E6368",
               "car_black": "#1E1F21", "car_darkblue": "#24395A", "car_red": "#9C2A24",
               "car_lightblue": "#6E8FB3", "car_orange": "#C8662A", "car_taxi": "#E6D7B2"}
CAR_MIX = (["car_white"] * 5 + ["car_silver"] * 4 + ["car_grey"] * 4 + ["car_black"] * 4
           + ["car_darkblue"] * 2 + ["car_red"] * 2 + ["car_lightblue", "car_orange"])


def make_materials() -> dict:
    mats = {n: K.flat(n, h, 0.35, 0.3) for n, h in CAR_COLOURS.items()}
    mats["car_window"] = K.flat("car_window", "#1C2226", 0.1)
    mats["car_tyre"] = K.flat("car_tyre", "#1E1E1E", 0.8)
    mats["bus_white"] = K.flat("bus_white", "#D8DADA", 0.4)
    mats["bus_green"] = K.flat("bus_green", "#2F7D4F", 0.4)
    mats["taxi_sign"] = K.flat("taxi_sign", "#E8C33A", 0.5)
    for n, h in PERSON_COLOURS.items():
        mats[n] = K.flat(n, h, 0.8)
    mats["person_legs"] = K.flat("person_legs", "#2B2E33", 0.8)
    mats["person_skin"] = K.flat("person_skin", "#B89A84", 0.6)
    return mats


def _wheel(mb: K.MB, cx: float, cy: float, r: float, w: float, side: int, n: int = 8) -> None:
    """Cylinder along Y; outer cap on the `side` (+1 / -1) only."""
    y0, y1 = (cy - w / 2, cy + w / 2)
    ring = [(cx + r * math.cos(2 * math.pi * i / n), r + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    for i in range(n):
        (xa, za), (xb, zb) = ring[i], ring[(i + 1) % n]
        mb.face([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], [(0, 0)] * 4, "car_tyre")
    yc = y1 if side > 0 else y0
    pts = [(x, yc, z) for x, z in ring]
    mb.face(pts if side < 0 else pts[::-1], [(0, 0)] * n, "car_tyre")


def car(colour: str) -> K.MB:
    mb = K.MB()
    if colour == "car_taxi":                       # German taxi: light ivory, yellow roof sign
        K.box(mb, -0.35, -0.3, 1.45, 0.05, 0.3, 1.62, "taxi_sign")
    K.box(mb, -2.25, -0.9, 0.3, 2.25, 0.9, 0.95, colour)
    # Cabin: tapered prism, windows on the sides, roof in body colour.
    b = [(-1.35, -0.82), (1.15, -0.82), (1.15, 0.82), (-1.35, 0.82)]
    t = [(-0.95, -0.68), (0.55, -0.68), (0.55, 0.68), (-0.95, 0.68)]
    z0, z1 = 0.95, 1.45
    mb.face([(*p, z1) for p in t], [(0, 0)] * 4, colour)
    for i in range(4):
        a, c = b[i], b[(i + 1) % 4]
        d, e = t[(i + 1) % 4], t[i]
        mb.face([(*a, z0), (*c, z0), (*d, z1), (*e, z1)], [(0, 0)] * 4, "car_window")
    for x in (-1.45, 1.45):
        for y, s in ((-0.8, -1), (0.8, 1)):
            _wheel(mb, x, y, 0.33, 0.22, s)
    return mb


def bus() -> K.MB:
    mb = K.MB()
    K.box(mb, -6.0, -1.275, 0.35, 6.0, 1.275, 3.1, "bus_white")
    for y, d in ((-1.279, -1), (1.279, 1)):        # fictional regional livery: green skirt band
        pts = [(-6.0, y, 0.4), (6.0, y, 0.4), (6.0, y, 1.1), (-6.0, y, 1.1)]
        mb.face(pts if d < 0 else pts[::-1], [(0, 0)] * 4, "bus_green")
    mb.face([(6.012, -1.27, 0.4), (6.012, 1.27, 0.4), (6.012, 1.27, 1.0), (6.012, -1.27, 1.0)], [(0, 0)] * 4, "bus_green")
    for y, d in ((-1.28, -1), (1.28, 1)):
        x0, x1 = -5.6, 5.0
        pts = [(x0, y, 1.25), (x1, y, 1.25), (x1, y, 2.75), (x0, y, 2.75)]
        mb.face(pts if d < 0 else pts[::-1], [(0, 0)] * 4, "car_window")
    mb.face([(6.01, -1.1, 1.1), (6.01, 1.1, 1.1), (6.01, 1.1, 2.8), (6.01, -1.1, 2.8)], [(0, 0)] * 4,
            "car_window")
    for x in (-3.8, 3.6):
        for y, s in ((-1.05, -1), (1.05, 1)):
            _wheel(mb, x, y, 0.5, 0.3, s)
    return mb


def person(coat: str) -> K.MB:
    """1.75 m figure: two legs, torso, arms, head (reads as a person, not a post)."""
    mb = K.MB()
    for x in (-0.11, 0.03):
        K.box(mb, x, -0.08, 0.0, x + 0.08, 0.06, 0.85, "person_legs")
    K.box(mb, -0.2, -0.11, 0.85, 0.2, 0.11, 1.45, coat)
    for x in (-0.27, 0.2):
        K.box(mb, x, -0.06, 0.8, x + 0.07, 0.06, 1.42, coat)
    K.box(mb, -0.05, -0.05, 1.45, 0.05, 0.05, 1.52, "person_skin")
    K.box(mb, -0.1, -0.11, 1.52, 0.1, 0.1, 1.75, "person_skin")
    return mb
