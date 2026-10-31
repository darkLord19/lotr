"""Props: barrels, carts, signposts, lanterns, benches, tables, mugs, food, crates, sacks, hay."""
from __future__ import annotations

import math

from lib import parts
from lib.geo import m
from . import Spec

PI = math.pi


def cart(b, R, variant=0):
    L, W = (2.4, 1.3) if variant == 0 else (3.4, 1.7)
    b.box((0, 0, 0.9), (L, W, 0.12), R["wood"])
    for sy in (-1, 1):
        b.box((0, sy * W / 2, 1.2), (L, 0.1, 0.5), R["wood"])
    for sx in (-1, 1):
        b.box((sx * L / 2, 0, 1.2), (0.1, W, 0.5), R["wood"])
    b.box((0, 0, 0.78), (L + 0.2, 0.12, 0.12), R["wood_dark"])
    ax = 0.0
    for sy in (-1, 1):
        y = sy * (W / 2 + 0.12)
        b.cyl((ax, y - 0.04, 0.55), 0.55, 0.08, R["wood_dark"], 10, rot=(PI / 2, 0, 0))
        b.cyl((ax, y + 0.0, 0.55), 0.09, 0.14, R["metal"], 6, rot=(PI / 2, 0, 0))
        for k in range(4):
            a = k * PI / 4
            b.box((ax, y, 0.55), (0.06, 0.06, 1.0), R["wood"], rot=(0, a, 0))
    b.box((0, 0, 0.55), (0.1, W + 0.5, 0.1), R["metal"])
    b.beam((L / 2, -0.3, 0.9), (L / 2 + 1.7, -0.3, 0.55), 0.09, 0.09, R["wood_dark"])
    b.beam((L / 2, 0.3, 0.9), (L / 2 + 1.7, 0.3, 0.55), 0.09, 0.09, R["wood_dark"])
    if variant == 1:
        b.blob((0, 0, 1.55), (L / 2 - 0.05, W / 2 - 0.05, 0.5), R["hay"], 1, 0.12)
    else:
        parts.crate(b, R, (-0.5, 0, 0.96), 0.5)
        b.blob((0.5, 0.1, 1.2), (0.3, 0.3, 0.22), R["bark_light"], 1, 0.2)
    with b.collision():
        b.box((0.4, 0, 0.85), (L + 1.9, W + 0.6, 1.4))


def signpost(b, R, variant=0):
    b.box((0, 0, 1.2), (0.16, 0.16, 2.4), R["wood_dark"], top=(0.9, 0.9))
    b.box((0, 0, 2.45), (0.24, 0.24, 0.1), R["wood"], top=(0.5, 0.5))
    boards = [(2.1, 0.5, 1.0), (1.7, -0.3, 0.9)] if variant == 0 else [(2.0, 0.2, 1.1), (1.6, 0.9, 1.0), (1.2, -0.4, 0.9)]
    for z, yaw, ln in boards:
        with b.at((0, 0, z), (0, 0, yaw)):
            b.box((ln / 2 + 0.05, -0.1, 0), (ln, 0.05, 0.28), R["wood"], top=(1.0, 1.0))
            b.box((ln + 0.05, -0.1, 0), (0.2, 0.05, 0.2), R["wood"], rot=(0, PI / 4, 0))
            b.box((ln / 2, -0.14, 0), (ln - 0.2, 0.02, 0.06), R["plaster"])
    with b.collision():
        b.cyl((0, 0, 0), 0.12, 2.4, None, 5)


def lantern_post(b, R, variant=0):
    h = 2.6
    b.cyl((0, 0, 0), 0.12, h, R["metal"], 6, top_r=0.07)
    b.cyl((0, 0, 0), 0.2, 0.2, R["metal"], 6, top_r=0.12)
    b.beam((0, 0, h - 0.1), (0.5, 0, h + 0.1), 0.05, 0.05, R["metal"])
    parts.lantern(b, R, (0.5, 0, h - 0.36), 1.2)
    with b.collision():
        b.cyl((0, 0, 0), 0.12, h, None, 5)


def lantern_hand(b, R):
    parts.lantern(b, R, (0, 0, 0), 1.2)
    b.between((-0.1, 0, 0.35), (0.0, 0, 0.5), 0.015, R["metal"], 4)


def bench(b, R, variant=0):
    L = 1.8
    b.box((0, 0, 0.45), (L, 0.45, 0.08), R["wood"])
    for sx in (-1, 1):
        b.box((sx * (L / 2 - 0.15), 0, 0.22), (0.1, 0.4, 0.44), R["wood_dark"])
    if variant == 1:
        b.box((0, 0.2, 0.85), (L, 0.06, 0.35), R["wood"])
        for sx in (-1, 1):
            b.box((sx * (L / 2 - 0.15), 0.2, 0.65), (0.08, 0.08, 0.8), R["wood_dark"])
    with b.collision():
        b.box((0, 0, 0.45), (L, 0.5, 0.9 if variant else 0.5))


def table(b, R, variant=0):
    L, W = (1.4, 0.8) if variant == 0 else (2.8, 0.9)
    b.box((0, 0, 0.78), (L, W, 0.07), R["wood"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * (L / 2 - 0.1), sy * (W / 2 - 0.1), 0.38), (0.09, 0.09, 0.76), R["wood_dark"])
    b.box((0, 0, 0.25), (L - 0.2, 0.05, 0.05), R["wood_dark"])
    if variant == 1:
        parts.barrel  # (kept for clarity: long table is empty; props are placed separately)
    with b.collision():
        b.box((0, 0, 0.4), (L, W, 0.8))


def stool(b, R):
    b.cyl((0, 0, 0.4), 0.2, 0.06, R["wood"], 8)
    for a in range(3):
        b.between((math.cos(a * 2.1) * 0.12, math.sin(a * 2.1) * 0.12, 0.4), (math.cos(a * 2.1) * 0.2, math.sin(a * 2.1) * 0.2, 0.0), 0.03, R["wood_dark"], 4)
    with b.collision():
        b.cyl((0, 0, 0), 0.22, 0.45, None, 6)


def mug(b, R, variant=0):
    b.cyl((0, 0, 0), 0.05, 0.11, R["wood"] if variant == 0 else R["rock_light"], 8, top_r=0.06)
    b.cyl((0, 0, 0.09), 0.047, 0.02, R["ale"], 8)
    b.cyl((0, 0, 0.105), 0.048, 0.02, R["plaster"], 8)
    b.box((0.075, 0, 0.055), (0.025, 0.02, 0.07), R["wood"] if variant == 0 else R["rock_light"])


def barrel_prop(b, R, variant=0):
    if variant == 0:
        parts.barrel(b, R, (0, 0, 0), 0.95, 0.4)
    else:
        parts.barrel(b, R, (-0.45, 0, 0), 0.95, 0.4)
        parts.barrel(b, R, (0.45, 0, 0), 0.95, 0.4)
        parts.barrel(b, R, (0, 0.3, 0.9), 0.95, 0.4, lid=False) if False else parts.barrel(b, R, (0, 0.05, 0.95), 0.9, 0.38)
    with b.collision():
        b.cyl((0, 0, 0), 0.4, 0.95, None, 6) if variant == 0 else b.box((0, 0, 0.9), (1.3, 0.8, 1.8))


def food(b, R, variant=0):
    rng = b.rng
    if variant == 0:  # bread loaves on a board
        b.box((0, 0, 0.02), (0.5, 0.3, 0.04), R["wood"])
        for i in range(2):
            b.blob((-0.1 + i * 0.2, 0, 0.1), (0.1, 0.07, 0.06), R["food_crust"], 1, 0.08)
    elif variant == 1:  # cheese wheel + wedge
        b.cyl((0, 0, 0), 0.16, 0.1, R["food_cheese"], 10)
        b.cyl((0.3, 0, 0), 0.1, 0.07, R["food_cheese"], 3)
    elif variant == 2:  # apple basket
        b.cyl((0, 0, 0), 0.22, 0.2, R["wood"], 8, top_r=0.26)
        for i in range(7):
            a = rng.uniform(0, math.tau)
            r = rng.uniform(0, 0.17)
            b.blob((math.cos(a) * r, math.sin(a) * r, 0.22), (0.06, 0.06, 0.055), R["food_apple"], 1, 0.05)
    elif variant == 3:  # pie
        b.cyl((0, 0, 0), 0.14, 0.09, R["food_crust"], 10, top_r=0.12)
        b.cyl((0, 0, 0.085), 0.12, 0.02, R["food_crust"], 10, top_r=0.1)
    else:  # mushrooms
        for i in range(4):
            x, y, s = rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), rng.uniform(0.7, 1.2)
            b.cyl((x, y, 0), 0.02 * s, 0.07 * s, R["plaster"], 5)
            b.dome((x, y, 0.07 * s), (0.055 * s, 0.055 * s, 0.04 * s), R["brick"] if i % 2 else R["food_crust"], 7, 2)


def sack(b, R, variant=0):
    b.blob((0, 0, 0.3), (0.28, 0.24, 0.32), R["hay"] if variant == 0 else R["plaster_dark"], 1, 0.12)
    b.cyl((0, 0, 0.55), 0.1, 0.12, R["hay"] if variant == 0 else R["plaster_dark"], 6, top_r=0.07)
    with b.collision():
        b.cyl((0, 0, 0), 0.3, 0.6, None, 6)


def hay(b, R):
    b.box((0, 0, 0.25), (0.9, 0.45, 0.5), R["hay"])
    for z in (0.1, 0.4):
        b.box((0, 0, z), (0.92, 0.47, 0.03), R["thatch_dark"])
    with b.collision():
        b.box((0, 0, 0.25), (0.9, 0.45, 0.5))


def crate_prop(b, R):
    parts.crate(b, R, (0, 0, 0), 0.7)
    with b.collision():
        b.box((0, 0, 0.35), (0.7, 0.7, 0.7))


def specs():
    S = []
    for v in range(2):
        S.append(Spec(f"barrel_{v + 1}", "props", "prop", 500 + v, lambda b, R, v=v: barrel_prop(b, R, v), lods=False))
        S.append(Spec(f"cart_{v + 1}", "props", "prop", 510 + v, lambda b, R, v=v: cart(b, R, v), lods=False))
        S.append(Spec(f"signpost_{v + 1}", "props", "prop", 520 + v, lambda b, R, v=v: signpost(b, R, v), lods=False))
        S.append(Spec(f"bench_{v + 1}", "props", "prop", 530 + v, lambda b, R, v=v: bench(b, R, v), lods=False))
        S.append(Spec(f"table_{v + 1}", "props", "prop", 540 + v, lambda b, R, v=v: table(b, R, v), lods=False))
        S.append(Spec(f"mug_{v + 1}", "props", "prop", 550 + v, lambda b, R, v=v: mug(b, R, v), lods=False))
        S.append(Spec(f"sack_{v + 1}", "props", "prop", 560 + v, lambda b, R, v=v: sack(b, R, v), lods=False))
    S.append(Spec("lantern_post", "props", "prop", 570, lambda b, R: lantern_post(b, R), lods=False))
    S.append(Spec("lantern_hand", "props", "prop", 571, lantern_hand, lods=False))
    S.append(Spec("stool", "props", "prop", 572, stool, lods=False))
    S.append(Spec("hay_bale", "props", "prop", 573, hay, lods=False))
    S.append(Spec("crate", "props", "prop", 574, crate_prop, lods=False))
    for v, n in enumerate(["bread", "cheese", "apple_basket", "pie", "mushrooms"]):
        S.append(Spec(f"food_{n}", "props", "prop", 580 + v, lambda b, R, v=v: food(b, R, v), lods=False))
    return S
