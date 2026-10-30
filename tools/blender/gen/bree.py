"""Bree-land buildings: stone/timber houses, hobbit-sized houses, the Prancing Pony, gates, dike and hedge, Bill Ferny's house."""
from __future__ import annotations

import math

from lib import parts
from lib.geo import m
from . import Spec

PI = math.pi


def house(b, R, w=7.0, d=5.2, floors=2, wall="stone", roof="slate", hobbit=False, jetty=False, wing=False, seed_tilt=0.0):
    fh = 2.1 if hobbit else 2.7
    wh = fh * floors
    wallc = {"stone": R["rock_mid"], "timber": R["plaster"], "plaster": R["plaster"]}[wall]
    roofc = {"slate": R["slate"], "thatch": R["thatch"], "tile": R["roof_tile"]}[roof]
    b.box((0, 0, 0.2), (w + 0.3, d + 0.3, 0.4), R["rock_dark"])
    z0 = 0.4
    if wall == "stone":
        b.box((0, 0, z0 + wh / 2), (w, d, wh), wallc)
        for i in range(floors - 1):  # string course
            b.box((0, 0, z0 + fh * (i + 1)), (w + 0.1, d + 0.1, 0.14), R["rock_light"])
        for sx in (-1, 1):  # corner quoins
            for sy in (-1, 1):
                b.box((sx * w / 2, sy * d / 2, z0 + wh / 2), (0.3, 0.3, wh), R["rock_light"], top=(1, 1))
    else:
        b.box((0, 0, z0 + fh / 2), (w, d, fh), wallc)
        ow = 0.4 if jetty else 0
        if floors > 1:
            b.box((0, -ow / 2, z0 + fh + (wh - fh) / 2), (w + ow, d + ow, wh - fh), wallc)
            if jetty:
                for x in range(-2, 3):
                    b.box((x * w / 5, -d / 2 - 0.1, z0 + fh - 0.08), (0.18, 0.5, 0.2), R["wood_dark"])
        parts.timber_wall(b, R, -w / 2, w / 2, -d / 2, z0, z0 + fh, "-y")
        parts.timber_wall(b, R, -w / 2, w / 2, d / 2, z0, z0 + fh, "+y")
        if floors > 1:
            parts.timber_wall(b, R, -w / 2 - ow / 2, w / 2 + ow / 2, -d / 2 - ow, z0 + fh, z0 + wh, "-y")
            parts.timber_wall(b, R, -w / 2, w / 2, d / 2, z0 + fh, z0 + wh, "+y")
    rise = 1.3 if hobbit else 2.2
    b.gable(-w / 2, -d / 2, w / 2, d / 2, z0 + wh, rise, wallc if wall != "timber" else R["plaster"], roofc, 0.4,
            0.24 if roof == "thatch" else 0.12, "x")
    if hobbit:
        parts.door(b, R, (-w * 0.2, -d / 2, z0), "-y", 0.9, 0.9, R["door_green"], round_=True)
        parts.window(b, R, (w * 0.18, -d / 2 - (0.0), z0 + 1.2), "-y", 0.6, 0.6, round_=True)
        parts.window(b, R, (w * 0.36, -d / 2, z0 + 1.2), "-y", 0.6, 0.6, round_=True)
    else:
        parts.door(b, R, (-0.0 if floors > 1 else -w * 0.2, -d / 2 - (0.2 if jetty and False else 0), z0), "-y", 1.1, 2.0, R["door_red"])
        n = 3 if w > 6 else 2
        for f in range(floors):
            for i in range(n):
                x = -w / 2 + (i + 0.5) * w / n + (0.0)
                if f == 0 and abs(x) < 0.9:
                    continue
                yo = -0.4 if (jetty and f == 1) else 0.0
                parts.window(b, R, (x, -d / 2 + yo, z0 + f * fh + 1.5), "-y", 0.7, 1.0, shutters=(R["door_blue"] if f else False))
        parts.window(b, R, (w / 2, 0, z0 + 1.6), "+x", 0.7, 1.0)
        if floors > 1:
            parts.window(b, R, (w / 2, 0, z0 + fh + 1.5), "+x", 0.7, 1.0)
            parts.window(b, R, (-w / 2, 0.8, z0 + fh + 1.5), "-x", 0.7, 1.0)
    parts.chimney(b, R, w / 2 - 0.9, 0.3, z0 + wh + rise * 0.6, 1.1 if not hobbit else 0.8, 0.7, R["rock_mid"])
    if w > 6.5:
        parts.chimney(b, R, -w / 2 + 0.9, -0.3, z0 + wh + rise * 0.6, 1.1, 0.7, R["rock_mid"])
    if wing:
        ww, wd = 3.8, 4.4
        wx, wy = w / 2 - ww / 2, d / 2 + wd / 2 - 0.3
        b.box((wx, wy, z0 + fh / 2), (ww, wd, fh), wallc)
        b.gable(wx - ww / 2, wy - wd / 2, wx + ww / 2, wy + wd / 2, z0 + fh, 1.6, wallc, roofc, 0.3, 0.14, "y")
        parts.window(b, R, (wx, wy + wd / 2, z0 + 1.4), "+y", 0.7, 0.9)
        parts.window(b, R, (wx + ww / 2, wy, z0 + 1.4), "+x", 0.7, 0.9)
    parts.barrel(b, R, (-w / 2 + 0.6, -d / 2 - 0.9, 0), 0.8, 0.3)
    with b.collision():
        b.box((0, 0, (wh + rise + 0.4) / 2), (w + 0.3, d + 0.3, wh + rise + 0.4))
    if wing:
        with b.collision("colonly"):
            b.box((0, 0, (wh + rise + 0.4) / 2), (w + 0.3, d + 0.3, wh + rise + 0.4))
            b.box((w / 2 - 1.9, d / 2 + 1.9, 1.7), (3.8, 4.4, 3.4))


def prancing_pony(b, R):
    z0 = 0.4
    fh = 2.9
    W, D = 17.0, 6.4          # main block along x, front at y=-D/2 .. back y=+D/2
    H = 2 * fh
    arch = 3.6
    # main block, split around the carriage arch
    for (x0, x1) in ((-W / 2, -arch / 2), (arch / 2, W / 2)):
        b.box(((x0 + x1) / 2, 0, z0 + H / 2), (x1 - x0, D, H), R["plaster"])
    b.box((0, 0, z0 + 3.3 + (H - 3.3) / 2), (arch, D, H - 3.3), R["plaster"])
    b.box((0, -D / 2 - 0.05, z0 + 3.35), (arch + 0.5, 0.3, 0.4), R["rock_light"])
    b.box((0, 0, z0 + 0.04), (arch, D + 0.1, 0.08), R["rock_dark"])
    b.box((0, 0, 0.2), (W + 0.4, D + 0.4, 0.4), R["rock_dark"])
    for i in range(2):
        parts.timber_wall(b, R, -W / 2, W / 2, -D / 2, z0 + fh * i + (0 if i == 0 else 0), z0 + fh * (i + 1), "-y", 1.4, diag=False)
    b.gable(-W / 2, -D / 2, W / 2, D / 2, z0 + H, 2.8, R["plaster"], R["slate"], 0.6, 0.16, "x")
    # wings along +y (courtyard between them)
    wl = 13.0
    for side, (wx, kind) in enumerate(((-W / 2 + 2.6, "rooms"), (W / 2 - 2.6, "stable"))):
        ww = 5.2
        cy = D / 2 + wl / 2 - 0.4
        if kind == "rooms":
            b.box((wx, cy, z0 + H / 2), (ww, wl, H), R["plaster"])
            b.gable(wx - ww / 2, cy - wl / 2, wx + ww / 2, cy + wl / 2, z0 + H, 2.3, R["plaster"], R["slate"], 0.5, 0.14, "y")
            for i in range(4):
                for f in range(2):
                    parts.window(b, R, (wx + ww / 2, cy - wl / 2 + 1.6 + i * 3.0, z0 + f * fh + 1.6), "+x", 0.7, 1.0)
                    parts.window(b, R, (wx - ww / 2, cy - wl / 2 + 1.6 + i * 3.0, z0 + f * fh + 1.6), "-x", 0.7, 1.0)
        else:
            sh = 3.2
            b.box((wx, cy, z0 + sh / 2), (ww, wl, sh), R["wood"])
            b.gable(wx - ww / 2, cy - wl / 2, wx + ww / 2, cy + wl / 2, z0 + sh, 1.9, R["wood"], R["thatch"], 0.5, 0.24, "y")
            for i in range(3):  # open stable bays facing the courtyard
                by = cy - wl / 2 + 2.4 + i * 3.8
                b.box((wx - ww / 2 - 0.02, by, z0 + 1.2), (0.06, 2.0, 2.4), R["wood_dark"])
                b.box((wx - ww / 2 - 0.1, by, z0 + 0.5), (0.1, 2.0, 1.0), R["wood_dark"])
                b.box((wx - ww / 2 - 0.45, by, z0 + 0.25), (0.8, 1.6, 0.5), R["hay"])
                b.blob((wx - ww / 2 - 0.5, by + 0.2, z0 + 0.7), (0.4, 0.4, 0.3), R["hay"], 1, 0.2)
    # back wall + gate pillars
    b.box((0, D / 2 + wl - 0.2, 1.2), (W - 10.4, 0.5, 2.4), R["rock_mid"])
    for sx in (-1, 1):
        b.box((sx * (W - 10.4) / 2, D / 2 + wl - 0.2, 1.5), (0.8, 0.8, 3.0), R["rock_light"])
    b.box((0, D / 2 + wl / 2, 0.06), (W - 10.4, wl, 0.1), R["path_mid"])  # cobbled yard
    for i in range(6):  # yard clutter
        parts.barrel(b, R, (-1.5 + i * 0.5 if i < 3 else 1.2 + (i - 3) * 0.4, D / 2 + 2.0 + (i // 3) * 0.6, 0), 0.8, 0.3)
    parts.crate(b, R, (1.0, D / 2 + 4.0, 0), 0.7, 0.4)
    # front details
    parts.door(b, R, (-5.8, -D / 2, z0), "-y", 1.5, 2.2, R["door_red"])
    for f in range(2):
        for x in (-7.2, -3.6, 3.8, 6.2, 7.6):
            if f == 0 and x == -7.2:
                continue
            parts.window(b, R, (x, -D / 2, z0 + f * fh + 1.7), "-y", 0.8, 1.1, shutters=R["door_green"] if f else False)
    for x in (-5.0, 5.2):
        b.gable(x - 1.0, -D / 2 + 0.5, x + 1.0, -D / 2 + 2.0, z0 + H + 0.3, 1.0, R["plaster"], R["slate"], 0.2, 0.1, "y")
        parts.window(b, R, (x, -D / 2 + 2.0, z0 + H + 0.9), "-y", 0.6, 0.7)
    for x in (-6.5, -1.5, 5.5, 7.5):
        parts.chimney(b, R, x, 0.5, z0 + H + 1.6, 1.4, 0.8)
    # hanging sign (white pony)
    b.box((-3.6, -D / 2 - 2.3, 2.0), (0.18, 0.18, 4.0), R["wood_dark"])
    b.box((-3.6, -D / 2 - 1.2, 3.8), (0.1, 2.4, 0.1), R["metal"])
    b.box((-3.6, -D / 2 - 1.6, 3.0), (0.07, 1.3, 1.1), R["wood_dark"])
    b.box((-3.7, -D / 2 - 1.6, 3.0), (0.04, 1.15, 0.95), R["door_blue"])
    b.blob((-3.75, -D / 2 - 1.6, 3.0), (0.04, 0.38, 0.22), R["flower_white"], 1, 0.1)
    b.blob((-3.75, -D / 2 - 1.95, 3.25), (0.04, 0.14, 0.14), R["flower_white"], 0, 0)
    parts.lantern(b, R, (-0.0 - 3.6, -D / 2 - 0.3, 2.5))
    with b.collision("colonly"):
        for (x0, x1) in ((-W / 2, -arch / 2), (arch / 2, W / 2)):
            b.box(((x0 + x1) / 2, 0, 4.0), (x1 - x0, D, 8.0))
        b.box((0, 0, 6.2), (arch, D, 3.6))
        b.box((-W / 2 + 2.6, D / 2 + wl / 2 - 0.4, 4.0), (5.2, wl, 8.0))
        b.box((W / 2 - 2.6, D / 2 + wl / 2 - 0.4, 2.5), (5.2, wl, 5.0))
        b.box((0, D / 2 + wl - 0.2, 1.2), (W - 10.4, 0.5, 2.4))


def gate(b, R, variant=0):
    for sx in (-1, 1):
        b.box((sx * 3.2, 0, 2.0), (0.7, 0.7, 4.0), R["wood"], top=(0.9, 0.9))
        b.box((sx * 3.2, 0, 4.1), (0.9, 0.9, 0.2), R["wood_dark"])
        b.box((sx * 3.2, 0, 0.2), (1.0, 1.0, 0.4), R["rock_mid"])
    b.box((0, 0, 4.2), (7.4, 0.5, 0.45), R["wood_dark"])
    b.box((0, 0, 4.7), (7.0, 0.6, 0.6), R["wood"], top=(0.9, 1.0))
    sign = R["plaster"]
    b.box((0, -0.35, 4.2), (2.2, 0.08, 0.7), R["wood_dark"])
    b.box((0, -0.4, 4.2), (2.0, 0.05, 0.5), sign)
    for sx in (-1, 1):  # open doors, swung back
        with b.at((sx * 2.9, 0, 0), (0, 0, sx * -1.15)):
            b.box((sx * -1.3 + 0.0, 0, 1.4), (2.6, 0.18, 2.8), R["wood"])
            for z in (0.4, 2.2):
                b.box((sx * -1.3, -0.1, z), (2.6, 0.06, 0.18), R["metal"])
            b.beam((sx * -2.4, -0.1, 0.4), (sx * -0.3, -0.1, 2.3), 0.16, 0.06, R["wood_dark"])
    for sx in (-1, 1):
        parts.lantern(b, R, (sx * 3.2, -0.5, 3.0))
    if variant == 0:  # watch hut
        hx = 6.0
        b.box((hx, 0, 1.45), (3.2, 3.2, 2.5), R["rock_mid"])
        b.gable(hx - 1.6, -1.6, hx + 1.6, 1.6, 2.7, 1.5, R["rock_mid"], R["thatch"], 0.4, 0.2, "x")
        parts.door(b, R, (hx - 0.8, -1.6, 0.2), "-y", 0.9, 1.9, R["door_green"])
        parts.window(b, R, (hx + 0.7, -1.6, 1.8), "-y", 0.6, 0.7)
        parts.chimney(b, R, hx + 1.0, 0.6, 3.4, 0.9, 0.5)
        with b.collision("colonly"):
            b.box((hx, 0, 1.9), (3.2, 3.2, 3.8))
            for sx in (-1, 1):
                b.box((sx * 3.2, 0, 2.0), (0.7, 0.7, 4.0))
    else:
        for sx in (-1, 1):
            b.box((sx * 5.2, 0, 1.3), (3.0, 1.0, 2.6), R["rock_mid"], top=(0.9, 0.9))
            b.box((sx * 5.2, 0, 2.7), (3.2, 1.2, 0.2), R["rock_light"])
        with b.collision("colonly"):
            for sx in (-1, 1):
                b.box((sx * 3.2, 0, 2.0), (0.7, 0.7, 4.0))
                b.box((sx * 5.2, 0, 1.4), (3.0, 1.0, 2.8))


def dike(b, R, variant=0, length=4.0):
    rng = b.rng
    if variant < 2:
        pts = [(-3.0, -0.8), (-1.6, 0.0), (-1.2, 0.0), (-0.6, 1.5), (0.6, 1.5), (1.4, 0.0), (3.0, 0.0), (3.0, -0.8)]
        b.prism(pts, length, R["path_mid"], loc=(0, 0, 0))
        b.prism([(-0.7, 1.45), (0.7, 1.45), (0.55, 1.65), (-0.55, 1.65)], length, R["grass_mid"])
    if variant in (0, 2):
        L = [R["forest_floor_dark"], R["forest_floor_mid"], R["grass_dark"]]
        base = 1.5 if variant == 0 else 0.0
        n = max(2, int(length / 1.0))
        for i in range(n):
            y = -length / 2 + (i + 0.5) * length / n
            b.blob((0, y, base + 0.7), (0.8, length / n * 0.85, 0.75), L[i % 3], 1, 0.15)
            b.blob((rng.uniform(-0.2, 0.2), y + 0.2, base + 1.35), (0.55, length / n * 0.6, 0.45), L[(i + 1) % 3], 1, 0.15)
            for k in range(2):  # thorn sprigs
                b.cone((rng.uniform(-0.5, 0.5), y + rng.uniform(-0.3, 0.3), base + 1.4), 0.04, 0.5, R["bark"], 3,
                       rot=(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0))
    with b.collision():
        b.box((0, 0, 1.0), (2.4, length, 2.0))


def bill_ferny(b, R):
    rng = b.rng
    w, d, h = 5.4, 4.4, 2.6
    b.box((0, 0, 0.15), (w + 0.2, d + 0.2, 0.3), R["rock_dark"])
    b.box((0, 0, 0.3 + h / 2), (w, d, h), R["plaster_dark"], rot=(0.0, 0.0, 0.02))
    with b.at((0.15, -0.15, 0.3 + h), (0.035, -0.03, 0.05)):
        b.box((0, 0, 1.2), (w - 0.4, d - 0.3, 2.4), R["wood"])
    b.gable(-w / 2 - 0.1, -d / 2 - 0.1, w / 2 + 0.3, d / 2, 0.3 + h + 2.2, 1.9, R["wood"], R["thatch_dark"], 0.5, 0.26, "x", True)
    b.box((0.8, -d / 2 - 0.3, 0.3 + h + 3.0), (1.6, 0.1, 0.9), R["wood_dark"], rot=(0.5, 0, 0.1))  # patched hole
    parts.door(b, R, (-1.0, -d / 2, 0.3), "-y", 1.0, 1.9, R["door_red"])
    parts.window(b, R, (1.5, -d / 2, 1.9), "-y", 0.7, 0.9, glow=0.2)
    for i in range(3):  # boards nailed across upstairs window
        parts.window(b, R, (-1.2, -d / 2 + 0.0, 4.4), "-y", 0.7, 0.9, glow=0.2, mullion=False)
        b.beam((-1.7, -d / 2 - 0.25, 4.0 + i * 0.25), (-0.7, -d / 2 - 0.25, 4.3 + i * 0.2 - 0.1), 0.2, 0.05, R["bark_light"])
    parts.chimney(b, R, w / 2 - 0.6, 0.3, 5.2, 1.2, 0.6, R["brick"])
    b.box((w / 2 + 1.3, 0.5, 1.0), (2.2, 2.6, 1.8), R["wood_dark"], rot=(0, 0, 0.06))  # shed
    b.box((w / 2 + 1.3, 0.5, 2.0), (2.5, 2.9, 0.15), R["thatch_dark"], rot=(0.1, 0, 0.06))
    parts.crate(b, R, (-2.6, -d / 2 - 0.8, 0), 0.7, 0.3)
    parts.crate(b, R, (-2.7, -d / 2 - 0.7, 0.7), 0.5, 0.9)
    parts.barrel(b, R, (-3.4, -d / 2 - 0.5, 0), 0.9, 0.33)
    for i in range(4):
        b.blob((2.5 + i * 0.3, -d / 2 - 1.5 + rng.random(), 0.2), (0.4, 0.3, 0.25), R["bark"], 1, 0.3)  # junk heap
    b.cyl((3.4, -d / 2 - 1.3, 0.1), 0.45, 0.06, R["wood_dark"], 8, rot=(0.3, 0.2, 0))
    for i in range(4):  # broken fence
        b.box((-w / 2 - 1.0 + i * 1.6 - 2.0, -d / 2 - 2.6, 0.5), (0.12, 0.12, 1.0 - 0.3 * (i == 2)), R["wood_dark"], rot=(0, rng.uniform(-0.2, 0.2), 0))
    with b.collision():
        b.box((0, 0, 2.7), (w + 3.0, d + 0.4, 5.4))


def specs():
    S = []
    S.append(Spec("bree_house_stone_1", "bree", "house", 400, lambda b, R: house(b, R, 7.0, 5.2, 2, "stone", "slate")))
    S.append(Spec("bree_house_stone_2", "bree", "house", 401, lambda b, R: house(b, R, 6.4, 5.0, 2, "stone", "thatch", wing=True)))
    S.append(Spec("bree_house_timber_1", "bree", "house", 402, lambda b, R: house(b, R, 7.4, 5.4, 2, "timber", "tile", jetty=True)))
    S.append(Spec("bree_house_timber_2", "bree", "house", 403, lambda b, R: house(b, R, 8.4, 5.0, 2, "timber", "thatch")))
    S.append(Spec("bree_house_hobbit_1", "bree", "house", 404, lambda b, R: house(b, R, 5.6, 4.2, 1, "plaster", "thatch", hobbit=True)))
    S.append(Spec("bree_house_hobbit_2", "bree", "house", 405, lambda b, R: house(b, R, 6.2, 4.4, 1, "stone", "thatch", hobbit=True)))
    S.append(Spec("prancing_pony", "bree", "bighouse", 410, prancing_pony))
    S.append(Spec("bree_gate_watch", "bree", "structure", 411, lambda b, R: gate(b, R, 0)))
    S.append(Spec("bree_gate_stone", "bree", "structure", 412, lambda b, R: gate(b, R, 1)))
    S.append(Spec("bree_dike_hedge", "bree", "structure", 413, lambda b, R: dike(b, R, 0)))
    S.append(Spec("bree_dike", "bree", "structure", 414, lambda b, R: dike(b, R, 1)))
    S.append(Spec("bree_hedge", "bree", "structure", 415, lambda b, R: dike(b, R, 2)))
    S.append(Spec("bill_ferny_house", "bree", "house", 416, bill_ferny))
    return S
