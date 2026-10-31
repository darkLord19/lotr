"""Modular clothing pieces. Each is a shell that samples the body profile (grown outward) and reuses the body's
skinning functions, so clothes follow the body exactly. Piece ids are used in looks.json `pieces`."""
from __future__ import annotations

import math
import random
from collections.abc import Callable

from mathutils import Vector

from .rig import Dims, Skin, Weights, chain, ring_x, ring_xz, ring_yz, sm

DOUBLE_SIDED = {"cloak", "robe", "robe2", "apron", "hood", "dress"}


def w_robe(d: Dims) -> Callable[[Vector], Weights]:
    """Skirt/robe skinning: torso weights above the hip, blending into the legs below it, left/right by x."""
    def f(p: Vector) -> Weights:
        if p.z >= d.hip_z:
            return d.w_torso(p)
        b = min(0.75, 0.95 * (d.hip_z - p.z) / max(d.hip_z - d.ankle_z, 0.01))
        a = sm(0.5 + p.x / (2.0 * d.hip_hw * 0.9))
        out: Weights = {"Hips": 1.0 - b}
        for side, wt in (("R", a), ("L", 1.0 - a)):
            lw = chain(-p.z, [-(d.hip_z + 0.01), -d.knee_z, -(d.ankle_z + 0.02)],
                       ["Hips", f"UpperLeg_{side}", f"LowerLeg_{side}", f"Foot_{side}"], 0.04 * d.hip_z)
            for k, v in lw.items():
                out[k] = out.get(k, 0.0) + b * wt * v
        return out
    return f


def torso_shell(s: Skin, d: Dims, z0: float, z1: float, grow: float, mat: str, n: int = 5, seg: int = 10,
                wf=None, arc=None, cap0: bool = True, cap1: bool = True) -> None:
    rings = []
    for i in range(n):
        z = z0 + (z1 - z0) * i / (n - 1)
        hw, hd = d.torso_profile(z)
        rings.append(ring_x((0, 0, z), hw + grow, hd + grow))
    s.tube(rings, mat, wf or d.w_torso, seg=seg, cap0=cap0, cap1=cap1, arc=arc)


def sleeves(s: Skin, d: Dims, mat: str, grow: float, x_end: float | None = None, flare: float = 0.0) -> None:
    """Arm shells from the shoulder to x_end (default wrist); `flare` widens toward the cuff (robes)."""
    x_end = x_end if x_end is not None else d.sx + d.ua + d.la - 0.005
    for sg in (-1, 1):
        xs = [d.chest_hw * 0.6, d.sx, d.sx + 0.4 * d.ua, d.sx + d.ua, (d.sx + d.ua + x_end) / 2, x_end]
        xs = [x for x in xs if x <= x_end]
        rings = []
        for x in xs:
            f = max(0.0, (x - (d.sx + d.ua)) / d.la) * flare
            rings.append(ring_yz((sg * x, 0, d.az), d.arm_radius(x) + grow + f, d.arm_radius(x) + grow + f))
        s.tube(rings, mat, d.w_arm, seg=8, cap0=False)


def legs(s: Skin, d: Dims, mat: str, z_end: float, grow: float, z_top: float | None = None, flare_end: float = 0.0) -> None:
    for sg in (-1, 1):
        top = z_top if z_top is not None else d.hip_z + 0.03
        zs = [top, d.hip_z - 0.45 * d.thigh, d.knee_z, d.knee_z - 0.3 * d.shin, d.ankle_z + 0.04]
        zs = [z for z in zs if z > z_end] + [z_end]
        rings = []
        for z in zs:
            rings.append(ring_x((sg * d.leg_x, 0, z), d.leg_radius(z) + grow + (flare_end if z == z_end else 0.0),
                                d.leg_radius(z) * 1.02 + grow + (flare_end if z == z_end else 0.0)))
        s.tube(rings, mat, d.w_leg, seg=8, cap0=False)


def buttons(s: Skin, d: Dims, z0: float, z1: float, n: int, grow: float, mat: str = "trim") -> None:
    for i in range(n):
        z = z0 + (z1 - z0) * i / max(n - 1, 1)
        _, hd = d.torso_profile(z)
        s.box((0, hd + grow, z), (0.016, 0.01, 0.016), mat, d.w_torso)


def add_piece(s: Skin, d: Dims, piece: str, look: dict, rng: random.Random) -> None:
    hood_up = bool(look.get("hood_up"))
    t = d.torso
    if piece == "shirt":
        torso_shell(s, d, d.hip_z - 0.06 * t, d.shoulder_z - 0.005, 0.010, "shirt", n=5)
        sleeves(s, d, "shirt", 0.009)
    elif piece == "waistcoat":
        torso_shell(s, d, d.waist_z - 0.22 * t, d.shoulder_z - 0.03 * t, 0.022, "vest", n=5)
        buttons(s, d, d.waist_z - 0.1 * t, d.chest_z + 0.1 * t, 4, 0.024)
    elif piece == "jerkin":
        torso_shell(s, d, d.hip_z - 0.14 * t, d.shoulder_z - 0.01, 0.028, "jerkin", n=5)
        wr = w_robe(d)
        z0 = d.hip_z - 0.14 * t
        hw, hd = d.torso_profile(z0)
        s.tube([ring_x((0, 0, z0), hw + 0.028, hd + 0.028), ring_x((0, 0, z0 - 0.12 * d.thigh), hw + 0.07, hd + 0.075),
                ring_x((0, 0, z0 - 0.3 * d.thigh), hw + 0.1, hd + 0.1)], "jerkin", wr, seg=10, cap0=False)
    elif piece == "belt":
        torso_shell(s, d, d.waist_z - 0.1 * t, d.waist_z + 0.04 * t, 0.034, "belt", n=2)
        s.box((0, d.waist_hd + 0.036, d.waist_z - 0.03 * t), (0.04, 0.012, 0.03), "metal", d.w_torso)
    elif piece == "breeches":
        torso_shell(s, d, d.hip_z - 0.16 * t, d.waist_z + 0.04 * t, 0.014, "pants", n=3)
        legs(s, d, "pants", d.knee_z - 0.18 * d.shin, 0.014)
    elif piece == "trousers":
        torso_shell(s, d, d.hip_z - 0.16 * t, d.waist_z + 0.04 * t, 0.014, "pants", n=3)
        legs(s, d, "pants", d.ankle_z + 0.05, 0.012)
    elif piece == "boots":
        legs(s, d, "shoe", d.knee_z - 0.05 * d.shin, 0.012, z_top=d.knee_z + 0.14 * d.shin)
        for sg in (-1, 1):
            L, W, h = d.foot_len, d.foot_w, d.foot_h
            prof = [(-0.24, 0.52, 0.56), (0.05, 0.58, 0.58), (0.45, 0.62, 0.5), (0.82, 0.54, 0.36)]
            s.tube([ring_xz((sg * d.leg_x, y * L, v * h * 1.0), W * a, h * v * 1.05) for y, a, v in prof], "shoe", d.w_leg, seg=8)
    elif piece == "apron":
        # A front panel from chest to knee with a neck strap; a sheet (double-sided), not a closed shell.
        arc = (math.pi / 2 - 0.95, math.pi / 2 + 0.95)
        zt, zb = d.chest_z + 0.14 * t, d.hip_z - 0.5 * d.thigh
        rings = []
        for i in range(6):
            z = zt + (zb - zt) * i / 5
            hw, hd = d.torso_profile(max(z, d.hip_z - 0.16 * t))
            flare = max(0.0, d.hip_z - z) * 0.25
            rings.append(ring_x((0, 0, z), hw + 0.03 + flare, hd + 0.03 + flare * 0.6))
        s.tube(rings, "apron", w_robe(d), seg=6, cap0=False, cap1=False, arc=arc)
        s.tube([ring_x((0, 0, d.shoulder_z - 0.02), d.neck_r * 1.6, d.chest_hd * 0.9), ring_x((0, 0, zt), d.chest_hw * 0.6, d.chest_hd + 0.03)],
               "apron", d.w_torso, seg=4, cap0=False, cap1=False, arc=(math.pi / 2 - 0.5, math.pi / 2 + 0.5))
    elif piece == "dress":
        torso_shell(s, d, d.waist_z - 0.05 * t, d.shoulder_z - 0.005, 0.014, "dress", n=4)
        sleeves(s, d, "dress", 0.009, x_end=d.sx + d.ua * 0.9)
        z0 = d.waist_z - 0.05 * t
        hw, hd = d.torso_profile(z0)
        zh = d.ankle_z + 0.25 * d.shin
        rings = [ring_x((0, 0, z0), hw + 0.014, hd + 0.014), ring_x((0, 0, d.hip_z - 0.2 * d.thigh), d.hip_hw * 1.25, d.hip_hd * 1.45),
                 ring_x((0, 0, d.knee_z), d.hip_hw * 1.65, d.hip_hd * 1.9), ring_x((0, 0, zh), d.hip_hw * 1.95, d.hip_hd * 2.2)]
        s.tube(rings, "dress", w_robe(d), seg=12, cap0=False, cap1=False, jag=0.0)
    elif piece in ("cloak", "ranger_cloak"):
        long = piece == "ranger_cloak"
        zt = d.shoulder_z + 0.45 * d.neck_len
        zh = (d.knee_z - 0.55 * d.shin) if long else (d.hip_z - 0.3 * d.thigh)
        rings = []
        for i in range(7):
            k = i / 6
            z = zt + (zh - zt) * k
            drop = max(0.0, d.shoulder_z - z)
            ru = d.sx + 0.035 + 0.30 * drop + (0 if i else -(d.sx - d.neck_r * 2.0))
            rv = d.chest_hd * 1.45 + 0.22 * drop
            rings.append(ring_x((0, -d.chest_hd * 0.15, z), ru, rv))
        s.tube(rings, "cloak", w_robe(d), seg=14, cap0=False, cap1=False, arc=(0.9 * math.pi, 2.1 * math.pi), jag=0.035 if long else 0.0)
        _hood(s, d, hood_up, "cloak", closed=False)
    elif piece == "rider_robe":
        _rider_robe(s, d, look, rng)
    else:
        raise ValueError(f"unknown outfit piece {piece}")


def _hood(s: Skin, d: Dims, up: bool, mat: str, closed: bool) -> None:
    hr = d.head_r
    wr = float(d.r.get("head_width", 0.92))
    wh = lambda p: d.w_torso(p) if p.z < d.shoulder_z + 0.3 * d.neck_len else {"Head": 1.0}  # noqa: E731
    if not up:  # bunched hood resting on the shoulders behind the neck
        s.ellipsoid((0, -d.chest_hd * 1.05, d.shoulder_z + 0.25 * d.neck_len), (hr * 0.95, hr * 0.5, hr * 0.5), mat, d.w_torso, seg=8, rings=4)
        return
    c = Vector((0, -hr * 0.12, d.head_c + hr * 0.02))
    keep = None if closed else (lambda m: m.y < 0.38 or m.z > 0.72)
    s.ellipsoid(c, (hr * wr * 1.28, hr * 1.36, hr * 1.34), mat, lambda p: {"Head": 1.0} if p.z > d.neck_top else d.w_torso(p), seg=12, rings=7, keep=keep)
    # shoulder cowl joining the hood to the cloak
    s.tube([ring_x((0, -hr * 0.1, d.neck_top + hr * 0.2), hr * wr * 1.15, hr * 1.1),
            ring_x((0, -d.chest_hd * 0.3, d.shoulder_z + 0.2 * d.neck_len), hr * wr * 1.45, hr * 1.25),
            ring_x((0, -d.chest_hd * 0.2, d.shoulder_z - 0.04 * d.torso), d.chest_hw * 1.3, d.chest_hd * 1.55)], mat, wh, seg=10, cap0=False, cap1=False,
           arc=(0.3 * math.pi, 1.7 * math.pi) if not closed else None)


def _rider_robe(s: Skin, d: Dims, look: dict, rng: random.Random) -> None:
    t = d.torso
    torso_shell(s, d, d.hip_z - 0.1 * t, d.shoulder_z - 0.003, 0.03, "robe", n=5)
    sleeves(s, d, "robe", 0.028, x_end=d.sx + d.ua + d.la * 0.97, flare=0.06)
    zg = 0.03
    rings = [ring_x((0, 0, d.waist_z), d.waist_hw + 0.03, d.waist_hd + 0.03), ring_x((0, 0, d.hip_z), d.hip_hw + 0.06, d.hip_hd + 0.06),
             ring_x((0, 0, d.knee_z + 0.1), d.hip_hw * 1.8, d.hip_hd * 2.0), ring_x((0, 0, d.knee_z - 0.3 * d.shin), d.hip_hw * 2.3, d.hip_hd * 2.5),
             ring_x((0, 0, zg), d.hip_hw * 2.9, d.hip_hd * 3.1)]
    s.tube(rings, "robe", w_robe(d), seg=14, cap0=False, cap1=False, jag=0.06)
    # over-cloak: open at the front, falls to the ground behind, in a slightly different black
    zt = d.shoulder_z + 0.4 * d.neck_len
    cl = []
    for i in range(7):
        z = zt + (zg - zt) * i / 6
        drop = max(0.0, d.shoulder_z - z)
        cl.append(ring_x((0, -d.chest_hd * 0.2, z), d.sx + 0.05 + 0.34 * drop - (d.sx - d.neck_r * 2.2 if i == 0 else 0), d.chest_hd * 1.55 + 0.3 * drop))
    s.tube(cl, "robe2", w_robe(d), seg=14, cap0=False, cap1=False, arc=(0.88 * math.pi, 2.12 * math.pi), jag=0.07)
    # closed hood + the black void where a face should be
    hr = d.head_r
    c = Vector((0, -hr * 0.1, d.head_c + hr * 0.05))
    hood_w = lambda p: {"Head": 1.0} if p.z > d.neck_top else d.w_torso(p)  # noqa: E731
    s.ellipsoid(c, (hr * 1.3, hr * 1.42, hr * 1.42), "robe2", hood_w, seg=12, rings=7, keep=lambda m: not (m.y > 0.55 and abs(m.x) < 0.55 and -0.5 < m.z < 0.55))
    s.ellipsoid(c + Vector((0, hr * 0.45, -hr * 0.1)), (hr * 0.82, hr * 0.8, hr * 1.0), "void", {"Head": 1.0}, seg=10, rings=5)
    s.cone(c + Vector((0, -hr * 0.2, hr * 1.1)), hr * 0.75, hr * 0.7, "robe2", {"Head": 1.0}, seg=8, tip=(0, -hr * 0.5, 0))  # peaked cowl
    s.tube([ring_x((0, 0, d.neck_top + hr * 0.1), hr * 1.3, hr * 1.2), ring_x((0, -d.chest_hd * 0.2, d.shoulder_z), d.chest_hw * 1.35, d.chest_hd * 1.7)],
           "robe2", lambda p: d.w_torso(p), seg=10, cap0=False, cap1=False)
