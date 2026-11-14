"""Passenger-car kit: five fictional vehicle types built from real vehicle-class dimensions.

Used by vehicle_pieces.py (export + budgets + studio previews) and vehicle_landside.py (curb preview).
Dimensions, pieces and Godot settings: vehicles.md.

How a car is built (cheap but real proportions):
- The body is a loft: a cross-section ring (sill, body side, shoulder, belt line, greenhouse,
  roof edge, roof) is sampled at stations along the length. Every height and width comes from
  per-type profile tables (side view and plan view), so bonnet, windscreen rake, roof, tailgate,
  overhangs and wheel arches sit where the real vehicle class has them.
- Wheel arches are cut by lifting the underside along a circle around each axle.
- Lamps, grille, plates, handles, fuel flap are flat decals a few mm in front of the body,
  mapped to the shared atlas (vehicle_atlas.py). Shut lines are thin quads of darkened paint.
- Two materials: `vehicle` (opaque atlas; paint tinted per instance where the atlas alpha says so)
  and the shared `glass`. `_lodfar` uses only `vehicle` (opaque dark glass swatch).

Car axes: u = metres from the front bumper backwards, v = to the car's left, z = up.
Blender: X = -v, Y = L/2 - u, Z = z: the nose points to +Y in Blender. The glTF exporter turns
Blender +Y into -Z, so in Godot the car faces -Z (Node3D forward, look_at) as the code lane expects.
Origin = ground centre.
"""
import math
import os
import sys
from bisect import bisect_right

sys.dont_write_bytecode = True  # no __pycache__ in art/
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "landside"))
import vehicle_atlas as A  # noqa: E402
import landside_kit as K  # noqa: E402  (MB mesh builder, hex helpers, shared glass)

OFF = 0.005  # decal offset in front of the body


def lerp_table(table: list, u: float) -> float:
    us = [p[0] for p in table]
    if u <= us[0]:
        return table[0][1]
    if u >= us[-1]:
        return table[-1][1]
    i = bisect_right(us, u) - 1
    (u0, a), (u1, b) = table[i], table[i + 1]
    return a + (b - a) * (u - u0) / (u1 - u0)


# --- Type specs --------------------------------------------------------------------------------
# L/W/H: overall (mirrors excluded, roof rails / sign included in H where the class has them).
# Profiles are (u, value) tables. A0 = windscreen base (cowl), A1 = windscreen top, R1 = roof end,
# C1 = bottom of the rear window (top of the tail / boot deck).
SPECS = {
    "car_small": dict(
        label="Small car (hatchback)", L=4.07, W=1.75, H=1.45, wb=2.56, fo=0.83, r=0.315, tw=0.195,
        gc=0.14, A0=1.08, A1=1.86, R1=3.66, C1=3.94, drop=0.06, k1=0.10,
        top=[(0, 0.73), (0.15, 0.80), (0.6, 0.875), (1.08, 0.93), (1.86, 1.40), (2.4, 1.45), (3.25, 1.43),
             (3.66, 1.40), (3.94, 1.00), (4.07, 0.97)],
        belt=[(0, 0.64), (0.6, 0.82), (1.08, 0.90), (1.86, 0.94), (3.3, 1.00), (3.8, 1.00), (4.07, 0.93)],
        bot=[(0, 0.25), (0.35, 0.17), (0.6, 0.15), (3.6, 0.15), (3.8, 0.24), (4.07, 0.33)],
        w=[(0, 0.79), (0.12, 0.845), (0.32, 0.870), (0.6, 0.875), (3.5, 0.875), (3.82, 0.865),
           (3.97, 0.83), (4.07, 0.77)],
        roof_w=[(1.86, 0.60), (2.6, 0.645), (3.66, 0.58)],
        windows=[(1.30, 2.30), (2.40, 3.10)], bpillar=(2.30, 2.40), belt_trim="trim_black",
        seams=[1.10, 2.34, 3.16], handles=[2.10, 2.98], mirror_u=1.20, fuel=(3.50, 3.67),
        seats=(2.48, 3.28), floor=0.32, cargo=None, wheel="wheel_alloy5",
        head=("head_a", 0.575, 0.72, 0.40), grille=("grille_honey", 0.36, 0.50, 0.69),
        plate_f=(0.36, 0.47), intake=(0.40, 0.27, 0.35), fog=(0.63, 0.31, 0.39),
        tail=("tail_a", 0.78, 0.955, 0.48), plate_r=(0.58, 0.69), bumper_seam_r=0.51,
        reflector=(0.66, 0.38), exhaust=(0.45, 0.28, 0.032), rails=False, spoiler=True,
        rear_wiper=True, plate=0),
    "car_estate": dict(
        label="Estate", L=4.92, W=1.85, H=1.50, wb=2.84, fo=1.03, r=0.34, tw=0.215,
        gc=0.14, A0=1.42, A1=2.24, R1=4.66, C1=4.82, drop=0.06, k1=0.10,
        top=[(0, 0.74), (0.15, 0.815), (0.75, 0.895), (1.42, 0.97), (2.24, 1.43), (2.9, 1.47), (4.0, 1.46),
             (4.66, 1.42), (4.82, 1.03), (4.92, 0.99)],
        belt=[(0, 0.64), (0.75, 0.84), (1.42, 0.92), (2.24, 0.95), (4.3, 1.01), (4.75, 1.01), (4.92, 0.94)],
        bot=[(0, 0.27), (0.40, 0.18), (0.7, 0.15), (4.4, 0.15), (4.65, 0.24), (4.92, 0.34)],
        w=[(0, 0.83), (0.13, 0.895), (0.35, 0.920), (0.7, 0.925), (4.4, 0.925), (4.70, 0.915),
           (4.84, 0.885), (4.92, 0.83)],
        roof_w=[(2.24, 0.64), (3.0, 0.69), (4.66, 0.64)],
        windows=[(1.62, 2.66), (2.76, 3.62), (3.72, 4.42)], bpillar=(2.66, 2.76), belt_trim="chrome",
        seams=[1.45, 2.70, 3.66], handles=[2.45, 3.45], mirror_u=1.55, fuel=(4.10, 4.27),
        seats=(2.85, 3.65), floor=0.33, cargo=(3.70, 4.62), wheel="wheel_alloy5",
        head=("head_b", 0.585, 0.73, 0.44), grille=("grille_bars", 0.42, 0.53, 0.70),
        plate_f=(0.36, 0.47), intake=(0.46, 0.28, 0.35), fog=(0.68, 0.31, 0.39),
        tail=("tail_b", 0.79, 0.965, 0.42), plate_r=(0.57, 0.68), bumper_seam_r=0.50,
        reflector=(0.70, 0.40), exhaust=(0.50, 0.29, 0.034), rails=True, spoiler=True,
        rear_wiper=True, plate=1),
    "car_suv": dict(
        label="SUV (compact)", L=4.54, W=1.86, H=1.67, wb=2.68, fo=0.91, r=0.37, tw=0.235,
        gc=0.20, A0=1.18, A1=1.98, R1=4.05, C1=4.42, drop=0.06, k1=0.17,
        top=[(0, 0.88), (0.15, 0.97), (0.65, 1.04), (1.18, 1.12), (1.98, 1.58), (2.5, 1.625), (3.6, 1.615),
             (4.05, 1.575), (4.42, 1.13), (4.54, 1.08)],
        belt=[(0, 0.80), (0.65, 1.00), (1.18, 1.07), (1.98, 1.09), (3.6, 1.15), (4.30, 1.16), (4.54, 1.05)],
        bot=[(0, 0.42), (0.35, 0.27), (0.6, 0.20), (3.9, 0.20), (4.2, 0.30), (4.54, 0.46)],
        w=[(0, 0.83), (0.13, 0.90), (0.33, 0.926), (0.6, 0.93), (3.9, 0.93), (4.25, 0.92),
           (4.42, 0.885), (4.54, 0.82)],
        roof_w=[(1.98, 0.65), (2.8, 0.69), (4.05, 0.63)],
        windows=[(1.38, 2.42), (2.52, 3.32), (3.42, 3.88)], bpillar=(2.42, 2.52), belt_trim="trim_black",
        seams=[1.22, 2.46, 3.36], handles=[2.25, 3.18], mirror_u=1.32, fuel=(3.78, 3.96),
        seats=(2.62, 3.40), floor=0.45, cargo=(3.45, 4.02), wheel="wheel_alloy_multi",
        head=("head_b", 0.74, 0.87, 0.46), grille=("grille_honey", 0.42, 0.62, 0.85),
        plate_f=(0.48, 0.59), intake=None, fog=None,
        tail=("tail_a", 0.91, 1.07, 0.48), plate_r=(0.70, 0.81), bumper_seam_r=0.64,
        reflector=(0.72, 0.55), exhaust=(0.50, 0.40, 0.034), rails=True, spoiler=True,
        rear_wiper=True, plate=2, cladding=True),
    "car_taxi": dict(
        label="Taxi (executive saloon)", L=4.95, W=1.85, H=1.47, wb=2.94, fo=0.84, r=0.335, tw=0.225,
        gc=0.13, A0=1.38, A1=2.22, R1=3.78, C1=4.36, drop=0.06, k1=0.10,
        top=[(0, 0.735), (0.15, 0.81), (0.7, 0.88), (1.38, 0.95), (2.22, 1.41), (2.85, 1.47), (3.4, 1.465),
             (3.78, 1.42), (4.36, 1.05), (4.80, 1.03), (4.95, 0.98)],
        belt=[(0, 0.64), (0.7, 0.83), (1.38, 0.91), (2.22, 0.93), (3.9, 0.99), (4.6, 1.00), (4.95, 0.94)],
        bot=[(0, 0.25), (0.40, 0.16), (0.7, 0.14), (4.3, 0.14), (4.6, 0.24), (4.95, 0.34)],
        w=[(0, 0.83), (0.13, 0.895), (0.35, 0.920), (0.7, 0.925), (4.40, 0.925), (4.72, 0.915),
           (4.86, 0.885), (4.95, 0.83)],
        roof_w=[(2.22, 0.63), (3.0, 0.67), (3.78, 0.62)],
        windows=[(1.58, 2.72), (2.82, 3.56)], bpillar=(2.72, 2.82), belt_trim="chrome",
        seams=[1.42, 2.76, 3.62], handles=[2.50, 3.40], mirror_u=1.50, fuel=(4.02, 4.19),
        seats=(2.86, 3.68), floor=0.32, cargo=None, shelf=(3.70, 4.30), wheel="wheel_turbine",
        head=("head_b", 0.585, 0.725, 0.44), grille=("grille_bars", 0.36, 0.51, 0.70),
        plate_f=(0.36, 0.47), intake=(0.46, 0.28, 0.35), fog=(0.68, 0.31, 0.39),
        tail=("tail_b", 0.79, 0.96, 0.40), plate_r=(0.62, 0.73), bumper_seam_r=0.58,
        reflector=(0.70, 0.42), exhaust=(0.50, 0.29, 0.034), rails=False, spoiler=False,
        rear_wiper=False, plate=3, taxi=True, boot=True),
    "van": dict(
        label="Panel van", L=5.05, W=1.90, H=1.99, wb=3.00, fo=0.95, r=0.345, tw=0.215,
        gc=0.18, A0=0.78, A1=1.48, R1=5.05, C1=5.05, drop=0.05, k1=0.10,
        top=[(0, 0.86), (0.12, 0.95), (0.48, 1.04), (0.78, 1.10), (1.48, 1.93), (1.85, 1.975), (4.85, 1.975),
             (4.98, 1.965), (5.05, 1.95)],
        belt=[(0, 0.78), (0.48, 0.99), (0.78, 1.05), (1.48, 1.08), (5.05, 1.08)],
        bot=[(0, 0.36), (0.35, 0.24), (0.6, 0.19), (4.6, 0.19), (4.85, 0.28), (5.05, 0.40)],
        w=[(0, 0.86), (0.12, 0.925), (0.32, 0.947), (0.6, 0.95), (4.85, 0.95), (4.98, 0.935), (5.05, 0.90)],
        roof_w=[(1.48, 0.84), (2.0, 0.895), (4.85, 0.895), (5.05, 0.85)],
        windows=[(0.96, 1.86)], bpillar=None, belt_trim="trim_black",
        seams=[0.84, 1.90], seams_r=[1.98, 3.10], handles=[1.70], mirror_u=0.88, fuel=None,
        seats=(1.84, None), floor=0.42, cargo=None, wheel="wheel_steel",
        head=("head_van", 0.66, 0.85, 0.43), grille=("grille_van", 0.42, 0.66, 0.84),
        plate_f=(0.42, 0.53), intake=None, fog=None,
        tail=("tail_van", 0.80, 1.32, 0.775), plate_r=(0.66, 0.77), bumper_seam_r=None,
        reflector=None, exhaust=(0.52, 0.33, 0.035), rails=False, spoiler=False,
        rear_wiper=False, plate=0, van=True, rake_f=(0.05, 0.62), rake_r=(0.0, 1.0)),
}


class Car:
    def __init__(self, name: str) -> None:
        self.name = name
        self.s = SPECS[name]
        s = self.s
        self.L = s["L"]
        self.ua = (s["fo"], s["fo"] + s["wb"])          # axle positions
        self.ra = s["r"] + 0.045                         # arch radius
        self.lod0 = K.MB()
        self.far = K.MB()

    # --- profiles -------------------------------------------------------------------------------
    def zbot(self, u: float) -> float:
        z = lerp_table(self.s["bot"], u)
        for ua in self.ua:
            d = abs(u - ua)
            if d < self.ra:
                z = max(z, self.s["r"] + math.sqrt(self.ra ** 2 - d ** 2))
        return z

    def wbody(self, u: float) -> float:
        return lerp_table(self.s["w"], u)

    def wtop(self, u: float) -> float:
        s = self.s
        wb = self.wbody(u)
        bonnet = wb - 0.10
        if u <= s["A0"]:
            wt = bonnet
        elif u < s["A1"]:
            f = (u - s["A0"]) / (s["A1"] - s["A0"])
            wt = bonnet + (lerp_table(s["roof_w"], s["A1"]) - bonnet) * f
        elif u <= s["R1"]:
            wt = lerp_table(s["roof_w"], u)
        elif u < s["C1"]:
            f = (u - s["R1"]) / (s["C1"] - s["R1"])
            wt = lerp_table(s["roof_w"], s["R1"]) + (bonnet - lerp_table(s["roof_w"], s["R1"])) * f
        else:
            wt = bonnet
        return min(wt, wb - 0.06)

    def ring_half(self, u: float) -> list:
        """(lateral, z) of s0, s1, s2, s3, s3b, s4, s5, s6 for one side (lateral >= 0)."""
        s = self.s
        zb = self.zbot(u)
        belt = lerp_table(s["belt"], u)
        top = lerp_table(s["top"], u)
        wb, wt = self.wbody(u), self.wtop(u)
        z1 = max(min(zb + s["k1"], belt - 0.16), zb + 0.03)
        z2 = max(belt - 0.14, z1 + 0.02)
        z3 = max(belt, z2 + 0.02)
        z3b = z3 + 0.025
        z4 = max(top - s["drop"], z3b + 0.005)
        z5 = max(top - 0.012, z4 + 0.003)
        z6 = max(top, z5 + 0.002)
        return [(wb - 0.05, zb), (wb - 0.012, z1), (wb, z2), (wb - 0.035, z3), (wb - 0.05, z3b),
                (wt, z4), (wt - 0.13, z5), (0.0, z6)]

    def surface_v(self, u: float, z: float) -> float:
        """Lateral position of the body surface at (u, z) (side or top), from the section."""
        h = self.ring_half(u)
        for (v0, z0), (v1, z1) in zip(h, h[1:]):
            if z0 <= z <= z1 and z1 > z0:
                return v0 + (v1 - v0) * (z - z0) / (z1 - z0)
        return h[0][0] if z < h[0][1] else 0.0

    def rake(self, front: bool, z: float) -> float:
        """How far the end face leans back above the bumper (bumper proud, lamps and grille set back)."""
        s = self.s
        amount, z0 = s.get("rake_f", (0.07, s["plate_f"][1] + 0.03)) if front else \
            s.get("rake_r", (0.035, (s["bumper_seam_r"] or 0.7) + 0.02))
        u = 0.0 if front else self.L
        z1 = lerp_table(s["top"], u)
        return amount * min(max((z - z0) / max(z1 - z0, 0.01), 0.0), 1.0)

    def end_u(self, front: bool, z: float) -> float:
        return self.rake(True, z) if front else self.L - self.rake(False, z)

    def P(self, u: float, v: float, z: float) -> tuple:
        return (-v, self.L / 2 - u, z)

    # --- faces ------------------------------------------------------------------------------------
    def face(self, mb: K.MB, pts: list, key: str, out: tuple, uvs: list | None = None) -> None:
        """pts in car coords (u, v, z); out = outward direction (u, v, z). key = 'glass',
        'paint_body' (gradient by height), an atlas region (uvs given) or a swatch."""
        a, b, c = pts[0], pts[1], pts[2]
        e1 = [b[i] - a[i] for i in range(3)]
        e2 = [c[i] - a[i] for i in range(3)]
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        # Car coords (u, v, z) map to Blender (-v, -u, z) + offset: a mirror, so the winding flips.
        flip = (n[0] * out[0] + n[1] * out[1] + n[2] * out[2]) > 0
        if uvs is None:
            if key == "glass":
                uvs = [(0.0, 0.0)] * len(pts)
            elif key == "paint_body":
                uvs = [A.uv_in("paint_body", p[0] / self.L, p[2] / self.s["H"]) for p in pts]
            else:
                uvs = [A.uv_swatch(key)] * len(pts)
        order = list(range(len(pts)))
        if flip:
            order.reverse()
        mb.face([self.P(*pts[i]) for i in order], [uvs[i] for i in order],
                "glass_vehicle" if key == "glass" else "vehicle")

    def quad(self, mb, p0, p1, p2, p3, key, out, region_uv: tuple | None = None) -> None:
        """Quad p0..p3; with region_uv=(name, fu0, fv0, fu1, fv1): p0 -> (fu0, fv0), p1 -> (fu1, fv0),
        p2 -> (fu1, fv1), p3 -> (fu0, fv1)."""
        uvs = None
        if region_uv:
            n, fu0, fv0, fu1, fv1 = region_uv
            uvs = [A.uv_in(n, fu0, fv0), A.uv_in(n, fu1, fv0), A.uv_in(n, fu1, fv1), A.uv_in(n, fu0, fv1)]
        self.face(mb, [p0, p1, p2, p3], key, out, uvs)

    def box(self, mb, u0, u1, v0, v1, z0, z1, key, faces: str = "fbltrd") -> None:
        """Axis-aligned box in car coords. faces: f(ront -u) b(ack +u) l(eft +v) r(ight -v) t(op) d(own)."""
        c = {(i, j, k): (u, v, z) for i, u in enumerate((u0, u1)) for j, v in enumerate((v0, v1))
             for k, z in enumerate((z0, z1))}
        sides = {"f": ([(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)], (-1, 0, 0)),
                 "b": ([(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (1, 0, 0)),
                 "l": ([(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)], (0, 1, 0)),
                 "r": ([(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], (0, -1, 0)),
                 "t": ([(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, 1)),
                 "d": ([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], (0, 0, -1))}
        for f in faces:
            idx, out = sides[f]
            self.face(mb, [c[i] for i in idx], key, out)

    # --- body -------------------------------------------------------------------------------------
    def stations(self) -> list:
        s, L = self.s, self.L
        us = {0.0, 0.04, 0.13, 0.32, L - 0.32, L - 0.13, L - 0.04, L, s["A0"], s["A1"], s["R1"], s["C1"]}
        for tab in ("top", "belt", "bot", "w", "roof_w"):
            us |= {p[0] for p in s[tab]}
        for a, b in s["windows"]:
            us |= {a, b}
        if s["bpillar"]:
            us |= set(s["bpillar"])
        for ua in self.ua:
            for deg in range(0, 181, 30):
                us.add(ua + self.ra * math.cos(math.radians(deg)) * (0.999 if deg in (0, 180) else 1.0))
            us |= {ua - self.ra - 0.002, ua + self.ra + 0.002}
        must = {0.0, L}
        for ua in self.ua:
            must |= {ua - self.ra * 0.999, ua + self.ra * 0.999, ua - self.ra - 0.002, ua + self.ra + 0.002}
        us = sorted(u for u in us if 0.0 <= u <= L)
        keep = [us[0]]
        for u in us[1:]:
            if u - keep[-1] < 0.015 and u not in must:
                continue
            keep.append(u)
        return keep

    def in_ranges(self, u: float, ranges) -> bool:
        return any(a <= u <= b for a, b in ranges)

    def seg_key(self, seg: int, u: float) -> str:
        s = self.s
        cabin = s["A0"] < u < s["C1"]
        win = self.in_ranges(u, s["windows"])
        bp = s["bpillar"] and s["bpillar"][0] <= u <= s["bpillar"][1]
        if seg == 0:
            return "cladding" if (s.get("cladding") or s.get("van")) else "paint_low"
        if seg in (1, 2):
            return "paint_body"
        if seg == 3:
            if win:
                return s["belt_trim"]
            return "trim_gloss" if bp else "paint_body"
        if seg == 4:
            if win:
                return "glass"
            return "trim_gloss" if bp else "paint_body"
        if seg == 5:
            return "paint_body"
        if seg == 6:
            if s["A0"] < u < s["A1"] or (s["R1"] < u < s["C1"]):
                return "glass"
            return "paint_body"
        return "underbody"

    def build_body(self) -> None:
        mb = self.lod0
        st = self.stations()
        rings = []
        for u in st:
            h = self.ring_half(u)
            right = [(u, -v, z) for v, z in h[:-1]]
            left = [(u, v, z) for v, z in h[:-1]][::-1]
            ring = right + [(u, 0.0, h[-1][1])] + left
            if u < 0.05 or u > self.L - 0.05:                # end faces lean back above the bumper
                front = u < 0.05
                ring = [(p[0] + (self.end_u(front, p[2]) - (0.0 if front else self.L)), p[1], p[2]) for p in ring]
            rings.append(ring)
        n = len(rings[0])                                    # 15 points
        seg_of = [0, 1, 2, 3, 4, 5, 6, 6, 5, 4, 3, 2, 1, 0]
        for i in range(len(st) - 1):
            ra, rb = rings[i], rings[i + 1]
            um = (st[i] + st[i + 1]) / 2
            zc = (self.zbot(um) + lerp_table(self.s["top"], um)) / 2
            for k in range(n - 1):
                key = self.seg_key(seg_of[k], um)
                pts = [ra[k], rb[k], rb[k + 1], ra[k + 1]]
                cv = sum(p[1] for p in pts) / 4
                cz = sum(p[2] for p in pts) / 4
                if math.dist(pts[0], pts[1]) < 1e-6 and math.dist(pts[2], pts[3]) < 1e-6:
                    continue
                self.face(mb, pts, key, (0.0, cv, cz - zc))
            # Underside: wheel wells (liner) or floor pan.
            arch = any(abs(um - ua) < self.ra + 0.003 for ua in self.ua)
            self.face(mb, [ra[0], rb[0], rb[n - 1], ra[n - 1]], "liner" if arch else "underbody", (0, 0, -1))
        # End caps in horizontal strips (right and left ring points share their height), so the face
        # follows the rake exactly and the lamp / grille decals sit on it.
        for ring, out in ((rings[0], (-1, 0, 0)), (rings[-1], (1, 0, 0))):
            for k in range(n // 2 - 1):
                self.face(mb, [ring[k], ring[k + 1], ring[n - 2 - k], ring[n - 1 - k]], "paint_body", out)
            self.face(mb, [ring[n // 2 - 1], ring[n // 2], ring[n // 2 + 1]], "paint_body", out)

    def build_wheels(self) -> None:
        mb, s = self.lod0, self.s
        r, tw = s["r"], s["tw"]
        nseg = 14
        rv = r / math.cos(math.pi / nseg)                   # flat contact patch exactly at z = 0
        for ua in self.ua:
            wb = self.wbody(ua)
            for side in (1, -1):
                v_out = side * (wb - 0.03)
                v_ch = side * (wb - 0.045)
                v_in = side * (wb - 0.03 - tw)
                ang = [-math.pi / 2 + math.pi / nseg + 2 * math.pi * i / nseg for i in range(nseg)]
                ring = [(ua + rv * math.cos(a), r + rv * math.sin(a)) for a in ang]
                face_r = [(ua + rv * 0.94 * math.cos(a), r + rv * 0.94 * math.sin(a)) for a in ang]
                for i in range(nseg):
                    j = (i + 1) % nseg
                    (ua0, za0), (ub0, zb0) = ring[i], ring[j]
                    mu, mz = (ua0 + ub0) / 2 - ua, (za0 + zb0) / 2 - r
                    self.face(mb, [(ua0, v_in, za0), (ub0, v_in, zb0), (ub0, v_ch, zb0), (ua0, v_ch, za0)],
                              "rubber", (mu, 0, mz))
                    (fa, ga), (fb, gb) = face_r[i], face_r[j]
                    self.face(mb, [(ua0, v_ch, za0), (ub0, v_ch, zb0), (fb, v_out, gb), (fa, v_out, ga)],
                              "rubber", (mu, side * 0.7, mz))
                img = s["wheel"]
                pts = [(fu, v_out, fz) for fu, fz in face_r]
                uvs = [A.uv_in(img, 0.5 + 0.5 * (fu - ua) / (rv * 0.94) * (1 if side > 0 else -1),
                               0.5 + 0.5 * (fz - r) / (rv * 0.94), inset=0.5) for fu, fz in face_r]
                self.face(mb, pts, img, (0, side, 0), uvs)
                self.face(mb, [(fu, v_in, fz) for fu, fz in ring], "liner", (0, -side, 0))
                # Arch liner panel inboard of the wheel, so the well is closed.
                vl = side * (wb - 0.03 - tw - 0.03)
                arc = [(ua + self.ra * math.cos(math.radians(d)), r + self.ra * math.sin(math.radians(d)))
                       for d in range(0, 181, 30)]
                arc = [(au, min(az, self.zbot(au) + 0.002)) for au, az in arc]
                self.face(mb, [(au, vl, az) for au, az in arc], "liner", (0, side, 0))

    # --- details --------------------------------------------------------------------------------
    def side_quad(self, mb, side: int, u0: float, u1: float, z0: float, z1: float, key: str,
                  region: tuple | None = None, off: float = OFF) -> None:
        """Decal on the body side between u0..u1, z0..z1, following the section."""
        pts = []
        for u, z in ((u0, z0), (u1, z0), (u1, z1), (u0, z1)):
            pts.append((u, side * (self.surface_v(u, z) + off), z))
        fu0, fu1 = (0, 1) if side > 0 else (1, 0)
        reg = (region, fu0, 0, fu1, 1) if region else None
        if reg and side < 0:
            reg = (region, 0, 0, 1, 1)
            pts = [pts[1], pts[0], pts[3], pts[2]]
        self.quad(mb, *pts, key, (0, side, 0), reg)

    def seam_vertical(self, mb, u: float, side: int, z_from: float | None = None) -> None:
        h = self.ring_half(u)
        pts = [h[1], h[2], h[3]]
        if z_from is not None:
            pts = [(self.surface_v(u, z_from), z_from)] + [p for p in pts if p[1] > z_from + 0.02]
        hw = 0.005
        for (va, za), (vb, zb) in zip(pts, pts[1:]):
            self.quad(mb, (u - hw, side * (va + 0.003), za), (u + hw, side * (va + 0.003), za),
                      (u + hw, side * (vb + 0.003), zb), (u - hw, side * (vb + 0.003), zb), "paint_seam",
                      (0, side, 0))

    def seam_across(self, mb, u: float, k0: int = 5) -> None:
        """Shut line across the top (bonnet / boot) at u, from s(k0) over the crown."""
        h = self.ring_half(u)
        pts = [(-v, z) for v, z in h[k0:]] + [(v, z) for v, z in h[k0:-1]][::-1]
        hw = 0.005
        for (va, za), (vb, zb) in zip(pts, pts[1:]):
            self.quad(mb, (u - hw, va, za + 0.003), (u - hw, vb, zb + 0.003), (u + hw, vb, zb + 0.003),
                      (u + hw, va, za + 0.003), "paint_seam", (0, 0, 1))

    def seam_along(self, mb, u0: float, u1: float, k: int) -> None:
        """Shut line along ring point k (both sides) from u0 to u1."""
        us = [u for u in self.stations() if u0 < u < u1]
        us = [u0] + us + [u1]
        hw = 0.005
        for side in (1, -1):
            for ua, ub in zip(us, us[1:]):
                pa, pb = self.ring_half(ua)[k], self.ring_half(ub)[k]
                self.quad(mb, (ua, side * (pa[0] + 0.002), pa[1] + 0.003 - hw),
                          (ub, side * (pb[0] + 0.002), pb[1] + 0.003 - hw),
                          (ub, side * (pb[0] + 0.002), pb[1] + 0.003 + hw),
                          (ua, side * (pa[0] + 0.002), pa[1] + 0.003 + hw), "paint_seam", (0, side, 1))

    def cap_quad(self, mb, front: bool, v0: float, v1: float, z0: float, z1: float, key: str,
                 region: tuple | None = None, off: float = OFF) -> None:
        """Decal on the front (u = 0) or rear (u = L) face, v0 < v1."""
        d = -off if front else off
        ua, ub = self.end_u(front, z0) + d, self.end_u(front, z1) + d
        out = (-1, 0, 0) if front else (1, 0, 0)
        reg = (region, 0, 0, 1, 1) if region else None
        if reg and not front:
            reg = (region, 1, 0, 0, 1)                       # seen from behind, +v is on the left
        self.quad(mb, (ua, v0, z0), (ua, v1, z0), (ub, v1, z1), (ub, v0, z1), key, out, reg)

    def lamp(self, mb, front: bool, region: str, z0: float, z1: float, v_in: float, wrap_u: float = 0.15) -> None:
        """Lamp decal on a front/rear corner: 80 % on the end face, 20 % wrapped round the corner."""
        L = self.L
        u_face = 0.0 if front else L
        u_wrap = wrap_u if front else L - wrap_u
        d = -OFF if front else OFF
        for side in (1, -1):
            ve0 = self.surface_v(u_face, z0) - 0.005
            ve1 = self.surface_v(u_face, z1) - 0.005
            vw0 = self.surface_v(u_wrap, z0) + OFF
            vw1 = self.surface_v(u_wrap, z1) + OFF
            out = (-1 if front else 1, 0, 0)
            u0, u1 = self.end_u(front, z0) + d, self.end_u(front, z1) + d
            p = [(u0, side * v_in, z0), (u0, side * ve0, z0), (u1, side * ve1, z1), (u1, side * v_in, z1)]
            self.quad(mb, *p, region, out, (region, 0, 0, 0.8, 1))
            # Round the corner through the second station (u = 0.04 / L - 0.04), which is raked too.
            um = 0.04 if front else L - 0.04
            dm = -OFF * 0.7 if front else OFF * 0.7
            m0 = (self.end_u(front, z0) + (um - u_face) + dm, side * (self.surface_v(um, z0) + OFF * 0.7), z0)
            m1 = (self.end_u(front, z1) + (um - u_face) + dm, side * (self.surface_v(um, z1) + OFF * 0.7), z1)
            o = (-0.7 if front else 0.7, side * 0.7, 0)
            self.quad(mb, (u0, side * ve0, z0), m0, m1, (u1, side * ve1, z1), region, o, (region, 0.8, 0, 0.88, 1))
            self.quad(mb, m0, (u_wrap, side * vw0, z0), (u_wrap, side * vw1, z1), m1, region, o,
                      (region, 0.88, 0, 1, 1))

    def top_z(self, u: float) -> float:
        return self.ring_half(u)[-1][1]

    def build_details(self) -> None:
        mb, s, L = self.lod0, self.s, self.L
        van = s.get("van", False)
        # Lamps, grille, plates, intakes.
        hr, hz0, hz1, hv = s["head"]
        self.lamp(mb, True, hr, hz0, hz1, hv)
        g, gv, gz0, gz1 = s["grille"]
        self.cap_quad(mb, True, -gv, gv, gz0, gz1, g, g)
        if s["intake"]:
            iv, iz0, iz1 = s["intake"]
            self.cap_quad(mb, True, -iv, iv, iz0, iz1, "intake_mesh", "intake_mesh")
        pz0, pz1 = s["plate_f"]
        plate = f"plate_{s['plate']}"
        self.cap_quad(mb, True, -0.26, 0.26, pz0, pz1, plate, plate, off=0.036 if van else OFF * 2)
        if s["fog"]:
            fv, fz0, fz1 = s["fog"]
            for side in (1, -1):
                self.cap_quad(mb, True, side * fv - 0.045, side * fv + 0.045, fz0, fz1, "fog_round", "fog_round")
        if s["tail"]:
            tr, tz0, tz1, tv = s["tail"]
            self.lamp(mb, False, tr, tz0, tz1, tv)
        rz0, rz1 = s["plate_r"]
        self.cap_quad(mb, False, -0.26, 0.26, rz0, rz1, plate, plate, off=OFF * 2)
        if van:
            self.cap_quad(mb, False, -0.30, 0.30, rz0 - 0.02, rz1 + 0.02, "plate_back")
        if s["reflector"]:
            rv, rz = s["reflector"]
            for side in (1, -1):
                self.cap_quad(mb, False, side * rv - 0.07, side * rv + 0.07, rz, rz + 0.035,
                              "rear_reflector", "rear_reflector", off=OFF * 2)
        if s["bumper_seam_r"]:
            z = s["bumper_seam_r"]
            vmax = self.surface_v(L, z) - 0.01
            self.cap_quad(mb, False, -vmax, vmax, z - 0.005, z + 0.005, "paint_seam")
        # Third brake light at the roof end (top of the rear window / rear doors).
        if van:
            zt = self.top_z(L)
            self.cap_quad(mb, False, -0.18, 0.18, zt - 0.07, zt - 0.035, "red_light")
        else:
            u = s["R1"]
            zt = self.top_z(u)
            if s["spoiler"]:
                wt = self.wtop(u) - 0.05
                self.quad(mb, (u, -wt, zt - 0.005), (u + 0.09, -wt, zt - 0.03), (u + 0.09, wt, zt - 0.03),
                          (u, wt, zt - 0.005), "paint", (0.2, 0, 1))
                self.quad(mb, (u + 0.09, -wt, zt - 0.03), (u + 0.09, -wt, zt - 0.07), (u + 0.09, wt, zt - 0.07),
                          (u + 0.09, wt, zt - 0.03), "paint", (1, 0, 0))
                self.quad(mb, (u + 0.092, -0.20, zt - 0.06), (u + 0.092, 0.20, zt - 0.06),
                          (u + 0.092, 0.20, zt - 0.04), (u + 0.092, -0.20, zt - 0.04), "red_light", (1, 0, 0))
                self.quad(mb, (u, -wt, zt - 0.07), (u + 0.09, -wt, zt - 0.07), (u + 0.09, wt, zt - 0.07),
                          (u, wt, zt - 0.07), "trim_black", (0, 0, -1))
            else:
                du = (s["C1"] - s["R1"]) * 0.06
                z0 = self.top_z(u + du)
                self.quad(mb, (u + 0.01, -0.22, zt - 0.03), (u + 0.01, 0.22, zt - 0.03),
                          (u + du, 0.22, z0 - 0.02), (u + du, -0.22, z0 - 0.02), "red_light", (0.6, 0, 1))
        # Exhaust (left rear, under the bumper).
        ev, ez, er = s["exhaust"]
        n = 6
        for i in range(n):
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            p = [(L - 0.6, ev + er * math.cos(a0), ez + er * math.sin(a0)),
                 (L + 0.01, ev + er * math.cos(a0), ez + er * math.sin(a0)),
                 (L + 0.01, ev + er * math.cos(a1), ez + er * math.sin(a1)),
                 (L - 0.6, ev + er * math.cos(a1), ez + er * math.sin(a1))]
            am = (a0 + a1) / 2
            self.face(mb, p, "exhaust", (0, math.cos(am), math.sin(am)))
        self.face(mb, [(L + 0.005, ev + er * 0.85 * math.cos(2 * math.pi * i / n),
                        ez + er * 0.85 * math.sin(2 * math.pi * i / n)) for i in range(n)], "exhaust_in", (1, 0, 0))
        # Shut lines.
        for u in s["seams"]:
            for side in (1, -1):
                self.seam_vertical(mb, u, side)
        for u in s.get("seams_r", []):
            self.seam_vertical(mb, u, -1)
        self.seam_across(mb, s["A0"] - 0.05)                                   # bonnet rear edge
        self.seam_along(mb, 0.14, s["A0"] - 0.05, 4)                           # bonnet sides
        if s.get("boot"):
            self.seam_across(mb, s["C1"] + 0.03)
            self.seam_along(mb, s["C1"] + 0.03, L - 0.06, 4)
        if not van:
            zt = s["tail"][2] if s["tail"] else 1.0
            for side in (1, -1):                                               # tailgate / boot lid cut
                vv = s["tail"][3] - 0.012
                self.cap_quad(mb, False, side * vv - 0.005, side * vv + 0.005, s["bumper_seam_r"],
                              self.top_z(L) - 0.01, "paint_seam")
        else:
            zt = self.top_z(L)
            self.cap_quad(mb, False, -0.005, 0.005, s["plate_r"][1] + 0.04, zt - 0.03, "paint_seam")  # twin doors
            for side in (1, -1):
                vv = s["tail"][3] - 0.015
                self.cap_quad(mb, False, side * vv - 0.005, side * vv + 0.005, 0.63, zt - 0.03, "paint_seam")
            self.cap_quad(mb, False, -0.15, -0.05, 1.02, 1.05, "trim_black")              # rear door handle
        # Door handles, fuel flap.
        for u in s["handles"]:
            zb = lerp_table(s["belt"], u) - 0.10
            for side in (1, -1):
                self.side_quad(mb, side, u - 0.08, u + 0.08, zb - 0.025, zb + 0.025, "handle", "handle")
        if van:
            zb = lerp_table(s["belt"], 2.1) - 0.12
            self.side_quad(mb, -1, 2.04, 2.08, zb - 0.09, zb + 0.09, "trim_black")         # sliding door grip
        if s["fuel"]:
            f0, f1 = s["fuel"]
            zc = lerp_table(s["belt"], (f0 + f1) / 2) - 0.17
            h = (f1 - f0) / 2
            self.side_quad(mb, -1, f0, f1, zc - h, zc + h, "fuel_flap", "fuel_flap")
        # Mirrors.
        self.mirrors()
        # Wipers.
        self.wipers()
        # Antenna (shark fin) near the roof end.
        if not van:
            u = s["R1"] - 0.22
            z = self.top_z(u)
            self.face(mb, [(u, -0.025, z), (u + 0.17, -0.025, z), (u + 0.13, -0.008, z + 0.065)], "trim_gloss",
                      (0, -1, 0.2))
            self.face(mb, [(u, 0.025, z), (u + 0.17, 0.025, z), (u + 0.13, 0.008, z + 0.065)], "trim_gloss",
                      (0, 1, 0.2))
            self.face(mb, [(u + 0.17, -0.025, z), (u + 0.17, 0.025, z), (u + 0.13, 0.008, z + 0.065),
                           (u + 0.13, -0.008, z + 0.065)], "trim_gloss", (1, 0, 0.3))
        if s["rails"]:
            self.roof_rails()
        if s.get("taxi"):
            self.taxi_sign()
            for side in (1, -1):
                zc = lerp_table(s["belt"], 3.3) - 0.30
                self.side_quad(mb, side, 3.26, 3.36, zc - 0.05, zc + 0.05, "door_number", "door_number")
        if s.get("cladding"):
            self.suv_extras()
        if van:
            self.van_extras()
        self.interior()

    def mirrors(self) -> None:
        mb, s = self.lod0, self.s
        u0 = s["mirror_u"]
        u1 = u0 + 0.11
        belt = lerp_table(s["belt"], u0)
        z0, z1 = belt + 0.04, belt + 0.17
        for side in (1, -1):
            vb = self.surface_v(u0 + 0.05, belt + 0.03)
            vo = vb + 0.21
            vi = vb + 0.04
            sd = side
            # Arm / base (black plastic) on the door.
            self.box(mb, u0 + 0.03, u0 + 0.09, *sorted((sd * (vb - 0.01), sd * vi)), belt + 0.01, z0 + 0.03, "trim_black",
                     "fbt" + ("l" if side > 0 else "r"))
            # Housing: front rounded by a slanted face, glass at the back.
            P = lambda u, v, z: (u, sd * v, z)  # noqa: E731
            fr = [P(u0, vi, z0 + 0.02), P(u0, vo - 0.03, z0 + 0.03), P(u0, vo - 0.03, z1 - 0.02), P(u0, vi, z1)]
            bk = [P(u1, vi, z0), P(u1, vo, z0), P(u1, vo, z1), P(u1, vi, z1)]
            self.face(mb, fr, "paint", (-1, 0, 0))
            self.face(mb, [fr[1], bk[1], bk[2], fr[2]], "paint", (0, sd, 0))
            self.face(mb, [fr[3], fr[2], bk[2], bk[3]], "paint", (0, 0, 1))
            self.face(mb, [fr[0], fr[1], bk[1], bk[0]], "trim_black", (0, 0, -1))
            self.face(mb, [fr[0], fr[3], bk[3], bk[0]], "paint", (0, -sd, 0))
            g = [P(u1 + 0.002, vi + 0.015, z0 + 0.015), P(u1 + 0.002, vo - 0.015, z0 + 0.015),
                 P(u1 + 0.002, vo - 0.015, z1 - 0.015), P(u1 + 0.002, vi + 0.015, z1 - 0.015)]
            self.face(mb, g, "mirror_glass", (1, 0, 0))
            self.face(mb, [P(u0 + 0.02, vo - 0.025, z0 + 0.03), P(u0 + 0.06, vo + 0.004, z0 + 0.03),
                           P(u0 + 0.06, vo + 0.004, z0 + 0.06), P(u0 + 0.02, vo - 0.025, z0 + 0.06)], "amber",
                      (-0.3, sd, 0))
            self.face(mb, [fr[1], P(u0 + 0.06, vo + 0.004, z0 + 0.03), P(u0 + 0.06, vo + 0.004, z1 - 0.02), fr[2]],
                      "paint", (-0.5, sd, 0))

    def ws_point(self, u: float, v: float, lift: float = 0.012) -> tuple:
        """Point on the windscreen / rear window surface (between ring points s5 and s6)."""
        h = self.ring_half(u)
        (v5, z5), (_, z6) = h[6], h[7]
        f = min(abs(v) / v5, 1.0)
        return (u, v, z6 + (z5 - z6) * f + lift)

    def wipers(self) -> None:
        mb, s = self.lod0, self.s
        u = s["A0"] + 0.06
        for va, vb in ((-0.62, 0.02), (0.06, 0.60)):
            pa, pb = self.ws_point(u, va), self.ws_point(u + 0.03, vb)
            self.quad(mb, pa, pb, (pb[0] - 0.025, pb[1], pb[2] - 0.012), (pa[0] - 0.025, pa[1], pa[2] - 0.012),
                      "trim_black", (-0.5, 0, 1))
        if s["rear_wiper"]:
            u0 = s["C1"] - (s["C1"] - s["R1"]) * 0.12
            u1 = s["C1"] - (s["C1"] - s["R1"]) * 0.75
            pa, pb = self.ws_point(u0, 0.0), self.ws_point(u1, 0.38)
            self.quad(mb, pa, pb, (pb[0], pb[1] - 0.02, pb[2]), (pa[0], pa[1] - 0.02, pa[2]), "trim_black", (1, 0, 1))

    def roof_rails(self) -> None:
        mb, s = self.lod0, self.s
        us = [s["A1"] + 0.18 + (s["R1"] - 0.12 - s["A1"] - 0.18) * i / 3 for i in range(4)]
        for side in (1, -1):
            for ua, ub in zip(us, us[1:]):
                va = self.wtop(ua) - 0.07
                vb = self.wtop(ub) - 0.07
                za, zb = self.top_z(ua) - 0.03 + 0.06, self.top_z(ub) - 0.03 + 0.06
                for dv, out in ((0.015, 1), (-0.015, -1)):
                    self.quad(mb, (ua, side * (va + dv), za - 0.035), (ub, side * (vb + dv), zb - 0.035),
                              (ub, side * (vb + dv), zb), (ua, side * (va + dv), za), "chrome", (0, side * out, 0))
                self.quad(mb, (ua, side * (va - 0.015), za), (ub, side * (vb - 0.015), zb),
                          (ub, side * (vb + 0.015), zb), (ua, side * (va + 0.015), za), "chrome", (0, 0, 1))
            for u in (us[0], us[-1]):                                         # feet
                v = self.wtop(u) - 0.07
                z = self.top_z(u) - 0.03
                self.box(mb, u - 0.04, u + 0.04, *sorted((side * (v - 0.02), side * (v + 0.02))), z, z + 0.03,
                         "trim_black", "fblrt")

    def taxi_sign(self) -> None:
        mb, s = self.lod0, self.s
        u = s["A1"] + 0.42
        z = self.top_z(u)
        self.box(mb, u - 0.05, u + 0.05, -0.20, 0.20, z - 0.01, z + 0.02, "trim_black", "fblr")
        u0, u1, z0, z1 = u - 0.08, u + 0.08, z + 0.02, z + 0.155
        self.box(mb, u0, u1, -0.28, 0.28, z0, z1, "taxi_yellow", "lrt")
        self.quad(mb, (u0 - 0.002, -0.28, z0), (u0 - 0.002, 0.28, z0), (u0 - 0.002, 0.28, z1),
                  (u0 - 0.002, -0.28, z1), "taxi_sign", (-1, 0, 0), ("taxi_sign", 0, 0, 1, 1))
        self.quad(mb, (u1 + 0.002, 0.28, z0), (u1 + 0.002, -0.28, z0), (u1 + 0.002, -0.28, z1),
                  (u1 + 0.002, 0.28, z1), "taxi_sign", (1, 0, 0), ("taxi_sign", 0, 0, 1, 1))

    def suv_extras(self) -> None:
        mb, s, L = self.lod0, self.s, self.L
        # Lower front: skid plate (brushed metal look) and dark bumper base; rear: dark diffuser.
        v = self.surface_v(0, 0.47) - 0.03
        self.cap_quad(mb, True, -v, v, 0.43, 0.50, "cladding")
        self.cap_quad(mb, True, -0.36, 0.36, 0.435, 0.465, "exhaust", off=OFF * 2)
        v = self.surface_v(L, 0.55) - 0.03
        self.cap_quad(mb, False, -v, v, 0.47, 0.62, "cladding")
        tr, tz0, tz1, tv = s["tail"]
        self.cap_quad(mb, False, -tv, tv, tz0 + 0.035, tz0 + 0.06, "tail_bar", "tail_bar")

    def van_extras(self) -> None:
        mb, s, L = self.lod0, self.s, self.L
        # Dark bumpers proud of the body, wrapped round the corners.
        for front in (True, False):
            z0, z1 = (0.36, 0.64) if front else (0.40, 0.62)
            ue = -0.03 if front else L + 0.03
            uc = 0.28 if front else L - 0.28
            ve = self.surface_v(0.0 if front else L, z1) + 0.0
            vc = self.wbody(uc) + 0.015
            out_u = -1 if front else 1
            for side in (1, -1):
                pts = [(ue, side * 0.0, z0), (ue, side * ve, z0), (ue, side * ve, z1), (ue, side * 0.0, z1)]
                self.face(mb, pts, "cladding", (out_u, 0, 0))
                self.face(mb, [(ue, side * ve, z0), (uc, side * vc, z0), (uc, side * vc, z1), (ue, side * ve, z1)],
                          "cladding", (out_u * 0.6, side, 0))
                self.face(mb, [(ue, 0, z1), (ue, side * ve, z1), (uc, side * vc, z1),
                               (uc, side * (vc - 0.3), z1), (0.0 if front else L, 0, z1)][::1],
                          "step_metal" if not front else "cladding", (0, 0, 1))
        # Sliding door rail (right side) and side step, roof vent.
        z = lerp_table(s["belt"], 3.5)
        self.side_quad(mb, -1, 3.10, 4.62, z - 0.03, z + 0.01, "trim_black")
        self.box(mb, 2.02, 3.06, -(self.wbody(2.5) + 0.03), -(self.wbody(2.5) - 0.10), 0.26, 0.31, "trim_black", "fbrt")
        zt = self.top_z(3.9)
        self.box(mb, 3.70, 4.10, -0.22, 0.22, zt - 0.01, zt + 0.045, "trim_black", "fblrt")
        # Side marker lights (amber) on the long body, as on real vans over 6 m: skip, this one is 5 m.

    def interior(self) -> None:
        """Dark cabin silhouettes behind the glass: floor, door cards, headliner, dash, seats."""
        mb, s = self.lod0, self.s
        fl = s["floor"]
        u0 = s["A0"]
        u_end = s["R1"] if not s.get("van") else s["seats"][0] + 0.14
        if s.get("van"):
            u_end = s["windows"][0][1] + 0.10
        wi = self.wbody((u0 + u_end) / 2) - 0.11
        # Floor and door cards.
        self.quad(mb, (u0 + 0.3, -wi, fl), (u_end, -wi, fl), (u_end, wi, fl), (u0 + 0.3, wi, fl), "interior", (0, 0, 1))
        for side in (1, -1):
            bz = [lerp_table(s["belt"], u) - 0.02 for u in (u0 + 0.2, u_end)]
            self.quad(mb, (u0 + 0.2, side * wi, fl), (u_end, side * wi, fl), (u_end, side * wi, bz[1]),
                      (u0 + 0.2, side * wi, bz[0]), "interior", (0, -side, 0))
        # Headliner under the roof.
        ua, ub = s["A1"] - 0.05, min(s["R1"], u_end)
        za, zb = self.top_z(ua) - 0.05, self.top_z(ub) - 0.05
        wr = self.wtop((ua + ub) / 2) - 0.04
        self.quad(mb, (ua, -wr, za), (ub, -wr, zb), (ub, wr, zb), (ua, wr, za), "headliner", (0, 0, -1))
        # Dashboard.
        belt = lerp_table(s["belt"], u0 + 0.3)
        self.box(mb, u0 - 0.02, u0 + 0.42, -wi, wi, belt - 0.22, belt + 0.03, "dash", "bt")
        self.box(mb, u0 + 0.42, u0 + 0.50, 0.22, 0.48, belt - 0.12, belt + 0.10, "dash", "fbt")  # steering wheel rim
        # Seats.
        fb, rb = s["seats"]
        for vc in (0.37, -0.37):
            self.seat(fb, vc, 0.50, fl)
        if rb:
            self.seat(rb, 0.0, 2 * wi - 0.08, fl, heads=(-0.40, 0.40))
        if s.get("van"):                                                      # bulkhead behind the cab
            zt = self.top_z(u_end) - 0.04
            self.quad(mb, (u_end, wi, fl), (u_end, -wi, fl), (u_end, -wi, zt), (u_end, wi, zt), "interior",
                      (-1, 0, 0))
        if s.get("cargo"):
            c0, c1 = s["cargo"]
            z = lerp_table(s["belt"], c0) + 0.01
            self.quad(mb, (c0, -wi, z), (c1, -wi, z), (c1, wi, z), (c0, wi, z), "interior", (0, 0, 1))
        if s.get("shelf"):
            c0, c1 = s["shelf"]
            z = lerp_table(s["belt"], c0) + 0.01
            self.quad(mb, (c0, -wi, z), (c1, -wi, z), (c1, wi, z), (c0, wi, z), "dash", (0, 0, 1))

    def seat(self, u_back: float, vc: float, width: float, fl: float, heads: tuple = (0.0,)) -> None:
        mb = self.lod0
        w = width / 2
        self.box(mb, u_back - 0.48, u_back - 0.05, vc - w, vc + w, fl, fl + 0.24, "seat", "ft")
        # Backrest leaning back ~20°.
        b0, b1, zb0, zb1 = u_back - 0.08, u_back + 0.04, fl + 0.20, fl + 0.80
        lean = 0.20
        p = lambda u, v, z: (u + (z - zb0) / (zb1 - zb0) * lean, v, z)  # noqa: E731
        for (ua, ub), out in (((b0, b0), -1), ((b1, b1), 1)):
            self.face(mb, [p(ua, vc - w, zb0), p(ua, vc + w, zb0), p(ua, vc + w, zb1), p(ua, vc - w, zb1)],
                      "seat", (out, 0, 0.2))
        self.face(mb, [p(b0, vc - w, zb1), p(b1, vc - w, zb1), p(b1, vc + w, zb1), p(b0, vc + w, zb1)], "seat", (0, 0, 1))
        for sv in (-1, 1):
            vv = vc + sv * w
            self.face(mb, [p(b0, vv, zb0), p(b1, vv, zb0), p(b1, vv, zb1), p(b0, vv, zb1)], "seat", (0, sv, 0))
        for hv in heads:
            hc = vc + hv
            hu = u_back + lean + 0.0
            self.box(mb, hu - 0.06, hu + 0.04, hc - 0.13, hc + 0.13, zb1 + 0.05, zb1 + 0.24, "seat", "fblrt")
            self.box(mb, hu - 0.02, hu, hc - 0.06, hc + 0.06, zb1, zb1 + 0.05, "chrome", "fb")

    # --- far version (build view) -----------------------------------------------------------------
    def build_far(self) -> None:
        mb, s, L = self.far, self.s, self.L
        st = sorted({0.0, 0.15, s["A0"], s["A1"], s["R1"], s["C1"], L - 0.15, L})
        st = [u for i, u in enumerate(st) if i == 0 or u - st[i - 1] > 0.02]

        def ring(u):
            zb = lerp_table(s["bot"], u) + 0.08
            belt, top = lerp_table(s["belt"], u), lerp_table(s["top"], u)
            wb, wt = self.wbody(u), self.wtop(u)
            half = [(wb, zb), (wb, belt), (wt, max(top - s["drop"], belt + 0.02))]
            return [(u, -v, z) for v, z in half] + [(u, 0.0, top)] + [(u, v, z) for v, z in half][::-1]

        rings = [ring(u) for u in st]
        n = len(rings[0])
        segs = ["side", "upper", "top", "top", "upper", "side"]
        for i in range(len(st) - 1):
            um = (st[i] + st[i + 1]) / 2
            glass_top = s["A0"] < um < s["A1"] or s["R1"] < um < s["C1"]
            cabin = s["A0"] < um < s["C1"] and self.in_ranges(um, s["windows"] + ([s["bpillar"]] if s["bpillar"] else []))
            cabin = cabin or (s.get("van") is None and s["A1"] < um < s["R1"])
            for k in range(n - 1):
                pts = [rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k + 1]]
                kind = segs[k]
                key = "paint_body"
                if kind == "top" and glass_top:
                    key = "glass_far"
                elif kind == "upper" and (glass_top or cabin):
                    key = "glass_far"
                cv = sum(p[1] for p in pts) / 4
                cz = sum(p[2] for p in pts) / 4
                self.face(mb, pts, key, (0, cv, cz - 0.6))
        for rg, out in ((rings[0], (-1, 0, 0)), (rings[-1], (1, 0, 0))):
            for k in range(1, n - 1):
                self.face(mb, [rg[0], rg[k], rg[k + 1]], "paint_body", out)
        r = s["r"]
        for ua in self.ua:
            for side in (1, -1):
                v = side * (self.wbody(ua) - 0.03)
                pts = [(ua + r * math.cos(a), v, r + r * math.sin(a))
                       for a in [math.radians(-90 + 60 * i) for i in range(6)]]
                self.face(mb, pts, "rubber", (0, side, 0))
        if s.get("taxi"):
            u = s["A1"] + 0.42
            z = lerp_table(s["top"], u) + 0.15
            self.quad(mb, (u - 0.08, -0.28, z), (u + 0.08, -0.28, z), (u + 0.08, 0.28, z), (u - 0.08, 0.28, z),
                      "taxi_yellow", (0, 0, 1))

    def build(self) -> "Car":
        self.build_body()
        self.build_wheels()
        self.build_details()
        self.build_far()
        return self


TYPES = list(SPECS)

# Paint colours for the tintable types (sRGB albedo hex, metallic flake 0..1, weight in %).
# Weights: rough share in the European car fleet (KBA registrations: grey/black/white lead, then
# silver and blue; bright colours are rare). Black and white are kept off pure 0 / 1 (art_direction §3).
PAINTS = [
    ("white", "#D8DAD8", 0.0, 19),
    ("silver", "#A3A7AB", 1.0, 14),
    ("black", "#232426", 0.4, 20),
    ("anthracite", "#3D4145", 0.8, 21),
    ("dark_blue", "#1F2D47", 0.6, 9),
    ("blue_grey", "#5C6A77", 0.6, 6),
    ("dark_red", "#561618", 0.4, 5),
    ("dark_green", "#2A3C33", 0.5, 3),
    ("beige", "#BBAE93", 0.3, 3),
]
FIXED_PAINT = {"car_taxi": ("ivory_ral1015", "#E6D2B5", 0.0), "van": ("van_white", "#D8DAD8", 0.0)}
