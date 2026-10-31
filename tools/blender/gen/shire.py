"""Shire buildings and structures: hobbit-holes, cottages, mill, inns, fences, gates, gardens, wells, bridges, ferry, stone."""
from __future__ import annotations

import math

from lib import parts, style
from lib.geo import m
from . import Spec

PI = math.pi


def _hill_y(rx, ry, h, x, z):
    t = 1 - (x / rx) ** 2 - (z / h) ** 2
    return -ry * math.sqrt(max(t, 0.0))


def hobbit_hole(b, R, hill_r=6.5, door="door_green", windows=2, chimney=True, flowers=True):
    rng = b.rng
    rx, ry, h = hill_r, hill_r * 0.85, hill_r * 0.5
    b.dome((0, 0, -0.1), (rx, ry, h), R["grass_mid"], 14, 5, jitter=0.03)
    for i in range(5):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.2, 0.7)
        b.blob((math.cos(a) * rx * d, math.sin(a) * ry * d + 0.5, h * (1 - d * d) ** 0.5 * 0.9), (1.2, 1.0, 0.35),
               [R["grass_light"], R["grass_alt_mid"]][i % 2], 1, 0.2)
    if flowers:
        for i in range(8):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(0.3, 0.85)
            x, y = math.cos(a) * rx * d, math.sin(a) * ry * d
            z = h * math.sqrt(max(0, 1 - d * d)) * 0.97
            b.blob((x, y, z), (0.09, 0.09, 0.07), [R["flower_yellow"], R["flower_white"], R["flower_purple"]][i % 3], 0, 0)
    dz = 1.05
    dy = _hill_y(rx, ry, h, 0, dz)
    # recessed door tube + door disc
    b.cyl((0, dy + 1.0, dz), 1.15, 1.0, R["wood_dark"], 12, rot=(PI / 2, 0, 0))
    b.cyl((0, dy + 0.12, dz), 0.98, 0.2, R[door], 12, rot=(PI / 2, 0, 0))
    for k in range(3):
        a = k * math.tau / 3 + 0.5
        b.box((math.cos(a) * 0.55, dy - 0.1, dz + math.sin(a) * 0.55), (0.35, 0.04, 0.05), R["metal"], rot=(0, -a, 0))
    b.blob((0.32, dy - 0.12, dz - 0.05), (0.09, 0.09, 0.09), R["brass"], 1, 0)
    b.cyl((0, dy - 0.05, 0), 1.35, 0.1, R["rock_mid"], 12, top_r=1.45)  # threshold stone
    # side windows
    wx = rx * 0.4
    xs = {0: [], 1: [wx], 2: [-wx, wx], 3: [-wx * 1.4, wx * 1.4, 0.0]}[windows]
    for i, x in enumerate(xs):
        z = 1.5 if x != 0 else 3.2
        y = _hill_y(rx, ry, h, x, z)
        b.cyl((x, y + 0.7, z), 0.62, 0.8, R["wood_dark"], 10, rot=(PI / 2, 0, 0))
        b.cyl((x, y + 0.35, z), 0.5, 0.2, m(R["glass"], 1.0), 10, rot=(PI / 2, 0, 0))
        b.box((x, y - 0.05, z), (1.0, 0.04, 0.05), R["wood_dark"])
        b.box((x, y - 0.05, z), (0.05, 0.04, 1.0), R["wood_dark"])
    if chimney:
        cx, cy = rx * 0.28, ry * 0.2
        cz = h * math.sqrt(max(0, 1 - (cx / rx) ** 2 - (cy / ry) ** 2)) - 0.15
        parts.chimney(b, R, cx, cy, cz, 0.9, 0.55)
    for i in range(6):  # flagstone path
        b.cyl((rng.uniform(-0.25, 0.25) + math.sin(i * 0.7) * 0.4, dy - 1.1 - i * 0.95, 0), 0.5 + rng.random() * 0.12, 0.08,
              [R["rock_mid"], R["rock_light"]][i % 2], 7, rot=(0, 0, rng.random()))
    with b.collision():
        b.dome((0, 0, 0), (rx, ry, h), None, 8, 3)


def hobbit_cottage(b, R, variant=0):
    rng = b.rng
    w, d, wh = [(6.4, 4.6, 2.5), (7.2, 4.8, 2.6), (5.6, 4.4, 2.4)][variant]
    wall = [R["plaster"], R["brick"], R["plaster"]][variant]
    roofc = [R["thatch"], R["roof_tile"], R["thatch"]][variant]
    b.box((0, 0, 0.2), (w + 0.3, d + 0.3, 0.4), R["rock_mid"])
    b.box((0, 0, 0.4 + wh / 2), (w, d, wh), wall)
    b.gable(-w / 2, -d / 2, w / 2, d / 2, 0.4 + wh, 1.9, wall, roofc, 0.4, 0.22 if roofc == R["thatch"] else 0.14, "x")
    parts.door(b, R, (-w * 0.18, -d / 2, 0.4), "-y", 0.95, 0.95, [R["door_red"], R["door_green"], R["door_yellow"]][variant], round_=True)
    for sx in (w * 0.2, w * 0.38):
        parts.window(b, R, (sx - 0.1 if sx > w * 0.3 else sx, -d / 2, 1.7), "-y", 0.7, 0.8, shutters=R["door_green"] if variant != 1 else R["door_blue"], round_=(variant == 2))
    parts.window(b, R, (w / 2, -0.4, 1.8), "+x", 0.6, 0.7)
    parts.window(b, R, (0, d / 2, 1.8), "+y", 0.7, 0.8)
    parts.chimney(b, R, w / 2 - 0.5, 0.4, 0.4 + wh + 0.9 - 0.2, 1.3, 0.7, R["rock_mid"] if variant != 1 else R["brick"])
    if variant == 1:  # porch
        b.gable(-w * 0.18 - 1.0, -d / 2 - 1.1, -w * 0.18 + 1.0, -d / 2, 2.1, 0.55, wall, R["roof_tile"], 0.15, 0.1, "y")
        for sx in (-1, 1):
            b.box((-w * 0.18 + sx * 0.9, -d / 2 - 1.0, 1.05), (0.12, 0.12, 2.1), R["wood_dark"])
    if variant == 2:  # lean-to store and flower box
        b.box((w / 2 + 0.9, 0.3, 1.0), (1.6, 3.0, 2.0), R["wood"])
        b.gable(w / 2 + 0.1, -1.4, w / 2 + 1.7, 2.0, 2.0, 0.5, R["wood"], R["thatch_dark"], 0.15, 0.1, "y")
        b.box((w * 0.3, -d / 2 - 0.2, 1.1), (1.0, 0.25, 0.2), R["wood"])
        for i in range(4):
            b.blob((w * 0.3 - 0.37 + i * 0.25, -d / 2 - 0.2, 1.3), (0.12, 0.1, 0.1), [R["flower_red"], R["flower_yellow"]][i % 2], 0, 0)
    for i in range(3):  # garden bushes
        b.blob((-w / 2 + 0.8 + i * 1.2, -d / 2 - 0.6, 0.35), (0.5, 0.45, 0.4), R["grass_mid"], 1, 0.2)
    with b.collision():
        b.box((0, 0, (wh + 2.3) / 2), (w + 0.3, d + 0.3, wh + 2.3))


def mill(b, R):
    w, d, wh = 6.6, 5.6, 4.0
    b.box((0, 0, 0.3), (w + 0.4, d + 0.4, 0.6), R["rock_dark"])
    b.box((0, 0, 0.6 + wh / 2), (w, d, wh), R["plaster_dark"], top=(0.97, 0.97))
    b.box((0, 0, 0.6 + wh * 0.5), (w + 0.04, d + 0.04, 0.2), R["wood_dark"])
    b.gable(-w / 2, -d / 2, w / 2, d / 2, 0.6 + wh, 2.4, R["plaster_dark"], R["thatch"], 0.5, 0.25, "x")
    parts.door(b, R, (1.0, -d / 2, 0.6), "-y", 1.3, 2.0, R["door_red"])
    parts.window(b, R, (-1.6, -d / 2, 3.0), "-y", 0.8, 1.0)
    parts.window(b, R, (0.9, -d / 2, 4.1), "-y", 0.7, 0.8)
    b.box((0, -d / 2 - 0.5, 4.6), (0.15, 1.4, 0.15), R["wood_dark"])  # hoist beam
    b.box((0, -d / 2 - 1.0, 4.0), (0.8, 0.8, 0.8), R["hay"])
    parts.chimney(b, R, -w / 2 + 0.6, 1.0, 5.6, 1.5, 0.7)
    for i in range(5):
        b.blob((-1.6 + i * 0.8, -d / 2 - 0.9, 0.5), (0.35, 0.3, 0.3), R["hay"], 0, 0.1)
    # wheel on the east side (+x), axis along x
    wr, ww = 2.4, 0.9
    wx = w / 2 + 0.55
    wy, wz = 0.0, 2.5
    b.cyl((w / 2, wy, wz), 0.28, 1.1, R["wood_dark"], 8, rot=(0, PI / 2, 0))
    n = 10
    for side in (0.0, 0.65):
        for i in range(n):
            a0, a1 = i * math.tau / n, (i + 1) * math.tau / n
            p0 = (w / 2 + 0.15 + side, wy + math.cos(a0) * wr, wz + math.sin(a0) * wr)
            p1 = (w / 2 + 0.15 + side, wy + math.cos(a1) * wr, wz + math.sin(a1) * wr)
            b.beam(p0, p1, 0.12, 0.2, R["wood"])
            b.beam((w / 2 + 0.15 + side, wy, wz), p0, 0.1, 0.1, R["wood_dark"])
    for i in range(n):
        a = (i + 0.5) * math.tau / n
        b.box((w / 2 + 0.47, wy + math.cos(a) * (wr - 0.05), wz + math.sin(a) * (wr - 0.05)), (0.75, 0.08, 0.55), R["wood_dark"], rot=(a - PI / 2, 0, 0) if False else (0, 0, 0))
    b.box((w / 2 + 0.5, -2.5, 4.6), (0.3, 4.4, 0.3), R["wood"])  # race trough
    b.box((w / 2 + 0.5, -4.5, 4.2), (0.3, 0.3, 1.0), R["wood_dark"])
    with b.collision():
        b.box((0, 0, 3.3), (w + 0.4, d + 0.4, 6.6))


def inn(b, R, kind="dragon"):
    rng = b.rng
    if kind == "dragon":
        w, d, wh = 11.0, 5.4, 2.7
        wall, roofc, band = R["plaster"], R["thatch"], R["door_green"]
    else:
        w, d, wh = 8.6, 6.4, 2.6
        wall, roofc, band = R["brick"], R["roof_tile"], R["door_yellow"]
    b.box((0, 0, 0.2), (w + 0.3, d + 0.3, 0.4), R["rock_mid"])
    b.box((0, 0, 0.4 + wh / 2), (w, d, wh), wall)
    b.gable(-w / 2, -d / 2, w / 2, d / 2, 0.4 + wh, 2.2 if kind == "dragon" else 2.6, wall, roofc, 0.5, 0.25 if kind == "dragon" else 0.15, "x")
    if kind == "perch":
        b.box((0, 0, 0.4 + wh + 1.2), (w - 1, d - 1, 2.4), wall)  # attic-ish upper volume hidden under roof
        for sx in (-2.4, 2.4):
            b.gable(sx - 0.9, -d / 2 + 0.4, sx + 0.9, -d / 2 + 2.0, 0.4 + wh + 0.9, 0.9, wall, R["roof_tile"], 0.1, 0.1, "y")
            parts.window(b, R, (sx, -d / 2 + 2.0, 0.4 + wh + 0.55), "-y", 0.6, 0.7)
    parts.door(b, R, (0.0, -d / 2, 0.4), "-y", 1.6, 2.0, band)
    for sx in (-4.2, -2.4, 2.4, 4.2) if kind == "dragon" else (-3.2, -1.8, 1.8, 3.2):
        parts.window(b, R, (sx, -d / 2, 1.8), "-y", 0.8, 0.9, shutters=band)
    parts.window(b, R, (w / 2, 0, 1.8), "+x", 0.8, 0.9)
    parts.window(b, R, (-w / 2, 0, 1.8), "-x", 0.8, 0.9)
    parts.chimney(b, R, -w / 2 + 1.2, 0.6, 0.4 + wh + 1.1, 1.4, 0.9)
    parts.chimney(b, R, w / 2 - 1.2, -0.4, 0.4 + wh + 1.1, 1.4, 0.9)
    # hanging sign on a post
    px = 2.9 if kind == "dragon" else 2.4
    b.box((px, -d / 2 - 1.8, 1.6), (0.18, 0.18, 3.2), R["wood_dark"])
    b.box((px - 0.8, -d / 2 - 1.8, 3.0), (1.7, 0.1, 0.1), R["wood_dark"])
    sc = R["door_green"] if kind == "dragon" else R["brass"]
    b.box((px - 1.25, -d / 2 - 1.8, 2.5), (0.95, 0.07, 0.8), R["wood_dark"])
    b.box((px - 1.25, -d / 2 - 1.85, 2.5), (0.8, 0.05, 0.65), sc)
    b.blob((px - 1.25, -d / 2 - 1.9, 2.5), (0.22, 0.05, 0.16), R["brass"] if kind == "dragon" else R["wood_dark"], 0, 0)
    for i in range(3):
        parts.barrel(b, R, (-3.6 + i * 0.8, -d / 2 - 0.55, 0.0), 0.8, 0.33)
    b.box((-1.6, -d / 2 - 0.9, 0.35), (1.6, 0.5, 0.1), R["wood"])
    for sx in (-2.2, -1.0):
        b.box((sx, -d / 2 - 0.9, 0.17), (0.08, 0.4, 0.34), R["wood_dark"])
    with b.collision():
        b.box((0, 0, 3.0), (w + 0.3, d + 0.3, 6.0))


def fence(b, R, style_="rail", length=2.0):
    h = 1.05
    if style_ == "rail":
        for x in (-length / 2, length / 2):
            b.box((x, 0, h / 2), (0.14, 0.14, h), R["bark_light"], top=(0.8, 0.8))
        for z in (0.4, 0.78):
            b.box((0, 0, z), (length, 0.08, 0.1), R["wood"], rot=(0, b.rng.uniform(-0.02, 0.02), 0))
    elif style_ == "picket":
        for x in (-length / 2, length / 2):
            b.box((x, 0, 0.55), (0.12, 0.12, 1.1), R["plaster"])
        for z in (0.3, 0.75):
            b.box((0, 0.07, z), (length, 0.05, 0.09), R["plaster_dark"])
        n = 8
        for i in range(n):
            x = -length / 2 + (i + 0.5) * length / n
            b.box((x, -0.03, 0.5), (0.13, 0.03, 0.95), R["plaster"], top=(0.12, 1.0))
    else:  # dry-stone wall
        rng = b.rng
        n = 5
        for row in range(2):
            for i in range(n):
                x = -length / 2 + (i + 0.5 + 0.5 * row) * length / n
                if x > length / 2:
                    continue
                b.blob((x, rng.uniform(-0.05, 0.05), 0.2 + row * 0.3), (length / n * 0.62, 0.3, 0.2), [R["rock_mid"], R["rock_light"], R["rock_dark"]][(i + row) % 3], 1, 0.2)
        b.box((0, 0, 0.62), (length, 0.35, 0.1), R["grass_mid"])
    with b.collision():
        b.box((0, 0, h / 2), (length, 0.3, h))


def gate(b, R, style_="rail"):
    wood = R["wood"] if style_ == "rail" else R["plaster"]
    dark = R["wood_dark"] if style_ == "rail" else R["plaster_dark"]
    for x in (-1.0, 1.0):
        b.box((x, 0, 0.6), (0.18, 0.18, 1.2), R["bark_light"] if style_ == "rail" else R["plaster"], top=(0.85, 0.85))
    for z in (0.25, 0.6, 0.95):
        b.box((-0.05, 0, z), (1.75, 0.07, 0.1), wood)
    b.box((-0.85, 0, 0.6), (0.1, 0.08, 0.85), dark)
    b.box((0.7, 0, 0.6), (0.1, 0.08, 0.85), dark)
    b.beam((-0.85, 0, 0.22), (0.7, 0, 0.97), 0.1, 0.07, dark)
    b.box((0.75, -0.1, 0.65), (0.08, 0.08, 0.12), R["metal"])
    with b.collision():
        b.box((0, 0, 0.6), (2.2, 0.3, 1.2))


def garden(b, R, variant=0):
    rng = b.rng
    b.box((0, 0, 0.04), (4.0, 4.0, 0.08), R["soil"])
    for ex in (-2.0, 2.0):
        b.box((ex, 0, 0.12), (0.12, 4.0, 0.24), R["wood"])
        b.box((0, ex, 0.12), (4.0, 0.12, 0.24), R["wood"])
    for r in range(3):
        y = -1.2 + r * 1.2
        b.box((0, y, 0.12), (3.4, 0.7, 0.16), R["soil"], top=(0.9, 0.85))
        for i in range(5):
            x = -1.4 + i * 0.7
            if variant == 0:  # cabbages & carrots
                if r == 1:
                    b.blob((x, y, 0.3), (0.26, 0.26, 0.2), [R["grass_light"], R["grass_mid"]][i % 2], 1, 0.15)
                else:
                    for k in range(3):
                        b.cone((x + k * 0.1 - 0.1, y + k * 0.08, 0.15), 0.12, 0.32, R["grass_mid"], 4)
            elif variant == 1:  # bean poles
                if i % 2 == 0:
                    b.beam((x, y - 0.2, 0.1), (x, y, 1.5), 0.04, 0.04, R["bark_light"])
                    b.beam((x, y + 0.2, 0.1), (x, y, 1.5), 0.04, 0.04, R["bark_light"])
                    b.blob((x, y, 0.8), (0.2, 0.2, 0.55), R["grass_mid"], 1, 0.2)
                else:
                    b.blob((x, y, 0.28), (0.2, 0.2, 0.14), R["grass_light"], 0, 0.2)
            else:  # flowers & herbs
                col = [R["flower_yellow"], R["flower_purple"], R["flower_white"], R["flower_red"]][(i + r) % 4]
                b.blob((x, y, 0.28), (0.28, 0.28, 0.22), R["grass_mid"], 1, 0.2)
                b.blob((x, y, 0.45), (0.14, 0.14, 0.1), col, 0, 0.1)
    if variant == 1:
        b.beam((-1.4, 1.6, 0.8), (1.4, 1.6, 0.8), 0.05, 0.05, R["bark_light"])
    with b.collision():
        b.box((0, 0, 0.12), (4.0, 4.0, 0.24))


def well(b, R, variant=0):
    stone = variant == 0
    rr = 0.95
    b.cyl((0, 0, 0), rr, 0.95, R["rock_mid"] if stone else R["wood"], 10, top_r=rr * 0.93)
    b.cyl((0, 0, 0.95), rr * 1.0, 0.1, R["rock_light"] if stone else R["wood_dark"], 10)
    b.cyl((0, 0, 0.6), rr * 0.8, 0.02, R["water"], 10)
    if stone:
        for i in range(10):
            a = i * math.tau / 10
            b.box((math.cos(a) * rr * 0.97, math.sin(a) * rr * 0.97, 0.5), (0.05, 0.05, 0.9), R["rock_dark"], rot=(0, 0, a))
    for s in (-1, 1):
        b.box((s * 1.0, 0, 1.0), (0.14, 0.14, 2.0), R["wood_dark"])
    b.cyl((-1.05, 0, 1.75), 0.1, 2.1, R["bark_light"], 6, rot=(0, PI / 2, 0))
    b.gable(-1.25, -0.8, 1.25, 0.8, 2.05, 0.8, R["wood"], R["thatch"] if variant == 0 else R["roof_tile"], 0.25, 0.14, "x")
    b.beam((0, 0, 1.75), (0, 0, 1.0), 0.015, 0.015, R["metal"])
    b.cyl((0, 0, 0.85), 0.16, 0.2, R["wood"], 7, top_r=0.14)
    with b.collision():
        b.cyl((0, 0, 0), 1.0, 1.0, None, 8)


def bridge_small(b, R, variant=0):
    L, W = 6.0, 2.0
    if variant == 0:  # wooden plank
        n = 14
        for i in range(n):
            b.box((-L / 2 + (i + 0.5) * L / n, 0, 0.55), (L / n - 0.03, W, 0.1), R["wood"] if i % 2 else R["bark_light"])
        for y in (-0.7, 0.7):
            b.box((0, y, 0.4), (L + 0.4, 0.2, 0.2), R["wood_dark"])
        for sy in (-1, 1):
            for i in range(5):
                x = -L / 2 + 0.2 + i * (L - 0.4) / 4
                b.box((x, sy * (W / 2 - 0.05), 0.6), (0.12, 0.12, 0.9), R["wood_dark"])
            b.box((0, sy * (W / 2 - 0.05), 1.05), (L, 0.1, 0.1), R["wood"])
            b.box((0, sy * (W / 2 - 0.05), 0.75), (L, 0.07, 0.08), R["wood"])
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.cyl((sx * (L / 2 - 0.3), sy * 0.7, -0.6), 0.1, 1.0, R["bark"], 5)
        with b.collision("colonly"):
            b.box((0, 0, 0.5), (L + 0.2, W, 0.22))
    else:  # stone arch
        pts = [(-L / 2 - 0.3, 0), (-2.0, 0)]
        for k in range(1, 8):
            a = PI - k * PI / 8
            pts.append((math.cos(a) * 2.0, math.sin(a) * 1.1))
        pts += [(2.0, 0), (L / 2 + 0.3, 0), (L / 2 + 0.3, 1.4), (-L / 2 - 0.3, 1.4)]
        b.prism(pts, W, R["rock_mid"])
        for sy in (-1, 1):
            b.box((0, sy * (W / 2 - 0.15), 1.7), (L + 0.6, 0.3, 0.6), R["rock_light"])
            for i in range(5):
                b.box((-2.4 + i * 1.2, sy * (W / 2 - 0.15), 1.45), (0.5, 0.32, 0.12), R["rock_dark"])
        with b.collision("colonly"):
            b.box((0, 0, 0.7), (L + 0.6, W, 1.4))


def brandywine_bridge(b, R):
    L, W, H = 36.0, 5.0, 3.4
    span, pier = 8.0, 3.0
    pts = [(-L / 2, 0)]
    x = -L / 2 + 1.5
    for i in range(3):
        pts.append((x, 0))
        for k in range(1, 9):
            a = PI - k * PI / 9
            pts.append((x + span / 2 + math.cos(a) * span / 2, math.sin(a) * 2.6))
        pts.append((x + span, 0))
        x += span + pier
    pts += [(L / 2, 0), (L / 2, H), (-L / 2, H)]
    b.prism(pts, W, R["rock_mid"])
    for sy in (-1, 1):
        b.box((0, sy * (W / 2 - 0.2), H + 0.4), (L, 0.4, 0.8), R["rock_light"])
        b.box((0, sy * (W / 2 - 0.2), H + 0.82), (L + 0.1, 0.5, 0.1), R["rock_mid"])
        for i in range(16):
            b.box((-L / 2 + 1 + i * (L - 2) / 15, sy * (W / 2 - 0.2), H + 0.5), (0.7, 0.44, 0.15), R["rock_dark"])
    b.box((0, 0, H + 0.04), (L, W - 1.0, 0.1), R["path_mid"])
    # cutwaters on the piers
    x = -L / 2 + 1.5 + span
    for i in range(2):
        for sy in (-1, 1):
            b.box((x + pier / 2, sy * (W / 2 + 0.15), 1.0), (pier * 0.9, 0.4, 2.0), R["rock_dark"], top=(0.6, 1.0))
        x += span + pier
    # gate house + lamp posts at the east end
    gx = L / 2 - 2.2
    for sy in (-1, 1):
        b.box((gx, sy * (W / 2 + 0.6), H + 1.2), (1.6, 1.2, 2.4), R["plaster_dark"])
    b.gable(gx - 0.9, -W / 2 - 1.3, gx + 0.9, W / 2 + 1.3, H + 2.4, 0.9, R["plaster_dark"], R["thatch"], 0.4, 0.2, "y")
    for x in (-L / 2 + 0.6, L / 2 - 0.6):
        for sy in (-1, 1):
            b.box((x, sy * (W / 2 - 0.2), H + 1.5), (0.14, 0.14, 1.2), R["wood_dark"])
            parts.lantern(b, R, (x, sy * (W / 2 - 0.2), H + 2.1))
    with b.collision("colonly"):
        b.box((0, 0, H / 2), (L, W, H))
        b.box((0, W / 2 - 0.2, H + 0.4), (L, 0.4, 0.8))
        b.box((0, -W / 2 + 0.2, H + 0.4), (L, 0.4, 0.8))


def ferry_raft(b, R):
    L, W = 5.0, 3.2
    n = 12
    for i in range(n):
        b.box((-L / 2 + (i + 0.5) * L / n, 0, 0.3), (L / n - 0.04, W, 0.1), R["wood"] if i % 3 else R["bark_light"])
    for y in (-1.1, 0, 1.1):
        b.box((0, y, 0.2), (L + 0.2, 0.2, 0.14), R["wood_dark"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cyl((sx * (L / 2 - 0.2), sy * (W / 2 - 0.15), 0.25), 0.07, 1.0, R["wood_dark"], 5)
    for sy in (-1, 1):
        b.beam((-L / 2 + 0.2, sy * (W / 2 - 0.15), 1.1), (L / 2 - 0.2, sy * (W / 2 - 0.15), 1.0), 0.04, 0.04, R["thatch"])
    for sx in (-1, 1):
        b.beam((sx * (L / 2 - 0.2), -W / 2 + 0.15, 0.75), (sx * (L / 2 - 0.2), W / 2 - 0.15, 0.75), 0.04, 0.04, R["thatch"])
    b.cyl((-1.8, 0.9, 0.38), 0.05, 4.2, R["bark_light"], 5, rot=(0, PI / 2 + 0.05, 0))  # punt pole
    for y in (-1.0, 1.0):
        b.cyl((-L / 2 + 0.3, y, -0.25), 0.28, 0.55, R["wood_dark"], 7)
        b.cyl((L / 2 - 0.3, y, -0.25), 0.28, 0.55, R["wood_dark"], 7)
    b.cyl((1.3, -0.4, 0.35), 0.28, 0.14, R["thatch"], 7)  # rope coil
    with b.collision("colonly"):
        b.box((0, 0, 0.25), (L + 0.2, W, 0.3))


def three_farthing_stone(b, R):
    rng = b.rng
    b.dome((0, 0, -0.1), (1.9, 1.9, 0.5), R["grass_mid"], 8, 2, jitter=0.05)
    b.box((0, 0, 1.6), (0.9, 0.7, 3.2), R["rock_light"], rot=(0.03, -0.04, 0.4), top=(0.62, 0.7))
    b.box((0, 0, 3.25), (0.55, 0.45, 0.25), R["rock_mid"], rot=(0.03, -0.04, 0.4), top=(0.5, 0.6))
    b.box((0, -0.36, 1.5), (0.5, 0.05, 0.12), R["rock_dark"], rot=(0, 0, 0.4))
    b.box((0, -0.36, 1.2), (0.38, 0.05, 0.1), R["rock_dark"], rot=(0, 0, 0.4))
    for i in range(6):
        a = i * math.tau / 6 + 0.3
        b.blob((math.cos(a) * 1.0, math.sin(a) * 1.0, 0.2), (0.4, 0.35, 0.28), [R["rock_mid"], R["rock_dark"]][i % 2], 1, 0.25)
    for i in range(3):
        b.blob((math.cos(i * 2.1) * 0.5, math.sin(i * 2.1) * 0.5, 0.14), (0.18, 0.18, 0.1), R["flower_yellow"], 0, 0)
    with b.collision():
        b.cyl((0, 0, 0), 0.55, 3.3, None, 6)


def specs():
    out = []
    holes = [(5.8, "door_green", 2, True), (6.8, "door_red", 1, True), (7.6, "door_yellow", 3, False), (6.2, "door_blue", 2, True)]
    for v, (r, d, wn, ch) in enumerate(holes):
        out.append(Spec(f"hobbit_hole_{v + 1}", "shire", "house", 300 + v,
                        lambda b, R, r=r, d=d, wn=wn, ch=ch: hobbit_hole(b, R, r, d, wn, ch)))
    for v in range(3):
        out.append(Spec(f"hobbit_cottage_{v + 1}", "shire", "house", 310 + v, lambda b, R, v=v: hobbit_cottage(b, R, v)))
    out.append(Spec("mill_water", "shire", "house", 320, mill))
    out.append(Spec("inn_green_dragon", "shire", "house", 321, lambda b, R: inn(b, R, "dragon")))
    out.append(Spec("inn_golden_perch", "shire", "house", 322, lambda b, R: inn(b, R, "perch")))
    for s in ("rail", "picket", "stone"):
        out.append(Spec(f"fence_{s}", "shire", "structure", 330, lambda b, R, s=s: fence(b, R, s), lods=False))
    for s in ("rail", "picket"):
        out.append(Spec(f"gate_{s}", "shire", "structure", 335, lambda b, R, s=s: gate(b, R, s), lods=False))
    for v in range(3):
        out.append(Spec(f"garden_plot_{v + 1}", "shire", "structure", 340 + v, lambda b, R, v=v: garden(b, R, v)))
    for v in range(2):
        out.append(Spec(f"well_{v + 1}", "shire", "structure", 345 + v, lambda b, R, v=v: well(b, R, v), lods=False))
    out.append(Spec("bridge_small_wood", "shire", "structure", 350, lambda b, R: bridge_small(b, R, 0)))
    out.append(Spec("bridge_small_stone", "shire", "structure", 351, lambda b, R: bridge_small(b, R, 1)))
    out.append(Spec("bridge_brandywine", "shire", "bigstructure", 352, brandywine_bridge))
    out.append(Spec("ferry_raft", "shire", "structure", 353, ferry_raft))
    out.append(Spec("three_farthing_stone", "shire", "structure", 354, three_farthing_stone))
    return out
