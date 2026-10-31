"""The bare body: torso, neck, head with a simple face, arms, hands, legs and feet (hairy for hobbits), plus hair/beard/hats."""
from __future__ import annotations

import math
import random

from mathutils import Vector

from .rig import Dims, Skin, ring_x, ring_xz, ring_yz


def build_body(s: Skin, d: Dims, look: dict, rng: random.Random) -> None:
    r = d.r
    _torso(s, d)
    _head(s, d, look)
    for sg in (-1, 1):
        _arm(s, d, sg, look)
        _leg(s, d, sg, look, rng)


def _torso(s: Skin, d: Dims) -> None:
    zs = [d.hip_z - 0.16 * d.torso, d.hip_z, d.waist_z, d.chest_z, d.shoulder_z - 0.02 * d.torso]
    rings = []
    for z in zs:
        hw, hd = d.torso_profile(z)
        rings.append(ring_x((0, 0, z), hw, hd))
    s.tube(rings, "skin", d.w_torso, seg=10)
    # neck
    nr = d.neck_r
    s.tube([ring_x((0, 0, d.shoulder_z - 0.03 * d.torso), nr * 1.5, nr * 1.4),
            ring_x((0, 0, d.shoulder_z + 0.2 * d.neck_len), nr, nr),
            ring_x((0, 0, d.neck_top + 0.2 * d.head_r), nr * 0.95, nr * 0.95)], "skin", d.w_torso, seg=8, cap0=False)


def _head(s: Skin, d: Dims, look: dict) -> None:
    hr = d.head_r
    c = Vector((0, 0.0, d.head_c))
    wr = float(d.r.get("head_width", 0.92))
    s.ellipsoid(c, (hr * wr, hr * 1.0, hr * 1.06), "skin", d.w_head, seg=12, rings=7)
    # chin/jaw block so the head is not a perfect egg
    s.ellipsoid(c + Vector((0, hr * 0.28, -hr * 0.55)), (hr * wr * 0.7, hr * 0.62, hr * 0.5), "skin", d.w_head, seg=8, rings=4)
    if look.get("faceless"):
        return
    # eyes and brows/nose: small dark boxes. Eye height/spacing follow the head so hobbit heads read cute, not blank.
    ey = hr * (0.88 if not look.get("sneer") else 0.9)
    for sg in (-1, 1):
        s.box(c + Vector((sg * hr * 0.38 * wr, ey, hr * 0.1)), (hr * 0.17, hr * 0.1, hr * 0.14), "eye", d.w_head)
        s.box(c + Vector((sg * hr * 0.38 * wr, ey - hr * 0.02, hr * 0.3)), (hr * 0.3, hr * 0.1, hr * 0.06), "brow", d.w_head)
    ns = float(d.r.get("nose", 1.0))
    s.box(c + Vector((0, hr * 1.0, -hr * 0.12)), (hr * 0.16 * ns, hr * 0.3 * ns, hr * 0.3 * ns), "skin", d.w_head)
    s.box(c + Vector((0, hr * 0.86, -hr * 0.46)), (hr * 0.34, hr * 0.1, hr * 0.06), "mouth", d.w_head)
    # ears
    pointy = float(look.get("ear", d.r.get("ear", 0.0)))
    for sg in (-1, 1):
        s.ellipsoid(c + Vector((sg * hr * wr * 0.98, -hr * 0.05, -hr * 0.02)), (hr * 0.1, hr * 0.17, hr * (0.24 + 0.2 * pointy)), "skin", d.w_head, seg=6, rings=3)
        if pointy > 0.2:
            s.cone(c + Vector((sg * hr * wr * 1.0, -hr * 0.05, hr * 0.15)), hr * 0.1, hr * 0.38 * pointy, "skin", d.w_head, seg=4)


def _arm(s: Skin, d: Dims, sg: int, look: dict) -> None:
    x0, x1, x2 = d.sx, d.sx + d.ua, d.sx + d.ua + d.la
    xs = [d.chest_hw * 0.55, x0, x0 + 0.35 * d.ua, x1, x1 + 0.4 * d.la, x2]
    rings = [ring_yz((sg * x, 0, d.az), d.arm_radius(x) * 0.95, d.arm_radius(x)) for x in xs]
    s.tube(rings, "skin", d.w_arm, seg=8, cap0=False)
    # hand: flat mitten + thumb; palm faces down in T-pose
    hl, hw = d.hand_len, d.arm_r * 1.25
    hand = [ring_yz((sg * (x2 + hl * f), 0, d.az), hw * m, d.arm_r * 0.62 * m2)
            for f, m, m2 in ((0.0, 0.85, 0.9), (0.45, 1.0, 1.0), (0.9, 0.8, 0.8), (1.05, 0.4, 0.4))]
    s.tube(hand, "hand", d.w_arm, seg=6, cap0=False)
    s.tube([ring_yz((sg * (x2 + hl * 0.25), hw * 0.8, d.az + d.arm_r * 0.1), d.arm_r * 0.38, d.arm_r * 0.38),
            ring_yz((sg * (x2 + hl * 0.65), hw * 1.25, d.az + d.arm_r * 0.1), d.arm_r * 0.25, d.arm_r * 0.25)], "hand", d.w_arm, seg=5)


def _leg(s: Skin, d: Dims, sg: int, look: dict, rng: random.Random) -> None:
    lx = sg * d.leg_x
    zs = [d.hip_z + 0.03, d.hip_z - 0.45 * d.thigh, d.knee_z, d.knee_z - 0.3 * d.shin, d.ankle_z + 0.04]
    rings = [ring_x((lx, 0, z), d.leg_radius(z), d.leg_radius(z) * 1.02) for z in zs]
    s.tube(rings, "skin", d.w_leg, seg=8, cap0=False)
    # foot: low wedge; hobbit feet are big and covered in curly hair
    L, W, h = d.foot_len, d.foot_w, d.foot_h
    prof = [(-0.22, 0.46, 0.5), (0.05, 0.52, 0.5), (0.45, 0.56, 0.42), (0.78, 0.48, 0.3)]
    rings = [ring_xz((lx, y * L, v * h * 0.95), W * a, h * v) for y, a, v in prof]
    s.tube(rings, "skin", d.w_leg, seg=8)
    if d.r.get("hairy_feet"):
        for _ in range(int(d.r["hairy_feet"])):
            ty = rng.uniform(-0.15, 0.7) * L
            tx = lx + rng.uniform(-0.55, 0.55) * W
            tz = h * rng.uniform(0.7, 1.15)
            rad = W * rng.uniform(0.2, 0.3)
            s.ellipsoid((tx, ty, tz), (rad, rad * 1.4, rad * 0.8), "foot_hair", d.w_leg, seg=5, rings=3, jitter=0.2, rng=rng)
        # ankle ruff
        s.tube([ring_x((lx, 0, d.ankle_z + 0.1 * d.shin), d.leg_radius(d.ankle_z) * 1.35, d.leg_radius(d.ankle_z) * 1.35),
                ring_x((lx, 0, d.ankle_z + 0.32 * d.shin), d.leg_radius(d.ankle_z) * 1.2, d.leg_radius(d.ankle_z) * 1.2)], "foot_hair", d.w_leg, seg=7)


# --- hair ------------------------------------------------------------------------------------

def build_hair(s: Skin, d: Dims, look: dict, rng: random.Random) -> None:
    style = look.get("hair_style", "short")
    if style in ("none", "hooded"):
        return
    hr, hc = d.head_r, Vector((0, 0, d.head_c))
    wr = float(d.r.get("head_width", 0.92))
    wH = d.w_head
    cap = lambda k: (lambda m: m.z > k)  # noqa: E731
    if style == "curly":
        s.ellipsoid(hc + Vector((0, -hr * 0.05, hr * 0.12)), (hr * wr * 1.06, hr * 1.05, hr * 1.06), "hair", wH, seg=9, rings=5, keep=lambda m: m.z > 0.45 or (m.z > 0.0 and m.y < 0.0))
        for _ in range(26):
            th, ph = rng.uniform(0, 2 * math.pi), rng.uniform(0.15, 1.15)
            p = Vector((math.sin(ph) * math.cos(th) * wr, math.sin(ph) * math.sin(th) * 0.95 - 0.04, math.cos(ph) * 1.0)) * hr * 1.0
            if p.y > hr * 0.55 and p.z < hr * 0.7:
                continue  # keep the face clear
            rad = hr * rng.uniform(0.2, 0.3)
            s.ellipsoid(hc + p + Vector((0, 0, hr * 0.1)), (rad, rad, rad), "hair", wH, seg=5, rings=3, jitter=0.18, rng=rng)
        for sg in (-1, 1):  # sideburn curls
            s.ellipsoid(hc + Vector((sg * hr * wr * 0.95, hr * 0.15, -hr * 0.2)), (hr * 0.14, hr * 0.14, hr * 0.28), "hair", wH, seg=5, rings=3)
    elif style in ("short", "mop"):
        k = 0.2 if style == "short" else 0.05
        s.ellipsoid(hc + Vector((0, -hr * 0.06, hr * 0.06)), (hr * wr * 1.08, hr * 1.08, hr * 1.1), "hair", wH, seg=10, rings=5, keep=lambda m: m.z > k and (m.y < 0.45 or m.z > 0.55))
        if style == "mop":
            for _ in range(7):
                th = rng.uniform(math.pi * 0.2, math.pi * 1.8)
                s.ellipsoid(hc + Vector((math.cos(th) * hr * wr * 1.0, math.sin(th) * hr * 0.95 - hr * 0.05, rng.uniform(-0.2, 0.5) * hr)), (hr * 0.22, hr * 0.22, hr * 0.22), "hair", wH, seg=5, rings=3, jitter=0.2, rng=rng)
    elif style == "long":
        s.ellipsoid(hc + Vector((0, -hr * 0.06, hr * 0.06)), (hr * wr * 1.08, hr * 1.1, hr * 1.1), "hair", wH, seg=10, rings=5, keep=lambda m: m.z > 0.0 and (m.y < 0.4 or m.z > 0.5))
        top = d.neck_top
        def wlong(p: Vector):
            return d.w_torso(p) if p.z < d.shoulder_z + 0.01 else {"Head": 1.0}
        rings = [ring_x((0, -hr * 0.62, hc.z - hr * 0.1), hr * wr * 1.0, hr * 0.5),
                 ring_x((0, -hr * 0.75, d.neck_top - hr * 0.5), hr * wr * 1.0, hr * 0.46),
                 ring_x((0, -d.chest_hd * 1.05, d.shoulder_z - 0.1 * d.torso), hr * wr * 1.0, hr * 0.3),
                 ring_x((0, -d.chest_hd * 1.05, d.chest_z), hr * wr * 0.8, hr * 0.22)]
        s.tube(rings, "hair", wlong, seg=8, cap1=True, cap0=False)
    elif style == "bun":
        s.ellipsoid(hc + Vector((0, -hr * 0.04, hr * 0.06)), (hr * wr * 1.06, hr * 1.06, hr * 1.08), "hair", wH, seg=10, rings=5, keep=lambda m: m.z > 0.1 and (m.y < 0.3 or m.z > 0.6))
        s.ellipsoid(hc + Vector((0, -hr * 0.85, hr * 0.62)), (hr * 0.38, hr * 0.38, hr * 0.38), "hair", wH, seg=6, rings=4)
    elif style == "bald":
        for sg in (-1, 1):
            s.ellipsoid(hc + Vector((sg * hr * wr * 0.85, -hr * 0.25, hr * 0.0)), (hr * 0.22, hr * 0.55, hr * 0.35), "hair", wH, seg=6, rings=3)
        s.ellipsoid(hc + Vector((0, -hr * 0.8, -hr * 0.05)), (hr * wr * 0.7, hr * 0.28, hr * 0.32), "hair", wH, seg=7, rings=3)
    elif style == "thin":  # old man: wispy cap pushed back
        s.ellipsoid(hc + Vector((0, -hr * 0.2, hr * 0.0)), (hr * wr * 1.05, hr * 1.0, hr * 1.04), "hair", wH, seg=9, rings=4, keep=lambda m: m.z > -0.1 and m.y < 0.0)
        for sg in (-1, 1):
            s.ellipsoid(hc + Vector((sg * hr * wr * 0.95, -hr * 0.1, -hr * 0.1)), (hr * 0.16, hr * 0.4, hr * 0.3), "hair", wH, seg=6, rings=3)


def build_beard(s: Skin, d: Dims, look: dict, rng: random.Random) -> None:
    kind = look.get("beard")
    if not kind:
        return
    hr, hc = d.head_r, Vector((0, 0, d.head_c))
    wr = float(d.r.get("head_width", 0.92))
    wH = d.w_head
    if kind == "stubble":
        s.ellipsoid(hc + Vector((0, hr * 0.32, -hr * 0.55)), (hr * wr * 0.74, hr * 0.68, hr * 0.5), "beard", wH, seg=8, rings=4, keep=lambda m: m.z < 0.2)
    elif kind == "short":
        s.ellipsoid(hc + Vector((0, hr * 0.3, -hr * 0.62)), (hr * wr * 0.8, hr * 0.74, hr * 0.62), "beard", wH, seg=8, rings=4, keep=lambda m: m.z < 0.3)
    elif kind == "long":
        def wb(p: Vector):
            return d.w_torso(p) if p.z < d.neck_top - 0.5 * d.head_r else {"Head": 1.0}
        z0 = hc.z - hr * 0.35
        rings = [ring_x((0, hr * 0.7, z0), hr * wr * 0.8, hr * 0.28),
                 ring_x((0, hr * 0.85, z0 - hr * 0.8), hr * wr * 0.78, hr * 0.34),
                 ring_x((0, d.chest_hd * 1.15, d.shoulder_z - 0.04 * d.torso), hr * 0.8, hr * 0.3),
                 ring_x((0, d.chest_hd * 1.2, d.chest_z - 0.03 * d.torso), hr * 0.5, hr * 0.22),
                 ring_x((0, d.chest_hd * 1.1, d.waist_z + 0.04 * d.torso), hr * 0.15, hr * 0.1)]
        s.tube(rings, "beard", wb, seg=7, cap0=False)
        s.ellipsoid(hc + Vector((0, hr * 0.5, -hr * 0.3)), (hr * 0.45, hr * 0.28, hr * 0.12), "beard", wH, seg=6, rings=3)  # moustache


def build_hat(s: Skin, d: Dims, look: dict) -> None:
    kind = look.get("hat")
    if not kind:
        return
    hr = d.head_r
    z0 = d.head_c + hr * 0.68
    wH = d.w_head
    def circ(z, rad, rv=None):
        return ring_x((0, -hr * 0.04, z), rad, rv if rv else rad)
    if kind == "pointed":  # wizard's hat: wide drooping brim, tall bent cone
        s.tube([circ(z0 - 0.02 * hr, hr * 2.05), circ(z0 + 0.03 * hr, hr * 1.7), circ(z0 + 0.1 * hr, hr * 1.2)], "hat", wH, seg=12)
        cone = [ring_x((0, -hr * 0.04 - k * k * hr * 0.9, z0 + hr * (0.05 + k * 3.0 - 0.5 * k * k)), hr * (1.15 - 1.1 * k), hr * (1.15 - 1.1 * k)) for k in (0.0, 0.3, 0.6, 0.85, 1.0)]
        s.tube(cone, "hat", wH, seg=10, cap0=False)
        s.tube([circ(z0 + 0.12 * hr, hr * 1.2), circ(z0 + 0.34 * hr, hr * 1.16)], "hat_band", wH, seg=10)
    elif kind == "slouch":
        s.tube([circ(z0 - 0.02 * hr, hr * 1.7), circ(z0 + 0.04 * hr, hr * 1.55), circ(z0 + 0.1 * hr, hr * 1.1)], "hat", wH, seg=10)
        s.tube([circ(z0 + 0.08 * hr, hr * 1.1), circ(z0 + 0.7 * hr, hr * 0.98), circ(z0 + 0.95 * hr, hr * 0.7)], "hat", wH, seg=10)
    elif kind == "straw":
        s.tube([circ(z0 - 0.1 * hr, hr * 1.9), circ(z0 - 0.04 * hr, hr * 1.7), circ(z0 + 0.1 * hr, hr * 1.1)], "hat", wH, seg=12)
        s.tube([circ(z0 + 0.1 * hr, hr * 1.08), circ(z0 + 0.62 * hr, hr * 0.98), circ(z0 + 0.7 * hr, hr * 0.8)], "hat", wH, seg=10)
        s.tube([circ(z0 + 0.1 * hr, hr * 1.1), circ(z0 + 0.26 * hr, hr * 1.06)], "hat_band", wH, seg=10)
    elif kind == "bonnet":
        s.ellipsoid(Vector((0, -hr * 0.1, d.head_c + hr * 0.1)), (hr * 1.0, hr * 1.14, hr * 1.12), "hat", wH, seg=10, rings=5, keep=lambda m: m.z > -0.2 and (m.y < 0.1 or m.z > 0.35))
        s.tube([ring_x((0, hr * 0.95, d.head_c + hr * 0.55), hr * 0.9, hr * 0.05), ring_x((0, hr * 1.5, d.head_c + hr * 0.35), hr * 0.85, hr * 0.05)], "hat_band", wH, seg=8, cap0=False, cap1=False, arc=(0, math.pi))
