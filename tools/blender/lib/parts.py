"""Reusable building parts (windows, doors, chimneys, timber framing, lanterns, barrels...).

All "face" parts are built facing -Y at the local origin on the wall surface; `face` rotates them to the
wall they belong to ('-y' front, '+y' back, '+x' right, '-x' left).
"""
from __future__ import annotations

import math

from .geo import m

YAW = {"-y": 0.0, "+x": math.pi / 2, "+y": math.pi, "-x": -math.pi / 2}


def window(b, R, pos, face="-y", w=0.8, h=1.0, shutters=False, round_=False, mullion=True, frame=None, sill=True, glow=1.0):
    frame = frame or R["wood_dark"]
    with b.at(pos, (0, 0, YAW[face])):
        glass = m(R["glass"], glow)
        if round_:
            b.cyl((0, 0.12, 0), w / 2 + 0.1, 0.2, frame, 10, rot=(math.pi / 2, 0, 0))
            b.cyl((0, 0.1, 0), w / 2, 0.2, glass, 10, rot=(math.pi / 2, 0, 0))
            if mullion:
                b.box((0, -0.12, 0), (w, 0.04, 0.06), frame)
                b.box((0, -0.12, 0), (0.06, 0.04, w), frame)
        else:
            b.box((0, -0.03, 0), (w + 0.18, 0.1, h + 0.18), frame)
            b.box((0, -0.09, 0), (w, 0.04, h), glass)
            if mullion:
                b.box((0, -0.12, 0), (w, 0.03, 0.05), frame)
                b.box((0, -0.12, 0), (0.05, 0.03, h), frame)
            if sill:
                b.box((0, -0.12, -h / 2 - 0.1), (w + 0.3, 0.2, 0.07), R["rock_light"])
            if shutters:
                for s in (-1, 1):
                    b.box((s * (w / 2 + 0.2), -0.1, 0), (w / 2 - 0.02, 0.04, h + 0.1), shutters if isinstance(shutters, str) else R["door_green"])


def door(b, R, pos, face="-y", w=1.0, h=1.9, color=None, round_=False, knob=True, arch=False):
    color = color or R["wood"]
    with b.at(pos, (0, 0, YAW[face])):
        if round_:
            r = w / 2
            b.cyl((0, 0.15, r), r + 0.12, 0.3, R["wood_dark"], 12, rot=(math.pi / 2, 0, 0))
            b.cyl((0, 0.05, r), r, 0.2, color, 12, rot=(math.pi / 2, 0, 0))
            if knob:
                b.blob((0, -0.16, r), (0.07, 0.07, 0.07), R["brass"], 0, 0)
            b.box((0, -0.13, r), (w * 0.95, 0.03, 0.06), R["metal"])
        else:
            b.box((0, 0, h / 2 + 0.05), (w + 0.2, 0.14, h + 0.1), R["wood_dark"])
            b.box((0, -0.06, h / 2), (w, 0.06, h), color)
            if knob:
                b.blob((w / 2 - 0.15, -0.12, h * 0.48), (0.05, 0.05, 0.05), R["brass"], 0, 0)
            b.box((0, -0.1, h * 0.25), (w * 0.9, 0.03, 0.06), R["metal"])
            b.box((0, -0.1, h * 0.75), (w * 0.9, 0.03, 0.06), R["metal"])
            b.box((0, -0.12, -0.05), (w + 0.5, 0.5, 0.12), R["rock_mid"])  # step


def chimney(b, R, x, y, z0, h=1.4, w=0.6, mat=None):
    mat = mat or R["rock_mid"]
    b.box((x, y, z0 + h / 2), (w, w, h), mat, top=(0.9, 0.9))
    b.box((x, y, z0 + h + 0.06), (w + 0.16, w + 0.16, 0.12), R["rock_dark"])
    b.box((x, y, z0 + h + 0.2), (w * 0.6, w * 0.6, 0.18), R["metal"])


def timber_wall(b, R, x0, x1, y, z0, z1, face="-y", post_gap=1.3, color=None, diag=True):
    """Dark timber frame over a flat wall at y (front/back walls running along x)."""
    color = color or R["wood_dark"]
    sgn = -1 if face == "-y" else 1
    yy = y + sgn * 0.04
    n = max(1, round((x1 - x0) / post_gap))
    step = (x1 - x0) / n
    for i in range(n + 1):
        b.box((x0 + i * step, yy, (z0 + z1) / 2), (0.16, 0.1, z1 - z0), color)
    b.box(((x0 + x1) / 2, yy, z0 + 0.08), (x1 - x0, 0.1, 0.16), color)
    b.box(((x0 + x1) / 2, yy, z1 - 0.08), (x1 - x0, 0.1, 0.16), color)
    b.box(((x0 + x1) / 2, yy, (z0 + z1) / 2), (x1 - x0, 0.1, 0.12), color)
    if diag:
        for i in range(0, n, 2):
            b.beam((x0 + i * step + 0.08, yy, z0 + 0.1), (x0 + (i + 1) * step - 0.08, yy, (z0 + z1) / 2 - 0.06), 0.1, 0.08, color)


def barrel(b, R, loc=(0, 0, 0), h=0.9, r=0.38, lid=True):
    with b.at(loc):
        b.cyl((0, 0, 0), r * 0.9, h, R["wood"], 8, top_r=r * 0.9)
        b.cyl((0, 0, h * 0.25), r, h * 0.5, R["wood"], 8, top_r=r)
        for z in (h * 0.14, h * 0.82):
            b.cyl((0, 0, z), r * 0.96, 0.07, R["metal"], 8)
        b.cyl((0, 0, h * 0.5 - 0.03), r * 1.02, 0.06, R["metal"], 8)
        if lid:
            b.cyl((0, 0, h - 0.01), r * 0.82, 0.03, R["wood_dark"], 8)


def crate(b, R, loc=(0, 0, 0), s=0.6, rot=0.0):
    with b.at(loc, (0, 0, rot)):
        b.box((0, 0, s / 2), (s, s, s), R["wood"])
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.box((sx * s / 2, sy * s / 2, s / 2), (0.06, 0.06, s + 0.02), R["wood_dark"])
        b.box((0, -s / 2 - 0.005, s * 0.5), (s, 0.02, 0.06), R["wood_dark"])


def lantern(b, R, loc=(0, 0, 0), s=1.0):
    with b.at(loc, (0, 0, 0), (s, s, s)):
        b.cyl((0, 0, 0), 0.1, 0.04, R["metal"], 6)
        b.cyl((0, 0, 0.04), 0.085, 0.22, m("#ffd98a", 1.6), 6)
        for a in range(4):
            x, y = math.cos(a * math.pi / 2 + math.pi / 4) * 0.09, math.sin(a * math.pi / 2 + math.pi / 4) * 0.09
            b.box((x, y, 0.15), (0.02, 0.02, 0.24), R["metal"])
        b.cyl((0, 0, 0.26), 0.12, 0.07, R["metal"], 6, top_r=0.02)
        b.blob((0, 0, 0.36), (0.03, 0.03, 0.03), R["metal"], 0, 0)


def sign_board(b, R, loc, w=0.9, h=0.6, color=None, face="-y"):
    with b.at(loc, (0, 0, YAW[face])):
        b.box((0, 0, 0), (w, 0.07, h), R["wood_dark"])
        b.box((0, -0.04, 0), (w - 0.1, 0.03, h - 0.1), color or R["plaster"])
