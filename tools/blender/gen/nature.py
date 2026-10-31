"""Trees, bushes, hedges, reeds, rocks, logs, grass/flower tufts. Shire palette (terrain shader tints by region)."""
from __future__ import annotations

import math

from lib import style
from lib.geo import m
from . import Spec

TAU = math.tau


def _leaf_mats(R, species, variant):
    gold = variant == 3 and species in ("beech", "birch", "oak")
    if gold:
        return [R["grass_alt_dark"], R["grass_alt_mid"], R["grass_alt_light"]]
    if species == "oak":
        return [R["forest_floor_mid"], R["grass_mid"], style.mix(R["grass_mid"], R["grass_light"], 0.4)]
    if species == "beech":
        return [style.mix(R["forest_floor_mid"], R["grass_alt_dark"], 0.3), style.mix(R["grass_mid"], R["grass_alt_mid"], 0.25),
                style.mix(R["grass_light"], R["grass_alt_mid"], 0.3)]
    if species == "birch":
        return [R["grass_mid"], style.mix(R["grass_light"], R["grass_alt_mid"], 0.2), R["grass_light"]]
    if species == "willow":
        return [style.mix(R["grass_mid"], R["grass_alt_mid"], 0.2), style.mix(R["grass_light"], R["grass_alt_mid"], 0.25),
                style.mix(R["grass_light"], R["grass_alt_light"], 0.4)]
    return [R["forest_floor_dark"], style.mix(R["forest_floor_dark"], R["forest_floor_mid"], 0.55), R["forest_floor_mid"]]


def tree(b, R, species="oak", variant=0):
    rng = b.rng
    L = _leaf_mats(R, species, variant)
    s = 0.9 + rng.random() * 0.25
    if species == "oak":
        th = 2.6 * s
        bark = R["bark"]
        b.cyl((0, 0, -0.1), 0.62 * s, 0.55, bark, 7, top_r=0.42 * s)
        b.cyl((0, 0, 0.4), 0.42 * s, th - 0.4, bark, 7, top_r=0.3 * s)
        n = 7 + variant % 2
        for i in range(n):
            a = TAU * i / n + rng.uniform(-0.3, 0.3)
            r = rng.uniform(1.5, 2.3) * s
            z = th + rng.uniform(0.2, 1.6) * s
            tip = (math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, z - 0.2)
            b.between((0, 0, th - 0.5), tip, 0.12 * s, bark, 5, 0.07)
            b.blob((math.cos(a) * r, math.sin(a) * r, z), (1.7 * s, 1.7 * s, 1.35 * s), L[i % 3], 1, 0.18)
        b.blob((0, 0, th + 2.2 * s), (2.1 * s, 2.1 * s, 1.5 * s), L[2], 1, 0.18)
        trunk_r, trunk_h = 0.5 * s, 3
    elif species == "beech":
        th = 4.2 * s
        bark = style.mix(R["rock_mid"], R["bark_light"], 0.35)
        b.cyl((0, 0, -0.1), 0.5 * s, 0.7, bark, 8, top_r=0.34 * s)
        b.cyl((0, 0, 0.5), 0.34 * s, th - 0.5, bark, 8, top_r=0.22 * s)
        for i in range(3):
            z = th + i * 1.7 * s
            w = (2.6 - i * 0.55) * s
            for k in range(3 - (1 if i == 2 else 0)):
                a = TAU * k / 3 + i * 1.1 + rng.uniform(-0.3, 0.3)
                off = w * 0.4
                b.blob((math.cos(a) * off, math.sin(a) * off, z + rng.uniform(-0.2, 0.3)), (w * 0.8, w * 0.8, 1.35 * s), L[(i + k) % 3], 1, 0.16)
        b.blob((0, 0, th + 4.7 * s), (1.0 * s, 1.0 * s, 0.9 * s), L[2], 1, 0.15)
        trunk_r, trunk_h = 0.35 * s, 4
    elif species == "birch":
        th = 5.0 * s
        lean = rng.uniform(-0.05, 0.05)
        b.cyl((0, 0, 0), 0.2 * s, th, R["birch"], 6, top_r=0.1 * s, rot=(lean, lean, 0))
        for i in range(4):
            z = 0.9 + i * th / 4.6
            b.cyl((0, 0, z), 0.215 * s * (1 - i * 0.12), 0.1, R["birch_dark"], 6)
        for i in range(6):
            a = TAU * i / 6 + rng.uniform(-0.4, 0.4)
            r = rng.uniform(0.7, 1.3) * s
            z = th + rng.uniform(-1.2, 1.3) * s
            b.between((0, 0, th * 0.7), (math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, z - 0.2), 0.05, R["birch"], 4, 0.03)
            b.blob((math.cos(a) * r, math.sin(a) * r, z), (0.95 * s, 0.95 * s, 1.1 * s), L[i % 3], 1, 0.2)
        b.blob((0, 0, th + 1.2 * s), (0.9 * s, 0.9 * s, 1.0 * s), L[2], 1, 0.2)
        trunk_r, trunk_h = 0.2 * s, 3
    elif species == "willow":
        th = 2.2 * s
        bark = R["bark_light"]
        b.cyl((0, 0, -0.1), 0.6 * s, 0.6, bark, 7, top_r=0.4 * s)
        b.cyl((0, 0, 0.5), 0.4 * s, th - 0.3, bark, 7, top_r=0.32 * s, rot=(0.08, 0.05, 0))
        b.dome((0, 0, th + 0.1), (2.7 * s, 2.7 * s, 1.9 * s), L[1], 9, 3, jitter=0.12)
        n = 9 + variant
        for i in range(n):
            a = TAU * i / n + rng.uniform(-0.2, 0.2)
            r = rng.uniform(2.2, 2.9) * s
            ln = rng.uniform(2.0, 2.8) * s
            x, y = math.cos(a) * r, math.sin(a) * r
            b.cyl((x, y, th + 0.7 * s - ln), 0.04, ln, L[i % 3], 4, top_r=0.38 * s)
        trunk_r, trunk_h = 0.4 * s, 2.5
    else:  # pine
        tiers = 5 + variant
        th = 1.6 * s
        b.cyl((0, 0, -0.1), 0.34 * s, th + 0.3, R["bark"], 6, top_r=0.2 * s)
        h = 1.0
        for i in range(tiers):
            f = 1 - i / tiers
            r = (0.9 + 1.8 * f) * s
            z = th + i * 1.25 * s * (0.9 + 0.2 * f) - 0.25
            b.cyl((0, 0, z), r, 1.9 * s, L[i % 2], 8, top_r=0.05, rot=(0, 0, rng.random()))
        trunk_r, trunk_h = 0.25 * s, 2.2
    with b.collision("convcolonly"):
        b.cyl((0, 0, 0), trunk_r, trunk_h, None, 6)


def bush(b, R, variant=0):
    rng = b.rng
    L = [R["forest_floor_mid"], R["grass_mid"], R["grass_light"]]
    if variant == 3:
        L = [R["grass_alt_dark"], R["grass_alt_mid"], R["grass_alt_light"]]
    n = 3 + variant % 3
    for i in range(n):
        a = TAU * i / n + rng.uniform(-0.4, 0.4)
        r = 0.35 + rng.random() * 0.2
        b.blob((math.cos(a) * r, math.sin(a) * r, 0.42), (0.55, 0.55, 0.5), L[i % 3], 1, 0.2)
    b.blob((0, 0, 0.62), (0.6, 0.6, 0.5), L[2], 1, 0.2)
    if variant == 1:  # berries
        for _ in range(7):
            a, e = rng.uniform(0, TAU), rng.uniform(0.3, 0.9)
            b.blob((math.cos(a) * 0.75 * e, math.sin(a) * 0.75 * e, 0.55 + 0.35 * (1 - e)), (0.06, 0.06, 0.06), R["flower_red"], 0, 0)
    if variant == 2:  # blossom
        for _ in range(8):
            a, e = rng.uniform(0, TAU), rng.uniform(0.3, 0.9)
            b.blob((math.cos(a) * 0.75 * e, math.sin(a) * 0.75 * e, 0.55 + 0.35 * (1 - e)), (0.08, 0.08, 0.06), R["flower_white"], 0, 0)
    with b.collision("convcolonly"):
        b.cyl((0, 0, 0), 0.6, 0.7, None, 6)


def hedge(b, R, variant=0, length=4.0):
    rng = b.rng
    L = [R["forest_floor_mid"], R["grass_mid"], style.mix(R["grass_mid"], R["grass_light"], 0.5)]
    n = max(2, int(length / 1.1))
    if variant == 2:  # end cap: rounded end
        n = 3
    for i in range(n):
        x = -length / 2 + (i + 0.5) * length / n
        b.blob((x, 0, 0.55), (length / n * 0.78, 0.62, 0.58), L[i % 3], 1, 0.12)
        b.blob((x + rng.uniform(-0.1, 0.1), 0, 1.05), (length / n * 0.62, 0.5, 0.4), L[(i + 1) % 3], 1, 0.12)
    with b.collision("convcolonly"):
        b.box((0, 0, 0.6), (length, 1.0, 1.2))


def reeds(b, R, variant=0):
    rng = b.rng
    n = 11 + variant * 3
    green = [R["grass_mid"], R["forest_floor_mid"], style.mix(R["grass_mid"], R["grass_alt_mid"], 0.4)]
    for i in range(n):
        a = rng.uniform(0, TAU)
        r = rng.uniform(0, 0.5)
        h = rng.uniform(1.2, 2.0)
        x, y = math.cos(a) * r, math.sin(a) * r
        lean = (rng.uniform(-0.18, 0.18), rng.uniform(-0.18, 0.18), 0)
        if variant == 0 or i % 3 == 0:
            b.cyl((x, y, 0), 0.04, h, green[i % 3], 3, top_r=0.0, rot=lean)
        else:  # cattail
            b.cyl((x, y, 0), 0.02, h, green[1], 3, rot=lean)
            tip = (x + math.sin(lean[1]) * h * 0.9, y - math.sin(lean[0]) * h * 0.9, h * 0.9)
            b.cyl(tip, 0.055, 0.28, R["bark"], 5, top_r=0.04)


def rock(b, R, variant=0):
    rng = b.rng
    cols = [R["rock_mid"], R["rock_dark"], R["rock_light"], style.mix(R["rock_mid"], R["grass_dark"], 0.18)]
    if variant < 3:
        sx, sy, sz = [(1.0, 0.85, 0.7), (0.8, 0.8, 1.0), (1.3, 0.9, 0.55)][variant]
        b.blob((0, 0, sz * 0.45), (sx, sy, sz), cols[0], 1, 0.28, (0, 0, rng.random()))
        b.blob((sx * 0.6, sy * 0.3, sz * 0.22), (sx * 0.5, sy * 0.45, sz * 0.4), cols[1], 1, 0.25)
        b.blob((-sx * 0.3, -sy * 0.5, sz * 0.9), (sx * 0.3, sy * 0.3, sz * 0.25), cols[2], 0, 0.2)
        b.blob((0, 0, sz * 0.06), (sx * 1.08, sy * 1.08, 0.18), style.mix(R["rock_dark"], R["grass_dark"], 0.5), 0, 0.1)
    elif variant == 3:  # cluster
        for i in range(4):
            a = TAU * i / 4 + rng.random()
            r = 0.55 * (i > 0)
            s = rng.uniform(0.3, 0.55)
            b.blob((math.cos(a) * r, math.sin(a) * r, s * 0.45), (s, s * 0.9, s * 0.8), cols[i % 3], 1, 0.28)
    elif variant == 4:  # standing slab
        b.box((0, 0, 0.8), (1.3, 0.45, 1.6), cols[0], rot=(0.05, 0.08, 0.3), top=(0.7, 0.8))
        b.blob((0.5, 0.4, 0.2), (0.55, 0.45, 0.3), cols[1], 1, 0.25)
    else:  # flat stepping stones
        for i in range(3):
            b.cyl((i * 0.9 - 0.9, rng.uniform(-0.1, 0.1), 0), 0.38 + rng.random() * 0.1, 0.18, cols[i % 3], 6, top_r=0.32,
                  rot=(0, 0, rng.random()))
    with b.collision("convcolonly"):
        b.box((0, 0, 0.35), (1.4, 1.0, 0.7)) if variant != 5 else b.box((0, 0, 0.09), (2.4, 0.9, 0.18))


def log(b, R, variant=0):
    bark, cut = R["bark"], R["bark_light"]
    if variant == 0:
        b.cyl((-1.1, 0, 0.3), 0.3, 2.2, bark, 8, rot=(0, math.pi / 2, 0))
        b.cyl((1.1, 0, 0.3), 0.31, 0.04, cut, 8, rot=(0, math.pi / 2, 0))
        b.blob((0.3, 0.2, 0.62), (0.7, 0.25, 0.1), R["grass_mid"], 0, 0.2)
        with b.collision():
            b.box((0, 0, 0.3), (2.3, 0.62, 0.62))
    elif variant == 1:  # pile
        for i, (y, z) in enumerate([(-0.33, 0.2), (0.33, 0.2), (0, 0.58), (-0.66, 0.58), (0.66, 0.58)]):
            b.cyl((-0.9, y * 1.0, z), 0.2 if i != 2 else 0.22, 1.8, bark, 6, rot=(0, math.pi / 2, 0))
            b.cyl((0.9, y * 1.0, z), 0.2, 0.03, cut, 6, rot=(0, math.pi / 2, 0))
        with b.collision():
            b.box((0, 0, 0.45), (1.9, 1.6, 0.9))
    else:  # stump
        b.cyl((0, 0, 0), 0.5, 0.45, bark, 7, top_r=0.4)
        b.cyl((0, 0, 0.45), 0.4, 0.04, cut, 7)
        for a in (0.4, 2.2, 4.0):
            b.between((math.cos(a) * 0.3, math.sin(a) * 0.3, 0.05), (math.cos(a) * 0.75, math.sin(a) * 0.75, -0.05), 0.09, bark, 4, 0.05)
        with b.collision():
            b.cyl((0, 0, 0), 0.5, 0.45, None, 6)


def tuft(b, R, variant=0):
    """Crossed blade fans (double-sided). variant 0/1 green/gold grass."""
    rng = b.rng
    cols = [[R["grass_mid"], R["grass_light"], R["grass_dark"]], [R["grass_alt_mid"], R["grass_alt_light"], R["grass_alt_dark"]]][variant % 2]
    for i in range(9):
        a = TAU * i / 9 + rng.uniform(-0.2, 0.2)
        h = rng.uniform(0.45, 0.85)
        lean = rng.uniform(0.12, 0.45)
        w = 0.07
        x, y = math.cos(a) * 0.08, math.sin(a) * 0.08
        dx, dy = math.cos(a) * lean * h, math.sin(a) * lean * h
        px, py = -math.sin(a) * w, math.cos(a) * w
        b.poly([(x - px, y - py, 0), (x + px, y + py, 0), (x + dx, y + dy, h)], m(cols[i % 3], 0, True))


def flowers(b, R, variant=0):
    rng = b.rng
    petal = [R["flower_yellow"], R["flower_white"], R["flower_purple"], R["flower_red"]][variant % 4]
    for i in range(6):
        a = rng.uniform(0, TAU)
        r = rng.uniform(0.0, 0.3)
        x, y = math.cos(a) * r, math.sin(a) * r
        h = rng.uniform(0.35, 0.65)
        b.cyl((x, y, 0), 0.015, h, R["grass_mid"], 3, rot=(rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))
        b.cyl((x, y, h), 0.09, 0.04, petal, 6, top_r=0.07)
        b.cyl((x, y, h + 0.04), 0.035, 0.03, R["flower_yellow"] if variant != 0 else R["bark"], 5)
        b.poly([(x, y, 0.05), (x + 0.2, y, 0.25), (x + 0.02, y, 0.3)], m(R["grass_dark"], 0, True))


def specs():
    out = []
    for sp in ("oak", "beech", "birch", "willow", "pine"):
        for v in range(4):
            out.append(Spec(f"tree_{sp}_{v + 1}", "nature", "tree", 100 + hash_s(sp) + v,
                            lambda b, R, sp=sp, v=v: tree(b, R, sp, v)))
    for v in range(4):
        out.append(Spec(f"bush_{v + 1}", "nature", "bush", 200 + v, lambda b, R, v=v: bush(b, R, v)))
    out.append(Spec("hedge_straight_1", "nature", "plant", 211, lambda b, R: hedge(b, R, 0, 4.0)))
    out.append(Spec("hedge_straight_2", "nature", "plant", 212, lambda b, R: hedge(b, R, 1, 4.0)))
    out.append(Spec("hedge_end_1", "nature", "plant", 213, lambda b, R: hedge(b, R, 2, 2.0)))
    for v in range(2):
        out.append(Spec(f"reeds_{v + 1}", "nature", "plant", 220 + v, lambda b, R, v=v: reeds(b, R, v), lods=False))
    for v in range(6):
        out.append(Spec(f"rock_{v + 1}", "nature", "rock", 230 + v, lambda b, R, v=v: rock(b, R, v)))
    for v in range(3):
        out.append(Spec(f"log_{['single', 'pile', 'stump'][v]}", "nature", "rock", 240 + v, lambda b, R, v=v: log(b, R, v)))
    for v in range(2):
        out.append(Spec(f"grass_tuft_{v + 1}", "nature", "plant", 250 + v, lambda b, R, v=v: tuft(b, R, v), lods=False))
    for v in range(4):
        out.append(Spec(f"flower_patch_{v + 1}", "nature", "plant", 260 + v, lambda b, R, v=v: flowers(b, R, v), lods=False))
    return out


def hash_s(s: str) -> int:
    return sum(ord(c) * (i + 1) for i, c in enumerate(s)) % 50 * 10
